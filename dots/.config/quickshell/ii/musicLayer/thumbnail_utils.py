#!/usr/bin/env python3
import re
from urllib.parse import urlsplit, urlunsplit

_YT_THUMB_RE = re.compile(r"^https?://(?:i|img)\.ytimg\.com/vi(?:_webp)?/([^/?#]+)/([^/?#]+)")


def _strip_query(url: str) -> str:
    if not url:
        return ""
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


def extract_video_id_from_thumbnail(url: str) -> str:
    if not url:
        return ""
    match = _YT_THUMB_RE.match(url)
    return match.group(1) if match else ""


def is_video_track(video_id: str = "", art_url: str = "") -> bool:
    if extract_video_id_from_thumbnail(art_url):
        return True
    return bool(video_id and "ytimg.com/vi/" in (art_url or ""))


def normalize_square_art_url(art_url: str, size: int = 544) -> str:
    art = art_url or ""
    if not art:
        return ""
    if "googleusercontent.com" in art and "=w" in art:
        base_url = art.split("=w")[0]
        return f"{base_url}=w{size}-h{size}"
    elif "googleusercontent.com" in art and "=s" in art:
        base_url = art.split("=s")[0]
        return f"{base_url}=s{size}"
    elif "ggpht.com" in art and "=s" in art:
        base_url = art.split("=s")[0]
        return f"{base_url}=s{size}"
    elif "=w" in art and "-h" in art:
        art = re.sub(r"=w\d+-h\d+.*", f"=w{size}-h{size}", art)
    return art


def iter_square_art_candidates(art_url: str, size: int = 544) -> list[str]:
    candidates: list[str] = []
    seen: set[str] = set()

    def add(url: str):
        if url and url not in seen:
            seen.add(url)
            candidates.append(url)

    normalized = normalize_square_art_url(art_url, size=size)
    add(normalized)
    add(_strip_query(normalized))
    add(_strip_query(art_url))
    add(art_url)
    return candidates


def get_landscape_thumbnail_candidates(video_id: str = "", art_url: str = "") -> list[str]:
    candidates: list[str] = []
    seen: set[str] = set()

    def add(url: str):
        if url and url not in seen:
            seen.add(url)
            candidates.append(url)

    resolved_video_id = video_id or extract_video_id_from_thumbnail(art_url)
    if not resolved_video_id:
        return candidates

    base = f"https://i.ytimg.com/vi/{resolved_video_id}"
    add(f"{base}/maxresdefault.jpg")
    add(f"{base}/hq720.jpg")
    add(f"{base}/sddefault.jpg")
    add(f"{base}/hqdefault.jpg")
    return candidates
