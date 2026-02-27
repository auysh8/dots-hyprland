#!/usr/bin/env python3
"""
Category diagnostics for ytmusicapi.

What this checks:
1) Which mood/genre categories are available for your account/session.
2) Which playlists each category returns.
3) Sample tracks from those playlists.

Run examples:
  python debug_categories.py
  python debug_categories.py --category "Pop"
  python debug_categories.py --category "Rock" --playlist-limit 4 --track-limit 8
"""

import argparse
import os
import sys
from typing import Any

from ytmusicapi import YTMusic


def _base_dir() -> str:
    return os.path.dirname(os.path.abspath(__file__))


def _build_client() -> tuple[YTMusic, str]:
    headers_path = os.path.join(_base_dir(), "headers_auth.json")
    if os.path.exists(headers_path):
        return YTMusic(headers_path), f"authenticated ({headers_path})"
    return YTMusic(), "unauthenticated"


def _normalize_categories(raw: Any) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []

    if isinstance(raw, dict):
        # Expected in recent ytmusicapi: {"Moods & moments": [...], "Genres": [...]}
        for group, entries in raw.items():
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                title = entry.get("title") or entry.get("name") or ""
                params = entry.get("params") or ""
                if title and params:
                    out.append({"group": str(group), "title": str(title), "params": str(params)})
    elif isinstance(raw, list):
        # Fallback for older/alternate shapes.
        for entry in raw:
            if not isinstance(entry, dict):
                continue
            title = entry.get("title") or entry.get("name") or ""
            params = entry.get("params") or ""
            group = entry.get("category") or "Unknown"
            if title and params:
                out.append({"group": str(group), "title": str(title), "params": str(params)})

    # Deduplicate by params while preserving order.
    seen = set()
    deduped: list[dict[str, str]] = []
    for item in out:
        key = item["params"]
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


def _pick_category(categories: list[dict[str, str]], wanted: str) -> dict[str, str] | None:
    q = wanted.strip().lower()
    if not q:
        return None

    # Exact title match first.
    for item in categories:
        if item["title"].lower() == q:
            return item

    # Then substring match.
    for item in categories:
        if q in item["title"].lower():
            return item
    return None


def _playlist_id(item: dict[str, Any]) -> str:
    pid = item.get("playlistId") or item.get("browseId") or ""
    if isinstance(pid, str) and pid.startswith("VL"):
        return pid[2:]
    return str(pid or "")


def _extract_text(node: Any) -> str:
    if isinstance(node, str):
        return node
    if not isinstance(node, dict):
        return ""
    if node.get("simpleText"):
        return str(node["simpleText"])
    runs = node.get("runs")
    if isinstance(runs, list):
        parts = []
        for run in runs:
            if isinstance(run, dict):
                t = run.get("text")
                if t:
                    parts.append(str(t))
        return "".join(parts)
    return ""


def _extract_flex_text(renderer: dict[str, Any], column_index: int) -> str:
    flex = renderer.get("flexColumns")
    if not isinstance(flex, list) or column_index >= len(flex):
        return ""
    col = flex[column_index].get("musicResponsiveListItemFlexColumnRenderer", {})
    return _extract_text(col.get("text", {}))


def _iter_category_item_lists(response: Any):
    stack: list[Any] = [response]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            for key, value in current.items():
                if key == "gridRenderer" and isinstance(value, dict):
                    items = value.get("items")
                    if isinstance(items, list):
                        yield items
                elif key in ("musicCarouselShelfRenderer", "musicImmersiveCarouselShelfRenderer") and isinstance(value, dict):
                    contents = value.get("contents")
                    if isinstance(contents, list):
                        yield contents

                if isinstance(value, (dict, list)):
                    stack.append(value)
        elif isinstance(current, list):
            for item in current:
                if isinstance(item, (dict, list)):
                    stack.append(item)


def _parse_playlist_or_song_entry(item: dict[str, Any]) -> dict[str, str] | None:
    two_row = item.get("musicTwoRowItemRenderer")
    if isinstance(two_row, dict):
        title = _extract_text(two_row.get("title", {})) or "Untitled"
        nav = two_row.get("navigationEndpoint", {})
        browse = nav.get("browseEndpoint", {})
        watch = nav.get("watchEndpoint", {})

        browse_id = browse.get("browseId") or ""
        page_type = (
            (((browse.get("browseEndpointContextSupportedConfigs") or {}).get("browseEndpointContextMusicConfig") or {}).get("pageType") or "")
        )
        playlist_id = ""
        if isinstance(browse_id, str) and browse_id.startswith("VL"):
            playlist_id = browse_id[2:]
        elif isinstance(browse_id, str) and "PLAYLIST" in str(page_type).upper():
            playlist_id = browse_id

        watch_playlist_id = watch.get("playlistId") or ""
        if isinstance(watch_playlist_id, str) and watch_playlist_id.startswith("VL"):
            watch_playlist_id = watch_playlist_id[2:]
        if not playlist_id and watch_playlist_id:
            playlist_id = watch_playlist_id

        if playlist_id:
            return {"kind": "playlist", "title": str(title), "playlistId": str(playlist_id)}

        video_id = watch.get("videoId")
        if video_id:
            artist = _extract_text(two_row.get("subtitle", {}))
            return {
                "kind": "song",
                "title": str(title),
                "artist": str(artist),
                "videoId": str(video_id),
            }

    responsive = item.get("musicResponsiveListItemRenderer")
    if isinstance(responsive, dict):
        title = _extract_flex_text(responsive, 0) or "Untitled"
        artist = _extract_flex_text(responsive, 1)

        playlist_item_data = responsive.get("playlistItemData", {})
        video_id = ""
        if isinstance(playlist_item_data, dict):
            video_id = str(playlist_item_data.get("videoId") or "")

        if not video_id:
            overlay = responsive.get("overlay", {}).get("musicItemThumbnailOverlayRenderer", {})
            play_btn = overlay.get("content", {}).get("musicPlayButtonRenderer", {})
            video_id = str(play_btn.get("playNavigationEndpoint", {}).get("watchEndpoint", {}).get("videoId") or "")

        if video_id:
            return {
                "kind": "song",
                "title": str(title),
                "artist": str(artist),
                "videoId": str(video_id),
            }

    return None


def _collect_items_from_raw_category_response(ytm: YTMusic, params: str) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    response = ytm._send_request(
        "browse",
        {"browseId": "FEmusic_moods_and_genres_category", "params": params},
    )

    playlists: list[dict[str, str]] = []
    songs: list[dict[str, str]] = []
    seen_playlists: set[str] = set()
    seen_songs: set[str] = set()

    for items in _iter_category_item_lists(response):
        for item in items:
            if not isinstance(item, dict):
                continue
            parsed = _parse_playlist_or_song_entry(item)
            if not parsed:
                continue

            if parsed["kind"] == "playlist":
                pid = parsed.get("playlistId", "")
                if not pid or pid in seen_playlists:
                    continue
                seen_playlists.add(pid)
                playlists.append({"title": parsed.get("title", "Untitled Playlist"), "playlistId": pid})
            elif parsed["kind"] == "song":
                vid = parsed.get("videoId", "")
                if not vid or vid in seen_songs:
                    continue
                seen_songs.add(vid)
                songs.append(
                    {
                        "title": parsed.get("title", "Unknown Title"),
                        "artist": parsed.get("artist", "Unknown Artist"),
                        "videoId": vid,
                    }
                )

    return playlists, songs


def _resolve_category_items(ytm: YTMusic, params: str) -> tuple[list[dict[str, str]], list[dict[str, str]], str]:
    parser_note = ""

    playlists: list[dict[str, str]] = []
    try:
        raw_playlists = ytm.get_mood_playlists(params)
        seen: set[str] = set()
        for pl in raw_playlists:
            if not isinstance(pl, dict):
                continue
            pid = _playlist_id(pl)
            if not pid or pid in seen:
                continue
            seen.add(pid)
            title = pl.get("title") or pl.get("name") or "Untitled Playlist"
            playlists.append({"title": str(title), "playlistId": str(pid)})
    except Exception as err:
        parser_note = f"ytmusicapi parser failed ({err.__class__.__name__}); using raw fallback parser."

    raw_playlists, raw_songs = _collect_items_from_raw_category_response(ytm, params)

    # Merge parser playlists with raw fallback playlists.
    merged_playlists = playlists[:]
    seen_playlists = {p["playlistId"] for p in merged_playlists}
    for rp in raw_playlists:
        pid = rp.get("playlistId", "")
        if pid and pid not in seen_playlists:
            seen_playlists.add(pid)
            merged_playlists.append(rp)

    return merged_playlists, raw_songs, parser_note


def _print_categories(categories: list[dict[str, str]], max_rows: int) -> None:
    print(f"\nAvailable categories: {len(categories)}")
    for i, item in enumerate(categories[:max_rows], start=1):
        print(f"{i:02d}. [{item['group']}] {item['title']}")


def _print_category_playlists_and_tracks(
    ytm: YTMusic,
    category: dict[str, str],
    playlist_limit: int,
    track_limit: int,
) -> int:
    print(f"\nCategory: {category['title']}  (group: {category['group']})")
    playlists, songs, parser_note = _resolve_category_items(ytm, category["params"])
    if parser_note:
        print(f"Note: {parser_note}")
    print(f"Playlists returned: {len(playlists)}")
    if songs:
        print(f"Song seeds found in category feed: {len(songs)}")

    tested = 0
    for i, pl in enumerate(playlists[:playlist_limit], start=1):
        title = pl.get("title") or pl.get("name") or "Untitled Playlist"
        pid = _playlist_id(pl)
        if not pid:
            print(f"  {i:02d}. {title} | no playlist id")
            continue

        print(f"  {i:02d}. {title}")
        try:
            tracks = ytm.get_playlist(pid, limit=track_limit).get("tracks", [])
            print(f"      tracks: {len(tracks)}")
            for t in tracks[:3]:
                t_title = t.get("title") or "Unknown Title"
                artists = t.get("artists") or []
                artist = "Unknown Artist"
                if isinstance(artists, list) and artists:
                    artist = artists[0].get("name") or artist
                print(f"        - {t_title} — {artist}")
            tested += 1
        except Exception as err:
            print(f"      error fetching tracks: {err}")

    if tested == 0 and songs:
        print("  Fallback songs (no playlist tracks fetched):")
        for i, song in enumerate(songs[: min(track_limit, 8)], start=1):
            print(f"    {i:02d}. {song.get('title', 'Unknown Title')} — {song.get('artist', 'Unknown Artist')}")
        tested = min(track_limit, len(songs))

    return tested


def main() -> int:
    parser = argparse.ArgumentParser(description="Test category-based discovery via ytmusicapi.")
    parser.add_argument("--category", default="", help='Category title to inspect, e.g. "Pop".')
    parser.add_argument("--max-categories", type=int, default=60, help="Max categories to print.")
    parser.add_argument("--playlist-limit", type=int, default=3, help="Playlists to inspect per category.")
    parser.add_argument("--track-limit", type=int, default=10, help="Tracks to fetch from each playlist.")
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="If no --category is provided, inspect the first category automatically.",
    )
    args = parser.parse_args()

    ytm, mode = _build_client()
    print(f"Client mode: {mode}")
    print("Note: ytmusicapi search() does not have a category parameter.")
    print("Category-based grouping is done via get_mood_categories() + get_mood_playlists().")

    try:
        raw = ytm.get_mood_categories()
    except Exception as err:
        print(f"Failed to fetch categories: {err}")
        return 1

    categories = _normalize_categories(raw)
    if not categories:
        print("No categories found. Raw response type:", type(raw).__name__)
        return 2

    _print_categories(categories, max_rows=max(1, args.max_categories))

    target = None
    if args.category:
        target = _pick_category(categories, args.category)
        if not target:
            print(f'\nCategory "{args.category}" was not found in the available list.')
            return 3
    elif args.smoke:
        target = categories[0]

    if target:
        tested = _print_category_playlists_and_tracks(
            ytm,
            target,
            playlist_limit=max(1, args.playlist_limit),
            track_limit=max(1, args.track_limit),
        )
        if tested == 0:
            print("\nNo playlists were testable for this category.")
            return 4

    return 0


if __name__ == "__main__":
    sys.exit(main())
