#!/usr/bin/env python3
import json
import os
import signal
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
import subprocess
from queue import Queue

from mpris_server import MprisServer, PYDBUS_AVAILABLE
from ytm_api import YTMClient
from player import Player
from cache_manager import CacheManager

class MusicBackend:
    def __init__(self):
        # Load Settings
        self.settings_path = os.path.expanduser("~/.config/quickshell/music_settings.json")
        self.settings = {
            "max_cache_size_mb": 500.0,
            "high_audio_quality": True,
            "tidal_lossless": False,
            "experimental_lyrics": False
        }
        self._load_settings()

        # Instantiate sub-components
        self.mpris = MprisServer(self)
        self.executor = ThreadPoolExecutor(max_workers=20)
        
        cache_dir = os.path.expanduser("~/.cache/quickshell/music")
        self.cache = CacheManager(cache_dir, max_size_mb=self.settings.get("max_cache_size_mb", 500.0), logger=self.log, executor=self.executor)
        
        # Create player first (needs send_response and log)
        self.player = Player(self.send_response, self.log, executor=self.executor)
        self.player.settings = self.settings # Pass settings reference
        # Set cache reference
        self.player.cache = self.cache
        
        # Then create API with player reference
        self.api = YTMClient(self.send_response, self.log, self.player, executor=self.executor)
        # Set cross-references
        self.player.api = self.api
        self.player.mpris = self.mpris
        
        self.mpris.start()
        if PYDBUS_AVAILABLE:
            self.log("MPRIS server started on org.mpris.MediaPlayer2.music-backend")
        else:
            self.log("pydbus not found — MPRIS metadata won't be published")

        signal.signal(signal.SIGTERM, self.player._sigterm_handler)
        signal.signal(signal.SIGHUP, self.player._sigterm_handler)

        # Response queue for thread-safe stdout writing
        self.response_queue = Queue()

    def _load_settings(self):
        try:
            if os.path.exists(self.settings_path):
                with open(self.settings_path, "r") as f:
                    data = json.load(f)
                    self.settings.update(data)
        except Exception as e:
            self.log(f"Failed to load settings: {e}")

    def _save_settings(self):
        try:
            os.makedirs(os.path.dirname(self.settings_path), exist_ok=True)
            with open(self.settings_path, "w") as f:
                json.dump(self.settings, f, indent=4)
        except Exception as e:
            self.log(f"Failed to save settings: {e}")

    def log(self, msg):
        print(f"[Backend] {msg}", file=sys.stderr)
        sys.stderr.flush()
        try:
            with open(os.path.expanduser("~/.cache/music_backend.log"), "a") as f:
                f.write(f"{msg}\n")
        except Exception:
            pass

    def send_response(self, data):
        """Send JSON to stdout for QML Process to read."""
        self.response_queue.put(json.dumps(data))

    def _process_responses(self):
        """Background thread to drain response queue to stdout."""
        while True:
            try:
                msg = self.response_queue.get()
                if msg:
                    print(msg, flush=True)
            except Exception as e:
                self.log(f"Response error: {e}")

    # Passthroughs for MPRIS server controlling the player
    def pause(self):
        self.player.pause()

    def resume(self):
        self.player.resume()

    def stop(self, notify=True):
        self.player.stop(notify)

    def next_track(self):
        self.player.next_track()

    def prev_track(self):
        self.player.prev_track()

    def seek(self, position_sec):
        self.player.seek(position_sec)

    def _ipc_get(self, prop_name):
        return self.player._ipc_get(prop_name)

    def _handle_command(self, req):
        """Handle a command from QML."""
        cmd = req.get("command")
        self.log(f"Received command: {cmd}")

        # ---- PLAYER ACTIONS ----
        if cmd == "play":
            video_id = req.get("videoId")
            title = req.get("title", "")
            artist = req.get("artist", "")
            art_url = req.get("artUrl", "")
            artist_id = req.get("artistId", "")
            album_id = req.get("albumId", "")
            album_name = req.get("album", "")
            queue = req.get("queue")
            is_liked = req.get("isLiked", False)
            if video_id:
                self.player.play(video_id, title, artist, art_url, queue, artist_id, album_id, album_name=album_name, is_liked=is_liked)

        elif cmd == "pause":
            self.player.pause()

        elif cmd == "resume":
            self.player.resume()

        elif cmd == "stop":
            self.player.stop()

        elif cmd == "seek":
            pos = req.get("position", 0)
            self.player.seek(pos)

        elif cmd == "next":
            self.player.next_track()

        elif cmd == "prev":
            self.player.prev_track()

        elif cmd == "toggle_repeat":
            self.player.repeat_mode = (self.player.repeat_mode + 1) % 3
            modes = ["off", "all", "one"]
            self.log(f"Repeat mode set to: {modes[self.player.repeat_mode]}")
            self.send_response({
                "type": "repeat_mode",
                "mode": modes[self.player.repeat_mode]
            })

        elif cmd == "set_repeat":
            mode = req.get("mode", 0)
            self.player.repeat_mode = mode % 3
            modes = ["off", "all", "one"]
            self.log(f"Repeat mode set to: {modes[self.player.repeat_mode]}")
            self.send_response({
                "type": "repeat_mode",
                "mode": modes[self.player.repeat_mode]
            })

        elif cmd == "previous":
            self.player.prev_track()

        elif cmd == "populate_radio":
            video_id = req.get("videoId")
            self.executor.submit(self.player._fetch_queue_task, video_id)

        # ---- API ACTIONS ----
        elif cmd == "get_home":
            self.executor.submit(self.api.get_home)

        elif cmd == "get_explore":
            self.executor.submit(self.api.get_explore)

        elif cmd == "get_library":
            self.executor.submit(self.api.get_library)

        elif cmd == "search":
            query = req.get("query", "")
            if query:
                self.executor.submit(self.api.search, query)

        elif cmd == "get_suggestions":
            query = req.get("query", "")
            if query:
                self.api.get_search_suggestions(query)

        elif cmd == "get_output_device":
            self.player.get_output_device()


        elif cmd == "get_credits":
            video_id = req.get("videoId")
            if video_id:
                self.executor.submit(self.api.get_credits, video_id)

        elif cmd == "get_artist":
            channel_id = req.get("channelId")
            if channel_id:
                self.executor.submit(self.api.get_artist, channel_id)

        elif cmd == "get_artist_items":
            channel_id = req.get("channelId")
            params = req.get("params")
            item_type = req.get("itemType")
            if channel_id and params and item_type:
                self.executor.submit(self.api.get_artist_items, channel_id, params, item_type)

        elif cmd == "get_artist_full_items":
            # Alias for get_artist_items - used by MusicArtistView for "See all" actions
            channel_id = req.get("channelId")
            params = req.get("params")
            item_type = req.get("itemType")
            if channel_id and params and item_type:
                self.executor.submit(self.api.get_artist_items, channel_id, params, item_type)

        elif cmd == "get_artist_full_songs":
            channel_id = req.get("channelId")
            songs_browse_id = req.get("songsBrowseId")
            if channel_id and songs_browse_id:
                self.executor.submit(self.api.get_artist_full_songs, channel_id, songs_browse_id)

        elif cmd == "get_playlist":
            browse_id = req.get("browseId")
            if browse_id:
                self.executor.submit(self.api.get_playlist, browse_id)

        elif cmd == "fetch_playlist_for_queue":
            video_id = req.get("videoId")
            if video_id:
                self.executor.submit(self.player.fetch_playlist, video_id)

        elif cmd == "toggle_like":
            video_id = req.get("videoId")
            is_liked = req.get("isLiked", False)
            if video_id:
                self.executor.submit(self.api._toggle_like_task, video_id, is_liked)

        elif cmd == "start_oauth":
            self.executor.submit(self.api.start_oauth)

        elif cmd == "cancel_oauth":
            self.api.cancel_oauth()

        elif cmd == "get_account_info":
            self.executor.submit(self.api.get_account_info)

        elif cmd == "logout":
            self.api.logout()

        elif cmd == "refresh_auth":
            self.executor.submit(self.api.refresh_auth)

        elif cmd == "sync_queue":
            queue = req.get("queue", [])
            with self.player._state_lock:
                self.player._current_queue = queue
                self.player._stream_cache.clear()  # Invalidate gapless cache on queue change
            self.log(f"Queue synced, {len(queue)} tracks")

        elif cmd == "reorder_queue":
            from_idx = req.get("from")
            to_idx = req.get("to")
            with self.player._state_lock:
                if 0 <= from_idx < len(self.player._current_queue) and 0 <= to_idx < len(self.player._current_queue):
                    track = self.player._current_queue.pop(from_idx)
                    self.player._current_queue.insert(to_idx, track)
                    self.player._stream_cache.clear()
            self.log(f"Queue reordered from {from_idx} to {to_idx}")

        elif cmd == "get_settings":
            self.send_response({
                "type": "settings_info",
                **self.settings
            })

        elif cmd == "update_settings":
            updates = req.get("settings", {})
            self.settings.update(updates)
            self._save_settings()
            
            # Apply dynamic changes
            if "max_cache_size_mb" in updates:
                self.cache.max_size_bytes = int(updates["max_cache_size_mb"] * 1024 * 1024)
                self.log(f"Cache size limit updated to {updates['max_cache_size_mb']}MB")
                
            self.send_response({
                "type": "settings_info",
                **self.settings
            })

        elif cmd == "copy_to_clipboard":
            text = req.get("text", "")
            if text:
                try:
                    # Try wl-copy (Wayland) then xclip (X11)
                    try:
                        subprocess.run(["wl-copy"], input=text.encode("utf-8"), check=True)
                    except (subprocess.CalledProcessError, FileNotFoundError):
                        subprocess.run(["xclip", "-selection", "clipboard"], input=text.encode("utf-8"), check=True)
                    self.log(f"Copied to clipboard: {text[:30]}...")
                except Exception as e:
                    self.log(f"Clipboard error: {e}")

        elif cmd == "cache_stats":
            self.executor.submit(lambda: self.send_response({
                "type": "cache_stats",
                **self.cache.get_stats()
            }))

        elif cmd == "clear_cache":
            what = req.get("what", "all")  # "all", "audio", "art"
            self.cache.clear(
                clear_art=(what in ("all", "art")),
                clear_audio=(what in ("all", "audio"))
            )
            self.log(f"Cache cleared: {what}")
            self.executor.submit(lambda: self.send_response({
                "type": "cache_stats",
                **self.cache.get_stats()
            }))

        else:
            self.log(f"Unknown command: {cmd}")

    def run(self):
        # Start response processor thread
        threading.Thread(target=self._process_responses, daemon=True).start()

        # Cleanup orphaned cache files on startup (non-blocking)
        self.executor.submit(self.cache.cleanup_orphans)

        # Send ready signal immediately
        self.send_response({
            "type": "ready",
            "authenticated": os.path.exists(self.api.oauth_path) or os.path.exists(self.api.headers_path)
        })

        # Send initial playback state
        with self.player._state_lock:
            vid = self.player.current_video_id
            title = getattr(self.player, "_current_title", "")
            artist = getattr(self.player, "_current_artist", "")
            art = getattr(self.player, "_current_art", "")
            art_url = getattr(self.player, "_current_art_url", "")
            quality = getattr(self.player, "_current_quality", "YouTube Music")

        status = "stopped"
        if self.player.mpv_process:
            pause_state = self.player._ipc_get("pause")
            if pause_state is True:
                status = "paused"
            elif pause_state is False:
                status = "playing"

        self.send_response({
            "type": "playback_state",
            "state": status,
            "videoId": vid,
            "title": title,
            "artist": artist,
            "artLocalPath": art,
            "artUrl": art_url,
            "quality": quality
        })
        self.send_response({"type": "queue_update", "queue": self.player._current_queue})

        self.log("Backend ready, waiting for commands...")

        # Read commands from stdin
        def handle_sig(signum, frame):
            self.log("Received exit signal, cleaning up...")
            self.player._cleanup_on_exit()
            sys.exit(0)

        signal.signal(signal.SIGINT, handle_sig)
        signal.signal(signal.SIGTERM, handle_sig)

        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
                self._handle_command(req)
            except json.JSONDecodeError:
                self.log("Invalid JSON from stdin")
            except Exception as e:
                self.log(f"Command error: {e}")

if __name__ == "__main__":
    backend = MusicBackend()
    backend.run()
