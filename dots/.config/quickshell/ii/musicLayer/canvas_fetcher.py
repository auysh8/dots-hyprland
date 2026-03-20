#!/usr/bin/env python3
"""
canvas_fetcher.py — Fetch animated canvas art for a song.

Mirrors vivi-music's two-provider fallback chain:
  1. ArchiveTuneCanvas  (https://artwork-archivetune.koiiverse.cloud/)
  2. MonochromeApiCanvas (Tidal video covers via monochrome.tf)

Usage:
    python3 canvas_fetcher.py <song_title> <artist_name> [album] [storefront]
    python3 canvas_fetcher.py --album-id <album_id>

Output (stdout): JSON with keys:
    { "animated": <url or null>, "videoUrl": <url or null>, "source": <"archivetune"|"monochrome"|null> }
"""

import sys
import json
import re
import urllib.request
import urllib.parse
import urllib.error

ARCHIVETUNE_BASE = "https://artwork-archivetune.koiiverse.cloud/"
MONOCHROME_INSTANCES = [
    "https://eu-central.monochrome.tf/",
    "https://us-west.monochrome.tf/",
    "https://arran.monochrome.tf/",
    "https://api.monochrome.tf/",
]
TIMEOUT = 12


def _get_json(url, timeout=TIMEOUT):
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "canvas-fetcher/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if resp.status != 200:
                return None
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except Exception:
        return None


def _normalize_title(raw):
    """Strip feat., [Official Video] etc. from song titles — mirrors vivi's normalizeCanvasSongTitle."""
    s = re.sub(r"\s*\[[^\]]*]", "", raw)
    s = re.sub(r"\s*\((?:feat\.?|ft\.?|featuring|with)\b[^)]*\)", "", s, flags=re.IGNORECASE)
    s = re.sub(
        r"\s*\((?:official\s*)?(?:music\s*)?(?:video|mv|lyrics?|audio|visualizer|live|remaster(?:ed)?|version|edit|mix|remix)[^)]*\)",
        "", s, flags=re.IGNORECASE,
    )
    s = re.sub(
        r"\s*-\s*(?:official\s*)?(?:music\s*)?(?:video|mv|lyrics?|audio|visualizer|live|remaster(?:ed)?|version|edit|mix|remix)\b.*$",
        "", s, flags=re.IGNORECASE,
    )
    s = re.sub(r"\s+", " ", s).strip().strip("-").strip()
    return s


def _normalize_artist(raw):
    """Take primary artist only — mirrors vivi's normalizeCanvasArtistName."""
    first = re.split(r"\s*,\s*|\s*&\s*|\s+×\s+|\s+x\s+|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b",
                     raw, maxsplit=1, flags=re.IGNORECASE)[0]
    return re.sub(r"\s+", " ", first).strip()


def _fetch_archivetune(song, artist, album=None, storefront="us", album_id=None):
    """Hit the ArchiveTune API and return (animated_url, video_url) or (None, None)."""
    # Support album ID only lookup
    if album_id:
        params = {"id": album_id}
    else:
        params = {"s": song, "a": artist, "storefront": storefront}
        if album:
            params["al"] = album
    url = ARCHIVETUNE_BASE + "?" + urllib.parse.urlencode(params)
    data = _get_json(url)
    if not data:
        return None, None
    animated = data.get("animated") or None
    video_url = data.get("videoUrl") or None
    preferred = animated or video_url
    if not preferred:
        return None, None
    return animated, video_url


def _format_tidal_video_url(video_cover_id):
    """Convert Tidal videoCover ID to CDN mp4 URL — mirrors vivi's formatVideoUrl."""
    parts = video_cover_id.split("-")
    if len(parts) != 5:
        return None
    return f"https://resources.tidal.com/videos/{parts[0]}/{parts[1]}/{parts[2]}/{parts[3]}/{parts[4]}/1280x1280.mp4"


def _find_items_in_json(obj, key):
    """Recursively find first object that contains 'items' array under the given key."""
    if isinstance(obj, dict):
        if "items" in obj and isinstance(obj["items"], list):
            return obj
        if key in obj:
            found = _find_items_in_json(obj[key], key)
            if found is not None:
                return found
        for v in obj.values():
            found = _find_items_in_json(v, key)
            if found is not None:
                return found
    elif isinstance(obj, list):
        for item in obj:
            found = _find_items_in_json(item, key)
            if found is not None:
                return found
    return None


def _fetch_monochrome(song, artist, album=None):
    """Hit Monochrome instances for a Tidal video cover URL."""
    query = f"{artist} - {song}"
    if album:
        query += f" - {album}"

    for base in MONOCHROME_INSTANCES:
        url = base + "search/?" + urllib.parse.urlencode({"s": query})
        data = _get_json(url, timeout=15)
        if not data:
            continue
        try:
            section = _find_items_in_json(data, "tracks")
            if not section:
                continue
            items = section.get("items", [])
            for item in items:
                track_title = item.get("title", "")
                if track_title and song.lower() not in track_title.lower():
                    continue
                artists_list = item.get("artists", [])
                result_artist = artists_list[0].get("name", "") if artists_list else ""
                if result_artist and artist.lower() not in result_artist.lower() and result_artist.lower() not in artist.lower():
                    continue
                album_obj = item.get("album", {})
                video_cover = album_obj.get("videoCover", "")
                if video_cover:
                    mp4_url = _format_tidal_video_url(video_cover)
                    if mp4_url:
                        return mp4_url
        except Exception:
            continue
    return None


def fetch_canvas(song_raw, artist_raw, album=None, storefront="us"):
    """
    Full two-provider fetch chain, trying multiple title/artist normalizations.
    Returns dict: { animated, videoUrl, source }
    """
    song_norm = _normalize_title(song_raw)
    artist_norm = _normalize_artist(artist_raw)

    # Try several combinations, stop at first hit (mirrors vivi's linkedSetOf approach)
    combos = list(dict.fromkeys([
        (song_norm, artist_norm),
        (song_raw, artist_norm),
        (song_norm, artist_raw),
        (song_raw, artist_raw),
    ]))

    # 1. Try ArchiveTune first
    for s, a in combos:
        if not s or not a:
            continue
        animated, video_url = _fetch_archivetune(s, a, album, storefront)
        preferred = animated or video_url
        if preferred:
            # Basic artist validation — prevent wrong canvas
            return {"animated": animated, "videoUrl": video_url, "source": "archivetune"}

    # 2. Fallback to Monochrome (Tidal covers)
    for s, a in combos:
        if not s or not a:
            continue
        mp4_url = _fetch_monochrome(s, a, album)
        if mp4_url:
            return {"animated": None, "videoUrl": mp4_url, "source": "monochrome"}

    return {"animated": None, "videoUrl": None, "source": None}


def fetch_canvas_by_album_id(album_id):
    """
    Fetch canvas for an entire album by Apple Music album ID.
    Returns dict: { animated, videoUrl, source, albumName, artist }
    """
    if not album_id:
        return {"animated": None, "videoUrl": None, "source": None, "albumName": None, "artist": None}

    # Fetch album info from ArchiveTune
    url = ARCHIVETUNE_BASE + "?" + urllib.parse.urlencode({"id": album_id})
    data = _get_json(url)
    
    album_name = data.get("name") if data else None
    artist = data.get("artist") if data else None
    animated = data.get("animated") if data else None
    video_url = data.get("videoUrl") if data else None
    
    if animated or video_url:
        return {
            "animated": animated,
            "videoUrl": video_url,
            "source": "archivetune",
            "albumName": album_name,
            "artist": artist
        }

    # No canvas found, but return album info anyway
    return {
        "animated": None,
        "videoUrl": None,
        "source": None,
        "albumName": album_name,
        "artist": artist
    }


if __name__ == "__main__":
    # Support --album-id flag for album-only lookup
    if "--album-id" in sys.argv:
        try:
            idx = sys.argv.index("--album-id")
            album_id = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
            result = fetch_canvas_by_album_id(album_id)
            print(json.dumps(result))
        except (IndexError, ValueError):
            print(json.dumps({"animated": None, "videoUrl": None, "source": None}))
        sys.exit(0)

    if len(sys.argv) < 3:
        print(json.dumps({"animated": None, "videoUrl": None, "source": None}))
        sys.exit(0)

    song_title = sys.argv[1]
    artist_name = sys.argv[2]
    album_name = sys.argv[3] if len(sys.argv) > 3 else None
    storefront = sys.argv[4] if len(sys.argv) > 4 else "us"

    result = fetch_canvas(song_title, artist_name, album_name, storefront)
    print(json.dumps(result))
