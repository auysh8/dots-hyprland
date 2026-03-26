import os
import re
import json
import time
import hashlib
import urllib.request
import threading
import subprocess
import shutil
import socket
import sys
from cache_manager import CacheManager
from lyrics_fetcher import LyricsSyncEngine, fetch_lyrics


class Player:
    def __init__(self, send_response_callback, logger, api=None, mpris_server=None):
        self.api = api
        self.mpris = mpris_server
        self.send_response = send_response_callback
        self.log = logger

        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self.ipc_socket = os.path.join(runtime_dir, f"mpv_music_{os.getuid()}.sock")

        self.mpv_process = None
        self._ytdlp_proc = None

        self.current_video_id = None
        self._state_lock = threading.Lock()
        self._playback_token = 0

        self.repeat_mode = 0
        self._stream_cache = {}

        cache_base = os.path.expanduser("~/.cache/quickshell/music")
        max_cache_mb = float(os.environ.get("MUSIC_CACHE_SIZE_MB", "500"))
        self.cache = CacheManager(cache_base, max_size_mb=max_cache_mb, logger=self.log)
        self.log(f"Cache initialized: {max_cache_mb}MB limit at {cache_base}")
        self.cache.cleanup_orphans()
        stats = self.cache.get_stats()
        self.log(f"Cache status: {stats['art_count']} art, {stats['audio_count']} audio, {stats['total_size_mb']:.1f}MB / {stats['max_size_mb']:.0f}MB")

        self._play_stack = []
        self._current_queue = []
        self._current_title = ""
        self._current_artist = ""
        self._current_art = ""
        self._current_art_url = ""
        self._is_auto_advancing = False

        # Independent lyrics engine — completely isolated from global LyricsService
        self._lyrics_engine = LyricsSyncEngine(self.send_response)

    def _sigterm_handler(self, signum, frame):
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

    def _resolve_ytdlp_path(self):
        local = os.path.join(os.path.dirname(os.path.abspath(__file__)), "venv", "bin", "yt-dlp")
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
        if video_id in self._play_stack:
            self._play_stack.remove(video_id)
        self._play_stack.append(video_id)
        if len(self._play_stack) > 20:
            self._play_stack = self._play_stack[-20:]

    def play(self, video_id, title, artist, art_url, queue_tracks=None):
        """
        Play a song with optional queue.
        
        Args:
            video_id: YouTube video ID
            title: Song title
            artist: Artist name
            art_url: Album art URL
            queue_tracks: List of track dicts to add to queue (optional)
        """
        self.log(f"Playing: {title} by {artist}")
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
        
        self.send_response({"type": "track_loading", "videoId": video_id, "title": title, "artist": artist, "artUrl": art_url})
        with self._state_lock:
            self._playback_token += 1
            token = self._playback_token
        threading.Thread(target=self._play_task, args=(video_id, title, artist, art_url, token, is_auto), daemon=True).start()

    def _prefetch_stream_url(self, video_id):
        if video_id in self._stream_cache:
            return
        self.log(f"Background prefetching next URL for gapless playback: {video_id}")
        try:
            ytdlp = self._resolve_ytdlp_path()
            result = subprocess.run([ytdlp, "-f", "bestaudio", "-g", "--no-warnings", f"https://music.youtube.com/watch?v={video_id}"], capture_output=True, text=True, check=True, timeout=30)
            stream_url = result.stdout.strip().split("\n")[-1].strip()
            if stream_url:
                with self._state_lock:
                    self._stream_cache[video_id] = stream_url
                self.log(f"Gapless URL ready for {video_id}")
        except Exception as e:
            self.log(f"Failed gapless prefetch: {e}")

    def _play_task(self, video_id, title, artist, art_url, token, is_auto=False):
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
                    stream_url = self._stream_cache.pop(video_id, None)
                if stream_url:
                    self.log(f"Using pre-fetched gapless URL")
                    self.cache.start_audio_cache_download(video_id, stream_url, title)
                else:
                    self.log("Fetching stream URL...")
                    ytdlp = self._resolve_ytdlp_path()
                    proc = subprocess.Popen([ytdlp, "-f", "bestaudio", "-g", "--no-warnings", f"https://music.youtube.com/watch?v={video_id}"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    self._ytdlp_proc = proc
                    stdout, _ = proc.communicate(timeout=30)
                    self._ytdlp_proc = None
                    if proc.returncode != 0:
                        raise ValueError(f"yt-dlp exited with code {proc.returncode}")
                    stream_url = stdout.strip().split("\n")[-1].strip()
                    self.log(f"Stream URL fetched")
                    self.cache.start_audio_cache_download(video_id, stream_url, title)

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

            # Removed automatic radio queue fetching to respect user intent (empty queue for standalone songs)

            self._cleanup_socket()
            cmd = ["mpv", "--no-video", "--no-terminal", "--really-quiet", "--no-config", "--load-scripts=no", f"--input-ipc-server={self.ipc_socket}", f"--force-media-title={title} • {artist}", stream_url]
            self.log(f"Launching mpv...")
            process = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.log(f"mpv PID: {process.pid}")

            with self._state_lock:
                if self._playback_token != token:
                    process.kill()
                    return
                self.mpv_process = process
                self.current_video_id = video_id

            self.log("mpv launched — playback started")

            with self._state_lock:
                next_id = video_id if self.repeat_mode == 2 else (self._current_queue[0].get("videoId") if self._current_queue else None)
            if next_id:
                threading.Thread(target=self._prefetch_stream_url, args=(next_id,), daemon=True).start()

            def _deferred_art_download():
                if art_url and not art_file_path:
                    try:
                        req = urllib.request.Request(art_url, headers={"User-Agent": "Mozilla/5.0"})
                        with urllib.request.urlopen(req, timeout=8) as r:
                            image_data = r.read()
                        cached_path = self.cache.cache_art(art_url, image_data)
                        if cached_path:
                            self.send_response({"type": "art_downloaded", "videoId": video_id, "path": cached_path})
                            self.mpris.update(status="Playing", title=title, artist=artist, art_local_path=cached_path, video_id=video_id, art_url=art_url)
                    except Exception as e:
                        self.log(f"Art download failed: {e}")
                elif art_file_path:
                    self.send_response({"type": "art_downloaded", "videoId": video_id, "path": art_file_path})
                    self.mpris.update(status="Playing", title=title, artist=artist, art_local_path=art_file_path, video_id=video_id, art_url=art_url)
            threading.Thread(target=_deferred_art_download, daemon=True).start()

            self.send_response({"type": "playback_started", "videoId": video_id, "title": title, "artist": artist, "artUrl": art_url, "artLocalPath": art_file_path or "", "isLiked": False})

            def _fetch_canvas():
                try:
                    # Check cache first
                    cached_canvas = self.cache.get_canvas(video_id)
                    if cached_canvas and cached_canvas.get("url"):
                        self.log(f"Canvas cache HIT for '{title}'")
                        with self._state_lock:
                            if self._playback_token == token:
                                self.send_response({"type": "canvas_url", "videoId": video_id, "url": cached_canvas["url"], "isAnimated": cached_canvas.get("isAnimated", False)})
                        return

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
                                # Cache the result
                                cache_entry = {"url": canvas_url, "isAnimated": bool(canvas_data.get("animated")), "ts": time.time()}
                                self.cache.cache_canvas(video_id, cache_entry)
                                self.log(f"Canvas cached for '{title}'")
                                with self._state_lock:
                                    if self._playback_token == token:
                                        self.send_response({"type": "canvas_url", "videoId": video_id, "url": canvas_url, "isAnimated": bool(canvas_data.get("animated"))})
                                break
                    else:
                        self.log(f"No canvas found for '{title}'")
                except Exception as e:
                    self.log(f"Canvas fetch error: {e}")
            threading.Thread(target=_fetch_canvas, daemon=True).start()

            self.mpris.publish()
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
                        self.mpris._cached_duration = int(float(dur) * 1_000_000)
                        self.mpris.update(status="Playing", title=title, artist=artist, art_local_path=art_file_path or "", video_id=video_id, art_url=art_url)
                        self.send_response({"type": "playback_duration", "durationSec": int(float(dur))})
                        break
            threading.Thread(target=_wait_for_duration, daemon=True).start()

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
                        pos_f = float(pos)
                        self.send_response({"type": "playback_progress", "positionSec": int(pos_f), "durationSec": int(float(dur)) if dur else 0})
                        self._lyrics_engine.set_position(pos_f)
            threading.Thread(target=_poll_position, daemon=True).start()

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
                    if self.repeat_mode == 2:
                        self.log(f"Repeat One: Replaying {title}")
                        self.play(video_id, title, artist, art_url)
                        return
                    if self._current_queue:
                        next_track = self._current_queue[0]
                        if self.repeat_mode == 1:
                            self._current_queue.append({"videoId": video_id, "title": title, "artist": artist, "artUrl": art_url})
                            self._current_queue.pop(0)
                        else:
                            self._current_queue.pop(0)
                        self.send_response({"type": "queue_updated", "queue": self._current_queue})
                        self.log(f"Auto-advancing to: {next_track['title']}")
                        self._is_auto_advancing = True
                        self.play(next_track["videoId"], next_track["title"], next_track["artist"], next_track["artUrl"], self._current_queue)
                    else:
                        if self.repeat_mode == 1:
                            self.play(video_id, title, artist, art_url)
                        else:
                            # Queue empty - stop playback, don't auto-fetch radio
                            self.log("Queue empty, stopping playback")
                            self.mpris.update("Stopped")
                            self.send_response({"type": "playback_stopped"})
            threading.Thread(target=_monitor, daemon=True).start()

        except subprocess.CalledProcessError as e:
            self.log(f"yt-dlp error: {e.stderr}")
            self.send_response({"type": "error", "message": f"yt-dlp failed: {e.stderr}"})
        except Exception as e:
            import traceback
            self.log(f"Play task error: {e}\n{traceback.format_exc()}")
            self.send_response({"type": "error", "message": str(e)})

    def _ipc(self, command):
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
        self._lyrics_engine.clear()
        self.mpris.update("Stopped")
        self.mpris.unpublish()
        if notify:
            self.send_response({"type": "playback_stopped"})

    def pause(self):
        if self._ipc(["set_property", "pause", True]):
            self.mpris.update("Paused", title=self._current_title, artist=self._current_artist, art_local_path=self._current_art, video_id=self.current_video_id or "", art_url=self._current_art_url)
            self.send_response({"type": "playback_paused"})

    def resume(self):
        if self._ipc(["set_property", "pause", False]):
            self.mpris.update("Playing", title=self._current_title, artist=self._current_artist, art_local_path=self._current_art, video_id=self.current_video_id or "", art_url=self._current_art_url)
            self.send_response({"type": "playback_resumed"})

    def seek(self, position_sec):
        if self.mpv_process:
            self._ipc(["set_property", "time-pos", position_sec])

    def next_track(self):
        """Go to next track in queue. Does nothing if queue is empty."""
        with self._state_lock:
            q = list(self._current_queue)
        if q:
            next_track = q[0]
            remaining_queue = q[1:]
            self._current_queue = remaining_queue
            self.send_response({"type": "queue_updated", "queue": self._current_queue})
            self._is_auto_advancing = True
            # Pass the remaining queue to play() so it doesn't get wiped out!
            self.play(next_track["videoId"], next_track["title"], next_track["artist"], next_track["artUrl"], remaining_queue)
        # If queue is empty, do nothing (no auto-radio)

    def populate_radio_queue(self, video_id=None):
        """
        Populate queue with radio songs based on current or specified track.
        
        Args:
            video_id: Video ID to base radio on (uses current_video_id if not provided)
        """
        if video_id is None:
            video_id = self.current_video_id
        if not video_id:
            self.log("No video ID for radio")
            return
        
        try:
            self.send_response({"type": "queue_fetching"})
            self.log(f"Fetching radio for: {video_id}")
            data = self.api.ytm.get_watch_playlist(videoId=video_id, limit=20)
            tracks = data.get("tracks", [])
            queue = []
            for item in tracks:
                vid = item.get("videoId")
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
            self.log(f"Radio queue populated with {len(self._current_queue)} tracks")
        except Exception as e:
            self.log(f"Radio fetch failed: {e}")
            self.send_response({"type": "error", "message": "Failed to fetch radio"})

    def _auto_continue(self, seed_video_id):
        try:
            self.send_response({"type": "queue_fetching"})
            self.log(f"Auto-continue: fetching radio for {seed_video_id}")
            data = self.api.ytm.get_watch_playlist(videoId=seed_video_id, limit=20)
            tracks = data.get("tracks", [])
            queue = []
            for item in tracks:
                vid = item.get("videoId")
                if not vid or vid == seed_video_id:
                    continue
                artist_name = "Unknown"
                artists_list = item.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    artist_name = artists_list[0].get("name", "Unknown")
                queue.append({"videoId": vid, "title": item.get("title", "Unknown"), "artist": artist_name, "artUrl": self._extract_art_url(item), "duration": self._extract_duration(item) or ""})
            if queue:
                first = queue[0]
                with self._state_lock:
                    self._current_queue = queue[1:]
                self.send_response({"type": "queue_updated", "queue": self._current_queue})
                self.log(f"Auto-continue: playing {first['title']}, {len(self._current_queue)} more")
                self._is_auto_advancing = True
                self.play(first["videoId"], first["title"], first["artist"], first["artUrl"])
            else:
                self.log("Auto-continue: no tracks found")
                self.mpris.update("Stopped")
                self.send_response({"type": "playback_stopped"})
        except Exception as e:
            self.log(f"Auto-continue failed: {e}")
            self.mpris.update("Stopped")
            self.send_response({"type": "playback_stopped"})

    def prev_track(self):
        with self._state_lock:
            vid = self.current_video_id
        if not vid or len(self._play_stack) < 2:
            return
        self._play_stack.pop()
        prev_id = self._play_stack[-1]
        try:
            s = self.api.ytm.get_song(prev_id)
            d = s.get("videoDetails", {})
            self.play(prev_id, d.get("title", ""), d.get("author", ""), d.get("thumbnail", {}).get("thumbnails", [{}])[-1].get("url", ""))
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
                artist_name = "Unknown"
                artists_list = item.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    artist_name = artists_list[0].get("name", "Unknown")
                queue.append({"videoId": vid, "title": item.get("title", "Unknown"), "artist": artist_name, "artUrl": self._extract_art_url(item), "duration": self._extract_duration(item) or ""})
            with self._state_lock:
                self._current_queue = queue
            self.send_response({"type": "queue_updated", "queue": self._current_queue})
            self.log(f"Queue updated with {len(self._current_queue)} tracks")
        except Exception as e:
            self.log(f"Failed to fetch queue: {e}")

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
