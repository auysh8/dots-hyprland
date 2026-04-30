import os
import re
import threading
import time

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
        self._cached_volume = 1.0
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
        return self._cached_volume

    @Volume.setter
    def Volume(self, v):
        try:
            self._cached_volume = max(0.0, min(1.0, float(v)))
            # mpv volume is 0-100
            if getattr(self._backend, "player", None):
                self._backend.player._ipc_send({"command": ["set_property", "volume", self._cached_volume * 100.0]})
        except Exception:
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
        if not getattr(self, "_backend", None) or not getattr(self._backend, "player", None):
            return False
        return len(self._backend.player._current_queue) > 0 or self._backend.player.repeat_mode != 0

    @property
    def CanGoPrevious(self):
        if not getattr(self, "_backend", None) or not getattr(self._backend, "player", None):
            return False
        return len(self._backend.player._play_stack) > 1

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
    def update(self, status, title="", artist="", album="", art_local_path="", video_id="", art_url=""):
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
        if album:
            meta["xesam:album"] = _GLib.Variant("s", album)

        if art_local_path and os.path.exists(art_local_path):
            meta["mpris:artUrl"] = _GLib.Variant("s", f"file://{art_local_path}")
        elif art_url:
            meta["mpris:artUrl"] = _GLib.Variant("s", art_url)

        self._meta = meta

        # Emit PropertiesChanged so widgets update immediately
        self._emit_properties_changed({
            "PlaybackStatus": _GLib.Variant("s", self._status),
            "Metadata": _GLib.Variant("a{sv}", self._meta),
            "CanGoNext": _GLib.Variant("b", self.CanGoNext),
            "CanGoPrevious": _GLib.Variant("b", self.CanGoPrevious),
        })

    def set_status(self, status):
        """Update just the playback status and notify clients."""
        if self._status == status:
            return
        self._status = status
        if status == "Stopped":
            self._cached_position = 0
            self._cached_duration = 0
            
        from gi.repository import GLib as _GLib
        self._emit_properties_changed({
            "PlaybackStatus": _GLib.Variant("s", self._status),
            "CanGoNext": _GLib.Variant("b", self.CanGoNext),
            "CanGoPrevious": _GLib.Variant("b", self.CanGoPrevious),
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

    def emit_seeked(self, position_microsec):
        """Emit the Seeked signal to notify clients of a discontinuous position change."""
        self._cached_position = position_microsec
        from gi.repository import GLib as _GLib
        con = self._bus_con
        if con is None:
            return
        try:
            con.emit_signal(
                None,  # broadcast
                "/org/mpris/MediaPlayer2",
                "org.mpris.MediaPlayer2.Player",
                "Seeked",
                _GLib.Variant("(x)", (position_microsec,)),
            )
        except Exception as e:
            self._backend.log(f"[MPRIS] Seeked emission error: {e}")

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
