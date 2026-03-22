import os
import re
import json
import time
import hashlib
import urllib.request
import threading
from ytmusicapi import YTMusic

class YTMClient:
    _DURATION_RE = re.compile(r"^(?:\d{1,2}:)?[0-5]?\d:[0-5]\d$")
    _HTTP_TIMEOUT = (8, 20)  # connect/read timeout for YTMusic requests
    _HOME_CACHE_TTL_SEC = 60

    _OAUTH_CLIENT_ID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
    _OAUTH_CLIENT_SECRET = "SboVhoG9s0rNafixCSGGKXAT"

    def __init__(self, send_response_callback, logger, player_ref=None):
        self.send_response = send_response_callback
        self.log = logger
        self.player = player_ref  # Reference to Player for accessing _play_stack
        
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



    def _load_canvas_cache(self):
        try:
            if os.path.exists(self._canvas_cache_path):
                with open(self._canvas_cache_path, "r", encoding="utf-8") as f:
                    self._canvas_cache = json.load(f)
        except Exception:
            self._canvas_cache = {}

    def _save_canvas_cache(self):
        try:
            os.makedirs(os.path.dirname(self._canvas_cache_path), exist_ok=True)
            with open(self._canvas_cache_path, "w", encoding="utf-8") as f:
                json.dump(self._canvas_cache, f)
        except Exception:
            pass

    def _make_oauth_credentials(self):
        from ytmusicapi.auth.oauth.credentials import OAuthCredentials
        return OAuthCredentials(self._OAUTH_CLIENT_ID, self._OAUTH_CLIENT_SECRET)

    def _init_ytm(self):
        if os.path.exists(self.oauth_path):
            self.ytm = YTMusic(self.oauth_path, oauth_credentials=self._make_oauth_credentials())
            self.log("Authenticated using oauth.json")
        elif os.path.exists(self.headers_path):
            self.ytm = YTMusic(self.headers_path)
            self.log("Authenticated using headers_auth.json")
        else:
            self.ytm = YTMusic()
            self.log("Running in anonymous mode")
        self._set_default_timeout(self.ytm)

    def _set_default_timeout(self, ytm_client):
        session = getattr(ytm_client, "_session", None)
        if session is None or getattr(session, "_ii_timeout_patched", False):
            return

        import requests.adapters
        from urllib3.util.retry import Retry

        retries = Retry(total=3, backoff_factor=0.5, status_forcelist=[500, 502, 503, 504])
        adapter = requests.adapters.HTTPAdapter(max_retries=retries)
        session.mount('https://', adapter)
        session.mount('http://', adapter)

        original_request = session.request
        timeout = self._HTTP_TIMEOUT

        def request_with_timeout(method, url, **kwargs):
            kwargs.setdefault("timeout", timeout)
            return original_request(method, url, **kwargs)

        session.request = request_with_timeout
        session._ii_timeout_patched = True

    def _get_home_data(self):
        now = time.monotonic()
        with self._home_cache_lock:
            if self._home_cache and (now - self._home_cache_ts) < self._HOME_CACHE_TTL_SEC:
                return self._home_cache

        try:
            home_data = self.ytm.get_home(limit=20)
            with self._home_cache_lock:
                self._home_cache = home_data
                self._home_cache_ts = now
            return home_data
        except Exception as e:
            self.log(f"Failed to fetch home: {e}")
            with self._home_cache_lock:
                return self._home_cache or []

    def _seconds_to_duration(self, total_seconds):
        if not total_seconds or total_seconds <= 0:
            return ""
        hours, rem = divmod(total_seconds, 3600)
        minutes, seconds = divmod(rem, 60)
        if hours > 0:
            return f"{hours}:{minutes:02d}:{seconds:02d}"
        return f"{minutes}:{seconds:02d}"

    def _normalize_duration_text(self, value):
        if not isinstance(value, str):
            return ""
        text = value.strip()
        if not text or not self._DURATION_RE.fullmatch(text):
            return ""
        if text in {"0:00", "00:00", "0:00:00", "00:00:00"}:
            return ""
        return text

    def _extract_nested_duration_text(self, obj, depth=0, max_depth=4):
        if depth > max_depth or obj is None:
            return ""
        if isinstance(obj, str):
            return self._normalize_duration_text(obj)
        if isinstance(obj, dict):
            for key in ("duration", "length", "durationText", "lengthText", "timeText", "simpleText", "text"):
                found = self._extract_nested_duration_text(obj.get(key), depth + 1, max_depth)
                if found:
                    return found
            for value in obj.values():
                found = self._extract_nested_duration_text(value, depth + 1, max_depth)
                if found:
                    return found
        if isinstance(obj, list):
            for entry in obj:
                found = self._extract_nested_duration_text(entry, depth + 1, max_depth)
                if found:
                    return found
        return ""

    def _extract_duration(self, item):
        for key in ("duration", "length", "durationText", "lengthText", "timeText"):
            duration = self._normalize_duration_text(item.get(key))
            if duration:
                return duration
        for key in ("duration_seconds", "durationSeconds", "lengthSeconds"):
            try:
                sec = int(item.get(key, 0))
                if sec > 0:
                    return self._seconds_to_duration(sec)
            except Exception:
                pass
        for key in ("durationMs", "lengthMs"):
            try:
                ms = int(item.get(key, 0))
                if ms > 0:
                    return self._seconds_to_duration(ms // 1000)
            except Exception:
                pass
        return self._extract_nested_duration_text(item)

    def format_track_item(self, item, index_offset=0):
        try:
            artist_name = ""
            artists_list = item.get("artists", [])
            if isinstance(artists_list, list) and artists_list:
                artist_name = artists_list[0].get("name", "")
            if not artist_name:
                artist_name = item.get("artist", "")
            if not artist_name:
                for key in ["subtitle", "longBylineText"]:
                    val = item.get(key)
                    if isinstance(val, dict):
                        val = val.get("runs", [{}])[0].get("text", "")
                    if isinstance(val, str) and val:
                        artist_name = val.split(" • ")[0]
                        break
            if not artist_name:
                artist_name = "Unknown Artist"
            title = item.get("title")
            if not title and item.get("resultType") in ["artist", "profile"]:
                title = artist_name
            if not title:
                title = item.get("name") or "Unknown Title"
            art_url = self._extract_art_url(item)

            artist_id = ""
            if isinstance(artists_list, list) and artists_list:
                artist_id = artists_list[0].get("id", "") or artists_list[0].get("browseId", "")

            final_id = item.get("videoId") or item.get("playlistId") or item.get("browseId")
            if not final_id and item.get("resultType") in ["artist", "profile"] and artist_id:
                final_id = artist_id

            return {
                "id": str(index_offset),
                "videoId": final_id,
                "actualVideoId": item.get("videoId") or "",
                "playlistId": item.get("playlistId") or "",
                "browseId": item.get("browseId") or "",
                "title": title,
                "artist": artist_name,
                "artistId": artist_id,
                "duration": self._extract_duration(item),
                "plays": item.get("views") or item.get("plays") or "",
                "artUrl": art_url,
            }
        except Exception as e:
            self.log(f"Error formatting item: {e}")
            return None

    def _download_art(self, url, path):
        try:
            if os.path.exists(path) and os.path.getsize(path) > 0:
                return True
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=8) as r, open(path, "wb") as f:
                f.write(r.read())
            return True
        except Exception as e:
            self.log(f"Art download failed: {e}")
            return False

    def _item_video_id(self, item):
        return item.get("videoId") or item.get("playlistId") or item.get("browseId")

    def _extract_art_url(self, item, size=544):
        thumbnails = item.get("thumbnails") or item.get("thumbnail") or []
        if isinstance(thumbnails, dict):
            thumbnails = thumbnails.get("thumbnails", [])
        if isinstance(thumbnails, list) and thumbnails:
            last_thumb = thumbnails[-1]
            art = last_thumb.get("url", "") if isinstance(last_thumb, dict) else ""
        else:
            art = ""
        if art:
            if "=w" in art and "-h" in art:
                art = re.sub(r"=w\d+-h\d+", f"=w{size}-h{size}", art)
            elif "googleusercontent.com" in art and "=s" in art:
                art = re.sub(r"=s\d+", f"=s{size}", art)
        return art

    def _append_unique(self, target, source, cap=96):
        if not source:
            return
        seen_local = {self._item_video_id(i) for i in target if self._item_video_id(i)}
        for item in source:
            vid = self._item_video_id(item)
            if not vid or vid in seen_local:
                continue
            target.append(item)
            seen_local.add(vid)
            if len(target) >= cap:
                break

    def _to_section_items(self, raw_items, limit, index_offset, sent_ids):
        out = []
        for item in raw_items:
            vid = self._item_video_id(item)
            if not vid or vid in sent_ids:
                continue
            fmt = self.format_track_item(item, index_offset + len(out))
            if not fmt:
                continue
            out.append(fmt)
            sent_ids.add(vid)
            if len(out) >= limit:
                break
        return out

    def _search_songs_for_home(self, query, limit=16):
        try:
            return self.ytm.search(query, filter="songs", limit=limit)
        except Exception as e:
            self.log(f"Personalized search failed for '{query}': {e}")
            return []

    def _pick_artists(self, items, limit=3):
        scores = {}
        for item in items:
            name = ""
            artists = item.get("artists")
            if isinstance(artists, list) and artists:
                name = artists[0].get("name", "")
            if not name:
                name = item.get("artist", "")
            if not name:
                continue
            scores[name] = scores.get(name, 0) + 1
        ranked = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
        return [name for name, _ in ranked[:limit]]

    def _build_history_track_pools(self, recent_history):
        from concurrent.futures import ThreadPoolExecutor, as_completed

        history_quick_tracks = []
        history_discover_tracks = []
        history_seed_ids = recent_history[:6]

        results = {}
        with ThreadPoolExecutor(max_workers=6) as pool:
            futures = {pool.submit(self.fetch_playlist, vid): idx for idx, vid in enumerate(history_seed_ids)}
            for future in as_completed(futures):
                idx = futures[future]
                try:
                    results[idx] = future.result()
                except Exception:
                    results[idx] = []

        for idx in sorted(results.keys()):
            if idx < 3:
                self._append_unique(history_quick_tracks, results[idx], cap=96)
            else:
                self._append_unique(history_discover_tracks, results[idx], cap=96)

        if not history_discover_tracks:
            self._append_unique(history_discover_tracks, history_quick_tracks, cap=96)

        history_seed_tracks = []
        self._append_unique(history_seed_tracks, history_quick_tracks, cap=128)
        self._append_unique(history_seed_tracks, history_discover_tracks, cap=128)
        return history_quick_tracks, history_discover_tracks, history_seed_tracks

    def _collect_home_section_candidates(self, home_data, rec_keywords, pick_keywords, discover_keywords):
        picks_raw = []
        recs_raw = []
        discover_raw = []
        discover_title = "Forgotten favourites"
        discover_playlist_candidates = []
        other_playable = []

        for section in home_data:
            title = section.get("title", "")
            t_lower = title.lower()
            contents = section.get("contents", [])

            playable = [c for c in contents if c.get("videoId") or c.get("playlistId") or c.get("browseId")]

            matched = False
            if any(k in t_lower for k in pick_keywords):
                self._append_unique(picks_raw, playable, cap=64)
                matched = True
            elif any(k in t_lower for k in rec_keywords):
                self._append_unique(recs_raw, playable, cap=64)
                matched = True
            elif any(k in t_lower for k in discover_keywords):
                self._append_unique(discover_raw, playable, cap=64)
                if playable and discover_title == "Forgotten favourites":
                    discover_title = title or discover_title
                matched = True

            if not matched and playable:
                other_playable.append(playable)

            for c in contents:
                pid = c.get("playlistId") or c.get("browseId")
                if pid and pid.startswith("VL"):
                    pid = pid[2:]
                if pid:
                    discover_playlist_candidates.append((pid, c.get("title", title) or title))
                    break

        if not picks_raw and other_playable:
            self._append_unique(picks_raw, other_playable.pop(0), cap=64)
        if not recs_raw and other_playable:
            self._append_unique(recs_raw, other_playable.pop(0), cap=64)
        if not discover_raw and other_playable:
            self._append_unique(discover_raw, other_playable.pop(0), cap=64)

        return picks_raw, recs_raw, discover_raw, discover_title, discover_playlist_candidates

    def _seed_discover_from_playlists(self, discover_raw, history_discover_tracks, discover_playlist_candidates, discover_title):
        if discover_raw or history_discover_tracks or not discover_playlist_candidates:
            return discover_raw, discover_title

        for pid, candidate_title in discover_playlist_candidates[:2]:
            try:
                tracks = self.ytm.get_playlist(pid, limit=24).get("tracks", [])
                if tracks:
                    self._append_unique(discover_raw, tracks, cap=64)
                    discover_title = candidate_title or discover_title
                    break
            except Exception:
                pass

        return discover_raw, discover_title

    def _build_recommendations_section(self, recs_raw, sent_ids):
        rec_pool = []
        self._append_unique(rec_pool, recs_raw, cap=96)
        return self._to_section_items(rec_pool, limit=16, index_offset=0, sent_ids=sent_ids)

    def _build_quick_picks_section(self, picks_raw, sent_ids):
        pick_pool = []
        self._append_unique(pick_pool, picks_raw, cap=96)
        if not pick_pool:
            try:
                fallback = self.ytm.get_watch_playlist(
                    playlistId="RDTMAK5uy_kset8DisdE7LSD4TNjEVvrKRTmG7a56sY", limit=24
                ).get("tracks", [])
                self._append_unique(pick_pool, fallback, cap=96)
            except Exception:
                pass
        return self._to_section_items(pick_pool, limit=16, index_offset=100, sent_ids=sent_ids)

    def _build_discover_section(self, history_discover_tracks, discover_raw, artist_profile, sent_ids, discover_title):
        discover_pool = []
        self._append_unique(discover_pool, discover_raw, cap=96)

        if not discover_pool and history_discover_tracks:
            self._append_unique(discover_pool, history_discover_tracks, cap=96)
            if discover_title == "Forgotten favourites":
                discover_title = "From Your History"

        if len(discover_pool) < 20:
            for artist in artist_profile[:3]:
                self._append_unique(
                    discover_pool,
                    self._search_songs_for_home(f"{artist} new release", limit=10),
                    cap=96,
                )
                self._append_unique(
                    discover_pool,
                    self._search_songs_for_home(f"{artist} latest songs", limit=10),
                    cap=96,
                )
                if len(discover_pool) >= 20:
                    break
        if not discover_pool:
            self._append_unique(
                discover_pool,
                self._search_songs_for_home("Trending Songs", limit=40),
                cap=96,
            )
            discover_title = "Trending Songs"

        shorts = []
        for item in discover_pool:
            vid = self._item_video_id(item)
            if not vid or vid in sent_ids:
                continue
            fmt = self.format_track_item(item, 200 + len(shorts))
            if not fmt:
                continue
            dur = fmt.get("duration", "")
            is_normal_song = True
            if "Trending" in discover_title and dur and dur.count(":") == 1:
                try:
                    mins = int(dur.split(":")[0])
                    if mins >= 10:
                        is_normal_song = False
                except Exception:
                    pass
            if is_normal_song:
                shorts.append(fmt)
                sent_ids.add(vid)
            if len(shorts) >= 16:
                break

        return shorts, discover_title

    def _append_search_songs(self, songs, song_ids, items, song_limit, allowed_types=None):
        for item in items:
            if allowed_types and item.get("resultType") not in allowed_types:
                continue
            fmt = self.format_track_item(item, len(songs))
            if not fmt:
                continue
            vid = fmt.get("videoId")
            if not vid or vid in song_ids:
                continue
            songs.append(fmt)
            song_ids.add(vid)
            if len(songs) >= song_limit:
                break

    def _collect_search_cards(self, items):
        artists = []
        albums = []
        for i, item in enumerate(items):
            fmt = self.format_track_item(item, i)
            if not fmt:
                continue
            rt = item.get("resultType")
            if rt == "artist":
                self.log(f"[DEBUG] Artist card: videoId={fmt.get('videoId')}, title={fmt.get('title')}, browseId={item.get('browseId')}")
                artists.append(fmt)
            elif rt == "album":
                albums.append(fmt)
        return artists, albums

    def _backfill_missing_song_durations(self, songs_to_send):
        missing_duration = [s for s in songs_to_send if not s.get("duration") and s.get("videoId")]
        if not missing_duration:
            return songs_to_send

        from concurrent.futures import ThreadPoolExecutor

        def fill_duration(song_item):
            try:
                data = self.ytm.get_song(song_item["videoId"])
                sec = int(data.get("videoDetails", {}).get("lengthSeconds", 0))
                if sec > 0:
                    song_item["duration"] = self._seconds_to_duration(sec)
            except Exception:
                pass
            return song_item

        with ThreadPoolExecutor(max_workers=4) as executor:
            return list(executor.map(fill_duration, songs_to_send))

    def get_home(self):
        self.log("UI requested get_home")
        threading.Thread(target=self._fetch_home_task, daemon=True).start()

    def _fetch_home_task(self):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                self.send_response({"type": "error", "message": "Failed to connect to YouTube Music."})
                return

        self.log("Executing fully personalized home fetch...")
        sent_ids = set()
        recent_history = list(reversed(self.player._play_stack[-8:])) if self.player and hasattr(self.player, '_play_stack') else []

        home_data = self._get_home_data()

        rec_keywords = ("listen again",)
        pick_keywords = ("quick pick", "quick picks", "top picks", "picked for you")
        discover_keywords = ("forgotten", "favourite", "favorite", "listen again", "discover")

        picks_raw, recs_raw, discover_raw, discover_title, discover_playlist_candidates = (
            self._collect_home_section_candidates(home_data, rec_keywords, pick_keywords, discover_keywords)
        )

        history_quick_tracks, history_discover_tracks, history_seed_tracks = (
            self._build_history_track_pools(recent_history)
        )

        discover_raw, discover_title = self._seed_discover_from_playlists(
            discover_raw, history_discover_tracks, discover_playlist_candidates, discover_title
        )

        artist_profile = self._pick_artists(history_seed_tracks + recs_raw + picks_raw, limit=4)

        # --- STREAM RECOMMENDATIONS (Listen Again) ---
        if len(recs_raw) < 8:
            self._append_unique(recs_raw, history_seed_tracks, cap=96)
        recs = self._build_recommendations_section(recs_raw, sent_ids)
        self.send_response({"type": "home_section", "section": "recommendations", "items": recs})
        self.log(f"Streamed {len(recs)} Listen Again (Recommendations)")

        time.sleep(0.4)

        # --- STREAM QUICK PICKS ---
        picks = self._build_quick_picks_section(picks_raw, sent_ids)
        self.send_response({"type": "home_section", "section": "quick_picks", "items": picks})
        self.log(f"Streamed {len(picks)} Quick Picks")

        time.sleep(0.4)

        # --- STREAM DISCOVER ---
        shorts, discover_title = self._build_discover_section(
            history_discover_tracks, discover_raw, artist_profile, sent_ids, discover_title
        )
        self.send_response({"type": "home_section", "section": "shorts", "items": shorts, "title": discover_title})
        self.log(f"Streamed {len(shorts)} Discover items ({discover_title})")

    def get_explore(self):
        self.log("UI requested get_explore")
        if self._explore_cache and (time.time() - self._explore_cache["ts"]) < self._explore_cache_ttl:
            self.log("Serving explore from cache (< 15 min old)")
            for section in self._explore_cache["sections"]:
                self.send_response(section)
            return
        threading.Thread(target=self._fetch_explore_task, daemon=True).start()

    def _toggle_like_task(self, video_id, is_liked):
        if not video_id:
            return
        try:
            if os.path.exists(self.oauth_path) or os.path.exists(self.headers_path):
                status = "LIKE" if is_liked else "INDIFFERENT"
                self.ytm.rate_song(video_id, status)
                self.log(f"Successfully rated song {video_id} as {status}")
                if video_id in self._song_meta_cache:
                    self._song_meta_cache[video_id]["is_liked"] = is_liked
        except Exception as e:
            self.log(f"Failed to rate song on YouTube Music: {e}")

    def _fetch_explore_task(self):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                return

        self.log("Fetching explore data via get_charts(IN)...")
        sent_ids = set()

        trending_items = []
        try:
            self.log("Fetching real-time trending charts for IN...")
            charts = self.ytm.get_charts(country="IN")

            playlist_ids = []
            for item in charts.get("daily", []):
                if "Trending" in item.get("title", "") or "Videos" in item.get("title", ""):
                    playlist_ids.append(item.get("playlistId"))
                    break

            for item in charts.get("weekly", []):
                if "Hindi" in item.get("title", ""):
                    playlist_ids.append(item.get("playlistId"))
                    break

            for pid in playlist_ids:
                if not pid:
                    continue
                raw_tracks = self.ytm.get_watch_playlist(playlistId=pid, limit=25).get("tracks", [])

                for item in raw_tracks:
                    vid = self._item_video_id(item)
                    if not vid or vid in sent_ids:
                        continue

                    vtype = item.get("videoType", "")
                    if vtype in ("MUSIC_VIDEO_TYPE_UGC", "MUSIC_VIDEO_TYPE_PODCAST_EPISODE"):
                        continue

                    fmt = self.format_track_item(item, len(trending_items))
                    if fmt:
                        trending_items.append(fmt)
                        sent_ids.add(vid)

                    if len(trending_items) >= 16:
                        break

                if len(trending_items) >= 16:
                    break

        except Exception as e:
            self.log(f"Dynamic Trending fetch failed: {e}")

        trending_response = {"type": "explore_section", "section": "trending", "items": trending_items}
        self.send_response(trending_response)
        self.log(f"Streamed {len(trending_items)} trending songs")

        # --- STREAM NEW RELEASES ---
        new_releases_items = []
        try:
            self.log("Fetching new releases from explore page...")
            explore_data = self.ytm.get_explore()
            releases = explore_data.get("new_releases", [])[:16]

            for release in releases:
                vid = release.get("videoId") or release.get("audioPlaylistId") or release.get("playlistId")
                if not vid:
                    continue

                release_thumbs = release.get("thumbnails", [])
                art_url = release_thumbs[-1].get("url", "") if release_thumbs else ""
                if art_url:
                    if "=w" in art_url and "-h" in art_url:
                        art_url = re.sub(r"=w\d+-h\d+", "=w544-h544", art_url)
                    elif "googleusercontent.com" in art_url and "=s" in art_url:
                        art_url = re.sub(r"=s\d+", "=s544", art_url)

                artist_name = "Unknown Artist"
                artists_list = release.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    artist_name = artists_list[0].get("name", "")
                elif isinstance(artists_list, str):
                    artist_name = artists_list

                new_releases_items.append({
                    "id": str(100 + len(new_releases_items)),
                    "videoId": vid,
                    "title": release.get("title", "Unknown"),
                    "artist": artist_name,
                    "duration": self._extract_duration(release) or "",
                    "artUrl": art_url,
                })
                sent_ids.add(vid)
        except Exception as e:
            self.log(f"New releases fetch failed: {e}")

        new_releases_response = {"type": "explore_section", "section": "new_releases", "items": new_releases_items}
        self.send_response(new_releases_response)
        self.log(f"Streamed {len(new_releases_items)} new releases — explore complete")

        self._explore_cache = {
            "ts": time.time(),
            "sections": [trending_response, new_releases_response],
        }
        self.log("Explore data cached for 15 minutes")

    def get_library(self):
        self.log("UI requested get_library")
        threading.Thread(target=self._fetch_library_task, daemon=True).start()

    def _fetch_library_task(self):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                return

        self.log("Fetching library data...")

        recent_tracks = []
        history_item = None

        try:
            if (os.path.exists(self.oauth_path) or os.path.exists(self.headers_path)) and getattr(self.ytm, 'get_history', None):
                self.log("Fetching account play history from YouTube Music...")
                account_history = self.ytm.get_history()

                seen_vids = set()
                index = 0
                for item in account_history:
                    vid = item.get("videoId")
                    if not vid or vid in seen_vids:
                        continue

                    art = ""
                    thumbs = item.get("thumbnails", [])
                    if thumbs:
                        art = thumbs[-1].get("url", "")
                        if "=w" in art and "-h" in art:
                            art = re.sub(r"=w\d+-h\d+", "=w544-h544", art)

                    artist_name = "Unknown Artist"
                    artists = item.get("artists", [])
                    if isinstance(artists, list) and artists:
                        artist_name = artists[0].get("name", "Unknown Artist")

                    track_item = {
                        "id": str(index),
                        "videoId": vid,
                        "title": item.get("title", ""),
                        "artist": artist_name,
                        "cover": art,
                    }
                    recent_tracks.append(track_item)
                    if index == 0:
                        history_item = track_item

                    seen_vids.add(vid)
                    index += 1
                    if len(recent_tracks) >= 10:
                        break

                if recent_tracks:
                    self.log("Successfully fetched recent tracks from account.")
        except Exception as e:
            self.log(f"Account history fetch failed (will fallback): {e}")

        self.send_response({"type": "library_section", "section": "recent_tracks", "items": recent_tracks})

        playlists = []
        liked_song_count = 0
        liked_song_art = ""
        try:
            lib_playlists = self.ytm.get_library_playlists(limit=25)
            for p in lib_playlists:
                title = p.get("title", "")
                count = str(p.get("count", "0"))
                art = ""
                thumbs = p.get("thumbnails", [])
                if thumbs:
                    art = thumbs[-1].get("url", "")
                    if "=w" in art and "-h" in art:
                        art = re.sub(r"=w\d+-h\d+", "=w544-h544", art)

                if title in ["Your Likes", "Liked Music"]:
                    try:
                        liked_song_count = int(count)
                    except Exception:
                        liked_song_count = 0
                    liked_song_art = art
                else:
                    playlists.append({
                        "id": p.get("playlistId", ""),
                        "title": title,
                        "count": count,
                        "cover": art
                    })
        except Exception as e:
            self.log(f"Failed to fetch library playlists: {e}")

        if liked_song_count == 0:
            try:
                liked = self.ytm.get_liked_songs(limit=1)
                if liked and "trackCount" in liked:
                    liked_song_count = int(liked["trackCount"])
                    if liked.get("thumbnails"):
                        liked_song_art = liked["thumbnails"][-1].get("url", "")
            except Exception:
                pass

        self.send_response({
            "type": "library_section",
            "section": "playlists",
            "items": playlists,
            "likedCount": liked_song_count,
            "likedArt": liked_song_art
        })

        community_playlists = []
        try:
            home_data = self.ytm.get_home(limit=10)
            for shelf in home_data:
                if "community" in str(shelf.get("title", "")).lower():
                    for r in shelf.get("contents", [])[:8]:
                        thumbs = r.get("thumbnails", [])
                        art = thumbs[-1].get("url", "") if thumbs else ""
                        if art and "=w" in art and "-h" in art:
                            art = re.sub(r"=w\d+-h\d+", "=w544-h544", art)
                        elif "googleusercontent.com" in art and "=s" in art:
                            art = re.sub(r"=s\d+", "=s544", art)

                        community_playlists.append({
                            "id": str(r.get("playlistId") or ""),
                            "title": str(r.get("title") or ""),
                            "artist": str(r.get("description") or ""),
                            "cover": str(art or "")
                        })
                    break
        except Exception as e:
            self.log(f"Failed to fetch community shelf from home: {e}")

        if not community_playlists:
            try:
                artist = history_item.get("artist", "") if history_item else ""
                title = history_item.get("title", "") if history_item else ""
                query = f"{artist} {title} community playlists" if artist and title else "popular community playlists"
                results = self.ytm.search(query, filter="playlists", limit=6)

                for r in results:
                    thumbs = r.get("thumbnails", [])
                    art = thumbs[-1].get("url", "") if thumbs else ""
                    if art and "=w" in art and "-h" in art:
                        art = re.sub(r"=w\d+-h\d+", "=w544-h544", art)

                    community_playlists.append({
                        "id": str(r.get("browseId") or ""),
                        "title": str(r.get("title") or ""),
                        "artist": str(r.get("author") or ""),
                        "cover": str(art or "")
                    })
            except Exception as e:
                self.log(f"Failed to search fallback community playlists: {e}")

        self.send_response({"type": "library_section", "section": "community_playlists", "items": community_playlists})
        self.log("Streamed library data complete.")

    def get_artist(self, channel_id):
        threading.Thread(target=self._artist_task, args=(channel_id,), daemon=True).start()

    def _artist_task(self, channel_id):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                self.send_response({"type": "error", "message": "Connection error."})
                return

        try:
            self.log(f"Fetching artist: {channel_id}")
            data = self.ytm.get_artist(channel_id)
            if not data:
                raise ValueError("Artist not found.")

            name = data.get("name", "Unknown Artist")
            description = data.get("description", "")
            subscribers = data.get("subscribers", "")
            views = data.get("views", "")

            thumbs = data.get("thumbnails", [])
            thumb_url = self._extract_art_url(data) if thumbs else ""

            songs_data = data.get("songs", {})
            songs_browse_id = songs_data.get("browseId", "")
            top_songs = []
            for item in (songs_data.get("results", []) or []):
                vid = item.get("videoId")
                if not vid:
                    continue
                artist_name = "Unknown"
                artists_list = item.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    artist_name = artists_list[0].get("name", "Unknown")
                top_songs.append({
                    "videoId": vid,
                    "title": item.get("title", "Unknown"),
                    "artist": artist_name,
                    "artUrl": self._extract_art_url(item),
                    "duration": self._extract_duration(item) or "",
                    "plays": item.get("views", ""),
                })

            albums_data = data.get("albums", {})
            albums_browse_id = albums_data.get("browseId", "")
            albums_params = albums_data.get("params", "")
            albums = []
            for item in (albums_data.get("results", []) or []):
                browse_id = item.get("browseId", "")
                if not browse_id:
                    continue
                albums.append({
                    "browseId": browse_id,
                    "title": item.get("title", ""),
                    "year": item.get("year", ""),
                    "artUrl": self._extract_art_url(item),
                    "type": item.get("type", "Album"),
                })

            singles_data = data.get("singles", {})
            singles_browse_id = singles_data.get("browseId", "")
            singles_params = singles_data.get("params", "")
            singles = []
            for item in (singles_data.get("results", []) or []):
                browse_id = item.get("browseId", "")
                if not browse_id:
                    continue
                singles.append({
                    "browseId": browse_id,
                    "title": item.get("title", ""),
                    "year": item.get("year", ""),
                    "artUrl": self._extract_art_url(item),
                    "type": "Single",
                })

            related_data = data.get("related", {})
            related = []
            for item in (related_data.get("results", []) or []):
                bid = item.get("browseId", "")
                if not bid:
                    continue
                related.append({
                    "browseId": bid,
                    "name": item.get("title", "") or item.get("name", ""),
                    "subscribers": item.get("subscribers", ""),
                    "artUrl": self._extract_art_url(item),
                })

            self.send_response({
                "type": "artist_details",
                "channelId": channel_id,
                "name": name,
                "description": description,
                "subscribers": subscribers,
                "views": views,
                "thumbnailUrl": thumb_url,
                "topSongs": top_songs,
                "albums": albums,
                "singles": singles,
                "relatedArtists": related,
                "songsBrowseId": songs_browse_id,
                "albumsParams": albums_params,
                "singlesParams": singles_params,
                "albumsBrowseId": albums_browse_id,
                "singlesBrowseId": singles_browse_id,
            })
            self.log(f"Artist loaded: {name} — {len(top_songs)} songs, {len(albums)} albums, {len(singles)} singles")

        except Exception as e:
            self.log(f"Failed to fetch artist {channel_id}: {e}")
            self.send_response({"type": "error", "message": "Couldn't load artist."})

    def get_artist_items(self, channel_id, params, item_type):
        threading.Thread(target=self._artist_items_task, args=(channel_id, params, item_type), daemon=True).start()

    def _artist_items_task(self, channel_id, params, item_type):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                return

        try:
            self.log(f"Fetching full artist {item_type} for {channel_id}")
            results = []
            try:
                results = self.ytm.get_artist_albums(channel_id, params, limit=200)
            except Exception as yt_err:
                self.log(f"ytmusicapi get_artist_albums failed ({yt_err}), falling back to manual browse")
                raw = self.ytm._send_request('browse', {'browseId': channel_id, 'params': params})
                tabs = raw.get('contents', {}).get('singleColumnBrowseResultsRenderer', {}).get('tabs', [])
                if tabs:
                    content = tabs[0].get('tabRenderer', {}).get('content', {})
                    sections = content.get('sectionListRenderer', {}).get('contents', [])
                    for sec in sections:
                        nodes = None
                        sec_title = ""
                        if 'gridRenderer' in sec:
                            nodes = sec['gridRenderer'].get('items', [])
                            header = sec['gridRenderer'].get('header', {})
                            if 'gridHeaderRenderer' in header:
                                sec_title = "".join(r.get("text", "") for r in header['gridHeaderRenderer'].get('title', {}).get('runs', []))
                        elif 'musicCarouselShelfRenderer' in sec:
                            nodes = sec['musicCarouselShelfRenderer'].get('contents', [])
                            header = sec['musicCarouselShelfRenderer'].get('header', {})
                            sec_title = "".join(r.get("text", "") for r in header.get('musicCarouselShelfBasicHeaderRenderer', {}).get('title', {}).get('runs', []))

                        if sec_title:
                            st = sec_title.lower()
                            if item_type == "albums" and "album" not in st:
                                continue
                            if item_type == "singles" and "single" not in st and "ep" not in st:
                                continue

                        if nodes:
                            added_any = False
                            for n in nodes:
                                data = n.get('musicTwoRowItemRenderer')
                                if not data:
                                    continue
                                bid = data.get('navigationEndpoint', {}).get('browseEndpoint', {}).get('browseId', '')
                                title = "".join(r.get("text", "") for r in data.get("title", {}).get("runs", []))
                                year_parts = []
                                for r in data.get("subtitle", {}).get("runs", []):
                                    t = r.get("text", "")
                                    if t and t.strip() and t != "•":
                                        year_parts.append(t.strip())

                                t_val = year_parts[0] if len(year_parts) > 1 else (year_parts[0] if len(year_parts) == 1 else item_type.capitalize())

                                results.append({
                                    "browseId": bid,
                                    "title": title,
                                    "year": year_parts[-1] if year_parts else "",
                                    "type": t_val,
                                    "thumbnails": data.get("thumbnailRenderer", {}).get("musicThumbnailRenderer", {}).get("thumbnail", {}).get("thumbnails", [])
                                })
                                added_any = True

                            if added_any:
                                break

            items = []
            for item in results:
                browse_id = item.get("browseId", "")
                if not browse_id:
                    continue
                t = item.get("type", item_type.capitalize())
                t_lower = t.lower()

                if item_type == "albums" and ("single" in t_lower or "ep" in t_lower):
                    continue
                if item_type == "singles" and "album" in t_lower:
                    continue

                items.append({
                    "browseId": browse_id,
                    "title": item.get("title", ""),
                    "year": item.get("year", ""),
                    "artUrl": self._extract_art_url(item),
                    "type": t,
                })

            self.send_response({
                "type": f"artist_full_{item_type}",
                "channelId": channel_id,
                "items": items,
            })
        except Exception as e:
            self.log(f"Failed to fetch artist {item_type} for {channel_id}: {e}")
            self.send_response({"type": "error", "message": f"Couldn't load full {item_type}."})

    def get_artist_full_songs(self, channel_id, songs_browse_id):
        threading.Thread(target=self._artist_full_songs_task, args=(channel_id, songs_browse_id), daemon=True).start()

    def _artist_full_songs_task(self, channel_id, songs_browse_id):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                return

        try:
            self.log(f"Fetching full artist songs for {channel_id} via playlist {songs_browse_id}")
            p = self.ytm.get_playlist(songs_browse_id, limit=10)
            items = p.get("tracks", []) if p else []

            songs = []
            for t in items:
                art = ""
                thumbs = t.get("thumbnails", [])
                if thumbs:
                    art = thumbs[-1].get("url", "")
                    if "=w" in art and "-h" in art:
                        art = re.sub(r"=w\d+-h\d+", "=w544-h544", art)

                artist_name = "Unknown Artist"
                if t.get("artists"):
                    artist_name = ", ".join([a.get("name", "") for a in t.get("artists")])

                songs.append({
                    "videoId": t.get("videoId"),
                    "title": t.get("title", ""),
                    "artist": artist_name,
                    "duration": t.get("duration", ""),
                    "artUrl": art,
                    "plays": t.get("views", "")
                })

            self.send_response({
                "type": "artist_full_songs",
                "channelId": channel_id,
                "items": songs,
            })
        except Exception as e:
            self.log(f"Failed to fetch full artist songs {channel_id}: {e}")
            self.send_response({"type": "error", "message": "Couldn't load full songs."})

    def get_playlist(self, browse_id):
        threading.Thread(target=self._playlist_task, args=(browse_id,), daemon=True).start()

    def _playlist_task(self, browse_id):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                self.send_response({"type": "error", "message": "Connection error."})
                return

        try:
            tracks = []
            title = "Playlist"
            author = ""
            cover_url = ""
            track_count = 0
            description = ""

            if browse_id in ["LM", "Liked Music"]:
                p = self.ytm.get_liked_songs(limit=None)
                if not p:
                    raise ValueError("Could not load liked songs.")

                title = "Liked Songs"
                track_count = p.get("trackCount", 0)
                items = p.get("tracks", [])

                for item in items:
                    thumbs = item.get("thumbnails", [])
                    if thumbs:
                        cover_url = thumbs[-1].get("url", "")
                        break

            elif browse_id.startswith("MPREb_"):
                p = self.ytm.get_album(browse_id)
                if not p:
                    raise ValueError("Album not found.")

                title = p.get("title", "")
                artists_list = p.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    author = ", ".join([a.get("name", "") for a in artists_list])
                else:
                    author = "Unknown Artist"

                description = p.get("description", "")
                track_count = p.get("trackCount", 0)
                thumbs = p.get("thumbnails", [])
                if thumbs:
                    cover_url = thumbs[-1].get("url", "")
                    if "=w" in cover_url and "-h" in cover_url:
                        cover_url = re.sub(r"=w\d+-h\d+", "=w544-h544", cover_url)

                items = p.get("tracks", [])
            else:
                p = self.ytm.get_playlist(browse_id, limit=None)
                if not p:
                    raise ValueError("Playlist not found.")

                title = p.get("title", "")
                author = p.get("author", {}).get("name", "") if isinstance(p.get("author"), dict) else p.get("author", "")
                description = p.get("description", "")
                track_count = p.get("trackCount", 0)
                thumbs = p.get("thumbnails", [])
                if thumbs:
                    cover_url = thumbs[-1].get("url", "")
                    if "=w" in cover_url and "-h" in cover_url:
                        cover_url = re.sub(r"=w\d+-h\d+", "=w544-h544", cover_url)

                items = p.get("tracks", [])

            for t in items:
                art = ""
                thumbs = t.get("thumbnails", [])
                if thumbs:
                    art = thumbs[-1].get("url", "")
                    if "=w" in art and "-h" in art:
                        art = re.sub(r"=w\d+-h\d+", "=w544-h544", art)

                artist_name = "Unknown Artist"
                if t.get("artists"):
                    artist_name = ", ".join([a.get("name", "") for a in t.get("artists")])

                tracks.append({
                    "videoId": t.get("videoId"),
                    "title": t.get("title", ""),
                    "artist": artist_name,
                    "duration": t.get("duration", ""),
                    "artUrl": art
                })

            self.send_response({
                "type": "playlist_details",
                "id": browse_id,
                "title": title,
                "author": author,
                "description": description,
                "cover": cover_url,
                "trackCount": track_count,
                "tracks": tracks
            })

        except Exception as e:
            self.log(f"Failed to fetch playlist {browse_id}: {e}")
            self.send_response({"type": "error", "message": "Couldn't load playlist."})

    def search(self, query, song_limit=20):
        threading.Thread(target=self._search_task, args=(query, song_limit), daemon=True).start()

    def _search_task(self, query, song_limit=20):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                self.send_response({"type": "error", "message": "Connection error."})
                return

        try:
            try:
                song_limit = max(10, min(20, int(song_limit)))
            except Exception:
                song_limit = 20

            cache_key = query.strip().lower()
            cached = self._search_cache.get(cache_key)
            if cached and (time.time() - cached["ts"]) < self._search_cache_ttl:
                self.log(f"Serving search results from cache for '{query}'")
                self.send_response(cached["response"])
                return

            artists, songs, albums = [], [], []
            song_ids = set()

            general_limit = max(30, song_limit + 10)
            general_results = self.ytm.search(query, limit=general_limit)

            artists, albums = self._collect_search_cards(general_results)

            try:
                self._append_search_songs(
                    songs, song_ids, self.ytm.search(query, filter="songs", limit=song_limit), song_limit
                )
            except Exception as e:
                self.log(f"Song search fallback (songs) failed: {e}")

            if len(songs) < song_limit:
                try:
                    self._append_search_songs(
                        songs, song_ids, self.ytm.search(query, filter="videos", limit=song_limit), song_limit
                    )
                except Exception as e:
                    self.log(f"Song search fallback (videos) failed: {e}")

            if len(songs) < song_limit:
                self._append_search_songs(
                    songs, song_ids, general_results, song_limit, allowed_types={"song", "video"}
                )

            songs_to_send = songs[:song_limit]
            songs_has_more = len(songs_to_send) > 5

            songs_to_send = self._backfill_missing_song_durations(songs_to_send)

            response = {
                "type": "search_results",
                "query": query,
                "artists": artists[:5],
                "songs": songs_to_send,
                "songLimit": song_limit,
                "songsHasMore": songs_has_more,
                "albums": albums[:5],
            }
            self.send_response(response)

            self._search_cache[cache_key] = {"ts": time.time(), "response": response}
            self.log(f"Search results cached for '{query}'")

            now = time.time()
            stale_keys = [k for k, v in self._search_cache.items() if (now - v["ts"]) > self._search_cache_ttl]
            for k in stale_keys:
                del self._search_cache[k]

        except Exception as e:
            self.log(f"Search error: {e}")

    def get_search_suggestions(self, query):
        threading.Thread(target=self._search_suggestions_task, args=(query,), daemon=True).start()

    def _search_suggestions_task(self, query):
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                return

        try:
            self.log(f"Fetching suggestions for: {query}")
            results = self.ytm.get_search_suggestions(query)
            self.send_response({
                "type": "suggestions",
                "query": query,
                "results": results
            })
        except Exception as e:
            self.log(f"Suggestions search error for '{query}': {e}")

    def refresh_auth(self):
        """Extract fresh cookies from browser and re-init YTMusic client."""
        threading.Thread(target=self._refresh_auth_task, daemon=True).start()

    def _refresh_auth_task(self):
        self.log("Refreshing auth from browser cookies...")
        try:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            extract_module = os.path.join(script_dir, "extract_cookies.py")

            import importlib.util
            spec = importlib.util.spec_from_file_location("extract_cookies", extract_module)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)

            result = mod.extract(self.headers_path)

            if result.get("success"):
                self.log(f"Cookie extraction OK ({result.get('cookies_found', 0)} cookies)")
                from ytmusicapi import YTMusic
                self.ytm = YTMusic(self.headers_path)
                self._set_default_timeout(self.ytm)
                self._home_cache_ts = 0.0
                self.send_response({"type": "auth_refreshed", "success": True})
            else:
                error = result.get("error", "Unknown error")
                self.log(f"Cookie extraction failed: {error}")
                self.send_response({"type": "auth_refreshed", "success": False, "error": error})
        except Exception as e:
            self.log(f"Refresh auth error: {e}")
            self.send_response({"type": "auth_refreshed", "success": False, "error": str(e)})

    def start_oauth(self):
        self._oauth_cancel = False
        threading.Thread(target=self._oauth_task, daemon=True).start()

    def cancel_oauth(self):
        self._oauth_cancel = True

    def _oauth_task(self):
        self.log("Starting seamless OAuth flow")
        try:
            import requests
            from ytmusicapi.auth.oauth.credentials import OAuthCredentials
            from ytmusicapi.auth.oauth.token import RefreshingToken

            client_id = self._OAUTH_CLIENT_ID
            client_secret = self._OAUTH_CLIENT_SECRET

            creds = OAuthCredentials(client_id, client_secret)
            code = creds.get_code()

            self.send_response({
                "type": "oauth_code",
                "url": code["verification_url"],
                "user_code": code["user_code"]
            })

            interval = code.get("interval", 5)
            expires_in = code.get("expires_in", 1800)
            device_code = code["device_code"]

            for _ in range(expires_in // interval):
                if getattr(self, "_oauth_cancel", False):
                    self.log("OAuth cancelled by user")
                    return
                time.sleep(interval)
                try:
                    raw_token = creds.token_from_code(device_code)
                    if raw_token and "access_token" in raw_token:
                        token = RefreshingToken(credentials=creds, **raw_token)
                        token.update(token.as_dict())

                        import json
                        with open(self.oauth_path, "w") as f:
                            json.dump(token.as_dict(), f)

                        self.log("OAuth flow successful, re-initializing ytmusic client")
                        from ytmusicapi import YTMusic
                        self._set_default_timeout(YTMusic)
                        self.ytm = YTMusic(self.oauth_path, oauth_credentials=self._make_oauth_credentials())
                        self._home_cache_ts = 0.0
                        self.send_response({"type": "oauth_success"})
                        return
                except Exception:
                    pass
        except Exception as e:
            self.log(f"OAuth flow error: {e}")

    def fetch_playlist(self, video_id):
        try:
            data = self.ytm.get_watch_playlist(videoId=video_id, limit=20)
            return data.get("tracks", [])
        except Exception:
            return []
