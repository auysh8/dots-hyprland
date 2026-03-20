def _sigterm_handler(self, signum, frame):
    """Handle SIGTERM/SIGHUP — clean up mpv and exit."""
    self._cleanup_on_exit()
    sys.exit(0)


def _cleanup_on_exit(self):
    try:
        if self.mpv_process:
            self.mpv_process.terminate()
            self.mpv_process.wait(timeout=2)
    except Exception:
        try:
            if self.mpv_process:
                self.mpv_process.kill()
        except Exception:
            pass

# ── logging ───────────────────────────────────────────────────────────────
def _resolve_ytdlp_path(self):
    local = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "venv", "bin", "yt-dlp"
    )
    if os.path.isfile(local):
        return local
    system = shutil.which("yt-dlp")
    if system:
        return system
    raise FileNotFoundError("yt-dlp not found")

def _cleanup_socket(self):
    if os.path.exists(self.ipc_socket):
        try:
            os.remove(self.ipc_socket)
        except OSError:
            pass

def _push_play_stack(self, video_id):
    """Track played video IDs in-memory for prev_track navigation."""
    if video_id in self._play_stack:
        self._play_stack.remove(video_id)
    self._play_stack.append(video_id)
    if len(self._play_stack) > 20:
        self._play_stack = self._play_stack[-20:]

def play(self, video_id, title, artist, art_url):
    self.log(f"Playing: {title} by {artist}")
    # Ensure high-res art URL
    if art_url:
        if "=w" in art_url and "-h" in art_url:
            art_url = re.sub(r"=w\d+-h\d+", "=w544-h544", art_url)
        elif "googleusercontent.com" in art_url and "=s" in art_url:
            art_url = re.sub(r"=s\d+", "=s544", art_url)
    self._push_play_stack(video_id)
    
    # Capture and reset auto-advancing flag before spawning thread
    # so each play task gets its own copy and rapid clicks don't interfere
    is_auto = getattr(self, "_is_auto_advancing", False)
    self._is_auto_advancing = False
    
    # Kill any in-flight yt-dlp fetch from previous play command
    try:
        if self._ytdlp_proc and self._ytdlp_proc.poll() is None:
            self._ytdlp_proc.kill()
            self._ytdlp_proc = None
    except Exception:
        pass
    
    self.stop(notify=False)
    
    self.send_response({
        "type": "track_loading",
        "videoId": video_id,
        "title": title,
        "artist": artist,
        "artUrl": art_url
    })
    
    with self._state_lock:
        self._playback_token += 1
        token = self._playback_token
        
    threading.Thread(
        target=self._play_task,
        args=(video_id, title, artist, art_url, token, is_auto),
        daemon=True,
    ).start()

def _prefetch_stream_url(self, video_id):
    if video_id in self._stream_cache:
        return
    self.log(f"Background prefetching next URL for gapless playback: {video_id}")
    try:
        ytdlp = self._resolve_ytdlp_path()
        result = subprocess.run(
            [ytdlp, "-f", "bestaudio", "-g", "--no-warnings", f"https://music.youtube.com/watch?v={video_id}"],
            capture_output=True, text=True, check=True, timeout=30,
        )
        stream_url = result.stdout.strip().split("\n")[-1].strip()
        if stream_url:
            with self._state_lock:
                self._stream_cache[video_id] = stream_url
            self.log(f"Gapless URL ready for {video_id}")
    except Exception as e:
        self.log(f"Failed gapless prefetch: {e}")

def _play_task(self, video_id, title, artist, art_url, token, is_auto=False):
    try:
        # Debounce: wait briefly so rapid next-button clicks settle
        # before starting expensive yt-dlp work. Only the last click survives.
        time.sleep(0.25)

        with self._state_lock:
            if self._playback_token != token:
                return

        # Check if this is a playlist/album ID (deferred from explore section)
        if video_id and (video_id.startswith("OLAK") or video_id.startswith("PL") or video_id.startswith("VL")):
            self.log(f"Resolving playlist/album lead track for: {video_id}")
            try:
                p_data = self.ytm.get_watch_playlist(playlistId=video_id, limit=1).get("tracks", [])
                if p_data and p_data[0].get("videoId"):
                    video_id = p_data[0].get("videoId")
                    with self._state_lock:
                        if self._playback_token == token:
                            self.current_video_id = video_id
            except Exception as e:
                self.log(f"Failed to resolve playlist videoId: {e}")

        with self._state_lock:
            if self._playback_token != token:
                return

        # 1. Get stream URL (art download deferred to after mpv launch to save bandwidth)
        with self._state_lock:
            stream_url = self._stream_cache.pop(video_id, None)
        
        # Compute art file path (download happens later, may already be cached)
        art_file_path = ""
        if art_url:
            digest = hashlib.md5(art_url.encode()).hexdigest()
            art_file_path = os.path.join(self.cache_dir, digest)

        if stream_url:
            self.log(f"Using instant pre-fetched gapless stream URL")
        else:
            self.log("Fetching stream URL...")
            ytdlp = self._resolve_ytdlp_path()
            proc = subprocess.Popen(
                [
                    ytdlp,
                    "-f",
                    "bestaudio",
                    "-g",
                    "--no-warnings",
                    f"https://music.youtube.com/watch?v={video_id}",
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self._ytdlp_proc = proc
            stdout, _ = proc.communicate(timeout=30)
            self._ytdlp_proc = None
            
            if proc.returncode != 0:
                raise ValueError(f"yt-dlp exited with code {proc.returncode}")
            stream_url = stdout.strip().split("\n")[-1].strip()
            
            # Recheck token after expensive fetch — bail if superseded
            with self._state_lock:
                if self._playback_token != token:
                    self.log("Playback task aborted after stream fetch.")
                    return
                    
        if not stream_url:
            raise ValueError("yt-dlp returned empty URL")
        self.log("Stream URL obtained")

        # Persist metadata for pause/resume re-broadcasts
        self._current_title = title
        self._current_artist = artist
        self._current_art = art_file_path
        self._current_art_url = art_url

        with self._state_lock:
            if self._playback_token != token:
                self.log("Playback task aborted, another play command was issued.")
                return

        # Fetch radio queue only for fresh (non-auto-advancing) plays
        # and only after token check to prevent stale tasks from replacing the queue
        if not is_auto:
            threading.Thread(target=self._fetch_queue_task, args=(video_id,), daemon=True).start()

        # 3. Build mpv command — pure subprocess, no libmpv
        self._cleanup_socket()
        cmd = [
            "mpv",
            "--no-video",  # audio only
            "--no-terminal",  # no terminal output
            "--really-quiet",  # suppress mpv stderr noise
            "--no-config",  # don't load user mpv config
            "--load-scripts=no",  # disable all scripts including MPRIS
            f"--input-ipc-server={self.ipc_socket}",  # for pause/resume/stop
            f"--force-media-title={title} \u2022 {artist}",
            stream_url,
        ]
        self.log(f"Launching mpv subprocess...")
        process = subprocess.Popen(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        with self._state_lock:
            # Re-check just in case, though we checked right before Popen
            if self._playback_token != token:
                process.kill()
                return
            self.mpv_process = process
            self.current_video_id = video_id

        self.log("mpv launched — playback started")
        
        # Attempt to prefetch the next track for gapless playback
        with self._state_lock:
            next_id = None
            if self.repeat_mode == 2:
                next_id = video_id # Repeat one
            elif getattr(self, "_current_queue", None):
                next_id = self._current_queue[0].get("videoId")
        
        if next_id:
            threading.Thread(target=self._prefetch_stream_url, args=(next_id,), daemon=True).start()

        # Download art in background (for MPRIS + ColorQuantizer, doesn't block playback)
        def _deferred_art_download():
            if art_url and art_file_path:
                if self._download_art(art_url, art_file_path):
                    # Notify QML so ColorQuantizer can extract colors
                    self.send_response({
                        "type": "art_downloaded",
                        "videoId": video_id,
                        "path": art_file_path,
                    })
                    # Update MPRIS with local art path
                    self.mpris.update(
                        status="Playing",
                        title=title,
                        artist=artist,
                        art_local_path=art_file_path,
                        video_id=video_id,
                        art_url=art_url,
                    )
        threading.Thread(target=_deferred_art_download, daemon=True).start()

        # 4. IMMEDIATELY notify QML — don't wait for history sync
        self.send_response(
            {
                "type": "playback_started",
                "videoId": video_id,
                "title": title,
                "artist": artist,
                "artUrl": art_url,
                "artLocalPath": art_file_path,
                "isLiked": False,  # updated async below
            }
        )

        # 4b. Fetch canvas animated art in background (non-blocking)
        def _fetch_canvas():
            try:
                # Check cache first
                cached_canvas = self._canvas_cache.get(video_id)
                if cached_canvas and (time.time() - cached_canvas["ts"]) < self._canvas_cache_ttl:
                    self.log(f"Canvas: Using cached canvas for '{title}'")
                    with self._state_lock:
                        still_current = self._playback_token == token
                    if still_current and cached_canvas.get("url"):
                        self.send_response({
                            "type": "canvas_url",
                            "videoId": video_id,
                            "url": cached_canvas["url"],
                            "isAnimated": cached_canvas["isAnimated"],
                        })
                    return

                # First, try to get album info from YTMusic for better canvas matching
                album_name = None
                try:
                    song_data = self.ytm.get_song(video_id)
                    if song_data:
                        album_dict = song_data.get('album', {})
                        if isinstance(album_dict, dict):
                            album_name = album_dict.get('name')
                        elif isinstance(album_dict, str):
                            album_name = album_dict
                        if album_name:
                            self.log(f"Canvas: Using album '{album_name}' for better matching")
                except Exception as e:
                    self.log(f"Canvas: Could not fetch album info: {e}")

                script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "canvas_fetcher.py")
                python = os.path.join(os.path.dirname(os.path.abspath(__file__)), "venv", "bin", "python3")
                if not os.path.exists(python):
                    python = sys.executable

                # Try different storefronts to maximize regional availability (like 'Photograph' being available in 'gb')
                storefronts_to_try = ["us", "gb", "au", "ca"]
                canvas_url = None
                is_animated = False
                source = None

                for sf in storefronts_to_try:
                    # Build command with optional album parameter
                    cmd = [python, script, title, artist, album_name or "", sf]

                    result = subprocess.run(
                        cmd,
                        capture_output=True, text=True, timeout=25,
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        canvas_data = json.loads(result.stdout.strip())
                        # Prefer direct MP4 (videoUrl) over complex HLS manifests (animated)
                        canvas_url = canvas_data.get("videoUrl") or canvas_data.get("animated")
                        if canvas_url:
                            is_animated = bool(canvas_data.get("animated"))
                            source = canvas_data.get('source')
                            self.log(f"Canvas art found for '{title}' via {source} (storefront: {sf}): {canvas_url[:80]}")
                            break # Stop searching if found
                
                if not canvas_url:
                    self.log(f"No canvas art found for '{title}' across storefronts: {storefronts_to_try}")

                # Cache the result (even if null to prevent re-fetching missing canvases)
                self._canvas_cache[video_id] = {
                    "url": canvas_url,
                    "isAnimated": is_animated,
                    "ts": time.time()
                }
                self._save_canvas_cache()

                if canvas_url:
                    with self._state_lock:
                        still_current = self._playback_token == token
                    if still_current:
                        self.send_response({
                            "type": "canvas_url",
                            "videoId": video_id,
                            "url": canvas_url,
                            "isAnimated": is_animated,
                        })
            except Exception as e:
                self.log(f"Canvas fetch error: {e}")
        threading.Thread(target=_fetch_canvas, daemon=True).start()

        # 5. Publish MPRIS on D-Bus
        self.mpris.publish()
        self.mpris.update(
            status="Playing",
            title=title,
            artist=artist,
            art_local_path=art_file_path,
            video_id=video_id,
            art_url=art_url,
        )

        # 6. History sync + like check in background (non-blocking)
        def _sync_history():
            try:
                if os.path.exists(self.oauth_path) or os.path.exists(self.headers_path):
                    self.log(f"Syncing '{title}' to YouTube Music history...")
                    cached_meta = self._song_meta_cache.get(video_id)
                    if cached_meta and (time.time() - cached_meta["ts"]) < self._song_meta_cache_ttl:
                        song_data = cached_meta["data"]
                        is_liked = cached_meta["is_liked"]
                    else:
                        song_data = self.ytm.get_song(video_id)
                        is_liked = bool(song_data and song_data.get('videoDetails', {}).get('likeStatus') == 'LIKE')
                        self._song_meta_cache[video_id] = {
                            "data": song_data,
                            "is_liked": is_liked,
                            "ts": time.time(),
                        }
                        
                    if song_data and getattr(self.ytm, 'add_history_item', None):
                        self.ytm.add_history_item(song_data)
                        self.log("History sync successful.")
                    
                    # Send liked status update to QML
                    if is_liked:
                        self.send_response({"type": "like_status", "videoId": video_id, "isLiked": True})
            except Exception as e:
                self.log(f"Failed to sync history to YouTube Music: {e}")
        threading.Thread(target=_sync_history, daemon=True).start()

        # Wait for mpv to resolve duration, then update metadata again to push length to clients
        def _wait_for_duration():
            for _ in range(20):
                time.sleep(0.5)
                if not self.mpv_process: break
                dur = self._ipc_get("duration")
                if dur is not None:
                    dur_sec = int(float(dur))
                    self.log(f"Resolved duration: {dur_sec}s, updating mpris")
                    # Set cached duration BEFORE calling update so it's included in the signal
                    self.mpris._cached_duration = int(float(dur) * 1_000_000)
                    self.mpris.update(
                        status="Playing",
                        title=title,
                        artist=artist,
                        art_local_path=art_file_path,
                        video_id=video_id,
                        art_url=art_url,
                    )
                    # Send duration to QML
                    self.send_response({
                        "type": "playback_duration",
                        "durationSec": dur_sec,
                    })
                    break
        threading.Thread(target=_wait_for_duration, daemon=True).start()

        # 7. Periodic position updates to QML
        def _poll_position():
            while True:
                time.sleep(1)
                with self._state_lock:
                    if self._playback_token != token:
                        break
                if not self.mpv_process:
                    break
                pos = self._ipc_get("time-pos")
                dur = self._ipc_get("duration")
                if pos is not None:
                    self.send_response({
                        "type": "playback_progress",
                        "positionSec": int(float(pos)),
                        "durationSec": int(float(dur)) if dur else 0,
                    })
        threading.Thread(target=_poll_position, daemon=True).start()

        # 8. Monitor process exit for auto-advance
        def _monitor():
            code = process.wait()
            self.log(f"mpv exited with code {code}")
            with self._state_lock:
                is_current = self._playback_token == token
                if is_current:
                    self.mpv_process = None
                    self.current_video_id = None
                    
            self._cleanup_socket()
            if is_current:
                # 1. Repeat One
                if self.repeat_mode == 2:
                    self.log(f"Repeat One: Replaying {title}")
                    self.play(video_id, title, artist, art_url)
                    return

                # 2. Auto-advance queue
                if self._current_queue:
                    next_track = self._current_queue[0]
                    if self.repeat_mode == 1:
                        # Repeat All: Push current track to the back of the queue
                        self._current_queue.append({
                            "videoId": video_id,
                            "title": title,
                            "artist": artist,
                            "artUrl": art_url
                        })
                        self._current_queue.pop(0)
                    else:
                        self._current_queue.pop(0)
                        
                    self.send_response({"type": "queue_updated", "queue": self._current_queue})
                    self.log(f"Auto-advancing to: {next_track['title']}")
                    self._is_auto_advancing = True
                    self.play(next_track["videoId"], next_track["title"], next_track["artist"], next_track["artUrl"])
                else:
                    if self.repeat_mode == 1:
                        # Repeat All but queue is empty -> replay track
                        self.log(f"Repeat All (Empty Queue): Replaying {title}")
                        self.play(video_id, title, artist, art_url)
                    else:
                        # Queue empty — auto-fetch more similar songs (radio mode)
                        self.log("Queue empty, fetching more radio tracks...")
                        threading.Thread(target=self._auto_continue, args=(video_id,), daemon=True).start()

        threading.Thread(target=_monitor, daemon=True).start()

    except subprocess.CalledProcessError as e:
        self.log(f"yt-dlp error: {e.stderr}")
        self.send_response(
            {"type": "error", "message": f"yt-dlp failed: {e.stderr}"}
        )
    except Exception as e:
        import traceback

        self.log(f"Play task error: {e}\n{traceback.format_exc()}")
        self.send_response({"type": "error", "message": str(e)})

def _ipc(self, command):
    """Send a JSON command to mpv via IPC socket."""
    if not os.path.exists(self.ipc_socket):
        return False
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(self.ipc_socket)
        s.sendall((json.dumps({"command": command}) + "\n").encode())
        s.close()
        return True
    except Exception:
        return False

def _ipc_get(self, prop_name):
    """Get a property from mpv via IPC socket."""
    if not os.path.exists(self.ipc_socket):
        return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(self.ipc_socket)
        s.sendall((json.dumps({"command": ["get_property", prop_name]}) + "\n").encode())
        f = s.makefile()
        for line in f:
            data = json.loads(line)
            if "data" in data or "error" in data:
                return data.get("data")
        s.close()
        return None
    except Exception:
        return None

def stop(self, notify=True):
    with self._state_lock:
        process = self.mpv_process
        self.mpv_process = None
        self.current_video_id = None
        self._playback_token += 1
    if process:
        try:
            process.terminate()
            process.wait(timeout=2)
        except Exception:
            try:
                process.kill()
            except Exception:
                pass
    self._cleanup_socket()
    self.mpris.update("Stopped")
    self.mpris.unpublish()
    if notify:
        self.send_response({"type": "playback_stopped"})

def pause(self):
    if self._ipc(["set_property", "pause", True]):
        self.mpris.update(
            "Paused",
            title=self._current_title,
            artist=self._current_artist,
            art_local_path=self._current_art,
            video_id=self.current_video_id or "",
            art_url=getattr(self, "_current_art_url", ""),
        )
        self.send_response({"type": "playback_paused"})

def resume(self):
    if self._ipc(["set_property", "pause", False]):
        self.mpris.update(
            "Playing",
            title=self._current_title,
            artist=self._current_artist,
            art_local_path=self._current_art,
            video_id=self.current_video_id or "",
            art_url=getattr(self, "_current_art_url", ""),
        )
        self.send_response({"type": "playback_resumed"})

def seek(self, position_sec):
    if self.mpv_process:
        self._ipc(["set_property", "time-pos", position_sec])

def next_track(self):
    with self._state_lock:
        vid = self.current_video_id
        q = list(self._current_queue)
        
    # 1. Use existing queue if we have one
    if q:
        next_track = q[0]
        self._current_queue = q[1:]
        self.send_response({"type": "queue_updated", "queue": self._current_queue})
        self._is_auto_advancing = True
        self.play(next_track["videoId"], next_track["title"], next_track["artist"], next_track["artUrl"])
        return

    # 2. Queue empty — auto-fetch more similar songs (radio mode)
    if vid:
        self.log("Queue empty on next_track, fetching radio...")
        threading.Thread(target=self._auto_continue, args=(vid,), daemon=True).start()

def _auto_continue(self, seed_video_id, title=None, artist=None, art_url=None):
    """Fetch radio tracks for seed_video_id, populate queue, and play the first one."""
    try:
        self.send_response({"type": "queue_fetching"})
        self.log(f"Auto-continue: fetching radio for {seed_video_id}")
        data = self.ytm.get_watch_playlist(videoId=seed_video_id, limit=20)
        tracks = data.get("tracks", [])
        queue = []

        for item in tracks:
            vid = self._item_video_id(item)
            if not vid or vid == seed_video_id:
                continue

            artist_name = "Unknown"
            artists_list = item.get("artists", [])
            if isinstance(artists_list, list) and artists_list:
                artist_name = artists_list[0].get("name", "Unknown")

            queue.append({
                "videoId": vid,
                "title": item.get("title", "Unknown"),
                "artist": artist_name,
                "artUrl": self._extract_art_url(item),
                "duration": self._extract_duration(item) or ""
            })

        if queue:
            first = queue[0]
            with self._state_lock:
                self._current_queue = queue[1:]
            self.send_response({"type": "queue_updated", "queue": self._current_queue})
            self.log(f"Auto-continue: playing {first['title']}, {len(self._current_queue)} more in queue")
            self._is_auto_advancing = True
            self.play(first["videoId"], first["title"], first["artist"], first["artUrl"])
        else:
            self.log("Auto-continue: no tracks found, stopping.")
            self.mpris.update("Stopped")
            self.send_response({"type": "playback_stopped"})
    except Exception as e:
        self.log(f"Auto-continue failed: {e}")
        self.mpris.update("Stopped")
        self.send_response({"type": "playback_stopped"})

def prev_track(self):
    with self._state_lock:
        vid = self.current_video_id
    if not vid:
        return
    if len(self._play_stack) >= 2:
        self._play_stack.pop()  # remove current
        prev_id = self._play_stack[-1]
        try:
            s = self.ytm.get_song(prev_id)
            d = s.get("videoDetails", {})
            self.play(
                prev_id,
                d.get("title", ""),
                d.get("author", ""),
                d.get("thumbnail", {}).get("thumbnails", [{}])[-1].get("url", ""),
            )
        except Exception:
            pass

# ── home / search ─────────────────────────────────────────────────────────
def _fetch_queue_task(self, video_id):
    try:
        self.send_response({"type": "queue_fetching"})
        self.log(f"Fetching radio queue for: {video_id}")
        data = self.ytm.get_watch_playlist(videoId=video_id, limit=20)
        tracks = data.get("tracks", [])
        queue = []
        
        # Skip the currently playing track (usually first)
        for item in tracks:
            vid = self._item_video_id(item)
            if not vid or vid == video_id:
                continue
                
            artist_name = "Unknown"
            artists_list = item.get("artists", [])
            if isinstance(artists_list, list) and artists_list:
                artist_name = artists_list[0].get("name", "Unknown")
                
            queue.append({
                "videoId": vid,
                "title": item.get("title", "Unknown"),
                "artist": artist_name,
                "artUrl": self._extract_art_url(item),
                "duration": self._extract_duration(item) or ""
            })
            
        with self._state_lock:
            self._current_queue = queue
            
        self.send_response({"type": "queue_updated", "queue": self._current_queue})
        self.log(f"Queue updated with {len(self._current_queue)} tracks")
    except Exception as e:
        self.log(f"Failed to fetch radio queue: {e}")

def fetch_playlist(self, video_id):
    try:
        data = self.ytm.get_watch_playlist(videoId=video_id, limit=20)
        return data.get("tracks", [])
    except Exception:
        return []

