#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from lyrics_fetcher import LyricsSyncEngine, fetch_lyrics
from thumbnail_utils import (
    get_landscape_thumbnail_candidates,
    is_video_track,
    iter_square_art_candidates,
    normalize_square_art_url,
)
from tidal_api import TidalClient
from apple_music_fetcher import AppleMusicCanvasFetcher

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
        
        # Tidal client
        self.tidal = TidalClient(logger)
        
        # Apple Music Fetcher
        self.apple_music = AppleMusicCanvasFetcher(logger)

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

    def play(self, video_id, title, artist, art_url, queue_tracks=None, artist_id="", album_id="", is_liked=False):
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
        art_url = normalize_square_art_url(art_url)
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
        
        # Check if already cached for loading state
        initial_quality = "YouTube Music"
        if self.cache.get_audio_path(video_id):
            initial_quality = "Local Cache"
        elif getattr(self, "settings", {}).get("tidal_lossless", False):
            initial_quality = "Checking Tidal..."

        self.current_video_id = video_id
        self._current_title = title
        self._current_artist = artist
        self._current_art_url = art_url
        self._current_quality = initial_quality

        self.send_response(
            self._build_track_payload(
                "track_loading",
                video_id,
                title,
                artist,
                art_url,
                artist_id=artist_id,
                album_id=album_id,
                quality=initial_quality
            )
        )
        with self._state_lock:
            self._playback_token += 1
            token = self._playback_token
        threading.Thread(
            target=self._play_task,
            args=(video_id, title, artist, art_url, token, is_auto, artist_id, album_id, is_liked),
            daemon=True,
        ).start()



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

                # Pre-cache audio for the next track — only when Tidal is OFF.
                # When Tidal is enabled we don't want a YouTube AAC file saved;
                # the track will play via Tidal FLAC when it actually starts.
                tidal_on = getattr(self, "settings", {}).get("tidal_lossless", False)
                if self.cache and not self.cache.get_audio_path(video_id) and not tidal_on:
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

    def _download_best_art(self, art_url: str, video_id: str = ""):
        if not art_url:
            return None

        import urllib.request

        last_error = None
        for candidate_url in iter_square_art_candidates(art_url):
            try:
                req = urllib.request.Request(candidate_url, headers={"User-Agent": "Mozilla/5.0"})
                with urllib.request.urlopen(req, timeout=15) as response:
                    status = getattr(response, "status", None) or response.getcode()
                    if status != 200:
                        continue

                    content_type = response.headers.get("Content-Type", "")
                    if content_type and not content_type.startswith("image/"):
                        continue

                    image_data = response.read()
                    if len(image_data) < 1024:
                        continue

                    if candidate_url != art_url:
                        self.log(f"Using upgraded thumbnail for {video_id or 'track'}: {candidate_url}")
                    return image_data
            except Exception as e:
                last_error = e

        if last_error:
            raise last_error
        return None

    def _build_track_payload(self, event_type, video_id, title, artist, art_url, *, art_local_path="", artist_id="", album_id="", is_liked=False, quality=""):
        return {
            "type": event_type,
            "videoId": video_id,
            "title": title,
            "artist": artist,
            "artistId": artist_id,
            "albumId": album_id,
            "artUrl": art_url,
            "artLocalPath": art_local_path,
            "isVideoTrack": is_video_track(video_id, art_url),
            "landscapeArtCandidates": get_landscape_thumbnail_candidates(video_id, art_url),
            "isLiked": is_liked,
            "quality": quality,
        }

    def _play_task(self, video_id, title, artist, art_url, token, is_auto=False, artist_id="", album_id="", is_liked_hint=False):
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

            # Smart cache check: use cached Tidal FLAC files but skip stale YouTube AAC.
            # .flac = Tidal-cached lossless  /  .m4a or .webm = YouTube-sourced, skip when Tidal on.
            tidal_enabled = getattr(self, "settings", {}).get("tidal_lossless", False)
            _raw_cache_path = self.cache.get_audio_path(video_id)
            if tidal_enabled and _raw_cache_path and not _raw_cache_path.endswith(".flac"):
                _raw_cache_path = None  # Ignore YouTube AAC/WebM; will use Tidal stream instead
            cached_audio_path = _raw_cache_path
            stream_url = None
            quality = "YouTube Music"
            is_tidal_stream = False

            # Try Tidal if enabled — but not for YouTube video tracks.
            # Video tracks (music videos, live performances) are identified by ytimg.com/vi/ art URLs.
            # They don't exist on Tidal, so searching wastes time and often returns a wrong match.
            if tidal_enabled and is_video_track(video_id, art_url):
                self.log("[Tidal] Skipping '%s' — YouTube video track, not on Tidal" % title)
                tidal_enabled = False
                cached_audio_path = self.cache.get_audio_path(video_id)  # Restore normal cache lookup

            # Track whether this is a YouTube video (music video) track.
            # Used below to avoid bandwidth contention during active streaming.
            _is_video_track = is_video_track(video_id, art_url)

            if tidal_enabled:
                # Use Tidal-cached FLAC if available (skip network resolve)
                if cached_audio_path:
                    self.log(f"[Tidal] Using cached FLAC for: {title}")
                    is_tidal_stream = True  # Still a Tidal-quality stream
                else:
                    self.log(f"[Tidal] Attempting to resolve high-res stream for: {title} by {artist}")
                    try:
                        tidal_url, tidal_quality = self.tidal.resolve_stream(title, artist)
                        if tidal_url:
                            self.log(f"[Tidal] Success! Using Tidal stream ({tidal_quality}): {tidal_url[:60]}...")
                            stream_url = tidal_url
                            quality = tidal_quality or "Tidal Lossless"
                            is_tidal_stream = True
                        else:
                            # Tidal failed — fall back to YouTube cache or live stream
                            self.log("[Tidal] No stream found, falling back to YouTube Music")
                            cached_audio_path = self.cache.get_audio_path(video_id)
                    except Exception as e:
                        self.log(f"[Tidal] Resolution failed: {e} — falling back to YouTube Music")
                        cached_audio_path = self.cache.get_audio_path(video_id)

            if cached_audio_path:
                self.log(f"Using cached audio: {title}")
                stream_url = f"file://{cached_audio_path}"
                # Cached Tidal FLAC — same quality, just label as "Tidal Lossless"
                quality = "Tidal Lossless" if cached_audio_path.endswith(".flac") else "Local Cache"
            elif stream_url:
                # Tidal URL already set above
                pass
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
            self._current_quality = quality
            self.log("Metadata set")

            with self._state_lock:
                if self._playback_token != token:
                    return

            self._cleanup_socket()

            # Detect Tidal HiRes DASH streams (local .mpd temp file)
            is_dash_mpd = stream_url.startswith("file://") and stream_url.endswith(".mpd")
            mpv_cmd = [
                "mpv", "--no-video", "--no-terminal", "--really-quiet",
                "--no-config", "--load-scripts=no", "--keep-open=yes",
                f"--input-ipc-server={self.ipc_socket}",
                "--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                f"--force-media-title={title} \u2022 {artist}",
                stream_url,
            ]
            self.log(f"Launching mpv{'  [DASH HiRes]' if is_dash_mpd else ''}...")
            process = subprocess.Popen(mpv_cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            if is_dash_mpd:
                # Clean up temp .mpd file after mpv has loaded it
                # Use longer delay to ensure all DASH segments are resolved
                mpd_path = stream_url[len("file://"):]
                def _cleanup_mpd():
                    import time as _t, os as _os
                    _t.sleep(60)
                    try:
                        _os.unlink(mpd_path)
                    except Exception:
                        pass
                threading.Thread(target=_cleanup_mpd, daemon=True).start()

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
                        image_data = self._download_best_art(art_url, video_id)
                        cached_path = self.cache.cache_art(art_url, image_data) if image_data else None
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
            is_live_stream = not stream_url.startswith("file://")

            if is_live_stream and is_tidal_stream and stream_url.startswith("https://"):
                # Tidal provided a direct CDN FLAC URL (BTS format, not DASH).
                # Download it in the background so replays are instant.
                _tidal_url_to_cache = stream_url
                def _cache_tidal_flac():
                    time.sleep(5)  # Brief delay to let mpv start
                    with self._state_lock:
                        if self._playback_token != token:
                            return  # Track was skipped
                    if self.cache.get_audio_path(video_id):
                        return  # Already cached (e.g. from a previous play)
                    try:
                        import urllib.request as _urllib
                        import shutil as _shutil
                        ext = "flac" if ".flac" in _tidal_url_to_cache else "m4a"
                        file_hash = self.cache._get_file_hash(video_id, "audio")
                        file_path = self.cache.audio_cache_dir / f"{file_hash}.{ext}"
                        temp_path = self.cache.audio_cache_dir / f"{file_hash}.{ext}.tmp"
                        self.log(f"[Cache] Downloading Tidal FLAC for: {title}")
                        req = _urllib.Request(
                            _tidal_url_to_cache,
                            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
                        )
                        with _urllib.urlopen(req, timeout=300) as resp, open(temp_path, "wb") as f:
                            _shutil.copyfileobj(resp, f)
                        temp_path.rename(file_path)
                        ok = self.cache.register_downloaded_audio(video_id, str(file_path))
                        if ok:
                            size_mb = file_path.stat().st_size / 1024 / 1024
                            self.log(f"[Cache] Tidal FLAC cached: {title} ({size_mb:.1f}MB)")
                    except Exception as e:
                        self.log(f"[Cache] Tidal FLAC cache failed for {title}: {e}")
                        try:
                            if temp_path.exists():
                                temp_path.unlink()
                        except Exception:
                            pass
                threading.Thread(target=_cache_tidal_flac, daemon=True).start()

            elif is_live_stream and not is_tidal_stream:
                # YouTube Music stream — download via yt-dlp for future offline playback.
                # For video tracks, wait much longer before downloading: starting a full yt-dlp download
                # 30s into playback creates two simultaneous YouTube connections and causes audio stutter.
                # Delay 3 minutes for video tracks so the download only kicks off near end of song.
                _cache_delay = 180 if _is_video_track else 30
                def _deferred_audio_cache(delay=_cache_delay):
                    time.sleep(delay)
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

            self.send_response(
                self._build_track_payload(
                    "playback_started",
                    video_id,
                    title,
                    artist,
                    art_url,
                    art_local_path=art_file_path or "",
                    artist_id=artist_id,
                    album_id=album_id,
                    is_liked=is_liked_hint,
                    quality=quality,
                )
            )

            if not is_liked_hint:
                def _fetch_like_status():
                    try:
                        song_data = self.api.ytm.get_song(video_id)
                        is_liked = song_data.get("videoDetails", {}).get("likeStatus") == "LIKE"
                        with self._state_lock:
                            if self._playback_token != token:
                                return
                        self.send_response({"type": "like_status", "videoId": video_id, "isLiked": is_liked})
                    except Exception as e:
                        self.log(f"Like status fetch error: {e}")
                threading.Thread(target=_fetch_like_status, daemon=True).start()

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
                    self.log(f"Fetching Apple Music canvas for: {title} by {artist}")
                    canvas_url = self.apple_music.get_canvas_mp4(title, artist)
                    with self._state_lock:
                        if self._playback_token != token:
                            return
                    if canvas_url:
                        self.log(f"Sending canvas_ready IPC message for videoId {video_id}")
                        self.send_response({"type": "canvas_ready", "videoId": video_id, "url": canvas_url})
                    else:
                        self.log(f"Sending canvas_failed IPC message for videoId {video_id}")
                        self.send_response({"type": "canvas_failed", "videoId": video_id})
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
                        self.send_response({"type": "playback_progress", "positionSec": float(pos)})
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
        return normalize_square_art_url(art, size=size)

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
