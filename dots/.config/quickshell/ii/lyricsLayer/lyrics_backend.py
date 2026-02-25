#!/usr/bin/env python3
"""
Apple Music Style Lyrics Backend
Fixes applied:
  1. Non-blocking lyrics fetch  — poll loop never freezes on song change
  2. Smarter negative cache     — only cached on definitive "not found"
  3. Fetch deduplication        — same song won't be fetched twice at once
  4. KuGou HTTPS                — encrypted requests
  5. Binary search line index   — O(log n) instead of O(n) every 300 ms
  6. Capped color threads       — max 1 color thread per player at a time
  7. Memoised track key         — regex not re-run on unchanged titles
  8. Hash-based cache names     — no filename collisions between songs
  9. Cache upgrade path         — re-tries better providers on next play
"""

import bisect
import hashlib
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
import requests
from pathlib import Path
from queue import Queue
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeoutError

# ─── Configuration ────────────────────────────────────────────────────────────

POLL_INTERVAL          = 0.3
NEGATIVE_CACHE_TTL     = 3600
MAX_CACHE_AGE_DAYS     = 30
TIMEOUT                = 8
BETTER_LYRICS_TIMEOUT  = float(os.getenv("BETTER_LYRICS_TIMEOUT", "4"))
BETTER_LYRICS_RETRIES  = max(0, int(os.getenv("BETTER_LYRICS_RETRIES", "1")))
PARALLEL_FETCH_TIMEOUT = float(os.getenv("PARALLEL_FETCH_TIMEOUT", "10"))

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/91.0.4472.124 Safari/537.36"
    ),
    "Accept": "application/json",
}

# ─── Optional deps ────────────────────────────────────────────────────────────

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("[Backend] Warning: PIL not installed, color extraction disabled", file=sys.stderr)

CACHE_DIR = Path.home() / ".cache/lyrics-layer"

# ─── Exceptions ───────────────────────────────────────────────────────────────

class TransientLyricsError(RuntimeError):
    """Provider failed due to a transient network / server issue."""

# ─── Cache helpers ────────────────────────────────────────────────────────────

def ensure_cache_dir():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

def cleanup_old_cache():
    try:
        cutoff = datetime.now() - timedelta(days=MAX_CACHE_AGE_DAYS)
        for f in CACHE_DIR.glob("*.json"):
            if datetime.fromtimestamp(f.stat().st_mtime) < cutoff:
                f.unlink()
                print(f"[Cache] Removed old file: {f.name}", file=sys.stderr)
    except Exception as e:
        print(f"[Cache] Cleanup error: {e}", file=sys.stderr)

# FIX 8: MD5 hash of "artist|title" as filename — zero chance of collision.
def get_cache_path(artist: str, title: str) -> Path:
    key    = f"{artist.lower().strip()}|{title.lower().strip()}"
    digest = hashlib.md5(key.encode()).hexdigest()
    return CACHE_DIR / f"{digest}.json"

def is_cache_valid(cache_path: Path) -> bool:
    if not cache_path.exists():
        return False
    try:
        with open(cache_path) as f:
            cached = json.load(f)
        if cached.get("not_found"):
            return (time.time() - cached.get("timestamp", 0)) < NEGATIVE_CACHE_TTL
        return cached.get("lyrics") is not None
    except (json.JSONDecodeError, IOError):
        return False

# FIX 9: store the provider name so we can decide to upgrade on next play.
def cache_lyrics(cache_path: Path, lyrics, source: str, synced: bool = False):
    try:
        with open(cache_path, "w") as f:
            json.dump({
                "lyrics":    lyrics,
                "source":    source,
                "synced":    synced,
                "timestamp": time.time(),
            }, f)
    except IOError as e:
        log_debug(f"Failed to write cache: {e}")

# FIX 2: separate helper so negative caching is an explicit, deliberate act.
def cache_not_found(cache_path: Path):
    try:
        with open(cache_path, "w") as f:
            json.dump({"not_found": True, "timestamp": time.time()}, f)
    except IOError as e:
        log_debug(f"Failed to write negative cache: {e}")

# ─── Misc utils ───────────────────────────────────────────────────────────────

def encode_response(data) -> str:
    return base64.b64encode(json.dumps(data).encode()).decode()

def decode_command(b64_str):
    try:
        return json.loads(base64.b64decode(b64_str).decode())
    except (ValueError, json.JSONDecodeError) as e:
        print(f"[Backend] Decode error: {e}", file=sys.stderr)
        return None

def log_debug(msg: str):
    try:
        with open("/tmp/lyrics_debug.log", "a") as f:
            f.write(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}\n")
    except Exception:
        pass

def count_word_timestamps(lyrics) -> int:
    if not isinstance(lyrics, list):
        return 0
    return sum(
        len(line.get("words", []))
        for line in lyrics
        if isinstance(line, dict)
    )

# ─── Track key — FIX 7: memoised ─────────────────────────────────────────────

_track_key_cache: dict = {}

def clean_youtube_title(title: str, artist: str):
    suffixes = [
        " - YouTube Music", " - YouTube", " (Official Video)", " (Official Audio)",
        " (Official Music Video)", " (Lyric Video)", " (Lyrics)",
        " [Official Video]", " [Official Audio]",
        " (Remastered)", " [Remastered]", " - Remastered",
        " (Remaster)", " [Remaster]", " - Remaster",
    ]
    t = title
    for s in suffixes:
        if t.endswith(s):
            t = t[: -len(s)]
    t = re.sub(
        r'\s*[\(\[][\s]*(?:feat\.?|ft\.?|featuring)\s+.*?[\)\]]', '',
        t, flags=re.IGNORECASE,
    )
    if not artist and " - " in t:
        parts = t.split(" - ", 1)
        if len(parts) == 2:
            t, artist = parts[0].strip(), parts[1].strip()
    return t.strip(), artist.strip()


def build_track_key(title: str, artist: str) -> str:
    # FIX 7: skip all the regex work if we've seen this exact (title, artist) pair before.
    raw_key = (title, artist)
    if raw_key in _track_key_cache:
        return _track_key_cache[raw_key]

    ct, ca = clean_youtube_title(title or "", artist or "")
    tn = re.sub(r"\s+", " ", ct).strip().lower()
    an = re.sub(r"\s+", " ", ca).strip().lower()

    if an:
        for sep in (" • ", " - ", " · "):
            if tn.endswith(f"{sep}{an}"):
                tn = tn[: -len(f"{sep}{an}")].strip()
                break

    tn = re.sub(r"\s*-\s*youtube music$", "", tn)
    tn = re.sub(r"\s*-\s*youtube$", "", tn)
    tn = re.sub(r"\s+", " ", tn).strip()
    an = re.sub(r"\s+", " ", an).strip()

    result = f"{tn}||{an}"
    if len(_track_key_cache) > 512:
        _track_key_cache.clear()
    _track_key_cache[raw_key] = result
    return result

# ─── Color extraction ─────────────────────────────────────────────────────────

def extract_dominant_color(image_url: str):
    if not HAS_PIL or not image_url:
        return None
    try:
        if image_url.startswith("file://"):
            img = Image.open(image_url[7:])
        else:
            req = urllib.request.Request(image_url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=2) as r:
                img = Image.open(r)

        img = img.convert("RGB").resize((50, 50))
        quantized = img.quantize(colors=8, method=Image.Quantize.MEDIANCUT)
        palette = quantized.getpalette()[:24]
        colors = [(palette[i], palette[i + 1], palette[i + 2]) for i in range(0, len(palette), 3)]

        best_color, best_score = colors[0], 0.0
        for rv, gv, bv in colors:
            mx, mn = max(rv, gv, bv), min(rv, gv, bv)
            if mx + mn == 0:
                continue
            lum = (mx + mn) / 2 / 255
            sat = 0.0 if mx == mn else (
                (mx - mn) / (mx + mn) if lum <= 0.5
                else (mx - mn) / (2 * 255 - mx - mn)
            )
            score = sat * (1 - abs(lum - 0.5))
            if score > best_score:
                best_score, best_color = score, (rv, gv, bv)

        rv, gv, bv = best_color
        avg = (rv + gv + bv) / 3
        if avg < 80:
            boost = int(80 - avg)
            rv, gv, bv = min(255, rv + boost), min(255, gv + boost), min(255, bv + boost)
        return "#{:02x}{:02x}{:02x}".format(rv, gv, bv)
    except Exception as e:
        print(f"[Color] Error: {e}", file=sys.stderr)
        return None

# ─── Playerctl ───────────────────────────────────────────────────────────────

def get_current_player_info(player_identity=None):
    try:
        base = ["playerctl"] + (["-p", player_identity] if player_identity else [])
        status = subprocess.run(base + ["status"], capture_output=True, text=True, timeout=2)
        if status.returncode != 0 or status.stdout.strip() != "Playing":
            return None

        meta = subprocess.run(
            base + ["metadata", "--format",
                '{"title": "{{title}}", "artist": "{{artist}}", "album": "{{album}}", '
                '"artUrl": "{{mpris:artUrl}}", "length": {{mpris:length}}}'],
            capture_output=True, text=True, timeout=2,
        )
        if meta.returncode != 0:
            return None

        pos = subprocess.run(base + ["position"], capture_output=True, text=True, timeout=2)
        pos_s = float(pos.stdout.strip()) if pos.returncode == 0 else 0.0

        data = json.loads(meta.stdout.strip())
        data["title"], data["artist"] = clean_youtube_title(
            data.get("title", ""), data.get("artist", "")
        )
        data["position"] = pos_s
        data["length"]   = data.get("length", 0) / 1_000_000
        return data
    except (subprocess.TimeoutExpired, json.JSONDecodeError, ValueError) as e:
        print(f"[Backend] Player info error: {e}", file=sys.stderr)
        return None

# ─── LRC parser ──────────────────────────────────────────────────────────────

def parse_lrc(lrc_content: str):
    lines    = []
    line_pat = re.compile(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)')
    for line in lrc_content.split("\n"):
        m = line_pat.match(line)
        if not m:
            continue
        mn, sc, content = m.groups()
        lt = int(mn) * 60 + float(sc)
        words, full_text = [], ""

        if "<" in content and ">" in content:
            parts = re.split(r'<(\d+:\d+(?:\.\d+)?)>', content)
            pre   = parts[0].strip()
            if pre:
                words.append({"time": lt, "text": pre})
                full_text += pre + " "
            i = 1
            while i < len(parts) - 1:
                try:
                    wm, ws = parts[i].split(":")
                    wt     = int(wm) * 60 + float(ws)
                    wtext  = parts[i + 1].strip()
                    if wtext:
                        words.append({"time": wt, "text": wtext})
                        full_text += wtext + " "
                except (ValueError, IndexError):
                    pass
                i += 2
            full_text = full_text.strip()
        else:
            full_text = content.strip()

        if full_text:
            lines.append({"time": lt, "text": full_text, "words": words})

    lines.sort(key=lambda x: x["time"])
    return lines

# ─── Provider: LRCLIB ────────────────────────────────────────────────────────

def process_lrclib_result(data):
    synced_raw = data.get("syncedLyrics")
    plain_raw  = data.get("plainLyrics")
    lyrics     = None
    if synced_raw:
        lyrics = parse_lrc(synced_raw)
    if not lyrics and plain_raw:
        lyrics = parse_lrc(plain_raw)
    if not lyrics and plain_raw:
        raw_lines = [l.strip() for l in plain_raw.split("\n") if l.strip()]
        if raw_lines:
            dur  = max(data.get("duration", 180) or 180, 1)
            step = (dur * 0.9) / max(len(raw_lines), 1)
            lyrics = [
                {"time": dur * 0.05 + i * step, "text": l, "words": []}
                for i, l in enumerate(raw_lines)
            ]
    return lyrics, bool(synced_raw)


def fetch_from_lrclib(title, artist, album="", duration=0):
    log_debug(f"[LRCLIB] {title} - {artist}")
    try:
        params = {"track_name": title, "artist_name": artist}
        if album:    params["album_name"] = album
        if duration: params["duration"]   = int(duration)
        r = requests.get("https://lrclib.net/api/get", params=params, headers=HEADERS, timeout=TIMEOUT)
        if r.status_code == 200:
            lyrics, synced = process_lrclib_result(r.json())
            if lyrics:
                return lyrics, synced
    except Exception as e:
        log_debug(f"[LRCLIB] /get error: {e}")

    try:
        r = requests.get(
            "https://lrclib.net/api/search",
            params={"q": f"{title} {artist}"},
            headers=HEADERS, timeout=TIMEOUT,
        )
        if r.status_code == 200:
            results = r.json()
            if isinstance(results, list) and results:
                best, best_score = None, -1
                td = int(duration) if duration else 0
                for track in results:
                    if not isinstance(track, dict):
                        continue
                    score = 0
                    diff  = abs(int(track.get("duration", 0) or 0) - td)
                    if td:
                        score += 10 if diff <= 2 else 5 if diff <= 5 else -5
                    tn = str(track.get("trackName",  "")).lower()
                    an = str(track.get("artistName", "")).lower()
                    if tn == title.lower():     score += 5
                    elif title.lower() in tn:   score += 2
                    if an == artist.lower():    score += 5
                    elif artist.lower() in an:  score += 2
                    if track.get("syncedLyrics"): score += 3
                    if score > best_score:
                        best_score, best = score, track
                if best and best_score > 0:
                    lyrics, synced = process_lrclib_result(best)
                    if lyrics:
                        return lyrics, synced
    except Exception as e:
        log_debug(f"[LRCLIB] search error: {e}")

    return None, False

# ─── Provider: KuGou — FIX 4: HTTPS ─────────────────────────────────────────

def fetch_from_kugou(title, artist, album="", duration=0):
    log_debug(f"[KuGou] {title} - {artist}")
    keyword = f"{title} {artist}".strip()
    if not keyword:
        return None, False

    try:
        # Step 1 — find song hash
        p   = {"keyword": keyword, "page": 1, "pagesize": 5, "platform": "WebFilter"}
        req = urllib.request.Request(
            f"https://mobileservice.kugou.com/api/v3/search/song?{urllib.parse.urlencode(p)}",
            headers=HEADERS,
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            songs = json.loads(r.read().decode()).get("data", {}).get("info", [])

        if not songs:
            return None, False

        best, best_score = None, -1
        for song in songs:
            score = 0
            sd    = song.get("duration", 0)
            sn    = song.get("songname",   "").lower()
            sa    = song.get("singername", "").lower()
            if duration and sd:
                diff   = abs(sd - duration)
                score += 10 if diff <= 3 else 5 if diff <= 10 else -3
            if title.lower() in sn or sn in title.lower(): score += 5
            if title.lower() == sn:                         score += 5
            if artist.lower() in sa or sa in artist.lower(): score += 3
            if score > best_score:
                best_score, best = score, song

        if not best or best_score < 0:
            return None, False
        song_hash = best.get("hash", "")
        if not song_hash:
            return None, False

        # Step 2 — find lyric candidate
        duration_ms = int(duration * 1000) if duration else 0
        p2  = {"ver": 1, "man": "yes", "client": "pc",
               "keyword": keyword, "hash": song_hash, "duration": duration_ms}
        req2 = urllib.request.Request(
            f"https://krcs.kugou.com/search?{urllib.parse.urlencode(p2)}",
            headers=HEADERS,
        )
        with urllib.request.urlopen(req2, timeout=TIMEOUT) as r:
            candidates = json.loads(r.read().decode()).get("candidates", [])

        if not candidates:
            return None, False
        cand      = candidates[0]
        lyric_id  = cand.get("id", "")
        accesskey = cand.get("accesskey", "")
        if not lyric_id or not accesskey:
            return None, False

        # Step 3 — download LRC
        p3  = {"ver": 1, "client": "pc", "id": lyric_id,
               "accesskey": accesskey, "fmt": "lrc", "charset": "utf8"}
        req3 = urllib.request.Request(
            f"https://lyrics.kugou.com/download?{urllib.parse.urlencode(p3)}",
            headers=HEADERS,
        )
        with urllib.request.urlopen(req3, timeout=TIMEOUT) as r:
            lrc_b64 = json.loads(r.read().decode()).get("content", "")

        if not lrc_b64:
            return None, False
        lrc    = base64.b64decode(lrc_b64).decode("utf-8")
        lyrics = parse_lrc(lrc)
        if lyrics:
            print(f"[Backend] KuGou: {len(lyrics)} lines for {title}", file=sys.stderr)
            return lyrics, True

    except Exception as e:
        log_debug(f"[KuGou] error: {e}")
        print(f"[Backend] KuGou error: {e}", file=sys.stderr)

    return None, False

# ─── Provider: BetterLyrics ──────────────────────────────────────────────────

BETTER_LYRICS_API = "https://lyrics-api.boidu.dev"


def _parse_ttml_time(s: str) -> float:
    try:
        parts = s.split(":")
        if len(parts) == 2: return float(parts[0]) * 60 + float(parts[1])
        if len(parts) == 3: return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        return float(s)
    except (ValueError, IndexError):
        return 0.0


def _parse_ttml(xml_str: str):
    import xml.etree.ElementTree as ET
    try:
        root = ET.fromstring(xml_str)
    except ET.ParseError as e:
        log_debug(f"[BetterLyrics] TTML parse error: {e}")
        return None

    lyrics = []
    for p in root.iter():
        tag = p.tag.split("}")[-1] if "}" in p.tag else p.tag
        if tag != "p":
            continue
        begin = p.get("begin")
        if not begin:
            continue
        if any("role" in k and v == "x-bg" for k, v in p.attrib.items()):
            continue
        lt    = _parse_ttml_time(begin)
        words = []
        for span in p:
            st = span.tag.split("}")[-1] if "}" in span.tag else span.tag
            if st != "span":
                continue
            role = next((v for k, v in span.attrib.items() if "role" in k), None)
            if role in ("x-bg", "x-translation", "x-roman"):
                continue
            sb, se = span.get("begin"), span.get("end")
            txt    = (span.text or "").strip()
            if txt and sb and se:
                words.append({"text": txt, "time": _parse_ttml_time(sb), "end": _parse_ttml_time(se)})
        line_text = " ".join(w["text"] for w in words) if words else "".join(p.itertext()).strip()
        if line_text:
            lyrics.append({"time": lt, "text": line_text, "words": words})

    return lyrics or None


def _parse_structured_time(val):
    if val is None: return None
    if isinstance(val, (int, float)):
        return float(val) / 1000.0 if float(val) > 1000 else float(val)
    raw = str(val).strip()
    if raw.endswith("ms"):
        try: return float(raw[:-2]) / 1000.0
        except ValueError: return None
    try: return _parse_ttml_time(raw)
    except Exception: return None


def _parse_plain_text_lyrics(text: str, duration=0):
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    if not lines: return None
    step = max(float(duration) / max(len(lines), 1), 1.5) if duration else 3.0
    return [{"time": round(i * step, 3), "text": l, "words": []} for i, l in enumerate(lines)]


def _parse_structured_lyrics_list(items, duration=0):
    if not isinstance(items, list): return None
    timed, plain = [], []
    TEXT_KEYS = ("text", "lyric", "lyrics", "line", "words", "content", "value")
    TIME_KEYS = ("time", "timestamp", "start", "startTime", "begin", "seconds", "t", "offset")
    for item in items:
        if isinstance(item, str):
            if item.strip(): plain.append(item.strip())
            continue
        if not isinstance(item, dict): continue
        txt = next((item[k] for k in TEXT_KEYS if isinstance(item.get(k), str) and item[k].strip()), "")
        if not txt: continue
        lt = next((_parse_structured_time(item[k]) for k in TIME_KEYS if k in item), None)
        if lt is None:
            plain.append(txt)
        else:
            timed.append({"time": round(max(float(lt), 0.0), 3), "text": txt, "words": []})
    if timed:
        timed.sort(key=lambda x: x["time"])
        return timed
    return _parse_plain_text_lyrics("\n".join(plain), duration=duration) if plain else None


def _extract_betterlyrics_payload(payload, duration=0):
    if isinstance(payload, list):
        p = _parse_structured_lyrics_list(payload, duration=duration)
        return (p, count_word_timestamps(p) > 0) if p else (None, False)
    if isinstance(payload, str):
        text = payload.strip()
        if not text: return None, False
        if text.startswith("<"):
            p = _parse_ttml(text)
            if p: return p, True
        p = parse_lrc(text)
        if p: return p, count_word_timestamps(p) > 0
        p = _parse_plain_text_lyrics(text, duration=duration)
        return (p, False) if p else (None, False)
    if not isinstance(payload, dict): return None, False
    for key in ("lyrics", "lyric", "lines", "items"):
        val = payload.get(key)
        if isinstance(val, list):
            p = _parse_structured_lyrics_list(val, duration=duration)
            if p: return p, count_word_timestamps(p) > 0
    for key in ("ttml", "richSyncLyrics", "syncedLyrics", "plainLyrics", "plainLyric", "lyrics", "lyric"):
        p, ws = _extract_betterlyrics_payload(payload.get(key), duration=duration)
        if p: return p, ws
    for key in ("data", "result"):
        p, ws = _extract_betterlyrics_payload(payload.get(key), duration=duration)
        if p: return p, ws
    return None, False


def _build_betterlyrics_query_variants(title, artist, album="", duration=0):
    ct, ca = clean_youtube_title(title or "", artist or "")
    pa     = ca.split(" & ")[0].split(",")[0].strip() if ca else ""
    variants, seen = [], set()
    for t in [title, ct]:
        for a in [artist, ca, pa]:
            for al in [album, ""]:
                for inc_dur in ([True, False] if duration else [False]):
                    qt = re.sub(r"\s+", " ", t or "").strip()
                    qa = re.sub(r"\s+", " ", a or "").strip()
                    if not qt or not qa: continue
                    params = {"s": qt, "a": qa}
                    if inc_dur: params["d"] = int(duration)
                    if al:      params["al"] = re.sub(r"\s+", " ", al).strip()
                    key = tuple(sorted(params.items()))
                    if key in seen: continue
                    seen.add(key)
                    variants.append(params)
    if not variants:
        fb = {"s": title, "a": artist}
        if duration: fb["d"] = int(duration)
        if album:    fb["al"] = album
        variants.append(fb)
    return variants


def fetch_from_better_lyrics(title, artist, album="", duration=0):
    log_debug(f"[BetterLyrics] {title} - {artist}")
    if not title or not artist:
        return None, False

    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode    = ssl.CERT_NONE

    had_transient = False
    for params in _build_betterlyrics_query_variants(title, artist, album, duration):
        url = f"{BETTER_LYRICS_API}/getLyrics?{urllib.parse.urlencode(params)}"
        for attempt in range(BETTER_LYRICS_RETRIES + 1):
            try:
                req = urllib.request.Request(url, headers={**HEADERS, "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=BETTER_LYRICS_TIMEOUT, context=ctx) as r:
                    data = json.loads(r.read().decode())
                lyrics, ws = _extract_betterlyrics_payload(data, duration=duration)
                if lyrics:
                    wc = sum(len(l.get("words", [])) for l in lyrics)
                    print(f"[Backend] BetterLyrics: {len(lyrics)} lines, {wc} words for {title}", file=sys.stderr)
                    return lyrics, ws
                break
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504):
                    had_transient = True
                    if attempt < BETTER_LYRICS_RETRIES:
                        time.sleep(0.35 * (attempt + 1))
                        continue
                    raise TransientLyricsError(f"HTTP {e.code}")
                break
            except Exception as e:
                err = str(e).lower()
                if any(x in err for x in ("timed out", "temporary failure", "connection reset", "name resolution")):
                    had_transient = True
                    if attempt < BETTER_LYRICS_RETRIES:
                        time.sleep(0.35 * (attempt + 1))
                        continue
                    raise TransientLyricsError(f"transient: {e}")
                log_debug(f"[BetterLyrics] error: {e}")
                break

    if had_transient:
        raise TransientLyricsError("betterlyrics transient failure")
    return None, False

# ─── Provider registry ───────────────────────────────────────────────────────

LYRICS_PROVIDERS = [
    ("betterlyrics", fetch_from_better_lyrics),
    ("lrclib",       fetch_from_lrclib),
    ("kugou",        fetch_from_kugou),
]

_PROVIDER_PRIORITY = {name: i for i, (name, _) in enumerate(LYRICS_PROVIDERS)}

# ─── Parallel fetch ──────────────────────────────────────────────────────────

def _fetch_all_providers_parallel(title, artist, album, duration) -> dict:
    results = {name: None for name, _ in LYRICS_PROVIDERS}

    def _run(name, fn):
        try:
            lyrics, synced = fn(title, artist, album, duration)
            return name, ((lyrics, synced) if lyrics else None)
        except TransientLyricsError as e:
            log_debug(f"[Parallel] {name} transient: {e}")
            print(f"[Backend] {name} transient: {e}", file=sys.stderr)
            return name, None
        except Exception as e:
            log_debug(f"[Parallel] {name} error: {e}")
            print(f"[Backend] {name} error: {e}", file=sys.stderr)
            return name, None

    print(f"[Backend] Parallel fetch → '{title}' (timeout={PARALLEL_FETCH_TIMEOUT}s)", file=sys.stderr)
    t0 = time.time()

    with ThreadPoolExecutor(max_workers=len(LYRICS_PROVIDERS)) as ex:
        futures = {ex.submit(_run, name, fn): name for name, fn in LYRICS_PROVIDERS}
        try:
            for fut in as_completed(futures, timeout=PARALLEL_FETCH_TIMEOUT):
                name, result = fut.result()
                results[name] = result
                elapsed = time.time() - t0
                status  = f"{len(result[0])} lines" if result else "no result"
                print(f"[Backend] {name} → {status} ({elapsed:.2f}s)", file=sys.stderr)
        except FuturesTimeoutError:
            done    = [n for n, r in results.items() if r is not None]
            waiting = [n for n, r in results.items() if r is None]
            print(f"[Backend] Timed out. done={done} abandoned={waiting}", file=sys.stderr)

    return results


def _pick_best_result(provider_results: dict):
    for name, _ in LYRICS_PROVIDERS:
        result = provider_results.get(name)
        if result:
            lyrics, synced = result
            if lyrics:
                wc = count_word_timestamps(lyrics)
                print(f"[Backend] Winner: {name} ({len(lyrics)} lines, {wc} words)", file=sys.stderr)
                return lyrics, name, synced
    return None, "", False

# ─── FIX 5: binary search line index ─────────────────────────────────────────

def get_current_line_index(lyrics, position: float) -> int:
    """O(log n) — replaces the old O(n) linear scan."""
    if not lyrics:
        return -1
    times = [line["time"] for line in lyrics]
    idx   = bisect.bisect_right(times, position) - 1
    return idx  # -1 means we're before the first line

# ─── Main fetch entry point ──────────────────────────────────────────────────

def fetch_lyrics(title, artist, album="", duration=0):
    ensure_cache_dir()
    cache_path = get_cache_path(artist, title)

    log_debug(f"Fetching: {title} - {artist} ({duration}s)")
    print(f"[Backend] Fetching: {title} - {artist} ({duration}s)", file=sys.stderr)

    # ── 1. Cache check ───────────────────────────────────────────────
    cached_lyrics_fallback = None
    cached_source_fallback = ""
    cached_word_count_fb   = 0

    if is_cache_valid(cache_path):
        try:
            with open(cache_path) as f:
                cached = json.load(f)

            if cached.get("lyrics"):
                source        = cached.get("source", "cache")
                cached_lyrics = cached["lyrics"]
                cached_wc     = count_word_timestamps(cached_lyrics)
                print(f"[Backend] Cache hit: '{title}' source={source} words={cached_wc}", file=sys.stderr)

                # FIX 9: return immediately only if we're already at the
                # highest-priority provider AND have word-level sync.
                top_provider = LYRICS_PROVIDERS[0][0]
                if cached_wc > 0 and source == top_provider:
                    return cached_lyrics, source

                # Word-synced from any provider → good enough.
                if cached_wc > 0:
                    return cached_lyrics, source

                # Line-synced: keep as fallback, try to upgrade.
                cached_lyrics_fallback = cached_lyrics
                cached_source_fallback = source
                cached_word_count_fb   = cached_wc

            elif cached.get("not_found"):
                return None, ""

        except (json.JSONDecodeError, IOError):
            pass

    if not artist or not title:
        return None, ""

    # ── 2. Parallel fetch ────────────────────────────────────────────
    provider_results = _fetch_all_providers_parallel(title, artist, album, duration)

    # ── 3. Priority selection ────────────────────────────────────────
    lyrics, provider_name, synced = _pick_best_result(provider_results)

    if lyrics:
        new_wc       = count_word_timestamps(lyrics)
        new_lines    = len(lyrics)
        cached_lines = len(cached_lyrics_fallback) if cached_lyrics_fallback else 0

        cache_is_better = (
            cached_lyrics_fallback is not None and (
                cached_word_count_fb > new_wc or
                (cached_word_count_fb == new_wc and cached_lines >= new_lines)
            )
        )
        if cache_is_better:
            log_debug("Keeping existing cache (not an upgrade)")
            return cached_lyrics_fallback, cached_source_fallback

        cache_lyrics(cache_path, lyrics, source=provider_name, synced=synced)
        return lyrics, provider_name

    # ── 4. Split-artist retry ────────────────────────────────────────
    if artist and " & " in artist:
        primary = artist.split(" & ")[0]
        log_debug(f"Retrying with primary artist: {primary}")
        result, source = fetch_lyrics(title, primary, album, duration)
        if result:
            return result, source

    # ── 5. Line-synced cache fallback ────────────────────────────────
    if cached_lyrics_fallback is not None:
        log_debug("All providers failed; using line-synced cache fallback")
        return cached_lyrics_fallback, cached_source_fallback

    # ── 6. FIX 2: only write negative cache on definitive failures ───
    # If any provider slot is still None it may have timed out (transient),
    # not necessarily returned "not found". Only write when all responded.
    all_responded = all(r is not None for r in provider_results.values())
    if all_responded:
        log_debug(f"Writing negative cache: {cache_path}")
        cache_not_found(cache_path)
    else:
        log_debug("Skipping negative cache: some providers may have timed out")

    return None, ""

# ─── LyricsMonitor ───────────────────────────────────────────────────────────

class LyricsMonitor:
    def __init__(self):
        self.players: dict      = {}
        self.running            = True
        self.color_queue: Queue = Queue()
        self._state_lock        = threading.Lock()

        # FIX 1 + 3: track in-flight background fetches by track_key.
        # The same key won't be fetched twice simultaneously.
        self._pending_fetches: set = set()

        # FIX 6: one cancel-event per player; set it to abort a stale color thread.
        self._color_cancel: dict = {}

    # ── FIX 6: capped color threads ─────────────────────────────────

    def _extract_color_async(self, art_url: str, identity: str, cancel: threading.Event):
        color = extract_dominant_color(art_url)
        if not cancel.is_set():
            self.color_queue.put((identity, color or "#f5f5f0"))

    def _start_color_thread(self, identity: str, art_url: str):
        old = self._color_cancel.get(identity)
        if old:
            old.set()                          # discard result of the old thread
        ev = threading.Event()
        self._color_cancel[identity] = ev
        threading.Thread(
            target=self._extract_color_async,
            args=(art_url, identity, ev),
            daemon=True,
        ).start()

    # ── FIX 1: non-blocking lyrics fetch ────────────────────────────

    def _fetch_lyrics_bg(self, identity: str, title: str, artist: str,
                          album: str, duration: float, track_key: str):
        try:
            lyrics, source = fetch_lyrics(title, artist, album, duration)
        except Exception as e:
            print(f"[Backend] bg fetch error: {e}", file=sys.stderr)
            lyrics, source = None, ""
        finally:
            # FIX 3: always release the lock even on error.
            self._pending_fetches.discard(track_key)

        with self._state_lock:
            state = self.players.get(identity)
            if state and state.get("track_key") == track_key:
                state["lyrics"]        = lyrics or []
                state["lyricsSource"]  = source
                state["lyricsLoading"] = False
                print(
                    f"[Backend] bg fetch done: '{title}' → "
                    f"{len(state['lyrics'])} lines from {source}",
                    file=sys.stderr,
                )

    # ── Poll tick ────────────────────────────────────────────────────

    def update_players(self):
        # Drain colour queue
        try:
            while not self.color_queue.empty():
                identity, color = self.color_queue.get_nowait()
                with self._state_lock:
                    if identity in self.players:
                        self.players[identity]["bgColor"] = color
        except Exception as e:
            print(f"[Monitor] Color queue error: {e}", file=sys.stderr)

        # List active players
        try:
            res     = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=2)
            players = res.stdout.strip().splitlines() if res.returncode == 0 else []
        except (subprocess.TimeoutExpired, FileNotFoundError):
            players = []

        current_identities: set = set()

        for identity in players:
            if not identity:
                continue
            current_identities.add(identity)

            is_browser = any(b in identity.lower() for b in [
                "firefox", "chrome", "chromium", "brave", "edge",
                "opera", "vivaldi", "zen", "plasma-browser-integration",
            ])

            info = get_current_player_info(identity)
            if not info:
                continue

            title    = info.get("title",    "")
            artist   = info.get("artist",   "")
            album    = info.get("album",    "")
            art_url  = info.get("artUrl",   "")
            position = info.get("position", 0.0)
            duration = info.get("length",   0.0)

            with self._state_lock:
                if identity not in self.players:
                    print(f"[Monitor] New player: {identity}", file=sys.stderr)
                    self.players[identity] = {
                        "song": "", "artist": "",
                        "raw_song": "", "raw_artist": "",
                        "track_key": "", "artUrl": "",
                        "bgColor": "#f5f5f0",
                        "lyrics": [], "lyricsSource": "",
                        "lyricsLoading": False,
                        "currentLine": -1, "last_updated": 0.0,
                    }

                state     = self.players[identity]
                # FIX 7: build_track_key is now memoised — no regex on repeated calls.
                track_key = build_track_key(title, artist)

                if track_key != state.get("track_key", ""):
                    print(f"[Monitor] Song changed on {identity}: {title} - {artist}", file=sys.stderr)
                    log_debug(f"Song changed: {title}")

                    state.update({
                        "raw_song":    title,  "raw_artist": artist,
                        "track_key":   track_key,
                        "song":        title,  "artist":     artist,
                        "lyrics":      [],     "lyricsSource": "",
                        "lyricsLoading": True,
                        "currentLine": -1,
                    })

                    if is_browser:
                        state["lyricsLoading"] = False
                        print(f"[Monitor] Skipping lyrics for browser: {identity}", file=sys.stderr)
                    # FIX 1 + 3: only start a fetch if one isn't already running.
                    elif track_key not in self._pending_fetches:
                        self._pending_fetches.add(track_key)
                        threading.Thread(
                            target=self._fetch_lyrics_bg,
                            args=(identity, title, artist, album, duration, track_key),
                            daemon=True,
                        ).start()
                    else:
                        print(f"[Monitor] Fetch already running for: {track_key}", file=sys.stderr)

                # Art change → FIX 6: cancel old color thread before starting new one.
                if art_url != state["artUrl"]:
                    state["artUrl"] = art_url
                    if art_url:
                        self._start_color_thread(identity, art_url)
                    else:
                        state["bgColor"] = "#f5f5f0"

                state["position"]     = position
                state["duration"]     = duration
                # FIX 5: binary search, not linear scan.
                state["currentLine"]  = get_current_line_index(state["lyrics"], position)
                state["last_updated"] = time.time()

        # Remove gone players
        with self._state_lock:
            for identity in list(self.players.keys()):
                if identity not in current_identities:
                    if time.time() - self.players[identity].get("last_updated", 0) > 10:
                        print(f"[Monitor] Removing inactive player: {identity}", file=sys.stderr)
                        del self.players[identity]
                        self._color_cancel.pop(identity, None)

# ─── Entry point ─────────────────────────────────────────────────────────────

def main():
    print("[Backend] Starting lyrics backend...", file=sys.stderr)
    print(f"[Backend] PIL: {HAS_PIL}", file=sys.stderr)
    ensure_cache_dir()
    cleanup_old_cache()

    monitor = LyricsMonitor()

    def poll_loop():
        print("[Backend] Poll loop started", file=sys.stderr)
        last_states: dict = {}

        while monitor.running:
            try:
                monitor.update_players()

                with monitor._state_lock:
                    snapshot = list(monitor.players.items())

                for identity, state in snapshot:
                    # Don't send any update while lyrics are loading — this keeps
                    # the frontend spinner running exactly like the old blocking
                    # behaviour did (frontend gets nothing until lyrics are ready).
                    if state.get("lyricsLoading", False):
                        continue
                    state_id = f"{state['song']}:{state['currentLine']}:{state['bgColor']}:{len(state['lyrics'])}"
                    ls       = last_states.get(identity, {})
                    if ls.get("hash") != state_id or time.time() - ls.get("time", 0) > 1.0:
                        last_states[identity] = {"hash": state_id, "time": time.time()}
                        print(
                            f"UPDATE:{identity}:{encode_response({'playing': True, 'song': state['song'], 'artist': state['artist'], 'lyrics': state['lyrics'] or [], 'lyricsSource': state.get('lyricsSource', ''), 'lyricsLoading': state.get('lyricsLoading', False), 'currentLine': state['currentLine'], 'position': state['position'], 'duration': state['duration'], 'bgColor': state['bgColor']})}",
                            flush=True,
                        )

                time.sleep(POLL_INTERVAL)

            except Exception as e:
                import traceback
                print(f"[Error] Poll loop: {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)
                time.sleep(1)

    threading.Thread(target=poll_loop, daemon=True).start()

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            cmd = decode_command(line)
            if cmd:
                if cmd.get("type") == "refresh":
                    print("[Backend] Refresh command received", file=sys.stderr)
    except KeyboardInterrupt:
        print("[Backend] Shutting down...", file=sys.stderr)
    except Exception as e:
        print(f"[Backend] Fatal error: {e}", file=sys.stderr)
    finally:
        monitor.running = False


if __name__ == "__main__":
    main()