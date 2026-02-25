#!/usr/bin/env python3
"""
Music backend using:
  - subprocess mpv  → reliable audio playback (no libmpv hang)
  - pydbus          → custom MPRIS2 server with correct artist/art metadata
Install deps: pip install pydbus ytmusicapi
"""

import hashlib
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.request

from ytmusicapi import YTMusic

# ── optional pydbus MPRIS server ─────────────────────────────────────────────
try:
    from gi.repository import GLib
    from pydbus import SessionBus

    PYDBUS_AVAILABLE = True
except ImportError:
    PYDBUS_AVAILABLE = False

MPRIS_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <property name="Identity"         type="s"  access="read"/>
    <property name="DesktopEntry"     type="s"  access="read"/>
    <property name="CanQuit"          type="b"  access="read"/>
    <property name="CanRaise"         type="b"  access="read"/>
    <property name="HasTrackList"     type="b"  access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes"  type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <property name="PlaybackStatus" type="s"  access="read"/>
    <property name="LoopStatus"     type="s"  access="readwrite"/>
    <property name="Rate"           type="d"  access="readwrite"/>
    <property name="Shuffle"        type="b"  access="readwrite"/>
    <property name="Metadata"       type="a{sv}" access="read"/>
    <property name="Volume"         type="d"  access="readwrite"/>
    <property name="Position"       type="x"  access="read"/>
    <property name="MinimumRate"    type="d"  access="read"/>
    <property name="MaximumRate"    type="d"  access="read"/>
    <property name="CanGoNext"      type="b"  access="read"/>
    <property name="CanGoPrevious"  type="b"  access="read"/>
    <property name="CanPlay"        type="b"  access="read"/>
    <property name="CanPause"       type="b"  access="read"/>
    <property name="CanSeek"        type="b"  access="read"/>
    <property name="CanControl"     type="b"  access="read"/>
    <method name="Play"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Next"/>
    <method name="Previous"/>
    <signal name="Seeked"><arg type="x" name="Position"/></signal>
  </interface>
</node>
"""


class MprisServer:
    """
    Minimal MPRIS2 implementation that owns the DBus name
    'org.mpris.MediaPlayer2.music-backend' and exposes
    correct Title / Artist / artUrl metadata.
    Runs its own GLib main loop in a daemon thread.
    """

    dbus = MPRIS_XML  # pydbus picks this up automatically

    def __init__(self, backend):
        self._backend = backend
        self._status = "Stopped"
        self._meta = {}
        self._loop = None
        self._pub = None

    # ── org.mpris.MediaPlayer2 properties ────────────────────────────────────
    @property
    def Identity(self):
        return "Music Backend"

    @property
    def DesktopEntry(self):
        return ""

    @property
    def CanQuit(self):
        return True

    @property
    def CanRaise(self):
        return False

    @property
    def HasTrackList(self):
        return False

    @property
    def SupportedUriSchemes(self):
        return ["https"]

    @property
    def SupportedMimeTypes(self):
        return ["audio/mpeg"]

    # ── org.mpris.MediaPlayer2.Player properties ──────────────────────────────
    @property
    def PlaybackStatus(self):
        return self._status

    @property
    def LoopStatus(self):
        return "None"

    @LoopStatus.setter
    def LoopStatus(self, v):
        pass

    @property
    def Rate(self):
        return 1.0

    @Rate.setter
    def Rate(self, v):
        pass

    @property
    def Shuffle(self):
        return False

    @Shuffle.setter
    def Shuffle(self, v):
        pass

    @property
    def Metadata(self):
        return self._meta

    @property
    def Volume(self):
        return 1.0

    @Volume.setter
    def Volume(self, v):
        pass

    @property
    def Position(self):
        return 0

    @property
    def MinimumRate(self):
        return 1.0

    @property
    def MaximumRate(self):
        return 1.0

    @property
    def CanGoNext(self):
        return True

    @property
    def CanGoPrevious(self):
        return True

    @property
    def CanPlay(self):
        return True

    @property
    def CanPause(self):
        return True

    @property
    def CanSeek(self):
        return False

    @property
    def CanControl(self):
        return True

    # ── org.mpris.MediaPlayer2.Player methods ─────────────────────────────────
    def Play(self):
        self._backend.resume()

    def Pause(self):
        self._backend.pause()

    def PlayPause(self):
        if self._status == "Playing":
            self._backend.pause()
        else:
            self._backend.resume()

    def Stop(self):
        self._backend.stop()

    def Next(self):
        self._backend.next_track()

    def Previous(self):
        self._backend.prev_track()

    # ── metadata update (called from backend) ────────────────────────────────
    def update(self, status, title="", artist="", art_local_path="", video_id=""):
        from gi.repository import GLib as _GLib

        self._status = status

        # DBus object paths only allow [A-Za-z0-9_/]. YouTube IDs often have hyphens.
        safe_id = re.sub(r"[^A-Za-z0-9]", "_", video_id or "0")
        meta = {
            "mpris:trackid": _GLib.Variant("o", f"/org/musicbackend/track/{safe_id}"),
            "xesam:title": _GLib.Variant("s", title),
            "xesam:artist": _GLib.Variant("as", [artist] if artist else []),
        }
        if art_local_path and os.path.exists(art_local_path):
            meta["mpris:artUrl"] = _GLib.Variant("s", f"file://{art_local_path}")

        self._meta = meta

        # Emit PropertiesChanged so widgets update immediately
        if self._pub:
            try:
                self._pub["org.mpris.MediaPlayer2.Player"].PropertiesChanged(
                    "org.mpris.MediaPlayer2.Player",
                    {
                        "PlaybackStatus": _GLib.Variant("s", self._status),
                        "Metadata": _GLib.Variant("a{sv}", self._meta),
                    },
                    [],
                )
            except Exception:
                pass

    def start(self):
        """Start the GLib loop in a daemon thread."""
        if not PYDBUS_AVAILABLE:
            return

        def _run():
            try:
                bus = SessionBus()
                self._pub = bus.publish("org.mpris.MediaPlayer2.music-backend", self)
                self._loop = GLib.MainLoop()
                self._loop.run()
            except Exception as e:
                print(f"[MPRIS] Failed to start: {e}", file=sys.stderr)

        t = threading.Thread(target=_run, daemon=True)
        t.start()

    def stop_loop(self):
        if self._loop:
            self._loop.quit()


# ── Main backend ──────────────────────────────────────────────────────────────


class MusicBackend:
    _DURATION_RE = re.compile(r"^(?:\d{1,2}:)?[0-5]?\d:[0-5]\d$")
    _HTTP_TIMEOUT = (4, 12)  # connect/read timeout for YTMusic requests
    _HOME_CACHE_TTL_SEC = 60

    def __init__(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        self.oauth_path = os.path.join(script_dir, "oauth.json")
        self.headers_path = os.path.join(script_dir, "headers_auth.json")

        if os.path.exists(self.oauth_path):
            self.ytm = YTMusic(self.oauth_path)
            self.log("Authenticated using oauth.json")
        elif os.path.exists(self.headers_path):
            self.ytm = YTMusic(self.headers_path)
            self.log("Authenticated using headers_auth.json")
        else:
            self.ytm = YTMusic()
            self.log("Running in anonymous mode")
        self._set_default_timeout(self.ytm)

        self.mpv_process = None
        self.history_file = os.path.join(script_dir, "history.json")
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self.ipc_socket = os.path.join(runtime_dir, f"mpv_music_{os.getuid()}.sock")
        self.current_video_id = None
        self._state_lock = threading.Lock()
        self._playback_token = 0
        self.cache_dir = os.path.expanduser("~/.cache/quickshell/media/coverart")
        os.makedirs(self.cache_dir, exist_ok=True)
        self._home_cache = []
        self._home_cache_ts = 0.0
        self._home_cache_lock = threading.Lock()

        # Track metadata state
        self._current_title = ""
        self._current_artist = ""
        self._current_art = ""

        # MPRIS server
        self.mpris = MprisServer(self)
        self.mpris.start()
        if PYDBUS_AVAILABLE:
            self.log("MPRIS server started on org.mpris.MediaPlayer2.music-backend")
        else:
            self.log(
                "pydbus not found — MPRIS metadata won't be published. Install: pip install pydbus"
            )

    # ── logging ───────────────────────────────────────────────────────────────
    def log(self, msg):
        print(f"[Backend] {msg}", file=sys.stderr)
        sys.stderr.flush()
        try:
            with open(os.path.expanduser("~/.cache/music_backend.log"), "a") as f:
                f.write(f"{msg}\n")
        except Exception:
            pass

    def _set_default_timeout(self, ytm_client):
        session = getattr(ytm_client, "_session", None)
        if session is None or getattr(session, "_ii_timeout_patched", False):
            return

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
            home_data = self.ytm.get_home()
            with self._home_cache_lock:
                self._home_cache = home_data
                self._home_cache_ts = now
            return home_data
        except Exception as e:
            self.log(f"Failed to fetch home: {e}")
            with self._home_cache_lock:
                return self._home_cache or []

    # ── helpers ───────────────────────────────────────────────────────────────
    def _seconds_to_duration(self, total_seconds):
        if not total_seconds or total_seconds <= 0: return ""
        hours, rem = divmod(total_seconds, 3600)
        minutes, seconds = divmod(rem, 60)
        if hours > 0: return f"{hours}:{minutes:02d}:{seconds:02d}"
        return f"{minutes}:{seconds:02d}"

    def _normalize_duration_text(self, value):
        if not isinstance(value, str): return ""
        text = value.strip()
        if not text or not self._DURATION_RE.fullmatch(text): return ""
        if text in {"0:00", "00:00", "0:00:00", "00:00:00"}: return ""
        return text

    def _extract_nested_duration_text(self, obj, depth=0, max_depth=4):
        if depth > max_depth or obj is None: return ""
        if isinstance(obj, str): return self._normalize_duration_text(obj)
        if isinstance(obj, dict):
            for key in ("duration", "length", "durationText", "lengthText", "timeText", "simpleText", "text"):
                found = self._extract_nested_duration_text(obj.get(key), depth + 1, max_depth)
                if found: return found
            for value in obj.values():
                found = self._extract_nested_duration_text(value, depth + 1, max_depth)
                if found: return found
        if isinstance(obj, list):
            for entry in obj:
                found = self._extract_nested_duration_text(entry, depth + 1, max_depth)
                if found: return found
        return ""

    def _extract_duration(self, item):
        # 1. Try standard keys
        for key in ("duration", "length", "durationText", "lengthText", "timeText"):
            duration = self._normalize_duration_text(item.get(key))
            if duration: return duration

        # 2. Try seconds/millis
        for key in ("duration_seconds", "durationSeconds", "lengthSeconds"):
            try:
                sec = int(item.get(key, 0))
                if sec > 0: return self._seconds_to_duration(sec)
            except: pass
        
        for key in ("durationMs", "lengthMs"):
            try:
                ms = int(item.get(key, 0))
                if ms > 0: return self._seconds_to_duration(ms // 1000)
            except: pass

        # 3. Recursive search for anything that looks like a timestamp
        return self._extract_nested_duration_text(item)

    def _resolve_ytdlp_path(self):
        local = os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "venv", "bin", "yt-dlp"
        )
        if os.path.isfile(local):
            return local
        system = shutil.which("yt-dlp")
        if system:
            return system
        raise FileNotFoundError("yt-dlp not found")

    def _cleanup_socket(self):
        if os.path.exists(self.ipc_socket):
            try:
                os.remove(self.ipc_socket)
            except OSError:
                pass

    def load_history(self):
        try:
            if os.path.exists(self.history_file):
                with open(self.history_file) as f:
                    return json.load(f)
        except Exception:
            pass
        return []

    def save_history(self, video_id):
        try:
            h = self.load_history()
            if video_id in h:
                h.remove(video_id)
            h.append(video_id)
            with open(self.history_file, "w") as f:
                json.dump(h[-20:], f)
        except Exception:
            pass

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
                        artist_name = val.split(" \u2022 ")[0]
                        break
            if not artist_name:
                artist_name = "Unknown Artist"
            title = item.get("title")
            if not title and item.get("resultType") in ["artist", "profile"]:
                title = artist_name
            if not title:
                title = item.get("name") or "Unknown Title"
            thumbnails = item.get("thumbnails") or item.get("thumbnail") or []
            art_url = thumbnails[-1].get("url") if thumbnails else ""
            
            # FORCE HIGH RES: YouTube often returns low-res URLs like =w120-h120.
            if art_url:
                if "=w" in art_url and "-h" in art_url:
                    art_url = re.sub(r"=w\d+-h\d+", "=w544-h544", art_url)
                elif "googleusercontent.com" in art_url and "=s" in art_url:
                    art_url = re.sub(r"=s\d+", "=s544", art_url)

            return {
                "id": str(index_offset),
                "videoId": item.get("videoId") or item.get("browseId"),
                "title": title,
                "artist": artist_name,
                "duration": self._extract_duration(item),
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

    # ── playback ──────────────────────────────────────────────────────────────
    def play(self, video_id, title, artist, art_url):
        self.log(f"Playing: {title} by {artist}")
        self.save_history(video_id)
        self.stop(notify=False)
        threading.Thread(
            target=self._play_task,
            args=(video_id, title, artist, art_url),
            daemon=True,
        ).start()

    def _play_task(self, video_id, title, artist, art_url):
        try:
            # 1. Get stream URL
            self.log("Fetching stream URL...")
            ytdlp = self._resolve_ytdlp_path()
            result = subprocess.run(
                [
                    ytdlp,
                    "-f",
                    "bestaudio",
                    "-g",
                    "--no-warnings",
                    f"https://music.youtube.com/watch?v={video_id}",
                ],
                capture_output=True,
                text=True,
                check=True,
                timeout=30,
            )
            stream_url = result.stdout.strip().split("\n")[-1].strip()
            if not stream_url:
                raise ValueError("yt-dlp returned empty URL")
            self.log("Stream URL obtained")

            # 2. Download art (blocking)
            art_file_path = ""
            if art_url:
                digest = hashlib.md5(art_url.encode()).hexdigest()
                art_file_path = os.path.join(self.cache_dir, digest)
                self._download_art(art_url, art_file_path)

            # Persist metadata for pause/resume re-broadcasts
            self._current_title = title
            self._current_artist = artist
            self._current_art = art_file_path

            # 3. Build mpv command — pure subprocess, no libmpv
            self._cleanup_socket()
            cmd = [
                "mpv",
                "--no-video",  # audio only
                "--no-terminal",  # no terminal output
                "--really-quiet",  # suppress mpv stderr noise
                "--script-opts=mpris-disable=yes",  # Disable mpv internal MPRIS
                f"--input-ipc-server={self.ipc_socket}",  # for pause/resume/stop
                f"--force-media-title={title} \u2022 {artist}",
                stream_url,
            ]
            self.log(f"Launching mpv subprocess...")
            process = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            with self._state_lock:
                self._playback_token += 1
                token = self._playback_token
                self.mpv_process = process
                self.current_video_id = video_id

            self.log("mpv launched — playback started")

            # 4. Update MPRIS metadata NOW (our own server, no mpv involvement)
            self.mpris.update(
                status="Playing",
                title=title,
                artist=artist,
                art_local_path=art_file_path,
                video_id=video_id,
            )

            # 5. Monitor process exit in a thread
            def _monitor():
                code = process.wait()
                self.log(f"mpv exited with code {code}")
                with self._state_lock:
                    is_current = self._playback_token == token
                    if is_current:
                        self.mpv_process = None
                        self.current_video_id = None
                self._cleanup_socket()
                if is_current:
                    self.mpris.update("Stopped")
                    self.send_response({"type": "playback_stopped"})

            threading.Thread(target=_monitor, daemon=True).start()

            # 6. Notify QML
            self.send_response(
                {
                    "type": "playback_started",
                    "videoId": video_id,
                    "title": title,
                    "artist": artist,
                    "artUrl": art_url,
                    "artLocalPath": art_file_path,
                }
            )

        except subprocess.CalledProcessError as e:
            self.log(f"yt-dlp error: {e.stderr}")
            self.send_response(
                {"type": "error", "message": f"yt-dlp failed: {e.stderr}"}
            )
        except Exception as e:
            import traceback

            self.log(f"Play task error: {e}\n{traceback.format_exc()}")
            self.send_response({"type": "error", "message": str(e)})

    def _ipc(self, command):
        """Send a JSON command to mpv via IPC socket."""
        if not os.path.exists(self.ipc_socket):
            return False
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(self.ipc_socket)
            s.sendall((json.dumps({"command": command}) + "\n").encode())
            s.close()
            return True
        except Exception:
            return False

    def stop(self, notify=True):
        with self._state_lock:
            process = self.mpv_process
            self.mpv_process = None
            self.current_video_id = None
            self._playback_token += 1
        if process:
            try:
                process.terminate()
                process.wait(timeout=2)
            except Exception:
                try:
                    process.kill()
                except Exception:
                    pass
        self._cleanup_socket()
        self.mpris.update("Stopped")
        if notify:
            self.send_response({"type": "playback_stopped"})

    def pause(self):
        if self._ipc(["set_property", "pause", True]):
            self.mpris.update(
                "Paused",
                title=self._current_title,
                artist=self._current_artist,
                art_local_path=self._current_art,
                video_id=self.current_video_id or "",
            )
            self.send_response({"type": "playback_paused"})

    def resume(self):
        if self._ipc(["set_property", "pause", False]):
            self.mpris.update(
                "Playing",
                title=self._current_title,
                artist=self._current_artist,
                art_local_path=self._current_art,
                video_id=self.current_video_id or "",
            )
            self.send_response({"type": "playback_resumed"})

    # ── track navigation ──────────────────────────────────────────────────────
    def fetch_playlist(self, video_id):
        try:
            data = self.ytm.get_watch_playlist(videoId=video_id, limit=20)
            return data.get("tracks", [])
        except Exception:
            return []

    def next_track(self):
        with self._state_lock:
            vid = self.current_video_id
        if not vid:
            return
        tracks = self.fetch_playlist(vid)
        for i, t in enumerate(tracks):
            if t.get("videoId") == vid and i + 1 < len(tracks):
                fmt = self.format_track_item(tracks[i + 1], i + 1)
                if fmt:
                    self.play(
                        fmt["videoId"], fmt["title"], fmt["artist"], fmt["artUrl"]
                    )
                return

    def prev_track(self):
        with self._state_lock:
            vid = self.current_video_id
        if not vid:
            return
        h = self.load_history()
        if len(h) >= 2:
            prev_id = h[-2]
            h.pop()
            with open(self.history_file, "w") as f:
                json.dump(h, f)
            try:
                s = self.ytm.get_song(prev_id)
                d = s.get("videoDetails", {})
                self.play(
                    prev_id,
                    d.get("title", ""),
                    d.get("author", ""),
                    d.get("thumbnail", {}).get("thumbnails", [{}])[-1].get("url", ""),
                )
            except Exception:
                pass

    # ── home / search ─────────────────────────────────────────────────────────
    def get_home(self):
        self.log("UI requested get_home")
        threading.Thread(target=self._fetch_home_task, daemon=True).start()

    def _fetch_home_task(self):
        self.log("Executing fully personalized home fetch...")
        sent_ids = set()
        history = self.load_history()
        recent_history = list(reversed(history[-8:]))

        def item_video_id(item):
            return item.get("videoId") or item.get("browseId")

        def append_unique(target, source, cap=96):
            if not source:
                return
            seen_local = {item_video_id(i) for i in target if item_video_id(i)}
            for item in source:
                vid = item_video_id(item)
                if not vid or vid in seen_local:
                    continue
                target.append(item)
                seen_local.add(vid)
                if len(target) >= cap:
                    break

        def to_section_items(raw_items, limit, index_offset):
            out = []
            for item in raw_items:
                vid = item_video_id(item)
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

        def search_songs(query, limit=16):
            try:
                return self.ytm.search(query, filter="songs", limit=limit)
            except Exception as e:
                self.log(f"Personalized search failed for '{query}': {e}")
                return []

        def pick_artists(items, limit=3):
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

        home_data = self._get_home_data()

        rec_keywords = (
            "listen again",
            "mixed for you",
            "similar to",
            "recommendations",
            "recommended",
            "for you",
            "because you listened",
        )
        pick_keywords = ("quick pick", "quick picks", "top picks", "picked for you")
        discover_keywords = (
            "discover",
            "new releases",
            "charts",
            "trending",
            "radio",
            "mood",
            "genre",
        )

        picks_raw = []
        recs_raw = []
        discover_raw = []
        discover_title = "Discover Music"
        discover_playlist_candidates = []

        for section in home_data:
            title = section.get("title", "")
            t_lower = title.lower()
            contents = section.get("contents", [])
            playable = [c for c in contents if c.get("videoId")]

            if any(k in t_lower for k in pick_keywords):
                append_unique(picks_raw, playable, cap=64)
                continue

            if any(k in t_lower for k in rec_keywords):
                append_unique(recs_raw, playable, cap=64)
                continue

            if any(k in t_lower for k in discover_keywords):
                append_unique(discover_raw, playable, cap=64)
                if playable and discover_title == "Discover Music":
                    discover_title = title or discover_title

            for c in contents:
                pid = c.get("playlistId") or c.get("browseId")
                if pid and pid.startswith("VL"):
                    pid = pid[2:]
                if pid:
                    discover_playlist_candidates.append((pid, c.get("title", title) or title))
                    break

        history_quick_tracks = []
        history_discover_tracks = []
        history_seed_ids = recent_history[:6]  # 3 most recent + older history seeds
        for idx, vid in enumerate(history_seed_ids):
            tracks = self.fetch_playlist(vid)
            if idx < 3:
                append_unique(history_quick_tracks, tracks, cap=96)
            else:
                append_unique(history_discover_tracks, tracks, cap=96)
        if not history_discover_tracks:
            append_unique(history_discover_tracks, history_quick_tracks, cap=96)

        history_seed_tracks = []
        append_unique(history_seed_tracks, history_quick_tracks, cap=128)
        append_unique(history_seed_tracks, history_discover_tracks, cap=128)

        if not discover_raw and not history_discover_tracks and discover_playlist_candidates:
            for pid, candidate_title in discover_playlist_candidates[:2]:
                try:
                    tracks = self.ytm.get_playlist(pid, limit=24).get("tracks", [])
                    if tracks:
                        append_unique(discover_raw, tracks, cap=64)
                        discover_title = candidate_title or discover_title
                        break
                except Exception:
                    pass

        artist_profile = pick_artists(history_seed_tracks + recs_raw + picks_raw, limit=4)

        # --- STREAM RECOMMENDATIONS ---
        rec_pool = []
        append_unique(rec_pool, recs_raw, cap=96)
        if len(rec_pool) < 24:
            for artist in artist_profile[:2]:
                append_unique(rec_pool, search_songs(artist, limit=12), cap=96)
                if len(rec_pool) >= 24:
                    break
        if not rec_pool:
            append_unique(rec_pool, search_songs("New Music", limit=24), cap=96)

        recs = to_section_items(rec_pool, limit=16, index_offset=0)
        self.send_response({"type": "home_section", "section": "recommendations", "items": recs})
        self.log(f"Streamed {len(recs)} Recommendations")

        # --- STREAM QUICK PICKS ---
        pick_pool = []
        append_unique(pick_pool, history_quick_tracks, cap=96)
        if len(pick_pool) < 24:
            for artist in artist_profile[:3]:
                append_unique(pick_pool, search_songs(f"{artist} popular songs", limit=10), cap=96)
                if len(pick_pool) >= 24:
                    break
        if len(pick_pool) < 24:
            append_unique(pick_pool, picks_raw, cap=96)
        if not pick_pool:
            try:
                fallback = self.ytm.get_watch_playlist(
                    playlistId="RDTMAK5uy_kset8DisdE7LSD4TNjEVvrKRTmG7a56sY", limit=24
                ).get("tracks", [])
                append_unique(pick_pool, fallback, cap=96)
            except Exception:
                pass

        # Keep quick picks responsive: avoid blocking on per-item duration lookups.
        picks = to_section_items(pick_pool, limit=16, index_offset=100)

        self.send_response({"type": "home_section", "section": "quick_picks", "items": picks})
        self.log(f"Streamed {len(picks)} Quick Picks")

        # --- STREAM DISCOVER ---
        discover_pool = []
        append_unique(discover_pool, history_discover_tracks, cap=96)
        if discover_pool and discover_title == "Discover Music":
            discover_title = "From Your History"
        append_unique(discover_pool, discover_raw, cap=96)
        if len(discover_pool) < 20:
            for artist in artist_profile[:3]:
                append_unique(discover_pool, search_songs(f"{artist} new release", limit=10), cap=96)
                append_unique(discover_pool, search_songs(f"{artist} latest songs", limit=10), cap=96)
                if len(discover_pool) >= 20:
                    break
        if not discover_pool:
            append_unique(discover_pool, search_songs("Trending Songs", limit=40), cap=96)
            discover_title = "Trending Songs"

        shorts = []
        for item in discover_pool:
            vid = item_video_id(item)
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

        self.send_response(
            {"type": "home_section", "section": "shorts", "items": shorts, "title": discover_title}
        )
        self.log(f"Streamed {len(shorts)} Discover items ({discover_title})")

    def search(self, query):
        threading.Thread(target=self._search_task, args=(query,), daemon=True).start()

    def _search_task(self, query):
        try:
            artists, songs, albums = [], [], []
            for i, item in enumerate(self.ytm.search(query)):
                fmt = self.format_track_item(item, i)
                if not fmt:
                    continue
                rt = item.get("resultType")
                if rt == "artist":
                    artists.append(fmt)
                elif rt in ("song", "video"):
                    songs.append(fmt)
                elif rt == "album":
                    albums.append(fmt)
            self.send_response(
                {
                    "type": "search_results",
                    "query": query,
                    "artists": artists[:5],
                    "songs": songs[:5],
                    "albums": albums[:5],
                }
            )
        except Exception as e:
            self.log(f"Search error: {e}")

    # ── I/O ───────────────────────────────────────────────────────────────────
    def send_response(self, data):
        print(json.dumps(data))
        sys.stdout.flush()

    # Track current metadata for pause/resume MPRIS updates
    _current_title = ""
    _current_artist = ""
    _current_art = ""

    def run(self):
        self.log("Music backend started.")
        self.send_response({"type": "ready"})

        def handle_sig(signum, frame):
            self.stop()
            self.mpris.stop_loop()
            sys.exit(0)

        signal.signal(signal.SIGTERM, handle_sig)
        signal.signal(signal.SIGINT, handle_sig)

        try:
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue
                try:
                    c = json.loads(line)
                    t = c.get("command")
                    if t == "search":
                        self.search(c.get("query", ""))
                    elif t == "get_suggestions":
                        try:
                            self.send_response(
                                {
                                    "type": "suggestions",
                                    "results": self.ytm.get_search_suggestions(
                                        c.get("query", "")
                                    ),
                                }
                            )
                        except Exception:
                            pass
                    elif t == "get_home":
                        self.get_home()
                    elif t == "play":
                        if c.get("videoId"):
                            self._current_title = c.get("title", "")
                            self._current_artist = c.get("artist", "")
                            self._current_art = (
                                ""  # updated after download in _play_task
                            )
                            self.play(
                                c["videoId"],
                                c.get("title", ""),
                                c.get("artist", ""),
                                c.get("artUrl", ""),
                            )
                        else:
                            self.resume()
                    elif t == "pause":
                        self.pause()
                    elif t == "resume":
                        self.resume()
                    elif t == "next":
                        self.next_track()
                    elif t == "previous":
                        self.prev_track()
                    elif t == "stop":
                        self.stop()
                    elif t == "quit":
                        break
                except Exception as e:
                    self.log(f"Command error: {e}")
        finally:
            self.stop()
            self.mpris.stop_loop()


if __name__ == "__main__":
    MusicBackend().run()
