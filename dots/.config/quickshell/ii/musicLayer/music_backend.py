#!/usr/bin/env python3
import asyncio
import json
import os
import signal
import sys
import threading
import websockets

from mpris_server import MprisServer, PYDBUS_AVAILABLE
from ytm_api import YTMClient
from player import Player

class MusicBackend:
    def __init__(self):
        self.clients = set()
        
        # Instantiate sub-components
        self.mpris = MprisServer(self) # We pass self to MPRIS because it calls pause()/play() on us
        
        self.api = YTMClient(self.send_response, self.log)
        self.player = Player(self.api, self.mpris, self.send_response, self.log)
        
        self.mpris.start()
        if PYDBUS_AVAILABLE:
            self.log("MPRIS server started on org.mpris.MediaPlayer2.music-backend")
        else:
            self.log("pydbus not found — MPRIS metadata won't be published. Install: pip install pydbus")

        signal.signal(signal.SIGTERM, self.player._sigterm_handler)
        signal.signal(signal.SIGHUP, self.player._sigterm_handler)

    def log(self, msg):
        print(f"[Backend] {msg}", file=sys.stderr)
        sys.stderr.flush()
        try:
            with open(os.path.expanduser("~/.cache/music_backend.log"), "a") as f:
                f.write(f"{msg}\n")
        except Exception:
            pass

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

    # ── WebSocket Server ──────────────────────────────────────────────────────
    def send_response(self, data):
        """Send JSON to all connected QML clients."""
        if not self.clients:
            return
        
        msg = json.dumps(data)
        websockets.broadcast(self.clients, msg)

    async def _handle_client(self, websocket):
        self.clients.add(websocket)
        self.log(f"Client connected. Total: {len(self.clients)}")

        # Send current player state on connect
        with self.player._state_lock:
            vid = self.player.current_video_id
            title = getattr(self.player, "_current_title", "")
            artist = getattr(self.player, "_current_artist", "")
            art = getattr(self.player, "_current_art", "")
            art_url = getattr(self.player, "_current_art_url", "")
            
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
            "artUrl": art_url
        })
        self.send_response({"type": "queue_update", "queue": self.player._current_queue})
        if vid and vid in self.api._song_meta_cache:
            self.send_response({"type": "like_status", "videoId": vid, "isLiked": self.api._song_meta_cache[vid]["is_liked"]})

        try:
            async for message in websocket:
                try:
                    req = json.loads(message)
                except json.JSONDecodeError:
                    self.log("Invalid JSON from client")
                    continue

                action = req.get("action")
                self.log(f"Received action: {action}")

                # ---- PLAYER ACTIONS ----
                if action == "play":
                    video_id = req.get("videoId")
                    title = req.get("title", "")
                    artist = req.get("artist", "")
                    art_url = req.get("artUrl", "")
                    if video_id:
                        self.player.play(video_id, title, artist, art_url)

                elif action == "pause":
                    self.player.pause()

                elif action == "resume":
                    self.player.resume()

                elif action == "stop":
                    self.player.stop()

                elif action == "seek":
                    pos = req.get("position", 0)
                    self.player.seek(pos)

                elif action == "next":
                    self.player.next_track()

                elif action == "prev":
                    self.player.prev_track()
                    
                elif action == "toggle_repeat":
                    self.player.repeat_mode = (self.player.repeat_mode + 1) % 3
                    modes = ["off", "all", "one"]
                    self.log(f"Repeat mode set to: {modes[self.player.repeat_mode]}")
                    self.send_response({
                        "type": "repeat_mode",
                        "mode": modes[self.player.repeat_mode]
                    })

                # ---- API ACTIONS ----
                elif action == "get_home":
                    threading.Thread(target=self.api.get_home, daemon=True).start()

                elif action == "get_explore":
                    threading.Thread(target=self.api.get_explore, daemon=True).start()
                    
                elif action == "get_library":
                    threading.Thread(target=self.api.get_library, daemon=True).start()

                elif action == "search":
                    query = req.get("query", "")
                    if query:
                        threading.Thread(target=self.api.search, args=(query,), daemon=True).start()

                elif action == "get_artist":
                    channel_id = req.get("channelId")
                    if channel_id:
                        threading.Thread(target=self.api.get_artist, args=(channel_id,), daemon=True).start()

                elif action == "get_artist_items":
                    channel_id = req.get("channelId")
                    params = req.get("params")
                    item_type = req.get("itemType")
                    if channel_id and params and item_type:
                        threading.Thread(target=self.api.get_artist_items, args=(channel_id, params, item_type), daemon=True).start()

                elif action == "get_artist_full_songs":
                    channel_id = req.get("channelId")
                    songs_browse_id = req.get("songsBrowseId")
                    if channel_id and songs_browse_id:
                        threading.Thread(target=self.api.get_artist_full_songs, args=(channel_id, songs_browse_id), daemon=True).start()

                elif action == "get_playlist":
                    browse_id = req.get("browseId")
                    if browse_id:
                        threading.Thread(target=self.api.get_playlist, args=(browse_id,), daemon=True).start()

                elif action == "fetch_playlist_for_queue":
                    video_id = req.get("videoId")
                    if video_id:
                        threading.Thread(target=self.player.fetch_playlist, args=(video_id,), daemon=True).start()

                elif action == "toggle_like":
                    video_id = req.get("videoId")
                    is_liked = req.get("isLiked", False)
                    if video_id:
                        threading.Thread(target=self.api._toggle_like_task, args=(video_id, is_liked), daemon=True).start()

                elif action == "start_oauth":
                    threading.Thread(target=self.api.start_oauth, daemon=True).start()
                    
                elif action == "cancel_oauth":
                    self.api.cancel_oauth()
                    
                elif action == "refresh_auth":
                    threading.Thread(target=self.api.refresh_auth, daemon=True).start()

        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.clients.remove(websocket)
            self.log(f"Client disconnected. Total: {len(self.clients)}")

    def run(self):
        async def main():
            # Force IPv4 binding (127.0.0.1) instead of localhost to avoid IPv6 issues
            async with websockets.serve(self._handle_client, "127.0.0.1", 8765):
                self.log("WebSocket server started on ws://127.0.0.1:8765")
                await asyncio.Future()  # run forever
                
        def handle_sig(signum, frame):
            self.log("Received exit signal, cleaning up...")
            self.player._cleanup_on_exit()
            sys.exit(0)
            
        signal.signal(signal.SIGINT, handle_sig)
        signal.signal(signal.SIGTERM, handle_sig)
        asyncio.run(main())

if __name__ == "__main__":
    backend = MusicBackend()
    backend.run()
