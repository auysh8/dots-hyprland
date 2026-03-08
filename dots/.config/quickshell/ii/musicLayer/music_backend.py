#!/usr/bin/env python3
"""
Music backend using:
  - subprocess mpv  → reliable audio playback (no libmpv hang)
  - pydbus          → custom MPRIS2 server with correct artist/art metadata
Install deps: pip install pydbus ytmusicapi
"""

import atexit
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
    <method name="Seek">
      <arg direction="in" name="Offset" type="x"/>
    </method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
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
        self._bus = None
        self._bus_con = None  # raw Gio.DBusConnection for signal emission
        self._cached_position = 0
        self._cached_duration = 0
        self._published = False

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
        from gi.repository import GLib as _GLib
        meta = dict(self._meta)
        if self._cached_duration > 0:
            meta["mpris:length"] = _GLib.Variant("x", self._cached_duration)
        return meta

    @property
    def Volume(self):
        return 1.0

    @Volume.setter
    def Volume(self, v):
        pass

    @property
    def Position(self):
        return self._cached_position

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
        return True

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

    def Seek(self, Offset: 'x'):
        current = getattr(self, "_cached_position", 0)
        new_pos = max(0, current + Offset)
        self._backend.seek(new_pos / 1_000_000.0)

    def SetPosition(self, TrackId: 'o', Position: 'x'):
        self._backend.seek(Position / 1_000_000.0)

    # ── metadata update (called from backend) ────────────────────────────────
    def update(self, status, title="", artist="", art_local_path="", video_id="", art_url=""):
        from gi.repository import GLib as _GLib

        self._status = status

        if status == "Stopped":
            self._cached_position = 0
            self._cached_duration = 0

        safe_id = re.sub(r"[^A-Za-z0-9]", "_", video_id or "0")
        if video_id:
            tid = f"/org/mpris/MediaPlayer2/music_backend/track_{safe_id}"
        else:
            tid = "/org/mpris/MediaPlayer2/TrackList/NoTrack"
        meta = {
            "mpris:trackid": _GLib.Variant("o", tid),
            "mpris:length": _GLib.Variant("x", self._cached_duration),
            "xesam:title": _GLib.Variant("s", title),
            "xesam:artist": _GLib.Variant("as", [artist] if artist else []),
            "xesam:url": _GLib.Variant("s", ""),
        }
        if art_local_path and os.path.exists(art_local_path):
            meta["mpris:artUrl"] = _GLib.Variant("s", f"file://{art_local_path}")
        elif art_url:
            meta["mpris:artUrl"] = _GLib.Variant("s", art_url)

        self._meta = meta

        # Emit PropertiesChanged so widgets update immediately
        self._emit_properties_changed({
            "PlaybackStatus": _GLib.Variant("s", self._status),
            "Metadata": _GLib.Variant("a{sv}", self._meta),
        })

    def _emit_properties_changed(self, changed_props):
        """Emit org.freedesktop.DBus.Properties.PropertiesChanged via raw GDBus."""
        from gi.repository import GLib as _GLib, Gio
        con = self._bus_con
        if con is None:
            return
        try:
            con.emit_signal(
                None,  # broadcast
                "/org/mpris/MediaPlayer2",
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                _GLib.Variant("(sa{sv}as)", (
                    "org.mpris.MediaPlayer2.Player",
                    changed_props,
                    [],
                )),
            )
        except Exception as e:
            self._backend.log(f"[MPRIS] Signal emission error: {e}")

    def start(self):
        """Start the GLib loop in a daemon thread (but don't publish yet)."""
        if not PYDBUS_AVAILABLE:
            return

        def _run():
            try:
                self._bus = SessionBus()
                self._bus_con = self._bus.con
                self._loop = GLib.MainLoop()
                self._loop.run()
            except Exception as e:
                self._backend.log(f"[MPRIS] Failed to start: {e}")

        t = threading.Thread(target=_run, daemon=True)
        t.start()

        # Background poller for position/duration — avoids blocking GLib thread
        def _poll_playback():
            while True:
                time.sleep(1)
                try:
                    if self._status != "Playing":
                        continue
                    pos = self._backend._ipc_get("time-pos")
                    if pos is not None:
                        self._cached_position = int(float(pos) * 1_000_000)
                    dur = self._backend._ipc_get("duration")
                    if dur is not None:
                        new_dur = int(float(dur) * 1_000_000)
                        if new_dur != self._cached_duration:
                            self._cached_duration = new_dur
                            # Re-emit metadata with correct duration
                            from gi.repository import GLib as _GLib
                            self._emit_properties_changed({
                                "Metadata": _GLib.Variant("a{sv}", self.Metadata),
                            })
                except Exception:
                    pass

        poller = threading.Thread(target=_poll_playback, daemon=True)
        poller.start()

    def publish(self):
        """Publish the MPRIS service on D-Bus (called when playback starts)."""
        if self._published or not self._bus:
            return
        try:
            self._pub = self._bus.publish(
                "org.mpris.MediaPlayer2.music-backend",
                ("/org/mpris/MediaPlayer2", self),
            )
            self._published = True
            self._backend.log("[MPRIS] Published on D-Bus")
        except Exception as e:
            self._backend.log(f"[MPRIS] Publish failed: {e}")

    def unpublish(self):
        """Remove the MPRIS service from D-Bus (called when playback stops)."""
        if not self._published or not self._pub:
            return
        try:
            self._pub.unpublish()
            self._pub = None
            self._published = False
            self._backend.log("[MPRIS] Unpublished from D-Bus")
        except Exception as e:
            self._backend.log(f"[MPRIS] Unpublish failed: {e}")

    def stop_loop(self):
        self.unpublish()
        if self._loop:
            self._loop.quit()


# ── Main backend ──────────────────────────────────────────────────────────────


class MusicBackend:
    _DURATION_RE = re.compile(r"^(?:\d{1,2}:)?[0-5]?\d:[0-5]\d$")
    _HTTP_TIMEOUT = (8, 20)  # connect/read timeout for YTMusic requests
    _HOME_CACHE_TTL_SEC = 60

    _OAUTH_CLIENT_ID = "861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com"
    _OAUTH_CLIENT_SECRET = "SboVhoG9s0rNafixCSGGKXAT"

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

    def __init__(self):
        script_dir = os.path.dirname(os.path.abspath(__file__))
        self.oauth_path = os.path.join(script_dir, "oauth.json")
        self.headers_path = os.path.join(script_dir, "headers_auth.json")

        self.ytm = None
        try:
            self._init_ytm()
        except Exception as e:
            self.log(f"YTMusic init failed (network issue?): {e}. Will retry dynamically.")
            # Explicitly keep self.ytm as None so that _fetch_explore_task or _fetch_home_task
            # cleanly retries _init_ytm() later instead of permanently running anonymously.

        self.mpv_process = None
        self._play_stack = []  # in-memory playback stack for prev_track
        self._current_queue = []  # upcoming tracks (radio queue)
        self.repeat_mode = 0 # 0: Off, 1: All, 2: One
        self._stream_cache = {} # Background cache for gapless playback URL transitions
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self.ipc_socket = os.path.join(runtime_dir, f"mpv_music_{os.getuid()}.sock")
        self.current_video_id = None
        self._state_lock = threading.Lock()
        self._playback_token = 0
        self._ytdlp_proc = None  # track current yt-dlp subprocess for cancellation
        self.cache_dir = os.path.expanduser("~/.cache/quickshell/media/coverart")
        os.makedirs(self.cache_dir, exist_ok=True)
        self._home_cache = []
        self._home_cache_ts = 0.0
        self._home_cache_lock = threading.Lock()

        # Search results cache: { query_lower: { "ts": float, "response": dict } }
        self._search_cache = {}
        self._search_cache_ttl = 300  # 5 minutes

        # Explore/Charts cache: { "sections": [...], "ts": float }
        self._explore_cache = None
        self._explore_cache_ttl = 900  # 15 minutes

        # Song metadata cache: { videoId: { "data": dict, "is_liked": bool, "ts": float } }
        self._song_meta_cache = {}
        self._song_meta_cache_ttl = 1800  # 30 minutes

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

        # Ensure mpv is killed when backend exits (e.g. quickshell restart)
        atexit.register(self._cleanup_on_exit)
        signal.signal(signal.SIGTERM, self._sigterm_handler)
        signal.signal(signal.SIGHUP, self._sigterm_handler)

    def _sigterm_handler(self, signum, frame):
        """Handle SIGTERM/SIGHUP — clean up mpv and exit."""
        self._cleanup_on_exit()
        sys.exit(0)


    def _cleanup_on_exit(self):
        try:
            if self.mpv_process:
                self.mpv_process.terminate()
                self.mpv_process.wait(timeout=2)
        except Exception:
            try:
                if self.mpv_process:
                    self.mpv_process.kill()
            except Exception:
                pass

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

        import requests.adapters
        from urllib3.util.retry import Retry

        # Add connection retries to workaround typical SSL drop / timeouts
        retries = Retry(total=3, backoff_factor=0.5, status_forcelist=[ 500, 502, 503, 504 ])
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

    def _push_play_stack(self, video_id):
        """Track played video IDs in-memory for prev_track navigation."""
        if video_id in self._play_stack:
            self._play_stack.remove(video_id)
        self._play_stack.append(video_id)
        if len(self._play_stack) > 20:
            self._play_stack = self._play_stack[-20:]

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
            art_url = self._extract_art_url(item)

            # Extract artist channelId if available
            artist_id = ""
            if isinstance(artists_list, list) and artists_list:
                artist_id = artists_list[0].get("id", "") or artists_list[0].get("browseId", "")

            final_id = item.get("videoId") or item.get("browseId")
            if not final_id and item.get("resultType") in ["artist", "profile"] and artist_id:
                final_id = artist_id

            return {
                "id": str(index_offset),
                "videoId": final_id,
                "title": title,
                "artist": artist_name,
                "artistId": artist_id,
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

    def _item_video_id(self, item):
        return item.get("videoId") or item.get("browseId")

    def _extract_art_url(self, item, size=544):
        """Extract thumbnail URL from item and force high resolution."""
        thumbnails = item.get("thumbnails") or item.get("thumbnail") or []
        if isinstance(thumbnails, dict):
            thumbnails = thumbnails.get("thumbnails", [])
        if isinstance(thumbnails, list) and thumbnails:
            last_thumb = thumbnails[-1]
            art = last_thumb.get("url", "") if isinstance(last_thumb, dict) else ""
        else:
            art = ""
        # Force high-res
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

        # Fetch all 6 history playlists in parallel
        results = {}
        with ThreadPoolExecutor(max_workers=6) as pool:
            futures = {pool.submit(self.fetch_playlist, vid): idx for idx, vid in enumerate(history_seed_ids)}
            for future in as_completed(futures):
                idx = futures[future]
                try:
                    results[idx] = future.result()
                except Exception:
                    results[idx] = []

        # Distribute results in order: first 3 → quick picks, rest → discover
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

    def _collect_home_section_candidates(
        self, home_data, rec_keywords, pick_keywords, discover_keywords
    ):
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
            playable = [c for c in contents if c.get("videoId")]

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
                    
        # Fallback for unauthenticated case where keywords might not match
        if not picks_raw and other_playable:
            self._append_unique(picks_raw, other_playable.pop(0), cap=64)
        if not recs_raw and other_playable:
            self._append_unique(recs_raw, other_playable.pop(0), cap=64)
        if not discover_raw and other_playable:
            self._append_unique(discover_raw, other_playable.pop(0), cap=64)

        return picks_raw, recs_raw, discover_raw, discover_title, discover_playlist_candidates

    def _seed_discover_from_playlists(
        self, discover_raw, history_discover_tracks, discover_playlist_candidates, discover_title
    ):
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
        if not rec_pool:
            pass # Fallback to empty if 'listen again' isn't found, rather than injecting random searches
            
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

        # Keep quick picks responsive: avoid blocking on per-item duration lookups.
        return self._to_section_items(pick_pool, limit=16, index_offset=100, sent_ids=sent_ids)

    def _build_discover_section(
        self, history_discover_tracks, discover_raw, artist_profile, sent_ids, discover_title
    ):
        discover_pool = []
        
        # Prioritize real YouTube Music authentic discovery feeds (discover_raw) FIRST
        self._append_unique(discover_pool, discover_raw, cap=96)
        
        # Only fallback to local "listening history" if YTM returned absolutely no discovery data
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

    # ── playback ──────────────────────────────────────────────────────────────
    def play(self, video_id, title, artist, art_url):
        self.log(f"Playing: {title} by {artist}")
        # Ensure high-res art URL
        if art_url:
            if "=w" in art_url and "-h" in art_url:
                art_url = re.sub(r"=w\d+-h\d+", "=w544-h544", art_url)
            elif "googleusercontent.com" in art_url and "=s" in art_url:
                art_url = re.sub(r"=s\d+", "=s544", art_url)
        self._push_play_stack(video_id)
        
        # Capture and reset auto-advancing flag before spawning thread
        # so each play task gets its own copy and rapid clicks don't interfere
        is_auto = getattr(self, "_is_auto_advancing", False)
        self._is_auto_advancing = False
        
        # Kill any in-flight yt-dlp fetch from previous play command
        try:
            if self._ytdlp_proc and self._ytdlp_proc.poll() is None:
                self._ytdlp_proc.kill()
                self._ytdlp_proc = None
        except Exception:
            pass
        
        self.stop(notify=False)
        
        self.send_response({
            "type": "track_loading",
            "videoId": video_id,
            "title": title,
            "artist": artist,
            "artUrl": art_url
        })
        
        with self._state_lock:
            self._playback_token += 1
            token = self._playback_token
            
        threading.Thread(
            target=self._play_task,
            args=(video_id, title, artist, art_url, token, is_auto),
            daemon=True,
        ).start()

    def _prefetch_stream_url(self, video_id):
        if video_id in self._stream_cache:
            return
        self.log(f"Background prefetching next URL for gapless playback: {video_id}")
        try:
            ytdlp = self._resolve_ytdlp_path()
            result = subprocess.run(
                [ytdlp, "-f", "bestaudio", "-g", "--no-warnings", f"https://music.youtube.com/watch?v={video_id}"],
                capture_output=True, text=True, check=True, timeout=30,
            )
            stream_url = result.stdout.strip().split("\n")[-1].strip()
            if stream_url:
                with self._state_lock:
                    self._stream_cache[video_id] = stream_url
                self.log(f"Gapless URL ready for {video_id}")
        except Exception as e:
            self.log(f"Failed gapless prefetch: {e}")

    def _play_task(self, video_id, title, artist, art_url, token, is_auto=False):
        try:
            # Debounce: wait briefly so rapid next-button clicks settle
            # before starting expensive yt-dlp work. Only the last click survives.
            time.sleep(0.25)

            with self._state_lock:
                if self._playback_token != token:
                    return

            # Check if this is a playlist/album ID (deferred from explore section)
            if video_id and (video_id.startswith("OLAK") or video_id.startswith("PL") or video_id.startswith("VL")):
                self.log(f"Resolving playlist/album lead track for: {video_id}")
                try:
                    p_data = self.ytm.get_watch_playlist(playlistId=video_id, limit=1).get("tracks", [])
                    if p_data and p_data[0].get("videoId"):
                        video_id = p_data[0].get("videoId")
                        with self._state_lock:
                            if self._playback_token == token:
                                self.current_video_id = video_id
                except Exception as e:
                    self.log(f"Failed to resolve playlist videoId: {e}")

            with self._state_lock:
                if self._playback_token != token:
                    return

            # 1. Get stream URL (art download deferred to after mpv launch to save bandwidth)
            with self._state_lock:
                stream_url = self._stream_cache.pop(video_id, None)
            
            # Compute art file path (download happens later, may already be cached)
            art_file_path = ""
            if art_url:
                digest = hashlib.md5(art_url.encode()).hexdigest()
                art_file_path = os.path.join(self.cache_dir, digest)

            if stream_url:
                self.log(f"Using instant pre-fetched gapless stream URL")
            else:
                self.log("Fetching stream URL...")
                ytdlp = self._resolve_ytdlp_path()
                proc = subprocess.Popen(
                    [
                        ytdlp,
                        "-f",
                        "bestaudio",
                        "-g",
                        "--no-warnings",
                        f"https://music.youtube.com/watch?v={video_id}",
                    ],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                )
                self._ytdlp_proc = proc
                stdout, _ = proc.communicate(timeout=30)
                self._ytdlp_proc = None
                
                if proc.returncode != 0:
                    raise ValueError(f"yt-dlp exited with code {proc.returncode}")
                stream_url = stdout.strip().split("\n")[-1].strip()
                
                # Recheck token after expensive fetch — bail if superseded
                with self._state_lock:
                    if self._playback_token != token:
                        self.log("Playback task aborted after stream fetch.")
                        return
                        
            if not stream_url:
                raise ValueError("yt-dlp returned empty URL")
            self.log("Stream URL obtained")

            # Persist metadata for pause/resume re-broadcasts
            self._current_title = title
            self._current_artist = artist
            self._current_art = art_file_path
            self._current_art_url = art_url

            with self._state_lock:
                if self._playback_token != token:
                    self.log("Playback task aborted, another play command was issued.")
                    return

            # Fetch radio queue only for fresh (non-auto-advancing) plays
            # and only after token check to prevent stale tasks from replacing the queue
            if not is_auto:
                threading.Thread(target=self._fetch_queue_task, args=(video_id,), daemon=True).start()

            # 3. Build mpv command — pure subprocess, no libmpv
            self._cleanup_socket()
            cmd = [
                "mpv",
                "--no-video",  # audio only
                "--no-terminal",  # no terminal output
                "--really-quiet",  # suppress mpv stderr noise
                "--no-config",  # don't load user mpv config
                "--load-scripts=no",  # disable all scripts including MPRIS
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
                # Re-check just in case, though we checked right before Popen
                if self._playback_token != token:
                    process.kill()
                    return
                self.mpv_process = process
                self.current_video_id = video_id

            self.log("mpv launched — playback started")
            
            # Attempt to prefetch the next track for gapless playback
            with self._state_lock:
                next_id = None
                if self.repeat_mode == 2:
                    next_id = video_id # Repeat one
                elif getattr(self, "_current_queue", None):
                    next_id = self._current_queue[0].get("videoId")
            
            if next_id:
                threading.Thread(target=self._prefetch_stream_url, args=(next_id,), daemon=True).start()

            # Download art in background (for MPRIS + ColorQuantizer, doesn't block playback)
            def _deferred_art_download():
                if art_url and art_file_path:
                    if self._download_art(art_url, art_file_path):
                        # Notify QML so ColorQuantizer can extract colors
                        self.send_response({
                            "type": "art_downloaded",
                            "videoId": video_id,
                            "path": art_file_path,
                        })
                        # Update MPRIS with local art path
                        self.mpris.update(
                            status="Playing",
                            title=title,
                            artist=artist,
                            art_local_path=art_file_path,
                            video_id=video_id,
                            art_url=art_url,
                        )
            threading.Thread(target=_deferred_art_download, daemon=True).start()

            # 4. IMMEDIATELY notify QML — don't wait for history sync
            self.send_response(
                {
                    "type": "playback_started",
                    "videoId": video_id,
                    "title": title,
                    "artist": artist,
                    "artUrl": art_url,
                    "artLocalPath": art_file_path,
                    "isLiked": False,  # updated async below
                }
            )

            # 5. Publish MPRIS on D-Bus
            self.mpris.publish()
            self.mpris.update(
                status="Playing",
                title=title,
                artist=artist,
                art_local_path=art_file_path,
                video_id=video_id,
                art_url=art_url,
            )

            # 6. History sync + like check in background (non-blocking)
            def _sync_history():
                try:
                    if os.path.exists(self.oauth_path) or os.path.exists(self.headers_path):
                        self.log(f"Syncing '{title}' to YouTube Music history...")
                        cached_meta = self._song_meta_cache.get(video_id)
                        if cached_meta and (time.time() - cached_meta["ts"]) < self._song_meta_cache_ttl:
                            song_data = cached_meta["data"]
                            is_liked = cached_meta["is_liked"]
                        else:
                            song_data = self.ytm.get_song(video_id)
                            is_liked = bool(song_data and song_data.get('videoDetails', {}).get('likeStatus') == 'LIKE')
                            self._song_meta_cache[video_id] = {
                                "data": song_data,
                                "is_liked": is_liked,
                                "ts": time.time(),
                            }
                            
                        if song_data and getattr(self.ytm, 'add_history_item', None):
                            self.ytm.add_history_item(song_data)
                            self.log("History sync successful.")
                        
                        # Send liked status update to QML
                        if is_liked:
                            self.send_response({"type": "like_status", "videoId": video_id, "isLiked": True})
                except Exception as e:
                    self.log(f"Failed to sync history to YouTube Music: {e}")
            threading.Thread(target=_sync_history, daemon=True).start()

            # Wait for mpv to resolve duration, then update metadata again to push length to clients
            def _wait_for_duration():
                for _ in range(20):
                    time.sleep(0.5)
                    if not self.mpv_process: break
                    dur = self._ipc_get("duration")
                    if dur is not None:
                        dur_sec = int(float(dur))
                        self.log(f"Resolved duration: {dur_sec}s, updating mpris")
                        # Set cached duration BEFORE calling update so it's included in the signal
                        self.mpris._cached_duration = int(float(dur) * 1_000_000)
                        self.mpris.update(
                            status="Playing",
                            title=title,
                            artist=artist,
                            art_local_path=art_file_path,
                            video_id=video_id,
                            art_url=art_url,
                        )
                        # Send duration to QML
                        self.send_response({
                            "type": "playback_duration",
                            "durationSec": dur_sec,
                        })
                        break
            threading.Thread(target=_wait_for_duration, daemon=True).start()

            # 7. Periodic position updates to QML
            def _poll_position():
                while True:
                    time.sleep(1)
                    with self._state_lock:
                        if self._playback_token != token:
                            break
                    if not self.mpv_process:
                        break
                    pos = self._ipc_get("time-pos")
                    dur = self._ipc_get("duration")
                    if pos is not None:
                        self.send_response({
                            "type": "playback_progress",
                            "positionSec": int(float(pos)),
                            "durationSec": int(float(dur)) if dur else 0,
                        })
            threading.Thread(target=_poll_position, daemon=True).start()

            # 8. Monitor process exit for auto-advance
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
                    # 1. Repeat One
                    if self.repeat_mode == 2:
                        self.log(f"Repeat One: Replaying {title}")
                        self.play(video_id, title, artist, art_url)
                        return

                    # 2. Auto-advance queue
                    if self._current_queue:
                        next_track = self._current_queue[0]
                        if self.repeat_mode == 1:
                            # Repeat All: Push current track to the back of the queue
                            self._current_queue.append({
                                "videoId": video_id,
                                "title": title,
                                "artist": artist,
                                "artUrl": art_url
                            })
                            self._current_queue.pop(0)
                        else:
                            self._current_queue.pop(0)
                            
                        self.send_response({"type": "queue_updated", "queue": self._current_queue})
                        self.log(f"Auto-advancing to: {next_track['title']}")
                        self._is_auto_advancing = True
                        self.play(next_track["videoId"], next_track["title"], next_track["artist"], next_track["artUrl"])
                    else:
                        if self.repeat_mode == 1:
                            # Repeat All but queue is empty -> replay track
                            self.log(f"Repeat All (Empty Queue): Replaying {title}")
                            self.play(video_id, title, artist, art_url)
                        else:
                            # Queue empty — auto-fetch more similar songs (radio mode)
                            self.log("Queue empty, fetching more radio tracks...")
                            threading.Thread(target=self._auto_continue, args=(video_id,), daemon=True).start()

            threading.Thread(target=_monitor, daemon=True).start()

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

    def _ipc_get(self, prop_name):
        """Get a property from mpv via IPC socket."""
        if not os.path.exists(self.ipc_socket):
            return None
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.5)
            s.connect(self.ipc_socket)
            s.sendall((json.dumps({"command": ["get_property", prop_name]}) + "\n").encode())
            f = s.makefile()
            for line in f:
                data = json.loads(line)
                if "data" in data or "error" in data:
                    return data.get("data")
            s.close()
            return None
        except Exception:
            return None

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
        self.mpris.unpublish()
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
                art_url=getattr(self, "_current_art_url", ""),
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
                art_url=getattr(self, "_current_art_url", ""),
            )
            self.send_response({"type": "playback_resumed"})

    def seek(self, position_sec):
        if self.mpv_process:
            self._ipc(["set_property", "time-pos", position_sec])

    def _fetch_queue_task(self, video_id):
        try:
            self.send_response({"type": "queue_fetching"})
            self.log(f"Fetching radio queue for: {video_id}")
            data = self.ytm.get_watch_playlist(videoId=video_id, limit=20)
            tracks = data.get("tracks", [])
            queue = []
            
            # Skip the currently playing track (usually first)
            for item in tracks:
                vid = self._item_video_id(item)
                if not vid or vid == video_id:
                    continue
                    
                artist_name = "Unknown"
                artists_list = item.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    artist_name = artists_list[0].get("name", "Unknown")
                    
                queue.append({
                    "videoId": vid,
                    "title": item.get("title", "Unknown"),
                    "artist": artist_name,
                    "artUrl": self._extract_art_url(item),
                    "duration": self._extract_duration(item) or ""
                })
                
            with self._state_lock:
                self._current_queue = queue
                
            self.send_response({"type": "queue_updated", "queue": self._current_queue})
            self.log(f"Queue updated with {len(self._current_queue)} tracks")
        except Exception as e:
            self.log(f"Failed to fetch radio queue: {e}")

    def fetch_playlist(self, video_id):
        try:
            data = self.ytm.get_watch_playlist(videoId=video_id, limit=20)
            return data.get("tracks", [])
        except Exception:
            return []

    def next_track(self):
        with self._state_lock:
            vid = self.current_video_id
            q = list(self._current_queue)
            
        # 1. Use existing queue if we have one
        if q:
            next_track = q[0]
            self._current_queue = q[1:]
            self.send_response({"type": "queue_updated", "queue": self._current_queue})
            self._is_auto_advancing = True
            self.play(next_track["videoId"], next_track["title"], next_track["artist"], next_track["artUrl"])
            return

        # 2. Queue empty — auto-fetch more similar songs (radio mode)
        if vid:
            self.log("Queue empty on next_track, fetching radio...")
            threading.Thread(target=self._auto_continue, args=(vid,), daemon=True).start()

    def _auto_continue(self, seed_video_id, title=None, artist=None, art_url=None):
        """Fetch radio tracks for seed_video_id, populate queue, and play the first one."""
        try:
            self.send_response({"type": "queue_fetching"})
            self.log(f"Auto-continue: fetching radio for {seed_video_id}")
            data = self.ytm.get_watch_playlist(videoId=seed_video_id, limit=20)
            tracks = data.get("tracks", [])
            queue = []

            for item in tracks:
                vid = self._item_video_id(item)
                if not vid or vid == seed_video_id:
                    continue

                artist_name = "Unknown"
                artists_list = item.get("artists", [])
                if isinstance(artists_list, list) and artists_list:
                    artist_name = artists_list[0].get("name", "Unknown")

                queue.append({
                    "videoId": vid,
                    "title": item.get("title", "Unknown"),
                    "artist": artist_name,
                    "artUrl": self._extract_art_url(item),
                    "duration": self._extract_duration(item) or ""
                })

            if queue:
                first = queue[0]
                with self._state_lock:
                    self._current_queue = queue[1:]
                self.send_response({"type": "queue_updated", "queue": self._current_queue})
                self.log(f"Auto-continue: playing {first['title']}, {len(self._current_queue)} more in queue")
                self._is_auto_advancing = True
                self.play(first["videoId"], first["title"], first["artist"], first["artUrl"])
            else:
                self.log("Auto-continue: no tracks found, stopping.")
                self.mpris.update("Stopped")
                self.send_response({"type": "playback_stopped"})
        except Exception as e:
            self.log(f"Auto-continue failed: {e}")
            self.mpris.update("Stopped")
            self.send_response({"type": "playback_stopped"})

    def prev_track(self):
        with self._state_lock:
            vid = self.current_video_id
        if not vid:
            return
        if len(self._play_stack) >= 2:
            self._play_stack.pop()  # remove current
            prev_id = self._play_stack[-1]
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
        if not self.ytm:
            try:
                self._init_ytm()
            except Exception as e:
                self.log(f"Deferred YTMusic init failed: {e}")
                self.send_response({"type": "error", "message": "Failed to connect to YouTube Music."})
                return

        self.log("Executing fully personalized home fetch...")
        sent_ids = set()
        recent_history = list(reversed(self._play_stack[-8:]))

        home_data = self._get_home_data()

        rec_keywords = ("listen again",)
        pick_keywords = ("quick pick", "quick picks", "top picks", "picked for you")
        discover_keywords = (
            "forgotten",
            "favourite",
            "favorite",
            "listen again",
            "discover",
        )

        picks_raw, recs_raw, discover_raw, discover_title, discover_playlist_candidates = (
            self._collect_home_section_candidates(
                home_data,
                rec_keywords,
                pick_keywords,
                discover_keywords,
            )
        )

        history_quick_tracks, history_discover_tracks, history_seed_tracks = (
            self._build_history_track_pools(recent_history)
        )

        discover_raw, discover_title = self._seed_discover_from_playlists(
            discover_raw,
            history_discover_tracks,
            discover_playlist_candidates,
            discover_title,
        )

        artist_profile = self._pick_artists(history_seed_tracks + recs_raw + picks_raw, limit=4)

        import time

        # --- STREAM RECOMMENDATIONS (Listen Again) ---
        recs = self._build_recommendations_section(recs_raw, sent_ids)
        self.send_response({"type": "home_section", "section": "recommendations", "items": recs})
        self.log(f"Streamed {len(recs)} Listen Again (Recommendations)")

        time.sleep(0.4)

        # --- STREAM QUICK PICKS ---
        picks = self._build_quick_picks_section(
            picks_raw,
            sent_ids,
        )
        self.send_response({"type": "home_section", "section": "quick_picks", "items": picks})
        self.log(f"Streamed {len(picks)} Quick Picks")

        time.sleep(0.4)

        # --- STREAM DISCOVER ---
        shorts, discover_title = self._build_discover_section(
            history_discover_tracks,
            discover_raw,
            artist_profile,
            sent_ids,
            discover_title,
        )

        self.send_response(
            {"type": "home_section", "section": "shorts", "items": shorts, "title": discover_title}
        )
        self.log(f"Streamed {len(shorts)} Discover items ({discover_title})")

    def get_explore(self):
        self.log("UI requested get_explore")
        # Check explore cache first
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
                # Update metadata cache to stay in sync
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

        # --- STREAM TRENDING: Fetch Dynamic Charts via API --
        trending_items = []
        try:
            self.log("Fetching real-time trending charts for IN...")
            charts = self.ytm.get_charts(country="IN")
            
            # We will merge two charts: "Trending 20 India" (Mainstream/Eng) and "Top Weekly Videos Hindi" (Hindi)
            playlist_ids = []
            
            # 1. Grab Mainstream/Eng (Trending 20 India)
            for item in charts.get("daily", []):
                if "Trending" in item.get("title", "") or "Videos" in item.get("title", ""):
                    playlist_ids.append(item.get("playlistId"))
                    break
                    
            # 2. Grab Hindi (Top Weekly Videos Hindi)
            for item in charts.get("weekly", []):
                if "Hindi" in item.get("title", ""):
                    playlist_ids.append(item.get("playlistId"))
                    break
                    
            # Process the fetched dynamic playlists
            for pid in playlist_ids:
                if not pid: continue
                raw_tracks = self.ytm.get_watch_playlist(playlistId=pid, limit=25).get("tracks", [])
                
                for item in raw_tracks:
                    vid = self._item_video_id(item)
                    if not vid or vid in sent_ids:
                        continue
                        
                    # CRITICAL FILTER: Enforce strictly "Songs" (Audio Track, or Official Music)
                    # Exclude "UGC" (User Generated Content) and "PODCAST" videos completely
                    vtype = item.get("videoType", "")
                    if vtype in ("MUSIC_VIDEO_TYPE_UGC", "MUSIC_VIDEO_TYPE_PODCAST_EPISODE"):
                        continue
                        
                    fmt = self.format_track_item(item, len(trending_items))
                    if fmt:
                        trending_items.append(fmt)
                        sent_ids.add(vid)
                    
                    # Stop if we've accumulated enough high quality songs
                    if len(trending_items) >= 16:
                        break
                
                if len(trending_items) >= 16:
                    break
                    
        except Exception as e:
            self.log(f"Dynamic Trending fetch failed: {e}")

        trending_response = {"type": "explore_section", "section": "trending", "items": trending_items}
        self.send_response(trending_response)
        self.log(f"Streamed {len(trending_items)} trending songs")

        # --- STREAM NEW RELEASES: Use get_explore() directly ---
        new_releases_items = []
        try:
            self.log("Fetching new releases from explore page...")
            explore_data = self.ytm.get_explore()
            releases = explore_data.get("new_releases", [])[:16]

            for release in releases:
                # API returns videoId for singles, audioPlaylistId/playlistId for albums
                vid = release.get("videoId") or release.get("audioPlaylistId") or release.get("playlistId")
                if not vid or vid in sent_ids:
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
                    # Explicitly prefix playlists so the player can resolve them correctly if needed
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

        # Save to explore cache
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
        
        # --- RECENT TRACKS ---
        recent_tracks = []
        history_item = None
        
        # First attempt: Sync from YouTube Music account if authenticated
        try:
            if (os.path.exists(self.oauth_path) or os.path.exists(self.headers_path)) and getattr(self.ytm, 'get_history', None):
                self.log("Fetching account play history from YouTube Music...")
                account_history = self.ytm.get_history()
                
                # Take up to 10 unique tracks (sometimes get_history has duplicate plays)
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

        # No local history fallback — if not authenticated, recent_tracks stays empty
        
        self.send_response({"type": "library_section", "section": "recent_tracks", "items": recent_tracks})

        # --- PLAYLISTS & LIKED SONGS ---
        playlists = []
        liked_song_count = 0
        liked_song_art = ""
        try:
            # Note: We fetch 25 but could be more. YTM puts 'Liked Music' first if you have likes.
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
                    try: liked_song_count = int(count)
                    except: liked_song_count = 0
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

        # if liked songs wasn't found in playlists list (sometimes it isn't), try to fetch directly
        if liked_song_count == 0:
             try:
                 liked = self.ytm.get_liked_songs(limit=1)
                 if liked and "trackCount" in liked:
                     liked_song_count = int(liked["trackCount"])
                     if liked.get("thumbnails"):
                         liked_song_art = liked["thumbnails"][-1].get("url", "")
             except: pass

        self.send_response({
            "type": "library_section", 
            "section": "playlists", 
            "items": playlists,
            "likedCount": liked_song_count,
            "likedArt": liked_song_art
        })

        # --- COMMUNITY PLAYLISTS (From the community or fallback) ---
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

    # ── artist ──────────────────────────────────────────────────────────────
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

            # Thumbnail
            thumbs = data.get("thumbnails", [])
            thumb_url = self._extract_art_url(data) if thumbs else ""

            # Top songs
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

            # Albums
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

            # Singles
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

            # Related artists
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
            })
            self.log(f"Artist loaded: {name} — {len(top_songs)} songs, {len(albums)} albums, {len(singles)} singles")

        except Exception as e:
            self.log(f"Failed to fetch artist {channel_id}: {e}")
            self.send_response({"type": "error", "message": f"Couldn't load artist."})

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
                # This works if the result is a simple grid
                results = self.ytm.get_artist_albums(channel_id, params)
            except Exception as yt_err:
                self.log(f"ytmusicapi get_artist_albums failed ({yt_err}), falling back to manual browse")
                raw = self.ytm._send_request('browse', {'browseId': channel_id, 'params': params})
                tabs = raw.get('contents', {}).get('singleColumnBrowseResultsRenderer', {}).get('tabs', [])
                if tabs:
                    content = tabs[0].get('tabRenderer', {}).get('content', {})
                    sections = content.get('sectionListRenderer', {}).get('contents', [])
                    for sec in sections:
                        nodes = None
                        if 'gridRenderer' in sec:
                            nodes = sec['gridRenderer'].get('items', [])
                        elif 'musicCarouselShelfRenderer' in sec:
                            nodes = sec['musicCarouselShelfRenderer'].get('contents', [])
                        
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
                # Special case for liked songs
                p = self.ytm.get_liked_songs(limit=None)
                if not p:
                    raise ValueError("Could not load liked songs.")
                
                title = "Liked Songs"
                track_count = p.get("trackCount", 0)
                items = p.get("tracks", [])
                
                # Fetch a valid art from the first song if available
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
            self.send_response({"type": "error", "message": f"Couldn't load playlist."})

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

            # Check search cache first
            cache_key = query.strip().lower()
            cached = self._search_cache.get(cache_key)
            if cached and (time.time() - cached["ts"]) < self._search_cache_ttl:
                self.log(f"Serving search results from cache for '{query}'")
                self.send_response(cached["response"])
                return

            artists, songs, albums = [], [], []
            song_ids = set()

            # Keep artist/album cards from mixed search.
            general_limit = max(30, song_limit + 10)
            general_results = self.ytm.search(query, limit=general_limit)
            artists, albums = self._collect_search_cards(general_results)

            # Fill songs from dedicated endpoints first so we actually get ~song_limit tracks.
            try:
                self._append_search_songs(
                    songs, song_ids, self.ytm.search(query, filter="songs", limit=song_limit), song_limit
                )
            except Exception as e:
                self.log(f"Song search fallback (songs) failed: {e}")

            if len(songs) < song_limit:
                try:
                    self._append_search_songs(
                        songs,
                        song_ids,
                        self.ytm.search(query, filter="videos", limit=song_limit),
                        song_limit,
                    )
                except Exception as e:
                    self.log(f"Song search fallback (videos) failed: {e}")

            if len(songs) < song_limit:
                self._append_search_songs(
                    songs,
                    song_ids,
                    general_results,
                    song_limit,
                    allowed_types={"song", "video"},
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

            # Save to search cache
            self._search_cache[cache_key] = {"ts": time.time(), "response": response}
            self.log(f"Search results cached for '{query}'")

            # Evict old entries to prevent unbounded memory growth
            now = time.time()
            stale_keys = [k for k, v in self._search_cache.items() if (now - v["ts"]) > self._search_cache_ttl]
            for k in stale_keys:
                del self._search_cache[k]

        except Exception as e:
            self.log(f"Search error: {e}")

    # ── Auth ──────────────────────────────────────────────────────────────────

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

    # ── OAuth ────────────────────────────────────────────────────────────────

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
                        # SUCCESS!
                        token = RefreshingToken(credentials=creds, **raw_token)
                        token.update(token.as_dict())
                        
                        import json
                        with open(self.oauth_path, "w") as f:
                            json.dump(token.as_dict(), f)
                            
                        self.log("OAuth flow successful, re-initializing ytmusic client")
                        from ytmusicapi import YTMusic
                        self._set_default_timeout(YTMusic)
                        self.ytm = YTMusic(self.oauth_path, oauth_credentials=self._make_oauth_credentials())
                        self._home_cache_ts = 0.0 # reset home cache
                        self.send_response({"type": "oauth_success"})
                        return
                except Exception:
                    pass
        except Exception as e:
            self.log(f"OAuth flow error: {e}")

    # ── I/O ───────────────────────────────────────────────────────────────────
    def send_response(self, data):
        print(json.dumps(data))
        sys.stdout.flush()

    # Track current metadata for pause/resume MPRIS updates
    _current_title = ""
    _current_artist = ""
    _current_art = ""
    _current_art_url = ""

    def run(self):
        # Bind process lifecycle to parent (Quickshell) using PR_SET_PDEATHSIG.
        # This guarantees the music backend and mpv die cleanly even if Quickshell crashes or forcefully restarts.
        try:
            import ctypes
            libc = ctypes.CDLL("libc.so.6")
            libc.prctl(1, signal.SIGTERM)  # 1 is PR_SET_PDEATHSIG
        except Exception as e:
            self.log(f"Failed to set PR_SET_PDEATHSIG: {e}")

        self.log("Music backend started.")
        is_authed = os.path.exists(self.oauth_path) or os.path.exists(self.headers_path)
        self.send_response({"type": "ready", "authenticated": is_authed})

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
                        self.search(c.get("query", ""), c.get("songLimit", 20))
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
                    elif t == "get_explore":
                        self.get_explore()
                    elif t == "get_library":
                        self.get_library()
                    elif t == "get_playlist":
                        self.get_playlist(c.get("browseId", ""))
                    elif t == "debug_log":
                        self.log(f"[QML_DEBUG] {c.get('message', '')}")
                    elif t == "get_artist":
                        self.get_artist(c.get("channelId", ""))
                    elif t == "get_artist_full_items":
                        self.get_artist_items(c.get("channelId", ""), c.get("params", ""), c.get("itemType", "albums"))
                    elif t == "get_artist_full_songs":
                        self.get_artist_full_songs(c.get("channelId", ""), c.get("songsBrowseId", ""))
                    elif t == "play":
                        if c.get("videoId"):
                            self._current_title = c.get("title", "")
                            self._current_artist = c.get("artist", "")
                            self._current_art = (
                                ""  # updated after download in _play_task
                            )
                            if "queue" in c:
                                with self._state_lock:
                                    self._current_queue = c["queue"]
                                self._is_auto_advancing = True
                                self.send_response({"type": "queue_updated", "queue": self._current_queue})
                            
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
                    elif t == "seek":
                        try:
                            pos = float(c.get("position", 0))
                            self.seek(pos)
                        except Exception:
                            pass
                    elif t == "reorder_queue":
                        with self._state_lock:
                            try:
                                src = int(c.get("from", -1))
                                dst = int(c.get("to", -1))
                                if 0 <= src < len(self._current_queue) and 0 <= dst < len(self._current_queue):
                                    item = self._current_queue.pop(src)
                                    self._current_queue.insert(dst, item)
                                    # No need to broadcast since the UI already updated visually
                            except Exception:
                                pass
                    elif t == "sync_queue":
                        with self._state_lock:
                            try:
                                q = c.get("queue")
                                if isinstance(q, list):
                                    self._current_queue = q
                            except Exception:
                                pass
                    elif t == "set_repeat":
                        try:
                            self.repeat_mode = int(c.get("mode", 0))
                            self.log(f"Repeat mode set to: {self.repeat_mode}")
                        except Exception:
                            pass
                    elif t == "toggle_like":
                        target_id = c.get("videoId") or self.current_video_id
                        threading.Thread(target=self._toggle_like_task, args=(target_id, c.get("liked")), daemon=True).start()
                    elif t == "oauth_start":
                        self.start_oauth()
                    elif t == "oauth_cancel":
                        self.cancel_oauth()
                    elif t == "refresh_auth":
                        self.refresh_auth()
                    elif t == "copy_clipboard":
                        txt = c.get("text", "")
                        try:
                            subprocess.run(["wl-copy"], input=txt.encode(), check=True)
                        except Exception as e:
                            self.log(f"Clipboard copy failed: {e}")
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
