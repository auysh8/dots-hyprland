#!/usr/bin/env python3
"""
Apple Music Style Lyrics Backend - Improved Version
Key improvements:
- Fixed unreachable code
- Better error handling
- Cache TTL for negative results
- Configurable polling
- Cache cleanup
"""

import json
import os
import sys
import base64
import subprocess
import threading
import time
import urllib.request
import urllib.parse
import re
from pathlib import Path
from queue import Queue
from datetime import datetime, timedelta
import contextlib
import io

# Configuration
POLL_INTERVAL = 0.3  # seconds between updates
NEGATIVE_CACHE_TTL = 3600  # 1 hour before retrying failed searches
MAX_CACHE_AGE_DAYS = 30  # Delete cache files older than this

# Try importing optional dependencies
try:
    import syncedlyrics
    HAS_SYNCEDLYRICS = True
except ImportError:
    HAS_SYNCEDLYRICS = False
    print("[Backend] Warning: syncedlyrics not installed, enhanced lyrics unavailable", file=sys.stderr)

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("[Backend] Warning: PIL not installed, color extraction disabled", file=sys.stderr)

CACHE_DIR = Path.home() / ".cache/lyrics-layer"

def ensure_cache_dir():
    """Create cache directory if it doesn't exist"""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

def cleanup_old_cache():
    """Remove cache files older than MAX_CACHE_AGE_DAYS"""
    try:
        cutoff = datetime.now() - timedelta(days=MAX_CACHE_AGE_DAYS)
        for cache_file in CACHE_DIR.glob("*.json"):
            if datetime.fromtimestamp(cache_file.stat().st_mtime) < cutoff:
                cache_file.unlink()
                print(f"[Cache] Cleaned up old file: {cache_file.name}", file=sys.stderr)
    except Exception as e:
        print(f"[Cache] Cleanup error: {e}", file=sys.stderr)

def encode_response(data):
    """Encode response as Base64"""
    json_str = json.dumps(data)
    return base64.b64encode(json_str.encode()).decode()

def decode_command(b64_str):
    """Decode Base64 command"""
    try:
        json_str = base64.b64decode(b64_str).decode()
        return json.loads(json_str)
    except (ValueError, json.JSONDecodeError) as e:
        print(f"[Backend] Decode error: {e}", file=sys.stderr)
        return None

def get_cache_path(artist, title):
    """Generate cache file path for a song"""
    safe_name = re.sub(r'[^\w\s-]', '', f"{artist}-{title}").strip().lower()
    safe_name = re.sub(r'[-\s]+', '-', safe_name)
    return CACHE_DIR / f"{safe_name}.json"

def clean_youtube_title(title, artist):
    """Clean up YouTube Music title format and extract artist if missing"""
    suffixes_to_remove = [
        " - YouTube Music", " - YouTube", " (Official Video)", " (Official Audio)",
        " (Official Music Video)", " (Lyric Video)", " (Lyrics)",
        " [Official Video]", " [Official Audio]"
    ]
    
    clean_title = title
    for suffix in suffixes_to_remove:
        if clean_title.endswith(suffix):
            clean_title = clean_title[:-len(suffix)]
    
    # Extract artist from "Title - Artist" format if artist is missing
    if not artist and " - " in clean_title:
        parts = clean_title.split(" - ", 1)
        if len(parts) == 2:
            clean_title = parts[0].strip()
            artist = parts[1].strip()
    
    return clean_title.strip(), artist.strip()

def extract_dominant_color(image_url):
    """Extract dominant vibrant color from image URL"""
    if not HAS_PIL or not image_url:
        return None
        
    try:
        # Handle file paths
        if image_url.startswith('file://'):
            image_path = image_url[7:]
            img = Image.open(image_path)
        else:
            # Handle HTTP URLs
            req = urllib.request.Request(image_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=2) as response:
                img = Image.open(response)
        
        # Resize to small size for faster processing
        img = img.convert("RGB").resize((50, 50))
        
        # Get color palette (quantize to 8 colors)
        quantized = img.quantize(colors=8, method=Image.Quantize.MEDIANCUT)
        palette = quantized.getpalette()[:24]
        
        # Extract colors from palette
        colors = []
        for i in range(0, len(palette), 3):
            r, g, b = palette[i], palette[i+1], palette[i+2]
            colors.append((r, g, b))
        
        # Find the most vibrant color
        best_color = colors[0]
        best_score = 0
        
        for color in colors:
            r, g, b = color
            max_c = max(r, g, b)
            min_c = min(r, g, b)
            
            # Avoid division by zero
            if max_c + min_c == 0:
                continue
                
            luminance = (max_c + min_c) / 2 / 255
            
            # Saturation calculation
            if max_c == min_c:
                saturation = 0
            elif luminance <= 0.5:
                saturation = (max_c - min_c) / (max_c + min_c)
            else:
                saturation = (max_c - min_c) / (2 * 255 - max_c - min_c)
            
            # Score: prefer saturated colors that aren't too dark or too light
            brightness_penalty = abs(luminance - 0.5) * 2
            score = saturation * (1 - brightness_penalty * 0.5)
            
            if score > best_score:
                best_score = score
                best_color = color
        
        # Ensure minimum brightness for dark colors
        r, g, b = best_color
        avg = (r + g + b) / 3
        
        if avg < 80:
            boost = 80 - avg
            r = min(255, r + int(boost))
            g = min(255, g + int(boost))
            b = min(255, b + int(boost))
        
        return '#{:02x}{:02x}{:02x}'.format(r, g, b)
        
    except Exception as e:
        print(f"[Color] Error extracting from {image_url}: {e}", file=sys.stderr)
        return None

def get_current_player_info(player_identity=None):
    """Get info about current playing track via playerctl"""
    try:
        base_cmd = ["playerctl"]
        if player_identity:
            base_cmd.extend(["-p", player_identity])
            
        status = subprocess.run(
            base_cmd + ["status"],
            capture_output=True, text=True, timeout=2
        )
        if status.returncode != 0 or status.stdout.strip() != "Playing":
            return None
        
        metadata = subprocess.run(
            base_cmd + ["metadata", "--format", 
             '{"title": "{{title}}", "artist": "{{artist}}", "album": "{{album}}", "artUrl": "{{mpris:artUrl}}", "length": {{mpris:length}}}'],
            capture_output=True, text=True, timeout=2
        )
        if metadata.returncode != 0:
            return None
        
        position = subprocess.run(
            base_cmd + ["position"],
            capture_output=True, text=True, timeout=2
        )
        pos_seconds = float(position.stdout.strip()) if position.returncode == 0 else 0
        
        data = json.loads(metadata.stdout.strip())
        
        # Clean title/artist
        title = data.get("title", "")
        artist = data.get("artist", "")
        title, artist = clean_youtube_title(title, artist)
        data["title"] = title
        data["artist"] = artist
        
        data["position"] = pos_seconds
        data["length"] = data.get("length", 0) / 1000000
        return data
    except (subprocess.TimeoutExpired, json.JSONDecodeError, ValueError) as e:
        print(f"[Backend] Error getting player info: {e}", file=sys.stderr)
        return None

def parse_lrc(lrc_content):
    """
    Parse LRC format (Standard or Enhanced) into list of:
    {
        "time": float (seconds),
        "text": string,
        "words": [ {"time": float, "text": string}, ... ]
    }
    """
    lines = []
    # Matches [mm:ss.xx] or [mm:ss]
    line_pattern = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)')
    
    for line in lrc_content.split('\n'):
        match = line_pattern.match(line)
        if not match:
            continue
            
        min_str, sec_str, content = match.groups()
        line_time = int(min_str) * 60 + float(sec_str)
        
        words = []
        full_text = ""
        
        # Check for enhanced timestamps <mm:ss.xx>
        if '<' in content and '>' in content:
            # Split by tag: <timestamp>
            parts = re.split(r'<(\d+:\d+(?:\.\d+)?)>', content)
            
            # Initial text (before first word tag)
            prefix_text = parts[0].strip()
            if prefix_text:
                full_text += prefix_text + " "
                words.append({"time": line_time, "text": prefix_text})

            i = 1
            while i < len(parts) - 1:
                w_time_str = parts[i]
                w_text = parts[i+1].strip()
                
                try:
                    wm, ws = w_time_str.split(':')
                    w_time = int(wm) * 60 + float(ws)
                    
                    if w_text:
                        words.append({"time": w_time, "text": w_text})
                        full_text += w_text + " "
                except (ValueError, IndexError):
                    pass
                i += 2
            
            full_text = full_text.strip()
        else:
            # Standard LRC
            full_text = content.strip()
        
        if full_text:
            lines.append({
                "time": line_time,
                "text": full_text,
                "words": words
            })
    
    lines.sort(key=lambda x: x["time"])
    return lines

def is_cache_valid(cache_path):
    """Check if cache file exists and is still valid"""
    if not cache_path.exists():
        return False
    
    try:
        with open(cache_path, 'r') as f:
            cached = json.load(f)
            
        # If it's a negative result, check TTL
        if cached.get("not_found"):
            cache_time = cached.get("timestamp", 0)
            age = time.time() - cache_time
            return age < NEGATIVE_CACHE_TTL
        
        # Positive results are always valid
        return cached.get("lyrics") is not None
    except (json.JSONDecodeError, IOError):
        return False

def fetch_lyrics(title, artist, album="", duration=0):
    """Fetch lyrics from syncedlyrics (Enhanced) or lrclib.net (Fallback)"""
    ensure_cache_dir()
    cache_path = get_cache_path(artist, title)
    
    # Check cache
    if is_cache_valid(cache_path):
        try:
            with open(cache_path, 'r') as f:
                cached = json.load(f)
                if cached.get("lyrics"):
                    print(f"[Backend] Using cached lyrics for {title}", file=sys.stderr)
                    return cached["lyrics"]
                elif cached.get("not_found"):
                    return None
        except (json.JSONDecodeError, IOError) as e:
            print(f"[Cache] Error reading cache: {e}", file=sys.stderr)
    
    # Priority 1: SyncedLyrics (Musixmatch) -> Word-by-word
    if HAS_SYNCEDLYRICS:
        try:
            term = f"{title} {artist}"
            print(f"[Backend] Searching SyncedLyrics for: {term}", file=sys.stderr)
            
            # Suppress stdout because syncedlyrics prints log messages
            f_io = io.StringIO()
            with contextlib.redirect_stdout(f_io), contextlib.redirect_stderr(f_io):
                lrc_content = syncedlyrics.search(term, enhanced=True)
            
            if lrc_content:
                lyrics = parse_lrc(lrc_content)
                if lyrics:
                    is_enhanced = any(len(line.get("words", [])) > 0 for line in lyrics)
                    print(f"[Backend] Found {len(lyrics)} lines (enhanced: {is_enhanced})", file=sys.stderr)
                    
                    # Cache positive result
                    with open(cache_path, 'w') as f:
                        json.dump({
                            "lyrics": lyrics,
                            "source": "syncedlyrics",
                            "timestamp": time.time()
                        }, f)
                    return lyrics
        except Exception as e:
            print(f"[Backend] SyncedLyrics error: {e}", file=sys.stderr)

    # Priority 2: Lrclib (Standard/Fallback)
    if artist:
        try:
            params = {
                "track_name": title,
                "artist_name": artist,
            }
            if album:
                params["album_name"] = album
            if duration > 0:
                params["duration"] = int(duration)
            
            url = f"https://lrclib.net/api/get?{urllib.parse.urlencode(params)}"
            req = urllib.request.Request(url, headers={"User-Agent": "LyricsLayer/1.0"})
            
            with urllib.request.urlopen(req, timeout=5) as response:
                data = json.loads(response.read().decode())
                lrc_content = data.get("syncedLyrics") or data.get("plainLyrics")
                
                if lrc_content:
                    if data.get("syncedLyrics"):
                        lyrics = parse_lrc(lrc_content)
                    else:
                        # Plain lyrics: fake timestamps
                        lyrics = [
                            {"time": i * 3, "text": line.strip(), "words": []} 
                            for i, line in enumerate(lrc_content.split('\n')) 
                            if line.strip()
                        ]
                    
                    if lyrics:
                        print(f"[Backend] Found lrclib lyrics ({len(lyrics)} lines)", file=sys.stderr)
                        
                        # Cache positive result
                        with open(cache_path, 'w') as f:
                            json.dump({
                                "lyrics": lyrics,
                                "source": "lrclib",
                                "timestamp": time.time()
                            }, f)
                        return lyrics
        except (urllib.error.URLError, json.JSONDecodeError, IOError) as e:
            print(f"[Backend] Lrclib error: {e}", file=sys.stderr)
    
    # Cache negative result with timestamp
    print(f"[Backend] No lyrics found for {title} - {artist}", file=sys.stderr)
    try:
        with open(cache_path, 'w') as f:
            json.dump({
                "not_found": True,
                "timestamp": time.time()
            }, f)
    except IOError as e:
        print(f"[Cache] Error writing negative cache: {e}", file=sys.stderr)
    
    return None

def get_current_line_index(lyrics, position):
    """Find the current line index based on playback position"""
    if not lyrics:
        return -1
    
    current_index = 0
    for i, line in enumerate(lyrics):
        if line["time"] <= position:
            current_index = i
        else:
            break
    return current_index

class LyricsMonitor:
    def __init__(self):
        self.players = {}  # { identity: player_state }
        self.running = True
        self.color_queue = Queue()
    
    def _extract_color_async(self, art_url, identity):
        """Background thread for color extraction"""
        color = extract_dominant_color(art_url)
        self.color_queue.put((identity, color if color else "#f5f5f0"))
    
    def update_players(self):
        """Update state for all active players"""
        # Check for color updates from background threads
        try:
            while not self.color_queue.empty():
                identity, color = self.color_queue.get_nowait()
                if identity in self.players:
                    self.players[identity]["bgColor"] = color
        except Exception as e:
            print(f"[Monitor] Color queue error: {e}", file=sys.stderr)

        # Get list of active players
        try:
            result = subprocess.run(
                ["playerctl", "-l"],
                capture_output=True,
                text=True,
                timeout=2
            )
            players = result.stdout.strip().splitlines() if result.returncode == 0 else []
        except (subprocess.TimeoutExpired, FileNotFoundError):
            players = []
            
        current_identities = set()
        
        for identity in players:
            if not identity:
                continue
            current_identities.add(identity)
            
            # Get info for this player
            info = get_current_player_info(identity)
            if not info:
                continue
            
            title = info.get("title", "")
            artist = info.get("artist", "")
            album = info.get("album", "")
            art_url = info.get("artUrl", "")
            position = info.get("position", 0)
            duration = info.get("length", 0)
            
            # Initialize player state if new
            if identity not in self.players:
                print(f"[Monitor] New player: {identity}", file=sys.stderr)
                self.players[identity] = {
                    "song": "",
                    "artist": "",
                    "artUrl": "",
                    "bgColor": "#f5f5f0",
                    "lyrics": [],
                    "currentLine": -1,
                    "last_updated": 0
                }
            
            player_state = self.players[identity]
            
            # Check if song changed
            if title != player_state["song"] or artist != player_state["artist"]:
                print(f"[Monitor] Song changed on {identity}: {title} - {artist}", file=sys.stderr)
                player_state["song"] = title
                player_state["artist"] = artist
                player_state["lyrics"] = fetch_lyrics(title, artist, album, duration)
                
                lyrics_count = len(player_state['lyrics']) if player_state['lyrics'] else 0
                print(f"[Monitor] Fetched {lyrics_count} lines", file=sys.stderr)
            
            # Check if art changed
            if art_url != player_state["artUrl"]:
                player_state["artUrl"] = art_url
                if art_url:
                    # Extract color in background thread
                    threading.Thread(
                        target=self._extract_color_async,
                        args=(art_url, identity),
                        daemon=True
                    ).start()
                else:
                    player_state["bgColor"] = "#f5f5f0"
            
            # Update positioning
            player_state["position"] = position
            player_state["duration"] = duration
            player_state["currentLine"] = get_current_line_index(
                player_state["lyrics"],
                position
            )
            player_state["last_updated"] = time.time()
        
        # Clean up old players (inactive for >10 seconds)
        for identity in list(self.players.keys()):
            if identity not in current_identities:
                last_update = self.players[identity].get("last_updated", 0)
                if time.time() - last_update > 10:
                    print(f"[Monitor] Removing inactive player: {identity}", file=sys.stderr)
                    del self.players[identity]

def main():
    """Main entry point"""
    print("[Backend] Starting lyrics backend...", file=sys.stderr)
    print(f"[Backend] SyncedLyrics: {HAS_SYNCEDLYRICS}, PIL: {HAS_PIL}", file=sys.stderr)
    
    ensure_cache_dir()
    cleanup_old_cache()  # Clean up on startup
    
    monitor = LyricsMonitor()
    
    # Poll loop in background thread
    def poll_loop():
        print("[Backend] Poll loop started", file=sys.stderr)
        last_states = {}  # { identity: state_hash }
        
        while monitor.running:
            try:
                monitor.update_players()
                
                # Send updates for each player
                for identity, state in monitor.players.items():
                    # Create state hash to detect changes
                    state_id = f"{state['song']}:{state['currentLine']}:{state['bgColor']}"
                    
                    # Send update if changed or periodically (every ~1 second)
                    should_update = (
                        identity not in last_states or
                        last_states[identity] != state_id or
                        int(time.time() * 2) % 2 == 0
                    )
                    
                    if should_update:
                        last_states[identity] = state_id
                        
                        response_data = {
                            "playing": True,
                            "song": state["song"],
                            "artist": state["artist"],
                            "lyrics": state["lyrics"] or [],
                            "currentLine": state["currentLine"],
                            "position": state["position"],
                            "duration": state["duration"],
                            "bgColor": state["bgColor"]
                        }
                        
                        print(f"UPDATE:{identity}:{encode_response(response_data)}", flush=True)
                
                time.sleep(POLL_INTERVAL)
                
            except Exception as e:
                print(f"[Error] Poll loop error: {e}", file=sys.stderr)
                import traceback
                traceback.print_exc(file=sys.stderr)
                time.sleep(1)
    
    # Start background thread
    threading.Thread(target=poll_loop, daemon=True).start()
    
    # Command loop (future expansion)
    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            
            cmd = decode_command(line)
            if cmd:
                # Handle commands here (future feature)
                command_type = cmd.get("type")
                if command_type == "refresh":
                    print("[Backend] Refresh command received", file=sys.stderr)
                    # Could force re-fetch of lyrics here
    except KeyboardInterrupt:
        print("[Backend] Shutting down...", file=sys.stderr)
    except Exception as e:
        print(f"[Backend] Fatal error: {e}", file=sys.stderr)
    finally:
        monitor.running = False

if __name__ == "__main__":
    main()