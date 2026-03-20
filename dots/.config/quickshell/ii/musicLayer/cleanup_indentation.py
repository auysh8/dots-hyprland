import os

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/ytm_methods.py", "r") as f:
    methods_code = f.read()

# Instead of stripping indentation to 0 in the previous script and trying to add it back,
# I will just write a new parser that keeps the exact original 4-space base indentation for methods.

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/music_backend.py", "r") as f:
    full_content = f.readlines()

ytm_methods = [
    "_make_oauth_credentials", "_init_ytm", "_set_default_timeout",
    "_get_home_data", "_seconds_to_duration", "_normalize_duration_text",
    "_extract_nested_duration_text", "_extract_duration", "format_track_item",
    "_download_art", "_item_video_id", "_extract_art_url", "_append_unique",
    "_to_section_items", "_search_songs_for_home", "_pick_artists",
    "_build_history_track_pools", "_collect_home_section_candidates",
    "_seed_discover_from_playlists", "_build_recommendations_section",
    "_build_quick_picks_section", "_build_discover_section",
    "_append_search_songs", "_collect_search_cards", "_backfill_missing_song_durations",
    "get_home", "_fetch_home_task", "get_explore", "_toggle_like_task",
    "_fetch_explore_task", "get_library", "_fetch_library_task", "get_artist",
    "_artist_task", "get_artist_items", "_artist_items_task", "get_artist_full_songs",
    "_artist_full_songs_task", "get_playlist", "_playlist_task", "search",
    "_search_task", "refresh_auth", "_refresh_auth_task", "start_oauth",
    "cancel_oauth", "_oauth_task", "_load_canvas_cache", "_save_canvas_cache"
]

method_blocks = []

for m in ytm_methods:
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

# Now we rebuild ytm_api.py properly

header = """import os
import re
import json
import time
import hashlib
import urllib.request
import threading
from ytmusicapi import YTMusic

class YTMClient:
    _DURATION_RE = re.compile(r"^(?:\\d{1,2}:)?[0-5]?\\d:[0-5]\\d$")
    _HTTP_TIMEOUT = (8, 20)  # connect/read timeout for YTMusic requests
    _HOME_CACHE_TTL_SEC = 60

    _OAUTH_CLIENT_ID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
    _OAUTH_CLIENT_SECRET = "SboVhoG9s0rNafixCSGGKXAT"

    def __init__(self, send_response_callback, logger):
        self.send_response = send_response_callback
        self.log = logger
        
        script_dir = os.path.dirname(os.path.abspath(__file__))
        self.oauth_path = os.path.join(script_dir, "oauth.json")
        self.headers_path = os.path.join(script_dir, "headers_auth.json")
        self.cache_dir = os.path.expanduser("~/.cache/quickshell/media/coverart")
        os.makedirs(self.cache_dir, exist_ok=True)
        
        # Home cache
        self._home_cache = []
        self._home_cache_ts = 0.0
        self._home_cache_lock = threading.Lock()

        # Search results cache
        self._search_cache = {}
        self._search_cache_ttl = 300  # 5 minutes

        # Explore/Charts cache
        self._explore_cache = None
        self._explore_cache_ttl = 900  # 15 minutes

        # Song metadata cache
        self._song_meta_cache = {}
        self._song_meta_cache_ttl = 1800  # 30 minutes
        
        # Canvas cache
        self._canvas_cache_path = os.path.expanduser("~/.cache/quickshell/media/canvas_cache.json")
        self._canvas_cache = {}
        self._canvas_cache_ttl = 86400 * 7  # 7 days
        self._load_canvas_cache()
        
        self.ytm = None
        try:
            self._init_ytm()
        except Exception as e:
            self.log(f"YTMusic init failed: {e}")
            self.ytm = None

"""

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/ytm_api.py", "w") as f:
    f.write(header + "".join(method_blocks))

