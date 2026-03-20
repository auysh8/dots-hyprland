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

class Player:
    def __init__(self, ytm_api, mpris_server, send_response_callback, logger):
        self.api = ytm_api
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
        
        self.repeat_mode = 0 # 0: Off, 1: All, 2: One
        self._stream_cache = {} # Background cache for gapless playback URL transitions
        
        self.cache_dir = os.path.expanduser("~/.cache/quickshell/media/coverart")
        os.makedirs(self.cache_dir, exist_ok=True)
        
        self._play_stack = []
        self._current_queue = []
        
        # Track metadata state
        self._current_title = ""
        self._current_artist = ""
        self._current_art = ""
        self._current_art_url = ""

    def _ipc_get(self, prop_name):
        return self.player._ipc_get(prop_name)

    # ── WebSocket Server ──────────────────────────────────────────────────────
    def stop(self, notify=True):
        self.player.stop(notify)

    def pause(self):
        self.player.pause()

    def resume(self):
        self.player.resume()

    def seek(self, position_sec):
        self.player.seek(position_sec)

    def next_track(self):
        self.player.next_track()

    def prev_track(self):
        self.player.prev_track()

