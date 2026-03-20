import re

with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/music_backend.py", "r") as f:
    content = f.read()

# Instead of stripping everything, we will create YTMClient and Player by string manipulation.

class Parser:
    def __init__(self, content):
        self.content = content
        self.lines = content.split('\n')
        
    def extract_method(self, method_name):
        start_idx = -1
        end_idx = -1
        
        for i, line in enumerate(self.lines):
            if line.startswith(f"    def {method_name}"):
                start_idx = i
                break
                
        if start_idx == -1:
            return ""
            
        for i in range(start_idx + 1, len(self.lines)):
            line = self.lines[i]
            if line.startswith("    def "):
                end_idx = i
                break
                
        if end_idx == -1:
            end_idx = len(self.lines)
            
        method_lines = self.lines[start_idx:end_idx]
        
        # fix indentation (remove 4 spaces)
        fixed_lines = []
        for line in method_lines:
            if line.startswith("    "):
                fixed_lines.append(line[4:])
            elif line == "":
                fixed_lines.append("")
            else:
                fixed_lines.append(line)
                
        return '\n'.join(fixed_lines)

p = Parser(content)
print("Extracting ytmapi methods...")

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

ytm_body = ""
for m in ytm_methods:
    ytm_body += p.extract_method(m) + "\n"
    
with open("/home/auysh/dots-hyprland/dots/.config/quickshell/ii/musicLayer/ytm_methods.py", "w") as f:
    f.write(ytm_body)

