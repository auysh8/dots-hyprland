#!/usr/bin/env python3
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from lyrics_fetcher import LyricsSyncEngine, fetch_lyrics

class Player:
    """Handles audio playback using mpv and track fetching using yt-dlp."""

    def __init__(self, send_response_callback, logger):
        self.send_response = send_response_callback
        self.log = logger
        self.mpv_process = None
        self.ipc_socket = "/tmp/quickshell-music-mpv.sock"
        self._playback_token = 0
        self._state_lock = threading.RLock()

        # Internal state
        self.current_video_id = None
        self._current_queue = []
        self._play_stack = []  # Stack of video IDs for 'back' functionality
        self.repeat_mode = 0  # 0: None, 1: All, 2: One
        self.shuffle_mode = False
        
        # Audio cache reference (will be set by backend)
        self.cache = None
        self.api = None
        self.mpris = None
        
        # Stream URL cache for gapless playback: {video_id: (url, expiry_timestamp)}
        self._stream_cache = {}
        self._ytdlp_proc = None

        # Tracks video IDs currently being downloaded to avoid duplicates
        self._active_downloads = set()
        self._download_lock = threading.Lock()

        # Independent lyrics engine
        self._lyrics_engine = LyricsSyncEngine(self.send_response)

    def _sigterm_handler(self, signum, frame):
        self.log(f"Received signal {signum}, stopping player...")
        self.stop()
        sys.exit(0)

    def _resolve_ytdlp_path(self):
        # Prefer venv version if it exists
        venv_ytdlp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "venv", "bin", "yt-dlp")
        if os.path.exists(venv_ytdlp):
            return venv_ytdlp
        return "yt-dlp"

    def stop(self, notify=True):
        with self._state_lock:
            self._playback_token += 1
            if self.mpv_process:
                try:
                    # Try to close gracefully first
                    self._ipc_send({"command": ["quit"]})
                    # Give it a tiny bit to close
                    time.sleep(0.05)
                    if self.mpv_process.poll() is None:
                        self.mpv_process.terminate()
                except Exception:
                    pass
                self.mpv_process = None
            self.current_video_id = None
            self._cleanup_socket()
            
        self._lyrics_engine.clear()
        
        if getattr(self, "mpris", None):
            self.mpris.set_status("Stopped")
        if notify:
            self.send_response({"type": "playback_stopped"})

    def pause(self):
        self._ipc_send({"command": ["set_property", "pause", True]})
        if getattr(self, "mpris", None):
            self.mpris.set_status("Paused")
        self.send_response({"type": "playback_paused"})

    def resume(self):
        self._ipc_send({"command": ["set_property", "pause", False]})
        if getattr(self, "mpris", None):
            self.mpris.set_status("Playing")
        self.send_response({"type": "playback_resumed"})

    def seek(self, position_sec):
        self._ipc_send({"command": ["set_property", "time-pos", position_sec]})
        if getattr(self, "mpris", None):
            self.mpris.emit_seeked(int(position_sec * 1_000_000))

    def set_repeat(self, mode):
        # mode: 0 (Off), 1 (All), 2 (One)
        self.repeat_mode = int(mode)
        self.log(f"Repeat mode set to: {self.repeat_mode}")

    def play(self, video_id, title, artist, art_url, queue_tracks=None, artist_id="", album_id=""):
        """
        Play a song with optional queue.
        
        Args:
            video_id: YouTube video ID
            title: Song title
            artist: Artist name
            art_url: Album art URL
            queue_tracks: List of track dicts to add to queue (optional)
            artist_id: Artist browse/channel ID
            album_id: Album browse ID
        """
        self.log(f"Playing: {title} by {artist} (artist_id={artist_id}, album_id={album_id})")
        if art_url:
            if "=w" in art_url and "-h" in art_url:
                art_url = re.sub(r"=w\d+-h\d+", "=w544-h544", art_url)
            elif "googleusercontent.com" in art_url and "=s" in art_url:
                art_url = re.sub(r"=s\d+", "=s544", art_url)
        self._push_play_stack(video_id)
        is_auto = getattr(self, "_is_auto_advancing", False)
        self._is_auto_advancing = False
        
        # Kill any in-flight yt-dlp fetch
        try:
            if self._ytdlp_proc and self._ytdlp_proc.poll() is None:
                self._ytdlp_proc.kill()
                self._ytdlp_proc = None
        except Exception:
            pass
        
        # Clear queue when playing new song (unless queue explicitly provided or auto-advancing)
        self.stop(notify=False)
        with self._state_lock:
            if queue_tracks is not None:
                self._current_queue = list(queue_tracks)
                self.log(f"Queue set with {len(self._current_queue)} tracks")
                self.send_response({"type": "queue_updated", "queue": self._current_queue})
            elif not is_auto:
                self._current_queue = []
                self.log("Queue cleared (manual standalone play)")
                self.send_response({"type": "queue_updated", "queue": []})
        
        self.send_response({"type": "track_loading", "videoId": video_id, "title": title, "artist": artist, "artistId": artist_id, "albumId": album_id, "artUrl": art_url})
        with self._state_lock:
            self._playback_token += 1
            token = self._playback_token
        threading.Thread(target=self._play_task, args=(video_id, title, artist, art_url, token, is_auto, artist_id, album_id), daemon=True).start()

    def _prefetch_stream_url(self, video_id, title=""):
        # Check cache with TTL — HLS URLs are valid ~6 hours
        with self._state_lock:
            cached = self._stream_cache.get(video_id)
            if cached and cached[1] > time.time():
                return  # Still valid
        self.log(f"Background prefetching next URL for gapless playback: {video_id}")
        try:
            ytdlp = self._resolve_ytdlp_path()
            cmd = [
                ytdlp, "-f", "bestaudio/best", "-g", "--no-warnings",
                "--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "--extractor-args", "youtube:player_client=android_music",
                f"https://music.youtube.com/watch?v={video_id}"
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=30)
            stream_url = result.stdout.strip().split("\n")[-1].strip()
            if stream_url:
                expiry = time.time() + 6 * 3600  # HLS URLs valid ~6h
                with self._state_lock:
                    self._stream_cache[video_id] = (stream_url, expiry)
                self.log(f"Gapless URL ready for {video_id}")

                # Also pre-cache audio for the next track if not already cached
                if self.cache and not self.cache.get_audio_path(video_id):
                    threading.Thread(
                        target=self._download_audio_to_cache,
                        args=(video_id, title or video_id),
                        daemon=True,
                    ).start()
        except Exception as e:
            self.log(f"Failed gapless prefetch: {e}")

    def _download_audio_to_cache(self, video_id: str, title: str):
        """Download audio for a video_id to the local cache using a fresh independent yt-dlp session."""
        with self._download_lock:
            if video_id in self._active_downloads:
                return  # Already in progress
            self._active_downloads.add(video_id)
        try:
            if self.cache.get_audio_path(video_id):
                return  # Already cached

            dest_path = self.cache.prepare_audio_download_path(video_id)
            ytdlp = self._resolve_ytdlp_path()
            self.log(f"[Cache] Downloading audio for: {title} ({video_id})")

            # Determine audio quality settings
            is_high_quality = getattr(self, "settings", {}).get("high_audio_quality", True)
            quality_arg = "0" if is_high_quality else "9"
            format_arg = "bestaudio[ext=m4a]/bestaudio/best" if is_high_quality else "worstaudio[ext=m4a]/worstaudio/worst"

            cmd = [
                ytdlp,
                "-f", format_arg,
                "--no-warnings", "--no-playlist",
                "--extract-audio", "--audio-format", "m4a",
                "--audio-quality", quality_arg,
                "--user-agent", "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36",
                "--extractor-args", "youtube:player_client=android_music",
                "--output", dest_path,
                f"https://music.youtube.com/watch?v={video_id}",
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if result.returncode == 0:
                ok = self.cache.register_downloaded_audio(video_id, dest_path)
                if ok:
                    self.log(f"[Cache] Audio cached: {title} ({video_id})")
                else:
                    self.log(f"[Cache] Download ok but file missing/small for: {title}")
            else:
                self.log(f"[Cache] yt-dlp download failed (rc={result.returncode}): {result.stderr[:200]}")
        except subprocess.TimeoutExpired:
            self.log(f"[Cache] Download timed out for: {title}")
        except Exception as e:
            self.log(f"[Cache] Download error for {title}: {e}")
        finally:
            with self._download_lock:
                self._active_downloads.discard(video_id)

    def _play_task(self, video_id, title, artist, art_url, token, is_auto=False, artist_id="", album_id=""):
        self.log(f"[PLAY_TASK] Starting for: {title} ({video_id}) token={token}")
        try:
            time.sleep(0.25)
            self.log(f"[PLAY_TASK] After debounce")
            with self._state_lock:
                if self._playback_token != token:
                    self.log(f"[PLAY_TASK] Aborted: token mismatch")
                    return

            if video_id and (video_id.startswith("OLAK") or video_id.startswith("PL") or video_id.startswith("VL")):
                self.log(f"Resolving playlist/album: {video_id}")
                try:
                    p_data = self.api.ytm.get_watch_playlist(playlistId=video_id, limit=1).get("tracks", [])
                    if p_data and p_data[0].get("videoId"):
                        video_id = p_data[0].get("videoId")
                        self.log(f"Resolved to: {video_id}")
                except Exception as e:
                    self.log(f"Failed to resolve: {e}")

            cached_audio_path = self.cache.get_audio_path(video_id)
            stream_url = None

            if cached_audio_path:
                self.log(f"Using cached audio: {title}")
                stream_url = f"file://{cached_audio_path}"
            else:
                with self._state_lock:
                    cached_entry = self._stream_cache.pop(video_id, None)
                # Unwrap tuple (url, expiry) — discard if expired
                if cached_entry and cached_entry[1] > time.time():
                    stream_url = cached_entry[0]
                else:
                    stream_url = None
                cmd = [
                    self._resolve_ytdlp_path(), "-f", "bestaudio/best", "-g", "--no-warnings",
                    "--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "--extractor-args", "youtube:player_client=android_music",
                    f"https://music.youtube.com/watch?v={video_id}"
                ]

                if stream_url:
                    self.log(f"Using pre-fetched gapless URL")

                else:
                    self.log("Fetching stream URL...")
                    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    self._ytdlp_proc = proc
                    stdout, stderr = proc.communicate(timeout=30)
                    self._ytdlp_proc = None
                    
                    with self._state_lock:
                        if self._playback_token != token:
                            self.log("Aborted after stream fetch (superseded)")
                            return

                    if proc.returncode != 0:
                        self.log(f"yt-dlp error: {stderr}")
                        raise ValueError(f"yt-dlp exited with code {proc.returncode}")
                        
                    stream_url = stdout.strip().split("\n")[-1].strip()
                    self.log(f"Stream URL fetched")



                with self._state_lock:
                    if self._playback_token != token:
                        self.log("Aborted after stream fetch")
                        return

            if not stream_url:
                raise ValueError("No stream URL")
            self.log("Stream URL obtained - continuing...")

            try:
                self.log(f"Getting art cache for: {art_url[:50] if art_url else 'None'}")
                art_file_path = self.cache.get_art_path(art_url) if art_url else None
                self.log(f"Art cache result: {'HIT' if art_file_path else 'MISS'}")
            except Exception as e:
                import traceback
                self.log(f"Art cache ERROR: {e}")
                self.log(traceback.format_exc())
                art_file_path = None

            self.log("Setting metadata...")
            self._current_title = title
            self._current_artist = artist
            self._current_art = art_file_path or ""
            self._current_art_url = art_url
            self.log("Metadata set")

            with self._state_lock:
                if self._playback_token != token:
                    return

            self._cleanup_socket()
            mpv_cmd = [
                "mpv", "--no-video", "--no-terminal", "--really-quiet",
                "--no-config", "--load-scripts=no", "--keep-open=yes",
                f"--input-ipc-server={self.ipc_socket}",
                "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                f"--force-media-title={title} \u2022 {artist}",
                stream_url,
            ]
            self.log(f"Launching mpv...")
            process = subprocess.Popen(mpv_cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            self.log(f"mpv PID: {process.pid}")

            with self._state_lock:
                if self._playback_token != token:
                    process.kill()
                    return
                self.mpv_process = process
                self.current_video_id = video_id

            self.log("mpv launched — playback started")

            with self._state_lock:
                next_track = None if self.repeat_mode == 2 else (self._current_queue[0] if self._current_queue else None)
                next_id = video_id if self.repeat_mode == 2 else (next_track.get("videoId") if next_track else None)
                next_title = next_track.get("title", next_id or "") if next_track else (title if self.repeat_mode == 2 else "")
            if next_id:
                threading.Thread(target=self._prefetch_stream_url, args=(next_id, next_title), daemon=True).start()


            def _deferred_art_download():
                if not art_file_path and art_url:
                    try:
                        import urllib.request
                        req = urllib.request.Request(art_url, headers={"User-Agent": "Mozilla/5.0"})
                        with urllib.request.urlopen(req, timeout=15) as response:
                            cached_path = self.cache.cache_art(art_url, response.read())
                        if cached_path:
                            self.send_response({"type": "art_downloaded", "videoId": video_id, "path": cached_path})
                            self.mpris.update(status="Playing", title=title, artist=artist, art_local_path=cached_path, video_id=video_id, art_url=art_url)
                    except Exception as e:
                        self.log(f"Art download failed: {e}")
                elif art_file_path:
                    self.send_response({"type": "art_downloaded", "videoId": video_id, "path": art_file_path})
                    self.mpris.update(status="Playing", title=title, artist=artist, art_local_path=art_file_path, video_id=video_id, art_url=art_url)
            threading.Thread(target=_deferred_art_download, daemon=True).start()

            # ── Deferred audio caching ─────────────────────────────────────────
            # Skip if this is already a cached playback (file:// URL)
            is_live_stream = not stream_url.startswith("file://")
            if is_live_stream:
                def _deferred_audio_cache():
                    # Wait 30s — if user skips before then, abort
                    time.sleep(30)
                    with self._state_lock:
                        if self._playback_token != token:
                            return  # Song was skipped
                    if self.cache.get_audio_path(video_id):
                        return  # Already cached by now
                    threading.Thread(
                        target=self._download_audio_to_cache,
                        args=(video_id, title),
                        daemon=True,
                    ).start()
                threading.Thread(target=_deferred_audio_cache, daemon=True).start()

            self.send_response({"type": "playback_started", "videoId": video_id, "title": title, "artist": artist, "artistId": artist_id, "albumId": album_id, "artUrl": art_url, "artLocalPath": art_file_path or "", "isLiked": False})

            def _fetch_lyrics():
                try:
                    lyrics, source = fetch_lyrics(title, artist, duration=0)
                    with self._state_lock:
                        if self._playback_token != token:
                            return
                    self._lyrics_engine.load(lyrics or [], source, token)
                except Exception as e:
                    self.log(f"Lyrics fetch error: {e}")
            threading.Thread(target=_fetch_lyrics, daemon=True).start()

            def _fetch_canvas():
                try:
                    # 1. Check for local video cache first (Smoothest)
                    local_canvas_path = self.cache.get_canvas_video_path(video_id)
                    if local_canvas_path:
                        self.log(f"Local canvas HIT for '{title}'")
                        with self._state_lock:
                            if self._playback_token == token:
                                self.send_response({
                                    "type": "canvas_url", 
                                    "videoId": video_id, 
                                    "url": f"file://{local_canvas_path}", 
                                    "isAnimated": True
                                })
                        return

                    # 2. Check for cached URL
                    cached_canvas = self.cache.get_canvas(video_id)
                    if cached_canvas and cached_canvas.get("url"):
                        self.log(f"Canvas URL cache HIT for '{title}'")
                        canvas_url = cached_canvas["url"]
                        is_animated = cached_canvas.get("isAnimated", False)
                        
                        # Start background download for next time
                        if is_animated:
                            self.cache.start_canvas_cache_download(video_id, canvas_url, title)
                            
                        with self._state_lock:
                            if self._playback_token == token:
                                self.send_response({
                                    "type": "canvas_url", 
                                    "videoId": video_id, 
                                    "url": canvas_url, 
                                    "isAnimated": is_animated
                                })
                        return

                    # 3. Fetch from scrapers
                    self.log(f"Canvas cache MISS for '{title}', fetching...")
                    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "canvas_fetcher.py")
                    python = os.path.join(os.path.dirname(os.path.abspath(__file__)), "venv", "bin", "python3")
                    if not os.path.exists(python):
                        python = sys.executable
                    for sf in ["us", "gb", "au", "ca"]:
                        cmd = [python, script, title, artist, "", sf]
                        result = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
                        if result.returncode == 0 and result.stdout.strip():
                            canvas_data = json.loads(result.stdout.strip())
                            canvas_url = canvas_data.get("videoUrl") or canvas_data.get("animated")
                            if canvas_url:
                                is_animated = bool(canvas_data.get("animated"))
                                # Cache the URL result
                                cache_entry = {"url": canvas_url, "isAnimated": is_animated, "ts": time.time()}
                                self.cache.cache_canvas(video_id, cache_entry)
                                
                                # Start background download
                                if is_animated:
                                    self.cache.start_canvas_cache_download(video_id, canvas_url, title)
                                    
                                self.log(f"Canvas cached for '{title}'")
                                with self._state_lock:
                                    if self._playback_token == token:
                                        self.send_response({
                                            "type": "canvas_url", 
                                            "videoId": video_id, 
                                            "url": canvas_url, 
                                            "isAnimated": is_animated
                                        })
                                break
                    else:
                        self.log(f"No canvas found for '{title}'")
                except Exception as e:
                    self.log(f"Canvas fetch error: {e}")
            threading.Thread(target=_fetch_canvas, daemon=True).start()

            self.mpris.publish()
            if getattr(self, "mpris", None):
                self.mpris.emit_seeked(0)
            self.mpris.update(status="Playing", title=title, artist=artist, art_local_path=art_file_path or "", video_id=video_id, art_url=art_url)

            def _sync_history():
                try:
                    if os.path.exists(self.api.oauth_path) or os.path.exists(self.api.headers_path):
                        self.log(f"Syncing '{title}' to history...")
                        song_data = self.api.ytm.get_song(video_id)
                        if song_data and getattr(self.api.ytm, 'add_history_item', None):
                            self.api.ytm.add_history_item(song_data)
                            self.log("History sync OK")
                except Exception as e:
                    self.log(f"History sync failed: {e}")
            threading.Thread(target=_sync_history, daemon=True).start()

            def _wait_for_duration():
                for _ in range(20):
                    time.sleep(0.5)
                    if not self.mpv_process:
                        break
                    dur = self._ipc_get("duration")
                    if dur is not None:
                        self.log(f"Duration: {dur}s")
                        self.send_response({"type": "playback_duration", "durationSec": int(dur)})
                        break
            threading.Thread(target=_wait_for_duration, daemon=True).start()

            def _progress_task():
                last_paused = None
                last_dur = None
                while True:
                    with self._state_lock:
                        if self._playback_token != token or not self.mpv_process:
                            break
                    
                    pos = self._ipc_get("time-pos")
                    dur = self._ipc_get("duration")
                    is_paused = self._ipc_get("pause")
                    
                    if is_paused is not None:
                        is_paused_bool = str(is_paused).lower() == 'true'
                        if is_paused_bool != last_paused:
                            last_paused = is_paused_bool
                            if is_paused_bool:
                                self.send_response({"type": "playback_paused"})
                                if getattr(self, "mpris", None):
                                    self.mpris.set_status("Paused")
                            else:
                                self.send_response({"type": "playback_resumed"})
                                if getattr(self, "mpris", None):
                                    self.mpris.set_status("Playing")

                    if pos is not None:
                        self.send_response({"type": "playback_progress", "positionSec": int(float(pos))})
                        self._lyrics_engine.set_position(float(pos))
                        
                        if dur is not None:
                            dur_int = int(float(dur))
                            if dur_int != last_dur and dur_int > 0:
                                last_dur = dur_int
                                self.send_response({"type": "playback_duration", "durationSec": dur_int})
                    
                    # Auto-advance check
                    if pos is not None and dur is not None:
                        pos_f = float(pos)
                        dur_f = float(dur)
                        if dur_f > 0 and pos_f >= (dur_f - 0.5):
                            self.log("End of track detected via progress")
                            self.next_track(is_auto=True)
                            # Do not break here! If queue is empty, next_track seeks to 0 and pauses. 
                            # We must keep polling so the user can hit play again.
                            # If queue has items, next_track calls play(), which changes token and breaks loop naturally.
                            time.sleep(2.0) # Sleep a bit longer to let seek take effect before next poll
                            continue
                            
                    time.sleep(1.0)
            threading.Thread(target=_progress_task, daemon=True).start()

        except Exception as e:
            with self._state_lock:
                if self._playback_token != token:
                    return # Silently exit if thread was intentionally superseded by user

            self.log(f"Play task error: {e}")
            import traceback
            self.log(traceback.format_exc())
            # Ensure the UI gets a stop command so it stops spinning 'loading...' forever
            self.stop(notify=True)

    def next_track(self, is_auto=False):
        with self._state_lock:
            if not self._current_queue:
                self.log("Queue empty, pausing playback at start")
                self.seek(0)
                self.pause()
                return
            
            # If repeat one is on and this is an auto-advance, play same song again
            if is_auto and self.repeat_mode == 2:
                next_track = {
                    "videoId": self.current_video_id,
                    "title": self._current_title,
                    "artist": self._current_artist,
                    "artUrl": self._current_art_url
                }
            else:
                next_track = self._current_queue.pop(0)
                
                # If repeat all is on, push back to end
                if self.repeat_mode == 1:
                    self._current_queue.append(next_track)
            
            self.send_response({"type": "queue_updated", "queue": self._current_queue})

            if len(self._current_queue) <= 3 and self.repeat_mode == 0:
                extension_seed_id = next_track.get("videoId")
                if extension_seed_id:
                    threading.Thread(target=self._extend_queue_task, args=(extension_seed_id,), daemon=True).start()

            self._is_auto_advancing = True
            self.play(next_track["videoId"], next_track.get("title", ""), next_track.get("artist", ""), next_track.get("artUrl", ""), self._current_queue)

    def get_output_device(self):
        try:
            # Get default sink description using pactl
            result = subprocess.run(["pactl", "info"], capture_output=True, text=True, check=True)
            default_sink_name = ""
            for line in result.stdout.split('\n'):
                if "Default Sink:" in line:
                    default_sink_name = line.split(":", 1)[1].strip()
                    break
            
            if default_sink_name:
                result = subprocess.run(["pactl", "list", "sinks"], capture_output=True, text=True, check=True)
                current_sink_section = False
                for line in result.stdout.split('\n'):
                    if f"Name: {default_sink_name}" in line:
                        current_sink_section = True
                    elif current_sink_section and "Description:" in line:
                        description = line.split(":", 1)[1].strip()
                        self.send_response({"type": "output_device", "device": description})
                        return
            
            self.send_response({"type": "output_device", "device": "Unknown"})
        except Exception as e:
            self.log(f"Failed to get output device: {e}")
            self.send_response({"type": "output_device", "device": "Unknown"})

    def prev_track(self):
        # 1. Check if we should restart the current song (if past 3 seconds)
        pos = self._ipc_get("time-pos")
        try:
            pos_f = float(pos) if pos is not None else 0.0
        except ValueError:
            pos_f = 0.0

        if pos_f >= 3.0:
            self.seek(0)
            return

        with self._state_lock:
            vid = self.current_video_id
            if len(self._play_stack) > 1:
                self._play_stack.pop()
                prev_id = self._play_stack[-1]
            else:
                prev_id = None
                
            # Abandoned current track goes back to the absolute front of the queue
            if vid and prev_id:
                abandoned_track = {
                    "videoId": vid,
                    "title": getattr(self, "_current_title", ""),
                    "artist": getattr(self, "_current_artist", ""),
                    "artUrl": getattr(self, "_current_art_url", "")
                }
                self._current_queue.insert(0, abandoned_track)
                self.send_response({"type": "queue_updated", "queue": self._current_queue})

        if not vid or not prev_id:
            self.seek(0)
            return

        try:
            s = self.api.ytm.get_song(prev_id)
            d = s.get("videoDetails", {})
            self.play(prev_id, d.get("title", ""), d.get("author", ""), d.get("thumbnail", {}).get("thumbnails", [{}])[-1].get("url", ""), self._current_queue)
        except Exception:
            pass

    def _fetch_queue_task(self, video_id):
        try:
            self.send_response({"type": "queue_fetching"})
            self.log(f"Fetching radio queue for: {video_id}")
            data = self.api.ytm.get_watch_playlist(videoId=video_id, limit=20)
            tracks = data.get("tracks", [])
            queue = []
            for item in tracks:
                vid = item.get("videoId")
                if not vid or vid == video_id:
                    continue
                queue.append(self.api.format_track_item(item, index_offset=len(queue)))
            
            with self._state_lock:
                self._current_queue = queue
                self.send_response({"type": "queue_updated", "queue": self._current_queue})
            self.log(f"Queue populated with {len(queue)} tracks")
        except Exception as e:
            self.log(f"Failed to fetch queue: {e}")
            self.send_response({"type": "error_toast", "message": "Failed to fetch radio queue.", "icon": "wifi_off"})

    def _extend_queue_task(self, video_id):
        try:
            self.log(f"Extending radio queue from seed: {video_id}")
            data = self.api.ytm.get_watch_playlist(videoId=video_id, limit=20)
            tracks = data.get("tracks", [])
            
            with self._state_lock:
                current_vids = {t.get("videoId") for t in self._current_queue}
                current_vids.add(self.current_video_id)
                for v in self._play_stack:
                    current_vids.add(v)
                
                added = 0
                for item in tracks:
                    vid = item.get("videoId")
                    if not vid or vid in current_vids:
                        continue
                    self._current_queue.append(self.api.format_track_item(item, index_offset=len(self._current_queue)))
                    current_vids.add(vid)
                    added += 1
                
                if added > 0:
                    self.send_response({"type": "queue_updated", "queue": self._current_queue})
                    self.log(f"Queue magically extended by {added} new tracks")
        except Exception as e:
            self.log(f"Failed to dynamically extend queue: {e}")
            self.send_response({"type": "error_toast", "message": "Failed to auto-extend radio.", "icon": "wifi_off"})

    def fetch_playlist(self, video_id):
        try:
            data = self.api.ytm.get_watch_playlist(videoId=video_id, limit=20)
            return data.get("tracks", [])
        except Exception:
            return []

    def _item_video_id(self, item):
        return item.get("videoId") or item.get("playlistId") or item.get("browseId")

    def _extract_art_url(self, item, size=544):
        thumbnails = item.get("thumbnails") or item.get("thumbnail") or []
        if isinstance(thumbnails, dict):
            thumbnails = thumbnails.get("thumbnails", [])
        if isinstance(thumbnails, list) and thumbnails:
            last_thumb = thumbnails[-1]
            art = last_thumb.get("url", "") if isinstance(last_thumb, dict) else ""
        else:
            art = ""
        if art:
            if "=w" in art and "-h" in art:
                art = re.sub(r"=w\d+-h\d+", f"=w{size}-h{size}", art)
            elif "googleusercontent.com" in art and "=s" in art:
                art = re.sub(r"=s\d+", f"=s{size}", art)
        return art

    def _extract_duration(self, item):
        for key in ("duration", "length", "durationText", "lengthText", "timeText"):
            duration = item.get(key)
            if duration:
                return duration
        for key in ("duration_seconds", "durationSeconds", "lengthSeconds"):
            try:
                sec = int(item.get(key, 0))
                if sec > 0:
                    minutes, seconds = divmod(sec, 60)
                    return f"{minutes}:{seconds:02d}"
            except Exception:
                pass
        return ""

    def _push_play_stack(self, video_id):
        if not video_id: return
        with self._state_lock:
            if video_id in self._play_stack:
                self._play_stack.remove(video_id)
            self._play_stack.append(video_id)
            if len(self._play_stack) > 50:
                self._play_stack.pop(0)

    def _cleanup_socket(self):
        if os.path.exists(self.ipc_socket):
            try:
                os.remove(self.ipc_socket)
            except Exception:
                pass

    def _ipc_send(self, data):
        if not self.mpv_process: return None
        try:
            import socket
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(self.ipc_socket)
            client.send((json.dumps(data) + "\n").encode("utf-8"))
            client.close()
        except Exception:
            return None

    def _ipc_get(self, property_name):
        if not self.mpv_process: return None
        try:
            import socket
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.settimeout(0.2)
            client.connect(self.ipc_socket)
            req = {"command": ["get_property", property_name]}
            client.send((json.dumps(req) + "\n").encode("utf-8"))
            resp = client.recv(1024).decode("utf-8")
            client.close()
            data = json.loads(resp.split("\n")[0])
            return data.get("data")
        except Exception:
            return None
