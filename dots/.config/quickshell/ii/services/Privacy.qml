pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * Microphone, Camera, and Screensharing Privacy Service.
 */
Singleton {
    id: root

    function load(): void {
        console.log("[Privacy] Service loaded. micActive:", root.micActive, "camActive:", root.camActive);
    }

    property int _updateTrigger: 0

    Connections {
        target: Pipewire.linkGroups ?? null
        function onValuesChanged() { root._updateTrigger++; }
    }
    Connections {
        target: Pipewire.nodes ?? null
        function onValuesChanged() { root._updateTrigger++; }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root._updateTrigger++
    }

    readonly property var activeMicLinks: {
        root._updateTrigger;
        if (!Pipewire.linkGroups || !Pipewire.linkGroups.values) return [];
        var res = Pipewire.linkGroups.values.filter(pwlg => {
            if (!pwlg || !pwlg.source || !pwlg.target) return false;
            // Source is physical microphone device (not a sink, not an app stream)
            const isInputDevice = !pwlg.source.isSink && !pwlg.source.isStream;
            // Target is an app stream receiving audio
            const isStreamTarget = pwlg.target.isStream;
            // Filter out cava visualizer loopbacks
            const tgtName = (pwlg.target.properties && pwlg.target.properties["application.name"]) || pwlg.target.name || "";
            if (tgtName.toLowerCase().indexOf("cava") !== -1) return false;

            return isInputDevice && isStreamTarget;
        });
        return res;
    }

    readonly property bool micActive: activeMicLinks.length > 0

    readonly property string micAppName: {
        if (!micActive || activeMicLinks.length === 0) return "";
        const target = activeMicLinks[0].target;
        if (!target) return "";
        return (target.properties && target.properties["application.name"])
            ? target.properties["application.name"]
            : (target.description || target.name || "Microphone");
    }

    property string v4l2CamApp: ""
    readonly property bool v4l2CamActive: v4l2CamApp.length > 0

    Process {
        id: camCheckProc
        command: ["bash", "-c", "for p in $(fuser /dev/video* 2>/dev/null); do comm=$(cat /proc/$p/comm 2>/dev/null); if [ -n \"$comm\" ] && [ \"$comm\" != \"iriunwebcam\" ]; then echo \"$comm\"; break; fi; done"]
        stdout: StdioCollector {
            id: camCollector
            onStreamFinished: {
                root.v4l2CamApp = camCollector.text.trim();
            }
        }
    }

    Timer {
        id: camCheckTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (!camCheckProc.running) {
                camCheckProc.running = true;
            }
        }
    }

    Component.onCompleted: {
        camCheckProc.running = true;
    }

    readonly property var activeCamLinks: {
        root._updateTrigger;
        if (!Pipewire.linkGroups || !Pipewire.linkGroups.values) return [];
        return Pipewire.linkGroups.values.filter(pwlg => {
            if (!pwlg || !pwlg.source || !pwlg.target) return false;
            const srcName = pwlg.source.name || "";
            const isV4l2 = srcName.startsWith("v4l2_input") || (pwlg.source.properties && pwlg.source.properties["device.api"] === "v4l2");
            return isV4l2 && pwlg.target.isStream;
        });
    }

    readonly property bool camActive: activeCamLinks.length > 0 || v4l2CamActive

    readonly property string camAppName: {
        if (activeCamLinks.length > 0 && activeCamLinks[0].target) {
            const target = activeCamLinks[0].target;
            return (target.properties && target.properties["application.name"])
                ? target.properties["application.name"]
                : (target.description || target.name || "Camera");
        }
        if (v4l2CamActive) {
            let app = root.v4l2CamApp;
            if (app === "zen-bin") return "Zen Browser";
            if (app === "chrome" || app === "chromium") return "Chromium";
            if (app === "firefox") return "Firefox";
            if (app === "obs") return "OBS Studio";
            if (app === "discord") return "Discord";
            if (app === "mpv") return "MPV";
            if (app === "ffmpeg") return "FFmpeg";
            return app;
        }
        return "";
    }

    readonly property var activeScreenShareLinks: {
        root._updateTrigger;
        if (!Pipewire.linkGroups || !Pipewire.linkGroups.values) return [];
        return Pipewire.linkGroups.values.filter(pwlg => {
            if (!pwlg || !pwlg.source || !pwlg.target) return false;
            const srcName = pwlg.source.name || "";
            const isPortal = srcName.startsWith("xdg-desktop-portal") || (pwlg.source.properties && pwlg.source.properties["media.class"] === "Stream/Output/Video");
            return isPortal && pwlg.target.isStream;
        });
    }

    readonly property bool screenSharing: activeScreenShareLinks.length > 0

    readonly property bool privacyActive: micActive || camActive || screenSharing

    readonly property bool micMuted: {
        if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) {
            return Pipewire.defaultAudioSource.audio.muted;
        }
        return false;
    }

    function toggleMicMute() {
        if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) {
            Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted;
        }
    }

    property list<real> micLevels: [0.0, 0.0, 0.0]

    Process {
        id: micCavaProc
        running: root.micActive && !root.micMuted
        command: ["cava", "-p", `${Directories.scripts}/cava/mic_visualizer_config.txt`]

        onRunningChanged: {
            if (!micCavaProc.running) {
                root.micLevels = [0.0, 0.0, 0.0];
            }
        }

        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) console.log("[Privacy] micCavaProc stderr:", text.trim())
        }

        stdout: SplitParser {
            onRead: data => {
                let parsed = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                if (parsed.length >= 3) {
                    root.micLevels = parsed.slice(0, 3);
                }
            }
        }
    }
}
