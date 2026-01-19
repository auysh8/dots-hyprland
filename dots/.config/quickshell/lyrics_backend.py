#!/usr/bin/env python3
"""
Stateless Lyrics & Color Backend
It waits for requests from QML, fetches data, and replies.
"""

import json
import sys
import base64
import urllib.request
import urllib.parse
import re
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    Image = None

CACHE_DIR = Path.home() / ".cache/lyrics-layer"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def encode_response(data):
    return base64.b64encode(json.dumps(data).encode()).decode()

def decode_request(b64_str):
    try:
        return json.loads(base64.b64decode(b64_str).decode())
    except:
        return None

# --- COLOR LOGIC ---
def extract_dominant_color(image_url):
    if not Image or not image_url: return None
    try:
        if image_url.startswith('file://'):
            img = Image.open(image_url[7:])
        else:
            req = urllib.request.Request(image_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=3) as response:
                img = Image.open(response)
        
        img = img.convert("RGB").resize((50, 50))
        quantized = img.quantize(colors=5, method=Image.Quantize.MEDIANCUT)
        palette = quantized.getpalette()[:15]
        
        best_color = (palette[0], palette[1], palette[2])
        best_sat = 0
        
        for i in range(0, len(palette), 3):
            r, g, b = palette[i], palette[i+1], palette[i+2]
            mx, mn = max(r,g,b), min(r,g,b)
            sat = (mx - mn) / mx if mx else 0
            if sat > best_sat:
                best_sat = sat
                best_color = (r,g,b)
        
        # Boost brightness
        r, g, b = best_color
        if (r+g+b)/3 < 60:
            boost = 60 - (r+g+b)/3
            r = min(255, r + boost)
            g = min(255, g + boost)
            b = min(255, b + boost)
            
        return '#{:02x}{:02x}{:02x}'.format(int(r), int(g), int(b))
    except:
        return None

# --- LYRICS LOGIC ---
def parse_lrc(lrc_content):
    lines = []
    for line in lrc_content.split('\n'):
        match = re.match(r'\[(\d+):(\d+)(?:\.(\d+))?\](.*)', line)
        if match:
            mins, secs = int(match.group(1)), int(match.group(2))
            cs = int(match.group(3)) if match.group(3) else 0
            text = match.group(4).strip()
            if text:
                lines.append({"time": mins * 60 + secs + cs/100, "text": text})
    return lines

def fetch_lyrics(title, artist, duration):
    safe_name = re.sub(r'[^\w\s-]', '', f"{artist}-{title}").strip().lower().replace(" ", "-")
    cache_file = CACHE_DIR / f"{safe_name}.json"
    
    # 1. Check Cache
    if cache_file.exists():
        try:
            with open(cache_file, 'r') as f:
                data = json.load(f)
                return data.get("lyrics")
        except: pass
        
    # 2. Fetch from API
    lyrics = None
    try:
        params = {"track_name": title, "artist_name": artist, "duration": duration}
        url = f"https://lrclib.net/api/get?{urllib.parse.urlencode(params)}"
        with urllib.request.urlopen(urllib.request.Request(url), timeout=4) as res:
            data = json.loads(res.read().decode())
            if data.get("syncedLyrics"):
                lyrics = parse_lrc(data["syncedLyrics"])
            elif data.get("plainLyrics"):
                lyrics = [{"time": i*3, "text": l} for i,l in enumerate(data["plainLyrics"].split('\n')) if l]
    except: pass
    
    # 3. Save Cache (even if empty, to stop spamming API)
    with open(cache_file, 'w') as f:
        json.dump({"lyrics": lyrics}, f)
        
    return lyrics

# --- MAIN LOOP ---
def main():
    # Signal ready
    print("READY", flush=True)
    
    for line in sys.stdin:
        try:
            req = decode_request(line.strip())
            if not req: continue
            
            title = req.get("title", "")
            artist = req.get("artist", "")
            art_url = req.get("artUrl", "")
            duration = req.get("duration", 0)
            req_id = req.get("id", "")
            
            # Process
            color = extract_dominant_color(art_url) or "#444444"
            lyrics = fetch_lyrics(title, artist, duration) or []
            
            resp = {
                "id": req_id, # Echo ID so QML knows which player this is for
                "color": color,
                "lyrics": lyrics
            }
            print("RESP:" + encode_response(resp), flush=True)
            
        except Exception as e:
            sys.stderr.write(f"Error: {e}\n")

if __name__ == "__main__":
    main()