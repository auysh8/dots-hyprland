#!/usr/bin/env python3
"""
File-based cache manager for album art and audio streams.
Implements LRU eviction based on total cache size.
"""
import os
import json
import time
import hashlib
import shutil
import threading
from pathlib import Path


class CacheManager:
    """Manages file-based cache for album art and audio streams with size limits."""

    def __init__(self, cache_dir: str, max_size_mb: float = 500.0, logger=None):
        """
        Initialize cache manager.

        Args:
            cache_dir: Base directory for cache files
            max_size_mb: Maximum cache size in megabytes (default 500MB)
            logger: Optional logger function
        """
        self.cache_dir = Path(cache_dir)
        self.max_size_bytes = int(max_size_mb * 1024 * 1024)
        self.log = logger or (lambda msg: None)

        # Subdirectories
        self.art_cache_dir = self.cache_dir / "album_art"
        self.audio_cache_dir = self.cache_dir / "audio"
        self.canvas_video_dir = self.cache_dir / "canvas_videos"
        self.meta_file = self.cache_dir / "cache_meta.json"

        # Create directories
        self.art_cache_dir.mkdir(parents=True, exist_ok=True)
        self.audio_cache_dir.mkdir(parents=True, exist_ok=True)
        self.canvas_video_dir.mkdir(parents=True, exist_ok=True)

        # Cache metadata: {file_hash: {"path": str, "size": int, "accessed": float, "type": str}}
        self.meta = self._load_meta()
        self._meta_lock = threading.Lock()

        # Enforce size limit on startup
        self._enforce_size_limit()

    def _load_meta(self) -> dict:
        """Load cache metadata from disk."""
        if self.meta_file.exists():
            try:
                with open(self.meta_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                self.log(f"Cache meta load error: {e}")
        return {}

    def _save_meta(self):
        """Save cache metadata to disk."""
        try:
            with open(self.meta_file, "w", encoding="utf-8") as f:
                json.dump(self.meta, f, indent=2)
        except Exception as e:
            self.log(f"Cache meta save error: {e}")

    def _get_file_hash(self, url_or_id: str, file_type: str) -> str:
        """Generate unique hash for cache key."""
        key = f"{file_type}:{url_or_id}"
        return hashlib.sha256(key.encode()).hexdigest()[:32]

    def _get_total_size(self) -> int:
        """Calculate total cache size in bytes."""
        total = 0
        for entry in self.meta.values():
            if os.path.exists(entry["path"]):
                total += entry["size"]
        return total

    def _enforce_size_limit(self):
        """Remove oldest files until cache is under size limit."""
        with self._meta_lock:
            current_size = self._get_total_size()
            if current_size <= self.max_size_bytes:
                return

            # Sort by access time (oldest first)
            sorted_entries = sorted(
                self.meta.items(),
                key=lambda x: x[1].get("accessed", 0)
            )

            for file_hash, entry in sorted_entries:
                if current_size <= self.max_size_bytes:
                    break

                try:
                    if os.path.exists(entry["path"]):
                        os.remove(entry["path"])
                    current_size -= entry["size"]
                    del self.meta[file_hash]
                    self.log(f"Cache eviction: {entry['path']}")
                except Exception as e:
                    self.log(f"Cache eviction error: {e}")

            self._save_meta()

    def _update_access_time(self, file_hash: str):
        """Update access time for LRU tracking."""
        with self._meta_lock:
            if file_hash in self.meta:
                self.meta[file_hash]["accessed"] = time.time()
                self._save_meta()

    # ── Album Art Caching ──────────────────────────────────────────────────────

    def get_art_path(self, art_url: str) -> str | None:
        """
        Get cached album art file path.

        Args:
            art_url: URL of the album art

        Returns:
            Path to cached file or None if not cached
        """
        if not art_url:
            return None

        file_hash = self._get_file_hash(art_url, "art")
        with self._meta_lock:
            if file_hash in self.meta:
                entry = self.meta[file_hash]
                if os.path.exists(entry["path"]):
                    # Update access time inline to avoid deadlock
                    entry["accessed"] = time.time()
                    self._save_meta()
                    return entry["path"]
        return None

    def cache_art(self, art_url: str, image_data: bytes) -> str:
        """
        Cache album art image.

        Args:
            art_url: URL of the album art
            image_data: Raw image bytes

        Returns:
            Path to cached file
        """
        file_hash = self._get_file_hash(art_url, "art")
        file_path = self.art_cache_dir / f"{file_hash}.jpg"

        with self._meta_lock:
            # Write file
            with open(file_path, "wb") as f:
                f.write(image_data)

            file_size = len(image_data)

            # Update metadata
            self.meta[file_hash] = {
                "path": str(file_path),
                "size": file_size,
                "accessed": time.time(),
                "type": "art",
                "url": art_url,
            }
            self._save_meta()

        # Enforce size limit after adding
        self._enforce_size_limit()

        return str(file_path)

    # ── Audio Stream Caching ───────────────────────────────────────────────────

    def get_audio_path(self, video_id: str) -> str | None:
        """
        Get cached audio file path.

        Args:
            video_id: YouTube video ID

        Returns:
            Path to cached file or None if not cached
        """
        if not video_id:
            return None

        file_hash = self._get_file_hash(video_id, "audio")
        with self._meta_lock:
            if file_hash in self.meta:
                entry = self.meta[file_hash]
                if os.path.exists(entry["path"]):
                    # Update access time inline to avoid deadlock
                    entry["accessed"] = time.time()
                    self._save_meta()
                    return entry["path"]
        return None

    def cache_audio(self, video_id: str, audio_data: bytes, duration_sec: int = 0) -> str:
        """
        Cache audio stream.

        Args:
            video_id: YouTube video ID
            audio_data: Raw audio bytes
            duration_sec: Duration in seconds (for info)

        Returns:
            Path to cached file
        """
        file_hash = self._get_file_hash(video_id, "audio")
        file_path = self.audio_cache_dir / f"{file_hash}.webm"

        with self._meta_lock:
            # Write file
            with open(file_path, "wb") as f:
                f.write(audio_data)

            file_size = len(audio_data)

            # Update metadata
            self.meta[file_hash] = {
                "path": str(file_path),
                "size": file_size,
                "accessed": time.time(),
                "type": "audio",
                "video_id": video_id,
                "duration": duration_sec,
            }
            self._save_meta()

        # Enforce size limit after adding
        self._enforce_size_limit()

        return str(file_path)

    def prepare_audio_download_path(self, video_id: str) -> str:
        """
        Returns the target path for a yt-dlp audio download.
        The caller must run the download externally; call register_downloaded_audio() when done.
        """
        file_hash = self._get_file_hash(video_id, "audio")
        return str(self.audio_cache_dir / f"{file_hash}.m4a")

    def register_downloaded_audio(self, video_id: str, file_path: str) -> bool:
        """
        Register a fully downloaded audio file into the cache.
        Returns True on success.
        """
        path = Path(file_path)
        if not path.exists() or path.stat().st_size < 4096:
            return False

        file_hash = self._get_file_hash(video_id, "audio")
        with self._meta_lock:
            self.meta[file_hash] = {
                "path": str(path),
                "size": path.stat().st_size,
                "accessed": time.time(),
                "type": "audio",
                "video_id": video_id,
            }
            self._save_meta()

        self._enforce_size_limit()
        return True

    def start_audio_cache_download(self, video_id: str, stream_url: str, title: str = "") -> str:
        """
        Start background download of audio stream to cache.

        Args:
            video_id: YouTube video ID
            stream_url: Direct stream URL from yt-dlp
            title: Optional title for logging

        Returns:
            Path where file will be cached (or existing cached path)
        """
        # Check if already cached
        cached = self.get_audio_path(video_id)
        if cached:
            self.log(f"Audio cache hit: {title}")
            return cached

        file_hash = self._get_file_hash(video_id, "audio")
        file_path = self.audio_cache_dir / f"{file_hash}.webm"
        temp_path = file_path.with_suffix(".webm.tmp")

        def _download():
            try:
                import urllib.request
                self.log(f"Caching audio: {title} ({video_id})")

                # Download with progress
                req = urllib.request.Request(stream_url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"})
                with urllib.request.urlopen(req, timeout=300) as response, open(temp_path, "wb") as out:
                    shutil.copyfileobj(response, out)

                # Rename temp to final
                temp_path.rename(file_path)
                file_size = file_path.stat().st_size

                # Get duration if possible
                duration = 0
                try:
                    import subprocess
                    result = subprocess.run(
                        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
                         "-of", "default=noprint_wrappers=1:nokey=1", str(file_path)],
                        capture_output=True, text=True, timeout=10
                    )
                    if result.returncode == 0:
                        duration = int(float(result.stdout.strip()))
                except Exception:
                    pass

                with self._meta_lock:
                    self.meta[file_hash] = {
                        "path": str(file_path),
                        "size": file_size,
                        "accessed": time.time(),
                        "type": "audio",
                        "video_id": video_id,
                        "duration": duration,
                    }
                    self._save_meta()

                self._enforce_size_limit()
                self.log(f"Audio cached: {title} ({file_size / 1024 / 1024:.1f}MB)")

            except Exception as e:
                self.log(f"Audio cache download failed: {e}")
                if temp_path.exists():
                    temp_path.unlink()

        threading.Thread(target=_download, daemon=True).start()
        return str(file_path)

    # ── Canvas Art & Video Caching ──────────────────────────────────────────────

    def get_canvas_video_path(self, video_id: str) -> str | None:
        """Get cached canvas video path."""
        if not video_id:
            return None
        file_hash = self._get_file_hash(video_id, "canvas_video")
        with self._meta_lock:
            if file_hash in self.meta:
                entry = self.meta[file_hash]
                if os.path.exists(entry["path"]):
                    entry["accessed"] = time.time()
                    self._save_meta()
                    return entry["path"]
        return None

    def start_canvas_cache_download(self, video_id: str, canvas_url: str, title: str = "") -> str:
        """Start background download of canvas video to cache."""
        cached = self.get_canvas_video_path(video_id)
        if cached:
            return cached

        file_hash = self._get_file_hash(video_id, "canvas_video")
        file_path = self.canvas_video_dir / f"{file_hash}.mp4"
        temp_path = file_path.with_suffix(".mp4.tmp")

        def _download():
            try:
                import urllib.request
                self.log(f"Caching canvas: {title} ({video_id})")
                req = urllib.request.Request(canvas_url, headers={"User-Agent": "Mozilla/5.0"})
                with urllib.request.urlopen(req, timeout=120) as response, open(temp_path, "wb") as out:
                    shutil.copyfileobj(response, out)
                temp_path.rename(file_path)
                file_size = file_path.stat().st_size
                with self._meta_lock:
                    self.meta[file_hash] = {
                        "path": str(file_path),
                        "size": file_size,
                        "accessed": time.time(),
                        "type": "canvas_video",
                        "video_id": video_id,
                        "url": canvas_url,
                    }
                    self._save_meta()
                self._enforce_size_limit()
                self.log(f"Canvas video cached: {title}")
            except Exception as e:
                self.log(f"Canvas video cache failed: {e}")
                if temp_path.exists():
                    temp_path.unlink()

        threading.Thread(target=_download, daemon=True).start()
        return str(file_path)

    def get_canvas(self, video_id: str) -> dict | None:
        """
        Get cached canvas art data.

        Args:
            video_id: YouTube video ID

        Returns:
            Canvas data dict or None if not cached/expired
        """
        if not video_id:
            return None

        file_hash = self._get_file_hash(video_id, "canvas")
        with self._meta_lock:
            if file_hash in self.meta:
                entry = self.meta[file_hash]
                # Check if expired
                if time.time() - entry.get("accessed", 0) > 86400 * 7:  # 7 days
                    return None
                if os.path.exists(entry["path"]):
                    try:
                        with open(entry["path"], "r", encoding="utf-8") as f:
                            canvas_data = json.load(f)
                        # Update access time inline
                        entry["accessed"] = time.time()
                        self._save_meta()
                        return canvas_data
                    except Exception:
                        pass
        return None

    def cache_canvas(self, video_id: str, canvas_data: dict) -> str | None:
        """
        Cache canvas art data.

        Args:
            video_id: YouTube video ID
            canvas_data: Canvas data dict with url, isAnimated, etc.

        Returns:
            Path to cached file or None on error
        """
        if not canvas_data or not canvas_data.get("url"):
            return None

        file_hash = self._get_file_hash(video_id, "canvas")
        file_path = self.cache_dir / "canvas" / f"{file_hash}.json"
        file_path.parent.mkdir(parents=True, exist_ok=True)

        with self._meta_lock:
            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    json.dump(canvas_data, f)

                file_size = file_path.stat().st_size

                self.meta[file_hash] = {
                    "path": str(file_path),
                    "size": file_size,
                    "accessed": time.time(),
                    "type": "canvas",
                    "video_id": video_id,
                    "url": canvas_data.get("url", ""),
                    "isAnimated": canvas_data.get("isAnimated", False),
                }
                self._save_meta()
            except Exception as e:
                self.log(f"Canvas cache error: {e}")
                return None

        self._enforce_size_limit()
        return str(file_path)

    # ── Cache Statistics ───────────────────────────────────────────────────────

    def get_stats(self) -> dict:
        """Get cache statistics."""
        with self._meta_lock:
            art_count = sum(1 for e in self.meta.values() if e["type"] == "art")
            audio_count = sum(1 for e in self.meta.values() if e["type"] == "audio")
            canvas_count = sum(1 for e in self.meta.values() if e["type"] == "canvas")
            cv_count = sum(1 for e in self.meta.values() if e["type"] == "canvas_video")
            
            art_size = sum(e["size"] for e in self.meta.values() if e["type"] == "art")
            audio_size = sum(e["size"] for e in self.meta.values() if e["type"] == "audio")
            canvas_size = sum(e["size"] for e in self.meta.values() if e["type"] == "canvas")
            cv_size = sum(e["size"] for e in self.meta.values() if e["type"] == "canvas_video")

            total_size = art_size + audio_size + canvas_size + cv_size

            return {
                "art_count": art_count,
                "audio_count": audio_count,
                "canvas_count": canvas_count,
                "canvas_video_count": cv_count,
                "art_size_mb": art_size / 1024 / 1024,
                "audio_size_mb": audio_size / 1024 / 1024,
                "canvas_size_mb": canvas_size / 1024 / 1024,
                "canvas_video_size_mb": cv_size / 1024 / 1024,
                "total_size_mb": total_size / 1024 / 1024,
                "max_size_mb": self.max_size_bytes / 1024 / 1024,
                "utilization": total_size / self.max_size_bytes * 100,
            }

    def clear(self, clear_art: bool = True, clear_audio: bool = True, clear_canvas: bool = True):
        """
        Clear cache.

        Args:
            clear_art: Clear album art cache
            clear_audio: Clear audio cache
            clear_canvas: Clear canvas cache
        """
        with self._meta_lock:
            to_remove = [
                h for h, e in self.meta.items()
                if (clear_art and e["type"] == "art") or 
                   (clear_audio and e["type"] == "audio") or
                   (clear_canvas and e["type"] in ("canvas", "canvas_video"))
            ]

            for file_hash in to_remove:
                entry = self.meta[file_hash]
                try:
                    if os.path.exists(entry["path"]):
                        os.remove(entry["path"])
                except Exception:
                    pass
                del self.meta[file_hash]

            self._save_meta()
            self.log(f"Cache cleared: {len(to_remove)} files removed")

    def cleanup_orphans(self):
        """Remove cache files not in metadata."""
        orphan_count = 0
        for cache_dir in [self.art_cache_dir, self.audio_cache_dir, self.canvas_video_dir]:
            if not cache_dir.exists():
                continue
            for file_path in cache_dir.glob("*"):
                if file_path.suffix == ".tmp":
                    file_path.unlink()
                    orphan_count += 1
                    continue
                file_str = str(file_path)
                found = any(e["path"] == file_str for e in self.meta.values())
                if not found:
                    file_path.unlink()
                    orphan_count += 1

        if orphan_count:
            self.log(f"Cleaned up {orphan_count} orphan cache files")
