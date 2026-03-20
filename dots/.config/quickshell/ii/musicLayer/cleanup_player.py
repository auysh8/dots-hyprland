import os

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/music_backend.py", "r") as f:
    full_content = f.readlines()

player_methods = [
    "_sigterm_handler", "_cleanup_on_exit", "_resolve_ytdlp_path", "_cleanup_socket",
    "_push_play_stack", "play", "_prefetch_stream_url", "_play_task",
    "_ipc", "_ipc_get", "stop", "pause", "resume", "seek", "next_track",
    "_auto_continue", "prev_track", "_fetch_queue_task", "fetch_playlist"
]

method_blocks = []

for m in player_methods:
    start_idx = -1
    for i, line in enumerate(full_content):
        if line.startswith(f"    def {m}("):
            start_idx = i
            break
            
    if start_idx == -1:
        continue
        
    end_idx = len(full_content)
    for i in range(start_idx + 1, len(full_content)):
        if full_content[i].startswith("    def "):
            end_idx = i
            break
            
    method_blocks.append("".join(full_content[start_idx:end_idx]))

header = """import os
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

"""

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/player.py", "w") as f:
    f.write(header + "".join(method_blocks))

