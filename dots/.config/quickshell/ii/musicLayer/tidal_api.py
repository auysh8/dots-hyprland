import json
import base64
import time
import urllib.request
import urllib.parse
import gzip
import io
import re
import tempfile
import os

class TidalClient:
    """A minimal Python client for Tidal using Monochrome community proxies.
    
    Proxy API (triton.squid.wtf, wolf.qqdl.site, etc.) uses:
      GET /search/?s=<query>         -> {data: {items: [...]}}
      GET /track/?id=<id>&quality=HI_RES_LOSSLESS
                                     -> {data: {manifest, audioQuality, sampleRate, bitDepth, ...}}
      GET /trackManifests/?id=<id>&formats=FLAC_HIRES,FLAC&...
                                     -> {data: {attributes: {uri}}} or manifest
    
    NOTE: The proxy uses query-string ?id=... NOT path segments /tracks/{id}/playbackinfo
    """

    # Community proxy instances (monochrome-style FastAPI proxy servers)
    # arran.monochrome.tf is excluded — consistently 502 Bad Gateway
    PROXIES = [
        "https://triton.squid.wtf",
        "https://wolf.qqdl.site",
        "https://maus.qqdl.site",
        "https://vogel.qqdl.site",
        "https://katze.qqdl.site",
        "https://hund.qqdl.site",
        "https://hifi.p1nkhamster.xyz",
    ]

    def __init__(self, logger):
        self.log = logger
        # Cache search results by (title, artist) to avoid re-searching on retry
        self._search_cache = {}

    def _request(self, url, data=None, headers=None, method=None, timeout=12):
        """Helper to make HTTP requests with proper headers and decompression."""
        if headers is None:
            headers = {}

        default_headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate",
        }
        for k, v in default_headers.items():
            if k not in headers:
                headers[k] = v

        req = urllib.request.Request(url, data=data, headers=headers, method=method)

        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                res_data = response.read()

                encoding = response.info().get("Content-Encoding")
                if encoding == "gzip":
                    try:
                        buf = io.BytesIO(res_data)
                        with gzip.GzipFile(fileobj=buf) as f:
                            res_data = f.read()
                    except Exception:
                        pass
                elif encoding == "deflate":
                    try:
                        import zlib
                        res_data = zlib.decompress(res_data)
                    except Exception:
                        pass

                if not res_data:
                    return None

                body = res_data.decode("utf-8", errors="replace")
                try:
                    return json.loads(body)
                except json.JSONDecodeError:
                    return None
        except Exception as e:
            if hasattr(e, "read"):
                try:
                    err_body = e.read()
                    if hasattr(e, "info") and e.info().get("Content-Encoding") == "gzip":
                        buf = io.BytesIO(err_body)
                        with gzip.GzipFile(fileobj=buf) as f:
                            err_body = f.read()
                    self.log(f"[Tidal] HTTP Error details: {err_body.decode('utf-8', errors='replace')[:300]}")
                except Exception:
                    pass
            raise e

    def _extract_stream_url_from_manifest(self, data):
        """
        Extract a playable URL from a monochrome proxy /track/ response.

        The proxy returns:
          {data: {manifest: <base64>, manifestMimeType: "...", audioQuality, sampleRate, bitDepth}}

        Manifest types:
          - application/vnd.tidal.bts  → JSON with {"urls": ["https://..."]}
            This is a single CDN .flac/.mp4 file — pass directly to mpv.
          - application/dash+xml       → MPEG-DASH XML with SegmentTemplate
            Saved to a temp .mpd file; mpv plays DASH natively via libavformat.
        """
        if not data:
            return None, None, None

        # Unwrap {version, data: {...}} envelope
        inner = data.get("data", data)
        if not inner:
            return None, None, None

        quality = inner.get("audioQuality", "")
        sample_rate = inner.get("sampleRate")
        bit_depth = inner.get("bitDepth")
        quality_label = self._make_quality_label(quality, sample_rate, bit_depth)

        manifest_b64 = inner.get("manifest")
        mime_type = inner.get("manifestMimeType", "")

        if not manifest_b64:
            # No manifest — maybe a direct URL in attributes (v2 style)
            attrs = inner.get("attributes", {})
            if attrs.get("uri"):
                return attrs["uri"], quality_label, inner
            return None, quality_label, inner

        # Decode base64 manifest
        try:
            decoded = base64.b64decode(manifest_b64).decode("utf-8")
        except Exception as e:
            self.log(f"[Tidal] Failed to decode manifest base64: {e}")
            return None, quality_label, inner

        # 1. BTS JSON format (LOSSLESS FLAC — single CDN URL)
        if "bts" in mime_type.lower() or decoded.strip().startswith("{"):
            try:
                manifest_json = json.loads(decoded)
                # BTS: {"mimeType": "audio/flac", "urls": ["https://..."], "encryptionType": "NONE"}
                urls = manifest_json.get("urls")
                if urls and isinstance(urls, list) and urls[0]:
                    self.log(f"[Tidal] BTS manifest → direct CDN URL ({quality_label})")
                    return urls[0], quality_label, inner
                if manifest_json.get("url"):
                    return manifest_json["url"], quality_label, inner
            except json.JSONDecodeError:
                pass

        # 2. MPEG-DASH XML (HI_RES_LOSSLESS — segmented stream)
        #    Write to a temp .mpd file; mpv plays DASH natively via libavformat
        if "dash" in mime_type.lower() or decoded.strip().startswith("<?xml") or decoded.strip().startswith("<MPD"):
            try:
                fd, mpd_path = tempfile.mkstemp(prefix="tidal_", suffix=".mpd")
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(decoded)
                self.log(f"[Tidal] DASH manifest → temp file {mpd_path} ({quality_label})")
                return f"file://{mpd_path}", quality_label, inner
            except Exception as e:
                self.log(f"[Tidal] Failed to write DASH manifest: {e}")
                return None, quality_label, inner

        # 3. Fallback: scan for any https:// URL in the decoded text
        urls_found = re.findall(r"https://[^\s<>\"']+", decoded)
        if urls_found:
            return urls_found[0], quality_label, inner

        return None, quality_label, inner

    def _make_quality_label(self, quality, sample_rate=None, bit_depth=None):
        """Convert Tidal quality tokens to human-readable labels."""
        labels = {
            "HI_RES_LOSSLESS": "Tidal HiRes Lossless",
            "LOSSLESS": "Tidal Lossless",
            "HIGH": "Tidal HQ (AAC)",
            "LOW": "Tidal (AAC)",
        }
        label = labels.get(quality, f"Tidal ({quality})" if quality else "Tidal")
        if quality == "HI_RES_LOSSLESS" and sample_rate and bit_depth:
            label += f" {sample_rate//1000}kHz/{bit_depth}bit"
        return label

    def search_track_via_proxy(self, proxy_base, title, artist):
        """
        Search for a track using the proxy /search/ endpoint.
        Returns the best matching Tidal track ID or None.
        """
        cache_key = (proxy_base, title.lower(), artist.lower())
        if cache_key in self._search_cache:
            return self._search_cache[cache_key]

        query = f"{title} {artist}"
        params = urllib.parse.urlencode({"s": query})
        url = f"{proxy_base}/search/?{params}"

        try:
            data = self._request(url, timeout=10)
            if not data:
                return None

            # Response: {version, data: {items: [...], limit, offset, totalNumberOfItems}}
            items = data.get("data", {}).get("items", [])
            if not items:
                return None

            # Find best match: exact title + artist name match first
            title_lower = title.lower()
            artist_lower = artist.lower()
            best_id = None

            for item in items:
                item_title = (item.get("title") or "").lower()
                item_artist = (item.get("artist") or {}).get("name", "").lower()
                # Skip non-streamable tracks
                if not item.get("streamReady", True):
                    continue
                if title_lower in item_title and artist_lower in item_artist:
                    best_id = item.get("id")
                    self.log(
                        f"[Tidal] Match: {item.get('title')} by {item.get('artist',{}).get('name')} "
                        f"(ID: {best_id}, quality: {item.get('audioQuality')})"
                    )
                    break

            # Fallback: use first result
            if best_id is None and items:
                item = items[0]
                best_id = item.get("id")
                self.log(
                    f"[Tidal] Fallback match: {item.get('title')} by {item.get('artist',{}).get('name')} "
                    f"(ID: {best_id})"
                )

            self._search_cache[cache_key] = best_id
            return best_id

        except Exception as e:
            self.log(f"[Tidal] Search via {proxy_base} failed: {e}")
            return None

    def get_stream_via_proxy(self, proxy_base, track_id):
        """
        Fetch a stream URL for track_id using the proxy /track/ endpoint.
        Uses the correct query-param format: /track/?id=<id>&quality=HI_RES_LOSSLESS
        Returns (stream_url, quality_label) or (None, None).
        """
        # Quality preference order:
        #   1. LOSSLESS → BTS JSON format → direct CDN .flac URL → mpv plays natively ✓
        #   2. HI_RES_LOSSLESS → MPEG-DASH XML → temp .mpd file → mpv DASH demuxer
        #   3. HIGH → fallback AAC
        qualities = ["LOSSLESS", "HI_RES_LOSSLESS", "HIGH"]

        for quality in qualities:
            params = urllib.parse.urlencode({"id": track_id, "quality": quality})
            url = f"{proxy_base}/track/?{params}"
            try:
                data = self._request(url, timeout=15)
                if not data:
                    continue
                stream_url, quality_label, raw = self._extract_stream_url_from_manifest(data)
                if stream_url:
                    return stream_url, quality_label
            except Exception as e:
                self.log(f"[Tidal] /track/ {quality} via {proxy_base} failed: {e}")
                # Don't retry different qualities on connection errors
                break

        return None, None

    def resolve_stream(self, title, artist):
        """
        High-level: go from (title, artist) to a playable stream URL.
        Tries each proxy in turn, searching for the track then fetching the stream.
        Returns (stream_url, quality_label) or (None, None).
        """
        last_track_id = None

        for proxy_base in self.PROXIES:
            self.log(f"[Tidal] Trying proxy: {proxy_base}")
            try:
                # Step 1: Search (reuse track_id if already found)
                track_id = last_track_id
                if track_id is None:
                    track_id = self.search_track_via_proxy(proxy_base, title, artist)
                    if not track_id:
                        self.log(f"[Tidal] No search results from {proxy_base}")
                        continue
                    last_track_id = track_id

                # Step 2: Get stream
                stream_url, quality_label = self.get_stream_via_proxy(proxy_base, track_id)
                if stream_url:
                    self.log(f"[Tidal] ✓ Stream resolved via {proxy_base}: {quality_label}")
                    return stream_url, quality_label

            except Exception as e:
                self.log(f"[Tidal] Proxy {proxy_base} error: {e}")
                continue

        self.log("[Tidal] All proxies exhausted — falling back to YouTube Music")
        return None, None
