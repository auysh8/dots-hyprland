import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Wayland._IdleNotify
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Io
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick.Controls

import "components"
import "pages"

Scope {
    id: dynamicIslandScope

    Variants {
        // For each monitor - only show when vertical bar is enabled
        model: {
            if (!Config.options.bar.vertical) return [];
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        PanelWindow {
            id: islandRoot
            required property ShellScreen modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: islandContainer.height + Appearance.sizes.hyprlandGapsOut * 2
            
            color: "transparent"
            
            WlrLayershell.namespace: "quickshell:dynamicIsland"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusiveZone: -1 // Don't reserve space, float over windows

            // Input mask uses a dynamic target to hug the content tightly
            mask: Region {
                item: maskTarget
            }

            // Main Container (Includes Trigger + Island)
            Item {
                id: islandContainer
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                
                // Height is just island height (since no gap now)
                // Fixed max surface size to prevent Wayland resize jitter
                implicitHeight: 200
                implicitWidth: 500
                
                // Dynamic Input Mask Target
                Item {
                    id: maskTarget
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    // When hidden, only mask the trigger area (10px height). When visible, cover the pill.
                    width: islandContainer.islandVisible ? Math.max(triggerArea.width, islandPill.width) : triggerArea.width
                    height: islandContainer.islandVisible ? Math.max(triggerArea.height, islandPill.height) : triggerArea.height
                }

                // Trigger area at the top (Thin strip)
                MouseArea {
                    id: triggerArea
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 300
                    height: 10
                    hoverEnabled: true // Always valid for hover
                    onExited: expandTimer.start()
                }

                // Logic Properties
                // Logic Controller
                IslandLogic { 
                    id: logic 
                    onBatteryEvent: (plugged) => {
                        islandContainer.batterySource = "system"; // Reset to system
                        islandContainer.isCharging = plugged;
                        islandContainer.modeOverride = 4;
                        modeTimer.restart();
                    }
                    onRequestCustomBattery: (percent, name) => {
                        islandContainer.batterySource = "custom";
                        islandContainer.customBatteryPercent = percent;
                        islandContainer.customBatteryName = name;
                        islandContainer.customBatteryCharging = false;
                        islandContainer.modeOverride = 4;
                        modeTimer.restart();
                    }
                }
                
                // Properties Shortcuts
                property var activePlayer: MprisController.activePlayer
                property bool hasMedia: activePlayer !== null
                
                property alias popupType: logic.popupType
                property alias popupTitle: logic.popupTitle
                property alias popupMessage: logic.popupMessage
                property alias hasPopup: logic.hasPopup
                property alias popupCategory: logic.popupCategory
                property alias popupAction: logic.popupAction
                
                property alias bluetoothDevices: logic.bluetoothDevices
                property alias hasBluetoothDevices: logic.hasBluetoothDevices
                
                // Hover state for M3 State Layer
                property bool isHovered: false

                // Battery State Shadow (Combines System and Log Events)
                property string batterySource: "system" // "system" or "custom"
                property real customBatteryPercent: 0
                property bool customBatteryCharging: false
                property string customBatteryName: "Battery"
                
                property bool isCharging: batterySource === "system" ? Battery.isPluggedIn : customBatteryCharging
                property real batteryPercent: batterySource === "system" ? Battery.percentage : customBatteryPercent

                // Modes: 0=Idle/Media, 1=Volume, 2=Brightness, 3=CustomPopup, 4=Battery
                property int modeOverride: 0
                property int mode: modeOverride > 0 ? modeOverride : (hasPopup ? 3 : 0)
                property string expandedPageKey: "media"
                
                property real lastVolume: Audio.value
                property real lastBrightness: Brightness.monitors.length > 0 ? Brightness.monitors[0].brightness : 0

                // Prevent startup triggers and hide island for 1s
                property bool initialized: false
                
                opacity: initialized ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 500 } }
                
                Timer {
                    id: startupTimer
                    interval: 1000 // 1 second delay
                    running: true
                    onTriggered: islandContainer.initialized = true
                }

                // UI Triggers (Volume/Brightness)
                Connections {
                    target: Audio.sink ? Audio.sink.audio : null
                    function onVolumeChanged() {
                        if (!islandContainer.initialized) return;
                        
                        var v = Audio.value;
                        if (isNaN(v) || v === undefined) return;
                        
                        // Suppress volume popup if Bluetooth popup is showing (ghost trigger on connect/disconnect)
                        if (islandContainer.hasPopup) {
                            var t = islandContainer.popupTitle.toLowerCase();
                            var m = islandContainer.popupMessage.toLowerCase();
                            if (t.includes("bluetooth") && (m.includes("connect") || m.includes("disconnect"))) return;
                        }
                        
                        // Snapshot current audio value before expanding
                        islandContainer.lastVolume = Audio.value;
                        islandContainer.modeOverride = 1
                        modeTimer.restart()
                    }
                    function onMutedChanged() {
                        if (!islandContainer.initialized) return;
                        
                        islandContainer.lastVolume = Audio.value;
                        islandContainer.modeOverride = 1
                        modeTimer.restart()
                    }
                }
                
                Connections {
                    target: Brightness
                    function onBrightnessChanged() {
                        // Snapshot current brightness before expanding
                        islandContainer.lastBrightness = (Brightness.monitors.length > 0) ? Brightness.monitors[0].brightness : islandContainer.lastBrightness;
                        islandContainer.modeOverride = 2
                        modeTimer.restart()
                    }
                }
                
                Connections {
                    target: Battery
                    function onIsPluggedInChanged() {
                        islandContainer.isCharging = Battery.isPluggedIn;
                        logic.popupCategory = "battery"
                        logic.popupAction = Battery.isPluggedIn ? "charging" : "unplugged"
                        islandContainer.modeOverride = 4
                        modeTimer.restart()
                    }
                    function onPercentageChanged() {
                        // Trigger if plugged in and reaches 100% (or very close to it)
                        // Use a flag or check checks to avoid spam, but since modeTimer resets status, a re-trigger is acceptable if it fluctuates logic wise.
                        if (Battery.isPluggedIn && Battery.percentage >= 0.99) {
                            islandContainer.batterySource = "system";
                            islandContainer.isCharging = Battery.isPluggedIn;
                            logic.popupCategory = "battery"
                            logic.popupAction = "charging"
                            islandContainer.modeOverride = 4;
                            modeTimer.restart();
                        }
                    }
                }


                    // Reactive open-window tracking (polling fallback)
                    property bool hasOpenWindow: false
                    property bool hasFullscreen: false

                    function updateHasOpenWindow() {
                        // find the monitor for this panel
                        var monitor = HyprlandData.monitors.find(m => m.name === islandRoot.screen.name);
                        if (!monitor || !monitor.activeWorkspace) {
                            hasOpenWindow = false;
                            hasFullscreen = false;
                            return;
                        }
                        var wid = monitor.activeWorkspace.id ?? -1;
                        if (wid < 0) {
                            hasOpenWindow = false;
                            hasFullscreen = false;
                            return;
                        }
                        var clients = HyprlandData.hyprlandClientsForWorkspace(wid);
                        hasOpenWindow = clients && clients.length > 0;
                        
                        // Check for fullscreen clients
                        let fs = false;
                        if (clients) {
                            for (let i = 0; i < clients.length; i++) {
                                if (clients[i].fullscreen) {
                                    fs = true;
                                    break;
                                }
                            }
                        }
                        hasFullscreen = fs;
                    }

                    // Poll at a lower rate to reduce background CPU usage.
                    Timer {
                        id: hyprPoll
                        interval: 2000
                        repeat: true
                        running: true
                        onTriggered: islandContainer.updateHasOpenWindow()
                    }
                    
                    IdleMonitor {
                        id: idleMon
                        timeout: 8.0 // Stay hidden longer before showing on idle
                        enabled: true
                    }
                    property bool islandVisible: !GlobalStates.overviewOpen && (
                        triggerArea.containsMouse
                        || expanded
                        || mode !== 0
                        || (!hasOpenWindow)                 // desktop -> show
                        || (hasOpenWindow && idleMon.isIdle && !hasFullscreen) // idle -> show (unless fullscreen)
                    )

                    Timer {
                        id: modeTimer
                        interval: islandContainer.batterySource === "custom" ? 5000 : 2000
                        onTriggered: {
                            islandContainer.modeOverride = 0
                            // Reset source after timeout
                            if (islandContainer.batterySource === "custom") {
                                islandContainer.batterySource = "system"
                            }
                        }
                    }

                    Timer {
                        id: expandTimer
                        interval: 2000
                        repeat: false
                    }

                    property bool expanded: (islandHoverTracker.hovered || expandTimer.running) && mode === 0 && !hasPopup

                    // The Island Pill
                    Item {
                        id: islandPill
                        anchors.top: parent.top
                        anchors.topMargin: 0 // Attached to top edge (Notch style)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: 0 // For Shake Animation
                        property int renderMode: islandContainer.mode
                        readonly property bool renderActive: islandContainer.islandVisible
                            || pillScaleAnim.running
                            || pillWidthAnim.running
                            || pillHeightAnim.running
                            || scale > 0.01
                        visible: renderActive
                        enabled: renderActive

                        Connections {
                            target: islandContainer
                            function onModeChanged() {
                                // Keep the currently shown mode while closing, then sync when visible again.
                                if (islandContainer.islandVisible || !islandPill.renderActive) {
                                    islandPill.renderMode = islandContainer.mode
                                }
                            }
                            function onIslandVisibleChanged() {
                                if (islandContainer.islandVisible) {
                                    islandPill.renderMode = islandContainer.mode
                                }
                            }
                        }

                        SequentialAnimation {
                            id: shakeAnimation
                            property int amplitude: 6
                            property int speed: 35
                            
                            NumberAnimation { target: islandPill; property: "anchors.horizontalCenterOffset"; from: 0; to: -shakeAnimation.amplitude; duration: shakeAnimation.speed; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: islandPill; property: "anchors.horizontalCenterOffset"; from: -shakeAnimation.amplitude; to: shakeAnimation.amplitude; duration: shakeAnimation.speed; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: islandPill; property: "anchors.horizontalCenterOffset"; from: shakeAnimation.amplitude; to: -shakeAnimation.amplitude; duration: shakeAnimation.speed; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: islandPill; property: "anchors.horizontalCenterOffset"; from: -shakeAnimation.amplitude; to: shakeAnimation.amplitude; duration: shakeAnimation.speed; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: islandPill; property: "anchors.horizontalCenterOffset"; from: shakeAnimation.amplitude; to: 0; duration: shakeAnimation.speed; easing.type: Easing.InOutQuad }
                        }
                        
                        // Delay timer to wait for island expansion before shaking
                        Timer {
                            id: shakeDelayTimer
                            interval: 280 // Wait for expansion animation to complete
                            onTriggered: shakeAnimation.restart()
                        }
                        
                        // Track if we need to shake when mode 3 becomes visible
                        property bool pendingBadShake: false

                        Connections {
                            target: islandContainer
                            function onPopupTypeChanged() {
                                if (islandContainer.popupType === "bad" && islandContainer.hasPopup) {
                                    if (islandContainer.mode === 3) {
                                        // Already in mode 3, shake after delay
                                        shakeDelayTimer.restart()
                                    } else {
                                        // Mark for shake when mode becomes 3
                                        islandPill.pendingBadShake = true
                                    }
                                }
                            }
                            function onHasPopupChanged() {
                                if (islandContainer.hasPopup && islandContainer.popupType === "bad") {
                                    if (islandContainer.mode === 3) {
                                        shakeDelayTimer.restart()
                                    } else {
                                        islandPill.pendingBadShake = true
                                    }
                                }
                            }
                            function onModeChanged() {
                                // When mode changes TO 3 and we have a pending bad shake
                                if (islandContainer.mode === 3 && islandPill.pendingBadShake) {
                                    islandPill.pendingBadShake = false
                                    shakeDelayTimer.restart()
                                }
                            }
                        }
                        

                        // Scale Logic
                        // Controlled centrally by islandContainer.islandVisible
                        
                        scale: islandContainer.islandVisible ? 1 : 0
                        transformOrigin: Item.Top

                        Behavior on scale {
                            NumberAnimation {
                                id: pillScaleAnim
                                duration: 400
                                easing.type: Easing.OutBack
                                easing.overshoot: 0.8
                            }
                        }


                    // Size Logic
                    property real collapsedWidth: 320 // Increased from 240
                    property real collapsedHeight: 36
                    

                    property bool pomodoroActive: TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)
                    property bool stopwatchActive: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0
                    property bool downloadActive: DownloadService.active
                    property bool timerActive: pomodoroActive || stopwatchActive

                    // Mode specific sizes
                     property real expandedWidth: {
                        if (islandPill.renderMode === 1 || islandPill.renderMode === 2) return 220; // Volume/Brightness
                        if (islandPill.renderMode === 3) return 320; // Notification (Match collapsed width roughly)
                        if (islandPill.renderMode === 4) return 260; // Battery
                        return 420;
                    }
                    property real expandedHeight: {
                        if (islandPill.renderMode === 1 || islandPill.renderMode === 2) return 48; // M3 Pill height
                        if (islandPill.renderMode === 3) return 64; // Popup (DoubleLine)
                        if (islandPill.renderMode === 4) return 52; // Battery
                        
                        // Check for multiple pages to add space for pagination dots
                        var pageCount = 0;
                        if (islandContainer.hasMedia) pageCount++;
                        if (pomodoroActive) pageCount++;
                        if (stopwatchActive) pageCount++;
                        if (downloadActive) pageCount++;

                        if (pageCount > 0) {
                             return pageCount > 1 ? 212 : 192;
                        }
                        return 60;
                    }
                    
                    width: (islandContainer.expanded || islandPill.renderMode !== 0) ? expandedWidth : collapsedWidth
                    height: (islandContainer.expanded || islandPill.renderMode !== 0) ? expandedHeight : collapsedHeight
                    
                    Behavior on width {
                        SpringAnimation {
                            id: pillWidthAnim
                            spring: 2.5
                            damping: 0.4
                            epsilon: 0.5
                            mass: 1.0
                        }
                    }
                    Behavior on height {
                        SpringAnimation {
                            id: pillHeightAnim
                            spring: 2.5
                            damping: 0.4
                            epsilon: 0.5
                            mass: 1
                        }
                    }

                    // Shadow
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 6
                        radius: 24
                        samples: 49
                        color: Appearance.colors.colShadow
                    }

                    // Island background (Single Shape - Flat Top, Rounded Bottom)
                    Item {
                        id: islandBackground
                        anchors.fill: parent
                        
                        property color bgColor: Appearance.colors.colLayer0
                        property real bottomRadius: 16
                        Behavior on bgColor { ColorAnimation { duration: 200 } }
                        
                        Shape {
                            anchors.fill: parent
                            
                            ShapePath {
                                strokeWidth: 1
                                strokeColor: Appearance.colors.colLayer0Border
                                fillColor: islandBackground.bgColor
                                
                                // Start at top-left corner
                                startX: 0
                                startY: 0
                                
                                // Top edge (straight)
                                PathLine { x: islandBackground.width; y: 0 }
                                
                                // Right edge down to curve start
                                PathLine { x: islandBackground.width; y: islandBackground.height - islandBackground.bottomRadius }
                                
                                // Bottom-right rounded corner
                                PathArc { 
                                    x: islandBackground.width - islandBackground.bottomRadius
                                    y: islandBackground.height
                                    radiusX: islandBackground.bottomRadius; radiusY: islandBackground.bottomRadius
                                    direction: PathArc.Clockwise
                                }
                                
                                // Bottom edge (straight)
                                PathLine { x: islandBackground.bottomRadius; y: islandBackground.height }
                                
                                // Bottom-left rounded corner
                                PathArc { 
                                    x: 0
                                    y: islandBackground.height - islandBackground.bottomRadius
                                    radiusX: islandBackground.bottomRadius; radiusY: islandBackground.bottomRadius
                                    direction: PathArc.Clockwise
                                }
                                
                                // Left edge back to start
                                PathLine { x: 0; y: 0 }
                            }
                        }

                    }

                    // Collapsed content
                    Item {
                        id: collapsedContent
                        anchors.fill: parent
                        // anchors.margins: 12

                        opacity: ((islandContainer.mode === 0 && !islandContainer.expanded) || islandContainer.mode === 3) ? 1 : 0
                        visible: opacity > 0
                        


                        // Standard Mode Content
                        Loader {
                            active: islandPill.renderActive && islandPill.renderMode === 0 && !islandContainer.expanded
                            anchors.centerIn: parent
                            sourceComponent: RowLayout {
                                // width: parent.width - 24 // Removed to allow true centering
                                spacing: 12
                                anchors.centerIn: parent

                                // Time / Timer / Stopwatch
                                Text {
                                    // Time / Timer / Stopwatch
                                    text: {
                                        if (TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)) {
                                            let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                                            let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                                            return "🍅 " + m + ":" + s;
                                        }
                                        if (TimerService.stopwatchRunning) {
                                            let t = TimerService.stopwatchTime / 100;
                                            let m = Math.floor(t / 60).toString().padStart(2, '0');
                                            let s = Math.floor(t % 60).toString().padStart(2, '0');
                                            return "⏱️ " + m + ":" + s;
                                        }
                                        return islandContainer.currentTime;
                                    }
                                    color: {
                                        if (TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)) return Appearance.colors.colError;
                                        if (TimerService.stopwatchRunning) return Appearance.colors.colPrimary;
                                        return Appearance.colors.colOnLayer0;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium

                                }

                                // Separator
                                Rectangle {
                                    width: 1
                                    height: 16
                                    color: Appearance.colors.colOutlineVariant
                                    visible: islandContainer.hasMedia || islandPill.downloadActive
                                }

                                // Download Indicator (Collapsed)
                                // Priority: Show only if Media is NOT showing
                                RowLayout {
                                    visible: islandPill.downloadActive && !islandContainer.hasMedia
                                    spacing: 6

                                    MaterialSymbol {
                                        text: "download"
                                        iconSize: 16
                                        color: Appearance.colors.colPrimary
                                    }

                                    Text {
                                        text: Math.round(DownloadService.progress * 100) + "%"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }

                                // No second separator needed as we are mutually exclusive now

                                // Media indicator (collapsed)
                                RowLayout {
                                    visible: islandContainer.hasMedia
                                    spacing: 6

                                    AudioVisualizer {
                                        playing: MprisController.isPlaying
                                        barColor: Appearance.colors.colPrimary
                                        barCount: 4
                                        maxBarHeight: 14
                                    }

                                    Text {
                                        text: {
                                            const title = MprisController.activeTrack.title;
                                            return title.length > 15 ? title.substring(0, 15) + "..." : title;
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                        }

                        // Popup Mode Content (Styled like Battery Mode)
                        Loader {
                            active: islandPill.renderActive && islandPill.renderMode === 3
                            anchors.fill: parent
                            anchors.margins: 8
                            sourceComponent: RowLayout {
                                spacing: 8

                                // Tonal Container for Icon (M3 Style)
                                Rectangle {
                                    id: popupIconContainer
                                    width: 34
                                    height: 34
                                    radius: 10
                                    color: Qt.rgba(popupIcon.color.r, popupIcon.color.g, popupIcon.color.b, 0.15)

                                    MaterialSymbol {
                                        id: popupIcon
                                        anchors.centerIn: parent
                                        text: {
                                            switch (islandContainer.popupCategory) {
                                                case "screenshot": return "screenshot";
                                                case "download": return islandContainer.popupAction === "complete" ? "download_done" : "download";
                                                case "clipboard": return "content_paste";
                                                case "media": return "music_note";
                                                case "microphone": return islandContainer.popupAction === "muted" ? "mic_off" : "mic";
                                                case "volume": return islandContainer.popupAction === "muted" ? "volume_off" : "volume_up";
                                                case "wifi": return islandContainer.popupAction === "disconnected" ? "wifi_off" : "wifi";
                                                case "bluetooth":
                                                    if (islandContainer.popupAction === "connected") return "bluetooth_connected";
                                                    if (islandContainer.popupAction === "disconnected") return "bluetooth_disabled";
                                                    return "bluetooth";
                                                case "battery":
                                                    if (islandContainer.popupAction === "charging") return "battery_charging_full";
                                                    if (islandContainer.popupAction === "low") return "battery_alert";
                                                    return "battery_std";
                                                case "pomodoro":
                                                    if (islandContainer.popupAction === "break") return "coffee";
                                                    if (islandContainer.popupAction === "complete") return "check_circle";
                                                    return "timer";
                                                case "brightness": return "brightness_6";
                                                case "notification": return "notifications";
                                                case "message": return "message";
                                                case "mail": return "mail";
                                                case "update": return "update";
                                                case "keyboard": return "keyboard";
                                                case "notification":
                                                    if (islandContainer.popupAction === "pinned") return "push_pin";
                                                    if (islandContainer.popupAction === "unpinned") return "block";
                                                    return "notifications";
                                                case "camera": return "videocam";
                                                case "file": return "description";
                                                default:
                                                    if (islandContainer.popupType === "bad") return "warning";
                                                    if (islandContainer.popupType === "good") return "check_circle";
                                                    return "info";
                                            }
                                        }
                                        color: {
                                            if (islandContainer.popupType === "bad")
                                                return Appearance.colors.colError;

                                            switch (islandContainer.popupCategory) {
                                                case "battery":
                                                    if (islandContainer.popupAction === "low") return Appearance.colors.colError;
                                                    if (islandContainer.popupAction === "charging") return Appearance.colors.colPrimary;
                                                    return Appearance.colors.colOnLayer0;

                                                case "wifi":
                                                case "bluetooth":
                                                case "microphone":
                                                    if (islandContainer.popupAction === "disconnected" ||
                                                        islandContainer.popupAction === "muted")
                                                        return Appearance.colors.colError;
                                                    return Appearance.colors.colPrimary;

                                                default:
                                                    return Appearance.colors.colPrimary;
                                            }
                                        }
                                        iconSize: 24
                                    }
                                }

                                // Double Line Layout for ALL Popups
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        text: islandContainer.popupTitle
                                        color: Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: islandContainer.popupMessage
                                        color: Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }

                    // Expanded content
                    Loader {
                        id: expandedContentLoader
                        active: islandPill.renderActive && islandContainer.expanded && islandPill.renderMode === 0
                        visible: islandContainer.expanded && islandContainer.mode === 0
                        anchors.fill: parent
                        anchors.margins: 12
                        sourceComponent: ColumnLayout {
                            id: expandedContent
                            spacing: 8

                            // Top row - Time and Date
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    text: islandContainer.currentTimeWithSeconds
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnLayer0
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: islandContainer.currentDate
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            // Page Components
                            Component { id: mediaPage; MediaPage { } }
                            Component { id: pomodoroPage; PomodoroPage { } }
                            Component { id: stopwatchPage; StopwatchPage { } }
                            Component { id: downloadPage; DownloadPage { } }

                            // Dynamic Page List
                            property var activePages: {
                                var pages = [];
                                if (islandContainer.hasMedia) pages.push({ key: "media", component: mediaPage });
                                if (islandPill.pomodoroActive) pages.push({ key: "pomodoro", component: pomodoroPage });
                                if (islandPill.stopwatchActive) pages.push({ key: "stopwatch", component: stopwatchPage });
                                if (islandPill.downloadActive) pages.push({ key: "download", component: downloadPage });
                                return pages;
                            }

                            function pageIndexForKey(key) {
                                for (var i = 0; i < activePages.length; ++i) {
                                    if (activePages[i].key === key) return i;
                                }
                                return -1;
                            }

                            function syncSwipeToSavedPage() {
                                if (activePages.length === 0) {
                                    islandContainer.expandedPageKey = "media";
                                    return;
                                }

                                var targetIndex = pageIndexForKey(islandContainer.expandedPageKey);
                                if (targetIndex < 0) targetIndex = 0;

                                if (contentSwipe.currentIndex !== targetIndex)
                                    contentSwipe.currentIndex = targetIndex;

                                var resolvedKey = activePages[targetIndex].key;
                                if (resolvedKey !== islandContainer.expandedPageKey)
                                    islandContainer.expandedPageKey = resolvedKey;
                            }

                            onActivePagesChanged: Qt.callLater(syncSwipeToSavedPage)

                            // 4. SwipeView for Content (Horizontal & Swipeable)

                            SwipeView {
                                id: contentSwipe
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                interactive: expandedContent.activePages.length > 1

                                Component.onCompleted: expandedContent.syncSwipeToSavedPage()
                                onCountChanged: expandedContent.syncSwipeToSavedPage()
                                onCurrentIndexChanged: {
                                    if (currentIndex < 0 || currentIndex >= expandedContent.activePages.length) return;
                                    var nextKey = expandedContent.activePages[currentIndex].key;
                                    if (nextKey !== islandContainer.expandedPageKey)
                                        islandContainer.expandedPageKey = nextKey;
                                }

                                Repeater {
                                    model: expandedContent.activePages
                                    Loader {
                                        id: pageLoader
                                        sourceComponent: modelData.component
                                        active: true
                                        visible: true

                                        opacity: 1
                                        scale: 1
                                    }
                                }
                            }

                            // Page Indicator
                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.bottomMargin: 4
                                spacing: 6
                                visible: expandedContent.activePages.length > 1

                                Repeater {
                                    model: contentSwipe.count
                                    Rectangle {
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: Appearance.colors.colOnLayer0
                                        opacity: contentSwipe.currentIndex === index ? 1 : 0.3

                                        Behavior on opacity { NumberAnimation { duration: 200 } }

                                        // Scale animation for fun
                                        scale: contentSwipe.currentIndex === index ? 1.2 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200 } }
                                    }
                                }
                            }
                        }
                    }

                    

                    
                    // Volume Content
                    // Volume Content (M3 Pill Slider)
                    Loader {
                        active: islandPill.renderActive && islandPill.renderMode === 1
                        anchors.fill: parent
                        anchors.margins: 10
                        sourceComponent: RowLayout {
                            spacing: 10

                            // Tonal Container for Icon
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 8
                                color: Qt.rgba(volumeIcon.color.r, volumeIcon.color.g, volumeIcon.color.b, 0.15)

                                MaterialSymbol {
                                    id: volumeIcon
                                    anchors.centerIn: parent
                                    text: {
                                        if (Audio.sink && Audio.sink.audio && Audio.sink.audio.muted) return "volume_off";
                                        if (Audio.value > 0.5) return "volume_up";
                                        if (Audio.value > 0) return "volume_down";
                                        return "volume_mute";
                                    }
                                    color: (Audio.sink && Audio.sink.audio && Audio.sink.audio.muted) ? Appearance.colors.colError : Appearance.colors.colPrimary
                                    iconSize: 18
                                }
                            }

                            // M3 Thick Pill Slider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 14
                                radius: 7
                                color: Qt.rgba(Appearance.colors.colOnLayer0.r, Appearance.colors.colOnLayer0.g, Appearance.colors.colOnLayer0.b, 0.12)
                                clip: true

                                // Filled portion
                                Rectangle {
                                    id: volumeFill
                                    // Use pill's *target* expandedWidth MINUS layout overhead (margins + icon + spacing + text)
                                    // Layout: 20(marg) + 28(icon) + 20(space) + 36(text) = 104px overhead
                                    width: (islandPill.expandedWidth - 104) * islandContainer.lastVolume
                                    height: parent.height
                                    radius: 7
                                    color: (Audio.sink && Audio.sink.audio && Audio.sink.audio.muted) ? Appearance.colors.colError : Appearance.colors.colPrimary
                                    Behavior on width {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                                    }

                                    // Integrated handle (subtle glow at end)
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 4
                                        height: parent.height
                                        radius: 2
                                        color: Qt.lighter(parent.color, 1.3)
                                        visible: Audio.value > 0.02
                                    }
                                }
                            }

                            Text {
                                text: {
                                    var v = Audio.value;
                                    return (isNaN(v) || v === undefined ? 0 : Math.round(v * 100)) + "%";
                                }
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // Brightness Content (M3 Pill Slider)
                    Loader {
                        active: islandPill.renderActive && islandPill.renderMode === 2
                        anchors.fill: parent
                        anchors.margins: 10
                        sourceComponent: RowLayout {
                            spacing: 10

                            // Tonal Container for Icon
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 8
                                color: Qt.rgba(brightnessIcon.color.r, brightnessIcon.color.g, brightnessIcon.color.b, 0.15)

                                MaterialSymbol {
                                    id: brightnessIcon
                                    anchors.centerIn: parent
                                    text: {
                                        var val = 0;
                                        if (Brightness.monitors.length > 0) val = Brightness.monitors[0].brightness;

                                        if (val > 0.6) return "brightness_high";
                                        if (val > 0.3) return "brightness_medium";
                                        return "brightness_low";
                                    }
                                    color: Appearance.colors.colPrimary
                                    iconSize: 18
                                }
                            }

                            // M3 Thick Pill Slider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 14
                                radius: 7
                                color: Qt.rgba(Appearance.colors.colOnLayer0.r, Appearance.colors.colOnLayer0.g, Appearance.colors.colOnLayer0.b, 0.12)
                                clip: true

                                // Filled portion
                                Rectangle {
                                    id: brightnessFill
                                    // Use pill's *target* expandedWidth MINUS layout overhead (104px)
                                    width: (islandPill.expandedWidth - 104) * islandContainer.lastBrightness
                                    height: parent.height
                                    radius: 7
                                    color: Appearance.colors.colPrimary

                                    Behavior on width {
                                        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                                    }

                                    // Integrated handle (subtle glow at end)
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 4
                                        height: parent.height
                                        radius: 2
                                        color: Qt.lighter(parent.color, 1.3)
                                        visible: brightnessFill.width > 4
                                    }
                                }
                            }

                            Text {
                                text: {
                                    if (Brightness.monitors.length > 0)
                                        return Math.round(Brightness.monitors[0].brightness * 100) + "%";
                                    return "0%";
                                }
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                Layout.preferredWidth: 36
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }



                    // Battery Content
                    Loader {
                        active: islandPill.renderActive && islandPill.renderMode === 4
                        anchors.fill: parent
                        anchors.margins: 8
                        sourceComponent: RowLayout {
                            spacing: 8

                            // Tonal Container for Battery Icon (M3 Style)
                            Rectangle {
                                id: batteryIconContainer
                                width: 34
                                height: 34
                                radius: 10
                                color: Qt.rgba(batteryIcon.color.r, batteryIcon.color.g, batteryIcon.color.b, 0.15)

                                MaterialSymbol {
                                    id: batteryIcon
                                    anchors.centerIn: parent
                                    text: {
                                        if (islandContainer.isCharging) return "battery_charging_full";
                                        var p = islandContainer.batteryPercent;
                                        if (p >= 0.95) return "battery_full";
                                        if (p >= 0.85) return "battery_6_bar";
                                        if (p >= 0.70) return "battery_5_bar";
                                        if (p >= 0.55) return "battery_4_bar";
                                        if (p >= 0.40) return "battery_3_bar";
                                        if (p >= 0.25) return "battery_2_bar";
                                        if (p >= 0.10) return "battery_1_bar";
                                        return "battery_0_bar";
                                    }
                                    color: islandContainer.isCharging ? Appearance.colors.colPrimary : (islandContainer.batteryPercent < 0.2 ? Appearance.colors.colError : Appearance.colors.colOnLayer0)
                                    iconSize: 24
                                }
                            }

                            Text {
                                text: Math.round(islandContainer.batteryPercent * 100) + "%"
                                color: Appearance.colors.colOnLayer0
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: islandContainer.batterySource === "custom" ? islandContainer.customBatteryName : (islandContainer.isCharging ? "Charging" : "Not Charging")
                                color: Appearance.colors.colOnLayer0
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Passive hover tracker (non-grabbing) for stable expand/collapse behavior.
                    HoverHandler {
                        id: islandHoverTracker
                        margin: 40
                        blocking: false

                        onHoveredChanged: {
                            if (hovered) {
                                expandTimer.stop()
                                islandContainer.isHovered = true
                            } else {
                                expandTimer.start()
                                islandContainer.isHovered = false
                            }
                        }
                    }
                }


            // Time State
            // Time State
            property string currentTime: Qt.formatTime(new Date(), "h:mm AP")
            property string currentTimeWithSeconds: Qt.formatTime(new Date(), "h:mm AP")
            property string currentDate: Qt.formatDate(new Date(), "ddd, MMM d")

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    islandContainer.currentTime = Qt.formatTime(new Date(), "h:mm AP")
                    islandContainer.currentTimeWithSeconds = Qt.formatTime(new Date(), "h:mm AP")
                    islandContainer.currentDate = Qt.formatDate(new Date(), "ddd, MMM d")
                }
            }
        }
    }
}
}
