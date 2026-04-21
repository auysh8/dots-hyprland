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

    def search_album_ids(self, title, artist):
        try:
            # Clean up query
            query = f"{title} {artist}"
            query = re.sub(r'\(.*?\)', '', query)
            query = re.sub(r'\[.*?\]', '', query)
            query = query.replace('feat.', '').strip()
            
            # Search both albums and songs and collect all unique collectionIds
            ids = []
            
            def is_artist_match(result_artist, search_artist):
                if not result_artist or not search_artist: return False
                r_lower = result_artist.lower()
                s_lower = search_artist.lower()
                return s_lower in r_lower or r_lower in s_lower

            # 1. Search Albums
            url_albums = "https://itunes.apple.com/search?" + urllib.parse.urlencode({
                "term": query,
                "media": "music",
                "entity": "album",
                "limit": "10"
            })
            data_albums = self._get(url_albums)
            for r in data_albums.get("results", []):
                cid = str(r.get("collectionId"))
                res_artist = r.get("artistName", "")
                if cid and cid not in ids and is_artist_match(res_artist, artist):
                    ids.append(cid)
                    
            # 2. Search Songs (to find parent albums of the exact song)
            url_songs = "https://itunes.apple.com/search?" + urllib.parse.urlencode({
                "term": query,
                "media": "music",
                "entity": "song",
                "limit": "15"
            })
            data_songs = self._get(url_songs)
            for r in data_songs.get("results", []):
                cid = str(r.get("collectionId"))
                res_artist = r.get("artistName", "")
                if cid and cid not in ids and is_artist_match(res_artist, artist):
                    ids.append(cid)
                    
            return ids
        except Exception as e:
            self.log(f"[AppleMusic] Search failed: {e}")
            return []

    def get_canvas_m3u8(self, title, artist):
        if not self._check_and_refresh_token():
            return None

        album_ids = self.search_album_ids(title, artist)
        if not album_ids:
            self.log(f"[AppleMusic] Could not find any Apple Music albums for '{title}' by '{artist}'")
            return None
            
        self.log(f"[AppleMusic] Found {len(album_ids)} potential Album IDs to check for canvas...")
        
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
                    
                # Prefer Tall (Portrait) format, fallback to square
                video_url = None
                if "motionDetailTall" in editorial_video:
                    video_url = editorial_video["motionDetailTall"].get("video")
                elif "motionSquareVideo1x1" in editorial_video:
                    video_url = editorial_video["motionSquareVideo1x1"].get("video")
                elif "motionDetailSquare" in editorial_video:
                    video_url = editorial_video["motionDetailSquare"].get("video")
                    
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
                
        self.log(f"[AppleMusic] Exhausted all {len(album_ids)} albums. No animated canvas found for '{title}'.")
        return None

    def get_canvas_mp4(self, title, artist):
        m3u8_url = self.get_canvas_m3u8(title, artist)
        if not m3u8_url:
            return None

        # Create cache directory
        cache_dir = os.path.expanduser("~/.cache/quickshell/music/canvas_videos")
        os.makedirs(cache_dir, exist_ok=True)
        
        import hashlib
        safe_name = hashlib.md5(f"{title}-{artist}".encode()).hexdigest()
        output_path = os.path.join(cache_dir, f"{safe_name}.mp4")

        # If already cached, return immediately
        if os.path.exists(output_path):
            self.log(f"[AppleMusic] Returning cached canvas: {output_path}")
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
