#!/usr/bin/env python3
"""
Standalone lyrics fetcher for the music backend.
Uses the same providers as the global lyrics system but runs
completely independently, emitting lyrics through the music
backend's own IPC channel so they are never mixed with other players.
"""

import bisect
import hashlib
import json
import os
import re
import sys
import threading
import time
import urllib.request
import urllib.parse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeoutError

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

TIMEOUT                = 8
BETTER_LYRICS_TIMEOUT  = float(os.getenv("BETTER_LYRICS_TIMEOUT", "4"))
BETTER_LYRICS_RETRIES  = max(0, int(os.getenv("BETTER_LYRICS_RETRIES", "1")))
PARALLEL_FETCH_TIMEOUT = float(os.getenv("PARALLEL_FETCH_TIMEOUT", "10"))
NEGATIVE_CACHE_TTL     = 3600

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/91.0.4472.124 Safari/537.36"
    ),
    "Accept": "application/json",
}

CACHE_DIR = Path.home() / ".cache/lyrics-layer"


def _log(msg):
    print(f"[LyricsFetcher] {msg}", file=sys.stderr, flush=True)


def ensure_cache_dir():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)


_track_key_cache: dict = {}

def clean_title(title: str, artist: str):
    suffixes = [
        " - YouTube Music", " - YouTube", " (Official Video)", " (Official Audio)",
        " (Official Music Video)", " (Lyric Video)", " (Lyrics)",
        " [Official Video]", " [Official Audio]",
        " (Remastered)", " [Remastered]", " - Remastered",
    ]
    t = title
    for s in suffixes:
        if t.endswith(s):
            t = t[: -len(s)]
    t = re.sub(r'\s*[\(\[][\s]*(?:feat\.?|ft\.?|featuring)\s+.*?[\)\]]', '', t, flags=re.IGNORECASE)
    if not artist and " - " in t:
        parts = t.split(" - ", 1)
        if len(parts) == 2:
            t, artist = parts[0].strip(), parts[1].strip()
    return t.strip(), artist.strip()


def get_cache_path(artist: str, title: str) -> Path:
    key = f"{artist.lower().strip()}|{title.lower().strip()}"
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
    except Exception:
        return False


def cache_lyrics(cache_path: Path, lyrics, source: str):
    try:
        with open(cache_path, "w") as f:
            json.dump({"lyrics": lyrics, "source": source, "timestamp": time.time()}, f)
    except Exception:
        pass


def cache_not_found(cache_path: Path):
    try:
        with open(cache_path, "w") as f:
            json.dump({"not_found": True, "timestamp": time.time()}, f)
    except Exception:
        pass


def parse_lrc(lrc_content: str):
    lines = []
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
            pre = parts[0].strip()
            if pre:
                words.append({"time": lt, "text": pre})
                full_text += pre + " "
            i = 1
            while i < len(parts) - 1:
                try:
                    wm, ws = parts[i].split(":")
                    wt = int(wm) * 60 + float(ws)
                    wtext = parts[i + 1].strip()
                    if wtext:
                        words.append({"time": wt, "text": wtext})
                        full_text += wtext + " "
                except Exception:
                    pass
                i += 2
            full_text = full_text.strip()
        else:
            full_text = content.strip()
        if full_text:
            lines.append({"time": lt, "text": full_text, "words": words})
    lines.sort(key=lambda x: x["time"])
    return lines


def fetch_from_lrclib(title, artist, album="", duration=0):
    if not HAS_REQUESTS:
        return None, False
    try:
        params = {"track_name": title, "artist_name": artist}
        if album:    params["album_name"] = album
        if duration: params["duration"] = int(duration)
        r = requests.get("https://lrclib.net/api/get", params=params, headers=HEADERS, timeout=TIMEOUT)
        if r.status_code == 200:
            data = r.json()
            synced_raw = data.get("syncedLyrics")
            plain_raw  = data.get("plainLyrics")
            lyrics = None
            if synced_raw:
                lyrics = parse_lrc(synced_raw)
            if not lyrics and plain_raw:
                lyrics = parse_lrc(plain_raw)
            if lyrics:
                return lyrics, bool(synced_raw)
    except Exception as e:
        _log(f"LRCLIB error: {e}")
    return None, False


BETTER_LYRICS_API = "https://lyrics-api.boidu.dev"

def fetch_from_better_lyrics(title, artist, album="", duration=0):
    import ssl
    ctx = ssl.create_default_context()
    ct, ca = clean_title(title or "", artist or "")
    params = {"s": ct or title, "a": ca or artist}
    if duration: params["d"] = int(duration)
    url = f"{BETTER_LYRICS_API}/getLyrics?{urllib.parse.urlencode(params)}"
    try:
        req = urllib.request.Request(url, headers={**HEADERS, "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=BETTER_LYRICS_TIMEOUT, context=ctx) as r:
            data = json.loads(r.read().decode())
        # Try to extract lyrics from common fields
        for key in ("lyrics", "syncedLyrics", "plainLyrics"):
            val = data.get(key)
            if isinstance(val, str) and val.strip():
                parsed = parse_lrc(val)
                if parsed:
                    return parsed, True
            elif isinstance(val, list) and val:
                lines = []
                for item in val:
                    if isinstance(item, dict):
                        t = item.get("time") or item.get("startTime") or 0
                        if isinstance(t, (int, float)) and t > 1000:
                            t = float(t) / 1000.0
                        txt = item.get("text") or item.get("lyric") or ""
                        if txt:
                            lines.append({"time": float(t), "text": txt, "words": []})
                if lines:
                    lines.sort(key=lambda x: x["time"])
                    return lines, True
    except Exception as e:
        _log(f"BetterLyrics error: {e}")
    return None, False


def fetch_lyrics(title: str, artist: str, album: str = "", duration: int = 0):
    """
    Fetch lyrics for the given track.
    Returns (lyrics_list, source_name) or (None, "").
    lyrics_list is a list of {"time": float, "text": str, "words": list}.
    """
    ensure_cache_dir()
    ct, ca = clean_title(title, artist)
    cache_path = get_cache_path(ca or artist, ct or title)

    if is_cache_valid(cache_path):
        try:
            with open(cache_path) as f:
                cached = json.load(f)
            if cached.get("lyrics"):
                _log(f"Cache hit: {ct}")
                return cached["lyrics"], cached.get("source", "cache")
            elif cached.get("not_found"):
                return None, ""
        except Exception:
            pass

    _log(f"Fetching lyrics: {ct} - {ca}")

    providers = [
        ("betterlyrics", lambda: fetch_from_better_lyrics(ct or title, ca or artist, album, duration)),
        ("lrclib",       lambda: fetch_from_lrclib(ct or title, ca or artist, album, duration)),
    ]

    with ThreadPoolExecutor(max_workers=len(providers)) as ex:
        futures = {ex.submit(fn): name for name, fn in providers}
        results = {}
        try:
            for fut in as_completed(futures, timeout=PARALLEL_FETCH_TIMEOUT):
                name = futures[fut]
                try:
                    lyrics, synced = fut.result()
                    results[name] = (lyrics, synced) if lyrics else None
                except Exception as e:
                    _log(f"{name} error: {e}")
                    results[name] = None
        except FuturesTimeoutError:
            pass

    for name, _ in providers:
        result = results.get(name)
        if result:
            lyrics, synced = result
            _log(f"Got lyrics from {name}: {len(lyrics)} lines")
            cache_lyrics(cache_path, lyrics, name)
            return lyrics, name

    _log(f"No lyrics found for {ct}")
    cache_not_found(cache_path)
    return None, ""


def get_current_line(lyrics, position: float) -> int:
    """Binary search for current lyric line."""
    if not lyrics:
        return -1
    times = [line["time"] for line in lyrics]
    return bisect.bisect_right(times, position) - 1


class LyricsSyncEngine:
    """
    Tracks playback position and emits currentLine updates.
    Runs in a background thread, sends events via send_response callback.
    """
    def __init__(self, send_response):
        self._send = send_response
        self._lock = threading.Lock()
        self._lyrics = []
        self._source = ""
        self._playing = False
        self._position = 0.0
        self._last_line = -1
        self._token = 0
        self._thread = None

    def load(self, lyrics, source, token):
        with self._lock:
            self._lyrics = lyrics or []
            self._source = source
            self._last_line = -1
            self._token = token
        self._send({
            "type": "lyrics",
            "lyrics": lyrics or [],
            "lyricsSource": source,
            "currentLine": -1,
        })

    def clear(self):
        with self._lock:
            self._lyrics = []
            self._source = ""
            self._last_line = -1
            self._token += 1
        self._send({"type": "lyrics", "lyrics": [], "lyricsSource": "", "currentLine": -1})

    def set_position(self, position: float):
        with self._lock:
            self._position = position
            if not self._lyrics:
                return
            idx = get_current_line(self._lyrics, position)
            if idx != self._last_line:
                self._last_line = idx
                self._send({"type": "lyrics_line", "currentLine": idx})

    def set_playing(self, playing: bool):
        with self._lock:
            self._playing = playing
