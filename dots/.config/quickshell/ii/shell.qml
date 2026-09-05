//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"
import "kdeConnect"
import "modules/ii/overview"
import "notesLayer"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every panel family
    ReloadPopup {}
    AppDrawerWindow {}
    OtherPopup {}
    NotesWindow {}
    KDEDrawer {}

    // Shake-to-locate cursor helper: runs only while enabled, and resets the
    // cursor zoom if it's killed mid-magnify.
    Process {
        id: cursorShakeProc
        property bool wanted: Config.ready && Config.options.cursor && Config.options.cursor.shakeMode !== "off"
        command: [
            Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/cursor/shake-zoom",
            Config.options.cursor ? Config.options.cursor.shakeMode : "off",
            String(Config.options.cursor ? Config.options.cursor.shakeZoomFactor : 2.0),
            String(Config.options.cursor ? Config.options.cursor.shakeGrowFactor : 2.5)
        ]

        running: wanted
    }

    Component.onCompleted: {
        Location.load()
        BluetoothStatus.reconnectTrustedAudioDevicesAtStartup()
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        DownloadService.load()
        CavaService.load()
    }


    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}

