import json
import os
import re
import urllib.request
import urllib.error
import urllib.parse
import threading

class AppleMusicCanvasFetcher:
    def __init__(self, logger):
        self.log = logger
        self.token = ""
        self.token_file = os.path.expanduser("~/.cache/quickshell/music/am_token.txt")
        self.lock = threading.Lock()
        self._load_token()

    def _load_token(self):
        try:
            if os.path.exists(self.token_file):
                with open(self.token_file, "r") as f:
                    self.token = f.read().strip()
        except Exception:
            pass

    def _save_token(self):
        try:
            os.makedirs(os.path.dirname(self.token_file), exist_ok=True)
            with open(self.token_file, "w") as f:
                f.write(self.token)
        except Exception:
            pass

    def _get(self, url, headers=None, as_json=True):
        if headers is None:
            headers = {}
        headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as response:
            data = response.read().decode('utf-8')
            if as_json:
                return json.loads(data)
            return data

    def _check_and_refresh_token(self):
        with self.lock:
            if self.token:
                try:
                    headers = {"authorization": f"Bearer {self.token}", "origin": "https://music.apple.com"}
                    # Test token
                    self._get('https://amp-api.music.apple.com/v1/catalog/us/albums/1551901062', headers=headers)
                    return True
                except urllib.error.HTTPError as e:
                    if e.code != 401 and e.code != 403:
                        return True # Valid, but maybe not found

            self.log("[AppleMusic] Token expired or missing. Fetching new token...")
            try:
                # Fetch html to find JS bundle
                html = self._get("https://music.apple.com/us/album/positions-deluxe-edition/1553944254", as_json=False)
                match = re.search(r"crossorigin src=\"(/assets/index.+?\.js)\"", html)
                if not match:
                    self.log("[AppleMusic] Failed to find JS bundle path in HTML")
                    return False
                
                js_path = match.group(1)
                js_content = self._get("https://music.apple.com" + js_path, as_json=False)
                
                # Extract bearer token
                token_match = re.search(r"(eyJhbGc.+?)\"", js_content)
                if not token_match:
                    self.log("[AppleMusic] Failed to extract JWT from JS bundle")
                    return False
                    
                self.token = token_match.group(1)
                self._save_token()
                self.log("[AppleMusic] Token successfully updated.")
                return True
            except Exception as e:
                self.log(f"[AppleMusic] Failed to refresh token: {e}")
                return False

    def _normalize_text(self, value):
        if not value:
            return ""
        text = value.lower().strip()
        text = re.sub(r"[^\w\s]", " ", text)
        text = re.sub(r"\s+", " ", text)
        return text.strip()

    def _normalize_release_title(self, value):
        text = self._normalize_text(value)
        if not text:
            return ""
        text = re.sub(
            r"\b("
            r"single|ep|deluxe|deluxe edition|extended edition|expanded edition|"
            r"remastered|remaster|bonus track version|acoustic|live"
            r")\b",
            " ",
            text,
        )
        text = re.sub(r"\s+", " ", text)
        return text.strip()

    def _is_title_match(self, left, right):
        norm_left = self._normalize_text(left)
        norm_right = self._normalize_text(right)
        if not norm_left or not norm_right:
            return False
        return (
            norm_left == norm_right
            or norm_left in norm_right
            or norm_right in norm_left
        )

    def _album_match_score(self, result_album, requested_album):
        wanted = self._normalize_release_title(requested_album)
        found = self._normalize_release_title(result_album)
        if not wanted or not found:
            return 0
        if wanted == found:
            return 3
        if found.startswith(wanted) or wanted.startswith(found):
            return 2
        if wanted in found:
            return 1
        return 0

    def search_album_ids(self, title, artist, album_title=None):
        try:
            # Clean up query
            query = f"{title} {artist} {album_title or ''}"
            query = re.sub(r'\(.*?\)', '', query)
            query = re.sub(r'\[.*?\]', '', query)
            query = query.replace('feat.', '').strip()
            
            # Search both albums and songs and collect all unique collectionIds
            candidates = []
            seen_ids = set()
            normalized_title = self._normalize_text(title)
            normalized_album_title = self._normalize_release_title(album_title)
            
            def is_artist_match(result_artist, search_artist):
                if not result_artist or not search_artist:
                    return False
                r_lower = result_artist.lower()
                s_lower = search_artist.lower()
                return s_lower in r_lower or r_lower in s_lower

            def try_add_candidate(result, source_kind):
                cid = str(result.get("collectionId") or "")
                if not cid or cid in seen_ids:
                    return

                res_artist = result.get("artistName", "")
                if not is_artist_match(res_artist, artist):
                    return

                res_album = result.get("collectionName", "") or result.get("collectionCensoredName", "") or ""
                album_score = self._album_match_score(res_album, album_title)
                res_track = result.get("trackName", "")
                track_match = self._is_title_match(res_track, title) if res_track else False
                
                if normalized_album_title:
                    # When we know the release title, keep matches strict enough to avoid
                    # pulling editorial videos from a different release with a similar name.
                    if album_score <= 0:
                        return
                    # Song results must also match the requested track title.
                    if source_kind == "song" and not track_match:
                        return
                else:
                    # Without a reliable album title, only accept exact track-led matches
                    # from song results. Album-only hits are too ambiguous and often wrong.
                    if source_kind != "song" or not track_match:
                        return

                seen_ids.add(cid)
                candidates.append({
                    "id": cid,
                    "album": res_album,
                    "artist": res_artist,
                    "score": album_score + (4 if track_match else 0),
                })

            # 1. Search Albums
            url_albums = "https://itunes.apple.com/search?" + urllib.parse.urlencode({
                "term": query,
                "media": "music",
                "entity": "album",
                "limit": "10"
            })
            data_albums = self._get(url_albums)
            for r in data_albums.get("results", []):
                try_add_candidate(r, "album")
                    
            # 2. Search Songs (to find parent albums of the exact song)
            url_songs = "https://itunes.apple.com/search?" + urllib.parse.urlencode({
                "term": query,
                "media": "music",
                "entity": "song",
                "limit": "15"
            })
            data_songs = self._get(url_songs)
            for r in data_songs.get("results", []):
                try_add_candidate(r, "song")

            candidates.sort(key=lambda candidate: candidate.get("score", 0), reverse=True)
            return candidates
        except Exception as e:
            self.log(f"[AppleMusic] Search failed: {e}")
            return []

    def get_cached_canvas(self, title, artist, album_title=None, album_key=None):
        import hashlib
        cache_dir = os.path.expanduser("~/.cache/quickshell/music/canvas_videos")
        cache_identity = album_key or album_title or ""
        safe_name = hashlib.md5(f"{title}-{artist}-{cache_identity}".encode()).hexdigest()
        output_path = os.path.join(cache_dir, f"{safe_name}.mp4")
        if os.path.exists(output_path):
            return f"file://{output_path}"
        return None

    def get_canvas_m3u8(self, title, artist, album_title=None, album_key=None):
        if not self._check_and_refresh_token():
            return None

        album_candidates = self.search_album_ids(title, artist, album_title=album_title)
        if not album_candidates:
            self.log(
                f"[AppleMusic] Could not find matching Apple Music album for '{title}' by '{artist}' "
                f"on release '{album_title}'"
            )
            return None
            
        album_ids = [candidate["id"] for candidate in album_candidates]
        self.log(
            f"[AppleMusic] Found {len(album_ids)} matching Album IDs to check for canvas "
            f"for release '{album_title}'..."
        )
        
        headers = {"authorization": f"Bearer {self.token}", "origin": "https://music.apple.com"}
        
        import concurrent.futures

        def check_album(album_id):
            try:
                url = f"https://amp-api.music.apple.com/v1/catalog/us/albums/{album_id}?extend=editorialVideo"
                data = self._get(url, headers=headers)
                
                if not data.get("data"):
                    return None
                    
                attributes = data["data"][0].get("attributes", {})
                editorial_video = attributes.get("editorialVideo")
                if not editorial_video:
                    return None
                    
                # Prefer Square format for the square UI thumbnail, fallback to Tall
                video_url = None
                if "motionSquareVideo1x1" in editorial_video:
                    video_url = editorial_video["motionSquareVideo1x1"].get("video")
                elif "motionDetailSquare" in editorial_video:
                    video_url = editorial_video["motionDetailSquare"].get("video")
                elif "motionDetailTall" in editorial_video:
                    video_url = editorial_video["motionDetailTall"].get("video")
                    
                if video_url:
                    return (album_id, video_url)
            except Exception:
                pass
            return None

        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            # Submit all tasks
            futures = {executor.submit(check_album, aid): aid for aid in album_ids}
            
            # Process results as they complete
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                if result:
                    album_id, video_url = result
                    self.log(f"[AppleMusic] Successfully found animated cover on album {album_id}: {video_url[:60]}...")
                    # Found a match, we can return immediately!
                    # The other threads will finish silently in the background
                    return video_url
                
        self.log(
            f"[AppleMusic] Exhausted all {len(album_ids)} matching albums. "
            f"No animated canvas found for '{title}' on release '{album_title}'."
        )
        return None

    def get_direct_mp4_url(self, m3u8_url):
        import urllib.request
        import urllib.parse
        try:
            req = urllib.request.Request(m3u8_url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req) as response:
                content = response.read().decode('utf-8')
            
            lines = content.split('\n')
            best_child_url = None
            for i, line in enumerate(lines):
                if line.startswith('#EXT-X-STREAM-INF') and 'RESOLUTION' in line:
                    if i + 1 < len(lines) and lines[i+1] and not lines[i+1].startswith('#'):
                        child_uri = lines[i+1].strip()
                        if not child_uri.startswith('http'):
                            child_uri = urllib.parse.urljoin(m3u8_url, child_uri)
                        best_child_url = child_uri
            
            if not best_child_url: return m3u8_url
            
            req = urllib.request.Request(best_child_url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req) as response:
                child_content = response.read().decode('utf-8')
                
            for line in child_content.split('\n'):
                if line.strip().endswith('.mp4'):
                    mp4_uri = line.strip()
                    if not mp4_uri.startswith('http'):
                        mp4_uri = urllib.parse.urljoin(best_child_url, mp4_uri)
                    return mp4_uri
                    
            return m3u8_url
        except Exception as e:
            self.log(f"[AppleMusic] Failed to resolve direct MP4 URL: {e}")
            return m3u8_url

    def m3u8_to_mp4(self, m3u8_url, title, artist, album_title=None, album_key=None):
        if not m3u8_url:
            return None

        # Create cache directory
        cache_dir = os.path.expanduser("~/.cache/quickshell/music/canvas_videos")
        os.makedirs(cache_dir, exist_ok=True)
        
        import hashlib
        cache_identity = album_key or album_title or ""
        safe_name = hashlib.md5(f"{title}-{artist}-{cache_identity}".encode()).hexdigest()
        output_path = os.path.join(cache_dir, f"{safe_name}.mp4")

        # If already cached, return immediately
        if os.path.exists(output_path):
            return f"file://{output_path}"

        self.log(f"[AppleMusic] Downloading m3u8 stream to MP4 via ffmpeg: {output_path}")
        import subprocess
        try:
            subprocess.run([
                'ffmpeg', '-loglevel', 'error', '-y', 
                '-i', m3u8_url, 
                '-t', '12',
                '-c', 'copy', 
                '-bsf:a', 'aac_adtstoasc', 
                output_path
            ], check=True)
            self.log("[AppleMusic] Successfully downloaded canvas to MP4.")
            return f"file://{output_path}"
        except Exception as e:
            self.log(f"[AppleMusic] FFmpeg failed to download canvas: {e}")
            if os.path.exists(output_path):
                os.remove(output_path)
            return None

    def get_canvas_mp4(self, title, artist, album_title=None, album_key=None):
        m3u8_url = self.get_canvas_m3u8(title, artist, album_title=album_title, album_key=album_key)
        return self.m3u8_to_mp4(m3u8_url, title, artist, album_title=album_title, album_key=album_key)
