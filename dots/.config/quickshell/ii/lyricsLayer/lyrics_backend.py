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
import shlex

# Configuration
POLL_INTERVAL = 0.3  # seconds between updates
NEGATIVE_CACHE_TTL = 3600  # 1 hour before retrying failed searches
MAX_CACHE_AGE_DAYS = 30  # Delete cache files older than this

# Try importing optional dependencies
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
        " [Official Video]", " [Official Audio]",
        " (Remastered)", " [Remastered]", " - Remastered",
        " (Remaster)", " [Remaster]", " - Remaster"
    ]
    
    clean_title = title
    for suffix in suffixes_to_remove:
        if clean_title.endswith(suffix):
            clean_title = clean_title[:-len(suffix)]
            
    # Remove (feat. X) / [ft. X] / (featuring X)
    clean_title = re.sub(r'\s*[\(\[][\s]*(?:feat\.?|ft\.?|featuring)\s+.*?[\)\]]', '', clean_title, flags=re.IGNORECASE)
    
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

def log_debug(msg):
    try:
        with open("/tmp/lyrics_debug.log", "a") as f:
            f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}\n")
    except Exception:
        pass



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

def cache_lyrics(cache_path, lyrics, source="lrclib", method="get", synced=False):
    """Save lyrics to cache file"""
    try:
        with open(cache_path, 'w') as f:
            json.dump({
                "lyrics": lyrics,
                "source": source,
                "method": method,
                "synced": synced,
                "timestamp": time.time()
            }, f)
    except IOError as e:
        log_debug(f"Failed to write cache: {e}")


def count_word_timestamps(lyrics):
    """Count timed words in a lyrics payload."""
    if not isinstance(lyrics, list):
        return 0
    total = 0
    for line in lyrics:
        if not isinstance(line, dict):
            continue
        words = line.get("words")
        if isinstance(words, list):
            total += len(words)
    return total


def process_lrclib_result(data):
    """Process LRCLIB API result into lyrics list"""
    synced = data.get("syncedLyrics")
    plain = data.get("plainLyrics")
    
    lyrics = None
    
    # Try synced lyrics first (has timestamps)
    if synced:
        lyrics = parse_lrc(synced)
    
    # If synced failed or empty, try parsing plain as LRC
    if not lyrics and plain:
        lyrics = parse_lrc(plain)
    
    # If still no lyrics but plain text exists, create unsynced entries
    if not lyrics and plain:
        log_debug("No synced lyrics, falling back to plain text")
        lines = [line.strip() for line in plain.split('\n') if line.strip()]
        if lines:
            track_duration = data.get("duration", 180)
            if track_duration <= 0:
                track_duration = 180
            
            start_time = track_duration * 0.05
            end_time = track_duration * 0.95
            interval = (end_time - start_time) / max(len(lines), 1)
            
            lyrics = []
            for i, line in enumerate(lines):
                lyrics.append({
                    "time": start_time + i * interval,
                    "text": line,
                    "words": []
                })
    
    return lyrics, bool(synced)

# ─── Provider: LRCLIB ────────────────────────────────────────────────

def fetch_from_lrclib(title, artist, album="", duration=0):
    """
    Fetch lyrics from LRCLIB.
    Strategy: exact match /get → fallback /search with scoring
    """
    log_debug(f"[LRCLIB] Trying for: {title} - {artist}")
    
    # 1. Try EXACT MATCH (/get endpoint)
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
            lyrics, synced = process_lrclib_result(data)
            if lyrics:
                log_debug("[LRCLIB] Exact match found!")
                return lyrics, synced

    except urllib.error.HTTPError as e:
        log_debug(f"[LRCLIB] /get failed with HTTP {e.code}")
    except Exception as e:
        log_debug(f"[LRCLIB] /get failed: {e}")

    # 2. FALLBACK: SEARCH (/search endpoint)
    try:
        params = {"q": f"{title} {artist}"}
        url = f"https://lrclib.net/api/search?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"User-Agent": "LyricsLayer/1.0"})
        
        with urllib.request.urlopen(req, timeout=5) as response:
            results = json.loads(response.read().decode())
            log_debug(f"[LRCLIB] /search returned {len(results)} results")
            
            if results:
                best_match = None
                best_score = -1
                target_duration = int(duration) if duration > 0 else 0
                
                for track in results:
                    score = 0
                    
                    track_dur = int(track.get("duration", 0))
                    if target_duration > 0 and track_dur > 0:
                        diff = abs(track_dur - target_duration)
                        if diff <= 2: score += 10
                        elif diff <= 5: score += 5
                        else: score -= 5
                    
                    t_title = track.get("trackName", "").lower()
                    if t_title == title.lower(): score += 5
                    elif title.lower() in t_title: score += 2
                    
                    t_artist = track.get("artistName", "").lower()
                    if t_artist == artist.lower(): score += 5
                    elif artist.lower() in t_artist: score += 2
                    
                    if track.get("syncedLyrics"): score += 3
                    
                    if score > best_score:
                        best_score = score
                        best_match = track
                
                if best_match and best_score > 0:
                    log_debug(f"[LRCLIB] Best match: {best_match.get('trackName')} (score={best_score})")
                    lyrics, synced = process_lrclib_result(best_match)
                    if lyrics:
                        return lyrics, synced

    except Exception as e:
        log_debug(f"[LRCLIB] Search error: {e}")
        print(f"[Backend] LRCLIB search error: {e}", file=sys.stderr)

    return None, False

# ─── Provider: KuGou ─────────────────────────────────────────────────

def fetch_from_kugou(title, artist, album="", duration=0):
    """
    Fetch synced lyrics from KuGou Music.
    3-step API flow:
    1. Search song by keyword → get hash
    2. Search lyrics by hash → get id + accesskey
    3. Download LRC content with id + accesskey
    """
    log_debug(f"[KuGou] Trying for: {title} - {artist}")
    
    keyword = f"{title} {artist}".strip()
    if not keyword:
        return None, False
    
    headers = {"User-Agent": "LyricsLayer/1.0"}
    duration_ms = int(duration * 1000) if duration > 0 else 0
    
    try:
        # Step 1: Search for the song to get its hash
        search_params = {
            "keyword": keyword,
            "page": 1,
            "pagesize": 5,
            "platform": "WebFilter",
        }
        search_url = f"http://mobileservice.kugou.com/api/v3/search/song?{urllib.parse.urlencode(search_params)}"
        req = urllib.request.Request(search_url, headers=headers)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            search_data = json.loads(response.read().decode())
        
        songs = search_data.get("data", {}).get("info", [])
        if not songs:
            log_debug("[KuGou] No songs found")
            return None, False
        
        # Find best matching song by duration and name
        best_song = None
        best_score = -1
        
        for song in songs:
            score = 0
            s_duration = song.get("duration", 0)  # in seconds
            s_name = song.get("songname", "").lower()
            s_artist = song.get("singername", "").lower()
            
            # Duration match
            if duration > 0 and s_duration > 0:
                diff = abs(s_duration - duration)
                if diff <= 3: score += 10
                elif diff <= 10: score += 5
                else: score -= 3
            
            # Title match
            if title.lower() in s_name or s_name in title.lower(): score += 5
            if title.lower() == s_name: score += 5
            
            # Artist match
            if artist.lower() in s_artist or s_artist in artist.lower(): score += 3
            
            if score > best_score:
                best_score = score
                best_song = song
        
        if not best_song or best_score < 0:
            log_debug("[KuGou] No good song match")
            return None, False
        
        song_hash = best_song.get("hash", "")
        if not song_hash:
            log_debug("[KuGou] Song has no hash")
            return None, False
        
        log_debug(f"[KuGou] Found song: {best_song.get('songname')} (hash={song_hash[:16]}...)")
        
        # Step 2: Search for lyrics using the hash → get id + accesskey
        lyrics_search_params = {
            "ver": 1,
            "man": "yes",
            "client": "pc",
            "keyword": keyword,
            "hash": song_hash,
            "duration": duration_ms,
        }
        lyrics_search_url = f"http://krcs.kugou.com/search?{urllib.parse.urlencode(lyrics_search_params)}"
        req = urllib.request.Request(lyrics_search_url, headers=headers)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            lyrics_search_data = json.loads(response.read().decode())
        
        candidates = lyrics_search_data.get("candidates", [])
        if not candidates:
            log_debug("[KuGou] No lyric candidates found")
            return None, False
        
        # Use the first (best) candidate
        candidate = candidates[0]
        lyric_id = candidate.get("id", "")
        accesskey = candidate.get("accesskey", "")
        
        if not lyric_id or not accesskey:
            log_debug("[KuGou] Candidate missing id/accesskey")
            return None, False
        
        log_debug(f"[KuGou] Found lyrics candidate id={lyric_id}")
        
        # Step 3: Download the lyrics in LRC format
        download_params = {
            "ver": 1,
            "client": "pc",
            "id": lyric_id,
            "accesskey": accesskey,
            "fmt": "lrc",
            "charset": "utf8",
        }
        download_url = f"http://lyrics.kugou.com/download?{urllib.parse.urlencode(download_params)}"
        req = urllib.request.Request(download_url, headers=headers)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            download_data = json.loads(response.read().decode())
        
        # The content is base64 encoded
        lrc_b64 = download_data.get("content", "")
        if not lrc_b64:
            log_debug("[KuGou] Empty lyrics content")
            return None, False
        
        try:
            lrc_content = base64.b64decode(lrc_b64).decode("utf-8")
        except Exception as e:
            log_debug(f"[KuGou] Failed to decode lyrics: {e}")
            return None, False
        
        lyrics = parse_lrc(lrc_content)
        if lyrics:
            log_debug(f"[KuGou] Got {len(lyrics)} synced lines!")
            print(f"[Backend] KuGou: Found {len(lyrics)} synced lines for {title}", file=sys.stderr)
            return lyrics, True
        
        log_debug("[KuGou] Parsed LRC was empty")
        return None, False
        
    except Exception as e:
        log_debug(f"[KuGou] Error: {e}")
        print(f"[Backend] KuGou error: {e}", file=sys.stderr)
        return None, False

# ─── Provider: BetterLyrics ──────────────────────────────────────────

BETTER_LYRICS_API = "https://lyrics-api.boidu.dev"

def _parse_ttml_time(time_str):
    """Parse TTML time format (mm:ss.xxx or hh:mm:ss.xxx) to seconds"""
    try:
        parts = time_str.split(':')
        if len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
        elif len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        return float(time_str)
    except (ValueError, IndexError):
        return 0.0

def _parse_ttml(ttml_xml):
    """
    Parse TTML XML into lyrics with word-level timestamps.
    Based on Metrolist's TTMLParser.kt implementation.
    """
    import xml.etree.ElementTree as ET

    try:
        root = ET.fromstring(ttml_xml)
    except ET.ParseError as e:
        log_debug(f"[BetterLyrics] TTML parse error: {e}")
        return None

    lyrics = []

    # Find all <p> elements regardless of namespace
    for p in root.iter():
        tag = p.tag.split('}')[-1] if '}' in p.tag else p.tag
        if tag != 'p':
            continue

        begin = p.get('begin')
        if not begin:
            continue

        line_time = _parse_ttml_time(begin)

        # Skip background vocal lines
        is_bg = any('role' in k and v == 'x-bg' for k, v in p.attrib.items())
        if is_bg:
            continue

        # Extract word spans from this <p> element
        words = []
        for span in p:
            span_tag = span.tag.split('}')[-1] if '}' in span.tag else span.tag
            if span_tag != 'span':
                continue

            # Skip bg/translation/romanization
            span_role = None
            for k, v in span.attrib.items():
                if 'role' in k:
                    span_role = v
            if span_role in ('x-bg', 'x-translation', 'x-roman'):
                continue

            span_begin = span.get('begin')
            span_end = span.get('end')
            span_text = (span.text or '').strip()

            if span_text and span_begin and span_end:
                words.append({
                    "text": span_text,
                    "time": _parse_ttml_time(span_begin),
                    "end": _parse_ttml_time(span_end),
                })

        # Build line text
        if words:
            line_text = ' '.join(w['text'] for w in words)
        else:
            line_text = ''.join(p.itertext()).strip()

        if not line_text:
            continue

        lyrics.append({
            "time": line_time,
            "text": line_text,
            "words": words,
        })

    return lyrics if lyrics else None

def fetch_from_better_lyrics(title, artist, album="", duration=0):
    """
    Fetch lyrics from BetterLyrics API.
    Returns TTML-based lyrics with word-level timestamps from Musixmatch.
    """
    log_debug(f"[BetterLyrics] Trying for: {title} - {artist}")

    if not title or not artist:
        return None, False

    try:
        params = {"s": title, "a": artist}
        if duration and duration > 0:
            params["d"] = int(duration)
        if album:
            params["al"] = album

        url = f"{BETTER_LYRICS_API}/getLyrics?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={
            "User-Agent": "LyricsLayer/1.0",
            "Accept": "application/json",
        })

        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

        # Response: { "ttml": "<xml>...</xml>" }
        ttml_content = data.get("ttml")

        if not ttml_content or ttml_content == "null":
            log_debug("[BetterLyrics] No TTML in response")
            return None, False

        lyrics = _parse_ttml(ttml_content)

        if lyrics:
            word_count = sum(len(l.get("words", [])) for l in lyrics)
            log_debug(f"[BetterLyrics] Got {len(lyrics)} lines, {word_count} words!")
            print(f"[Backend] BetterLyrics: {len(lyrics)} lines, {word_count} word timestamps for {title}", file=sys.stderr)
            return lyrics, True

        log_debug("[BetterLyrics] TTML parsing returned empty")
        return None, False

    except urllib.error.HTTPError as e:
        log_debug(f"[BetterLyrics] HTTP error {e.code}")
        return None, False
    except Exception as e:
        log_debug(f"[BetterLyrics] Error: {e}")
        print(f"[Backend] BetterLyrics error: {e}", file=sys.stderr)
        return None, False

# ─── Provider Chain ──────────────────────────────────────────────────

# Ordered list of providers to try. Each is a (name, function) tuple.
# The chain stops at the first provider that returns lyrics.
LYRICS_PROVIDERS = [
    ("betterlyrics", fetch_from_better_lyrics),
    ("lrclib", fetch_from_lrclib),
    ("kugou", fetch_from_kugou),
]

def _call_provider_with_retry(provider_fn, title, artist, album, duration, retries=1):
    """Call a provider function with retry for transient network errors"""
    for attempt in range(retries + 1):
        try:
            return provider_fn(title, artist, album, duration)
        except (ConnectionError, OSError) as e:
            if attempt < retries:
                log_debug(f"Retry {attempt+1} after transient error: {e}")
                time.sleep(0.5)
            else:
                raise

def fetch_lyrics(title, artist, album="", duration=0):
    """
    Fetch lyrics using the provider chain.
    Tries each provider in order until one succeeds.
    """
    ensure_cache_dir()
    cache_path = get_cache_path(artist, title)
    
    log_debug(f"Fetching lyrics for: {title} - {artist} (Duration: {duration}s)")
    print(f"[Backend] Fetching: {title} - {artist} ({duration}s)", file=sys.stderr)
    
    # 1. Check local cache
    cached_lyrics_fallback = None
    cached_source_fallback = ""
    cached_word_count_fallback = 0
    if is_cache_valid(cache_path):
        try:
            with open(cache_path, 'r') as f:
                cached = json.load(f)
                if cached.get("lyrics"):
                    source = cached.get("source", "cache")
                    cached_lyrics = cached["lyrics"]
                    cached_word_count = count_word_timestamps(cached_lyrics)
                    print(
                        f"[Backend] Using cached lyrics for {title} (from {source}, words={cached_word_count})",
                        file=sys.stderr
                    )
                    # If cache already has word timing, use it immediately.
                    if cached_word_count > 0:
                        return cached_lyrics, source

                    # Keep plain/line-synced cache as fallback, but retry providers
                    # to upgrade to word-sync when available.
                    cached_lyrics_fallback = cached_lyrics
                    cached_source_fallback = source
                    cached_word_count_fallback = cached_word_count
                elif cached.get("not_found"):
                    return None, ""
        except (json.JSONDecodeError, IOError):
            pass

    if not artist or not title:
        return None, ""

    # 2. Try each provider in the chain
    for provider_name, provider_fn in LYRICS_PROVIDERS:
        try:
            lyrics, synced = _call_provider_with_retry(provider_fn, title, artist, album, duration)
            if lyrics:
                new_word_count = count_word_timestamps(lyrics)
                print(
                    f"[Backend] Got lyrics from {provider_name} ({len(lyrics)} lines, words={new_word_count})",
                    file=sys.stderr
                )

                # Keep the existing cache when provider result does not improve word-sync.
                if (
                    cached_lyrics_fallback is not None
                    and new_word_count <= cached_word_count_fallback
                ):
                    return cached_lyrics_fallback, cached_source_fallback

                cache_lyrics(cache_path, lyrics, source=provider_name, synced=synced)
                return lyrics, provider_name
        except Exception as e:
            log_debug(f"[{provider_name}] Uncaught error: {e}")
            print(f"[Backend] {provider_name} error: {e}", file=sys.stderr)

    # 3. Retry with split artist (e.g. "Ruth B. & Dean Lewis" -> "Ruth B.")
    if artist and " & " in artist:
        primary_artist = artist.split(" & ")[0]
        log_debug(f"Retrying with primary artist: {primary_artist}")
        result, source = fetch_lyrics(title, primary_artist, album, duration)
        if result: return result, source

    # 4. Store negative result to prevent spamming
    if cached_lyrics_fallback is not None:
        return cached_lyrics_fallback, cached_source_fallback

    try:
        log_debug(f"Writing negative cache to {cache_path}")
        with open(cache_path, 'w') as f:
            json.dump({"not_found": True, "timestamp": time.time()}, f)
    except IOError as e:
        log_debug(f"Failed to write cache: {e}")
    
    log_debug("Returning None (no lyrics found)")
    return None, ""

def get_current_line_index(lyrics, position):
    """Find the current line index based on playback position"""
    if not lyrics:
        return -1
    
    current_index = -1
    
    # Iterate to find the last line that has started (time <= position)
    for i, line in enumerate(lyrics):
        if line["time"] <= position:
            current_index = i
        else:
            # We reached a line in the future, stop
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
            
            # Check if player is a browser
            is_browser = any(b in identity.lower() for b in ["firefox", "chrome", "chromium", "brave", "edge", "opera", "vivaldi", "zen", "plasma-browser-integration"])
            
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
            
            if identity not in self.players:
                print(f"[Monitor] New player: {identity}", file=sys.stderr)
                self.players[identity] = {
                    "song": "",
                    "artist": "",
                    "raw_song": "",    # Store raw playerctl title
                    "raw_artist": "",  # Store raw playerctl artist
                    "artUrl": "",
                    "bgColor": "#f5f5f0",
                    "lyrics": [],
                    "lyricsSource": "",
                    "currentLine": -1,
                    "last_updated": 0,
                }
            
            player_state = self.players[identity]
            
            # Check if song changed (compare against RAW values)
            if title != player_state["raw_song"] or artist != player_state["raw_artist"]:
                print(f"[Monitor] Song changed on {identity}: {title} - {artist}", file=sys.stderr)
                log_debug(f"Song changed: {title}")
                
                # Update RAW and EFFECTIVE values
                player_state["raw_song"] = title
                player_state["raw_artist"] = artist
                player_state["song"] = title
                player_state["artist"] = artist
                
                if is_browser:
                    print(f"[Monitor] Skipping lyrics for browser: {identity}", file=sys.stderr)
                    player_state["lyrics"] = []
                    player_state["lyricsSource"] = ""
                else:
                    lyrics, source = fetch_lyrics(title, artist, album, duration)
                    player_state["lyrics"] = lyrics
                    player_state["lyricsSource"] = source
                
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
    print(f"[Backend] PIL: {HAS_PIL}", file=sys.stderr)
    
    ensure_cache_dir()
    cleanup_old_cache()  # Clean up on startup
    
    monitor = LyricsMonitor()
    
    # Poll loop in background thread
    def poll_loop():
        print("[Backend] Poll loop started", file=sys.stderr)
        last_states = {}  # { identity: {"hash": str, "time": float} }
        
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
                        last_states[identity]["hash"] != state_id or
                        time.time() - last_states[identity].get("time", 0) > 1.0
                    )
                    
                    if should_update:
                        last_states[identity] = {"hash": state_id, "time": time.time()}
                        
                        response_data = {
                            "playing": True,
                            "song": state["song"],
                            "artist": state["artist"],
                            "lyrics": state["lyrics"] or [],
                            "lyricsSource": state.get("lyricsSource", ""),
                            "currentLine": state["currentLine"],
                            "position": state["position"],
                            "duration": state["duration"],
                            "bgColor": state["bgColor"],
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
