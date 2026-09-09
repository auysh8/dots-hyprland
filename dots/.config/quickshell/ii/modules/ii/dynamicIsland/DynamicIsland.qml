import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Wayland._IdleNotify
import "components"
import "pages"
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services

Scope {
    id: dynamicIslandScope

    Variants {
        // For each monitor - only show when vertical bar is enabled
        model: {
            if (!Config.options.bar.vertical)
                return [];

            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;

            return screens.filter((screen) => {
                return list.includes(screen.name);
            });
        }

        PanelWindow {
            id: islandRoot

            required property ShellScreen modelData

            screen: modelData
            implicitHeight: islandContainer.height + Appearance.sizes.hyprlandGapsOut * 2
            color: "transparent"
            WlrLayershell.namespace: "quickshell:dynamicIsland"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusiveZone: -1 // Don't reserve space, float over windows

            anchors {
                top: true
                left: true
                right: true
            }

            // Main Container (Includes Trigger + Island)
            Item {
                // desktop -> show
                // idle -> show (unless fullscreen)

                id: islandContainer

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
                property string batterySource: "system"
                // "system" or "custom"
                property real customBatteryPercent: 0
                property bool customBatteryCharging: false
                property string customBatteryName: "Battery"
                property bool isCharging: batterySource === "system" ? Battery.isPluggedIn : customBatteryCharging
                property real batteryPercent: batterySource === "system" ? Battery.percentage : customBatteryPercent
                // Reactive open-window tracking (polling fallback)
                property bool hasOpenWindow: false
                property bool hasFullscreen: false
                property bool suppressAutomaticModes: hasFullscreen
                property bool effectiveHasPopup: hasPopup && !suppressAutomaticModes
                // Modes: 0=Idle/Media, 1=Volume, 2=Brightness, 3=CustomPopup, 4=Battery
                property int modeOverride: 0
                property int mode: suppressAutomaticModes ? 0 : (modeOverride > 0 ? modeOverride : (effectiveHasPopup ? 3 : 0))
                property string expandedPageKey: "media"
                property real lastVolume: Audio.value
                property real lastBrightness: Brightness.monitors.length > 0 ? Brightness.monitors[0].brightness : 0
                // Prevent startup triggers and hide island for 1s
                property bool initialized: false
                property bool islandVisible: !GlobalStates.overviewOpen && (triggerArea.containsMouse || expanded || (!suppressAutomaticModes && (mode !== 0 || (!hasOpenWindow) || (hasOpenWindow && idleMon.isIdle))))
                property bool expanded: (islandHoverTracker.hovered || expandTimer.running) && mode === 0 && !effectiveHasPopup
                property bool storageWarningActive: false
                // Time State
                // Time State
                property string currentTime: Qt.formatTime(new Date(), "h:mm AP")
                property string currentTimeWithSeconds: Qt.formatTime(new Date(), "h:mm AP")
                property string currentDate: Qt.formatDate(new Date(), "ddd, MMM d")

                property list<real> visualizerPoints: GlobalStates.visualizerPoints
                readonly property bool visualizerActive: islandContainer.hasMedia
                    && islandPill.renderMode === 0
                    && !islandContainer.expanded
                    && islandContainer.islandVisible
                    && islandPill.renderActive
                    && islandPill.scale > 0.5
                    && (!islandContainer.hasOpenWindow || triggerArea.containsMouse)
                onVisualizerActiveChanged: {
                    CavaService.setIslandActive(islandRoot.screen.name, visualizerActive)
                }
                Component.onCompleted: {
                    if (visualizerActive) CavaService.setIslandActive(islandRoot.screen.name, true)
                }
                Component.onDestruction: {
                    CavaService.setIslandActive(islandRoot.screen.name, false)
                }

                function updateHasOpenWindow() {
                    // find the monitor for this panel
                    var monitor = HyprlandData.monitors.find((m) => {
                        return m.name === islandRoot.screen.name;
                    });
                    if (!monitor || !monitor.activeWorkspace) {
                        hasOpenWindow = false;
                        hasFullscreen = false;
                        return ;
                    }
                    var wid = monitor.activeWorkspace.id ?? -1;
                    if (wid < 0) {
                        hasOpenWindow = false;
                        hasFullscreen = false;
                        return ;
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

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                // Height is just island height (since no gap now)
                // Fixed max surface size to prevent Wayland resize jitter
                implicitHeight: 320
                implicitWidth: 500
                opacity: initialized ? 1 : 0

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
                        if (islandContainer.suppressAutomaticModes)
                            return;

                        islandContainer.batterySource = "system"; // Reset to system
                        islandContainer.isCharging = plugged;
                        islandContainer.modeOverride = 4;
                        modeTimer.restart();
                    }
                    onRequestCustomBattery: (percent, name) => {
                        if (islandContainer.suppressAutomaticModes)
                            return;

                        islandContainer.batterySource = "custom";
                        islandContainer.customBatteryPercent = percent;
                        islandContainer.customBatteryName = name;
                        islandContainer.customBatteryCharging = false;
                        islandContainer.modeOverride = 4;
                        modeTimer.restart();
                    }
                }

                Timer {
                    id: startupTimer

                    interval: 1000 // 1 second delay
                    running: true
                    onTriggered: islandContainer.initialized = true
                }

                // UI Triggers (Volume/Brightness)
                Connections {
                    function onVolumeChanged() {
                        if (!islandContainer.initialized)
                            return ;

                        if (islandContainer.suppressAutomaticModes)
                            return ;

                        var v = Audio.value;
                        if (isNaN(v) || v === undefined)
                            return ;

                        // Suppress volume popup if Bluetooth popup is showing (ghost trigger on connect/disconnect)
                        if (islandContainer.hasPopup) {
                            var t = islandContainer.popupTitle.toLowerCase();
                            var m = islandContainer.popupMessage.toLowerCase();
                            if (t.includes("bluetooth") && (m.includes("connect") || m.includes("disconnect")))
                                return ;

                        }
                        // Snapshot current audio value before expanding
                        islandContainer.lastVolume = Audio.value;
                        islandContainer.modeOverride = 1;
                        modeTimer.restart();
                    }

                    function onMutedChanged() {
                        if (!islandContainer.initialized)
                            return ;

                        if (islandContainer.suppressAutomaticModes)
                            return ;

                        islandContainer.lastVolume = Audio.value;
                        islandContainer.modeOverride = 1;
                        modeTimer.restart();
                    }

                    target: Audio.sink ? Audio.sink.audio : null
                }

                Connections {
                    function onBrightnessChanged() {
                        if (islandContainer.suppressAutomaticModes)
                            return ;

                        // Snapshot current brightness before expanding
                        islandContainer.lastBrightness = (Brightness.monitors.length > 0) ? Brightness.monitors[0].brightness : islandContainer.lastBrightness;
                        islandContainer.modeOverride = 2;
                        modeTimer.restart();
                    }

                    target: Brightness
                }

                Connections {
                    function onIsPluggedInChanged() {
                        if (islandContainer.suppressAutomaticModes)
                            return ;

                        islandContainer.isCharging = Battery.isPluggedIn;
                        logic.popupCategory = "battery";
                        logic.popupAction = Battery.isPluggedIn ? "charging" : "unplugged";
                        islandContainer.modeOverride = 4;
                        modeTimer.restart();
                    }

                    function onPercentageChanged() {
                        if (islandContainer.suppressAutomaticModes)
                            return ;

                        // Trigger if plugged in and reaches 100% (or very close to it)
                        // Use a flag or check checks to avoid spam, but since modeTimer resets status, a re-trigger is acceptable if it fluctuates logic wise.
                        if (Battery.isPluggedIn && Battery.percentage >= 0.99) {
                            islandContainer.batterySource = "system";
                            islandContainer.isCharging = Battery.isPluggedIn;
                            logic.popupCategory = "battery";
                            logic.popupAction = "charging";
                            islandContainer.modeOverride = 4;
                            modeTimer.restart();
                        }
                    }

                    target: Battery
                }

                Connections {
                    function onDiskUsedPercentageChanged() {
                        if (ResourceUsage.diskUsedPercentage >= 0.95) {
                            if (islandContainer.storageWarningActive)
                                return ;

                            islandContainer.storageWarningActive = true;
                            logic.showPopup("bad", "Storage", Math.round(ResourceUsage.diskUsedPercentage * 100) + "% full", "storage", "low");
                            if (!islandContainer.suppressAutomaticModes)
                                modeTimer.restart();
                        } else {
                            islandContainer.storageWarningActive = false;
                        }
                    }

                    target: ResourceUsage
                }

                // Poll at a lower rate to reduce background CPU usage.
                Timer {
                    id: hyprPoll

                    interval: 2000
                    repeat: true
                    running: true
                    onTriggered: islandContainer.updateHasOpenWindow()
                }

                Connections {
                    target: HyprlandData
                    function onWindowListChanged() {
                        islandContainer.updateHasOpenWindow();
                    }
                    function onActiveWorkspaceChanged() {
                        islandContainer.updateHasOpenWindow();
                    }
                    function onMonitorsChanged() {
                        islandContainer.updateHasOpenWindow();
                    }
                }

                IdleMonitor {
                    id: idleMon

                    timeout: 8 // Stay hidden longer before showing on idle
                    enabled: true
                }

                Timer {
                    id: modeTimer

                    interval: islandContainer.batterySource === "custom" ? 5000 : 2000
                    onTriggered: {
                        islandContainer.modeOverride = 0;
                        // Reset source after timeout
                        if (islandContainer.batterySource === "custom")
                            islandContainer.batterySource = "system";

                    }
                }

                Timer {
                    id: expandTimer

                    interval: 2000
                    repeat: false
                }

                // The Island Pill
                Item {
                    // Scale Logic
                    // Controlled centrally by islandContainer.islandVisible

                    id: islandPill

                    property int renderMode: islandContainer.mode
                    readonly property bool renderActive: islandContainer.islandVisible || pillScaleAnim.running || pillWidthAnim.running || pillHeightAnim.running || scale > 0.01
                    // Track if we need to shake when mode 3 becomes visible
                    property bool pendingBadShake: false
                    // Size Logic
                    TextMetrics {
                        id: titleMetrics
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: MprisController.activeTrack ? MprisController.activeTrack.title || "" : ""
                    }
                    
                    // Timer + Separator + Visualizer + Gaps = ~140px. Add text width. Cap at 320.
                    // Added +30 for extra left/right padding
                    property real dynamicMediaWidth: Math.min(Math.max(titleMetrics.advanceWidth, 40) + 170, 340)
                    
                    property real collapsedWidth: islandContainer.hasMedia ? dynamicMediaWidth : 200
                    // Increased from 240
                    property real collapsedHeight: 36
                    property bool pomodoroActive: TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)
                    property bool stopwatchActive: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0
                    property bool downloadActive: DownloadService.active
                    property bool timerActive: pomodoroActive || stopwatchActive
                    // Mode specific sizes
                    property real expandedWidth: {
                        if (islandPill.renderMode === 1 || islandPill.renderMode === 2)
                            return 220;
 // Volume/Brightness
                        if (islandPill.renderMode === 3)
                            return 320;
 // Notification (Match collapsed width roughly)
                        if (islandPill.renderMode === 4)
                            return 260;
 // Battery
                        return 420;
                    }
                    property real expandedHeight: {
                        if (islandPill.renderMode === 1 || islandPill.renderMode === 2)
                            return 48;
 // M3 Pill height
                        if (islandPill.renderMode === 3)
                            return 64;
 // Popup (DoubleLine)
                        if (islandPill.renderMode === 4)
                            return 52;
 // Battery
                        // Check for multiple pages to add space for pagination dots
                        var pageCount = 0;
                        if (islandContainer.hasMedia)
                            pageCount++;

                        if (pomodoroActive)
                            pageCount++;

                        if (stopwatchActive)
                            pageCount++;

                        if (downloadActive)
                            pageCount++;

                        if (pageCount > 0)
                            return pageCount > 1 ? 265 : 235;

                        return 60;
                    }

                    anchors.top: parent.top
                    anchors.topMargin: 0 // Attached to top edge (Notch style)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: 0 // For Shake Animation
                    visible: renderActive
                    enabled: renderActive
                    scale: islandContainer.islandVisible ? 1 : 0
                    transformOrigin: Item.Top
                    width: (islandContainer.expanded || islandPill.renderMode !== 0) ? expandedWidth : collapsedWidth
                    height: (islandContainer.expanded || islandPill.renderMode !== 0) ? expandedHeight : collapsedHeight
                    // Shadow
                    layer.enabled: true

                    Connections {
                        function onModeChanged() {
                            // Keep the currently shown mode while closing, then sync when visible again.
                            if (islandContainer.islandVisible || !islandPill.renderActive)
                                islandPill.renderMode = islandContainer.mode;

                        }

                        function onIslandVisibleChanged() {
                            if (islandContainer.islandVisible)
                                islandPill.renderMode = islandContainer.mode;

                        }

                        target: islandContainer
                    }

                    SequentialAnimation {
                        id: shakeAnimation

                        property int amplitude: 6
                        property int speed: 35

                        NumberAnimation {
                            target: islandPill
                            property: "anchors.horizontalCenterOffset"
                            from: 0
                            to: -shakeAnimation.amplitude
                            duration: shakeAnimation.speed
                            easing.type: Easing.InOutQuad
                        }

                        NumberAnimation {
                            target: islandPill
                            property: "anchors.horizontalCenterOffset"
                            from: -shakeAnimation.amplitude
                            to: shakeAnimation.amplitude
                            duration: shakeAnimation.speed
                            easing.type: Easing.InOutQuad
                        }

                        NumberAnimation {
                            target: islandPill
                            property: "anchors.horizontalCenterOffset"
                            from: shakeAnimation.amplitude
                            to: -shakeAnimation.amplitude
                            duration: shakeAnimation.speed
                            easing.type: Easing.InOutQuad
                        }

                        NumberAnimation {
                            target: islandPill
                            property: "anchors.horizontalCenterOffset"
                            from: -shakeAnimation.amplitude
                            to: shakeAnimation.amplitude
                            duration: shakeAnimation.speed
                            easing.type: Easing.InOutQuad
                        }

                        NumberAnimation {
                            target: islandPill
                            property: "anchors.horizontalCenterOffset"
                            from: shakeAnimation.amplitude
                            to: 0
                            duration: shakeAnimation.speed
                            easing.type: Easing.InOutQuad
                        }

                    }

                    // Delay timer to wait for island expansion before shaking
                    Timer {
                        id: shakeDelayTimer

                        interval: 280 // Wait for expansion animation to complete
                        onTriggered: shakeAnimation.restart()
                    }

                    Connections {
                        function onPopupTypeChanged() {
                            if (islandContainer.popupType === "bad" && islandContainer.hasPopup) {
                                if (islandContainer.mode === 3)
                                    // Already in mode 3, shake after delay
                                    shakeDelayTimer.restart();
                                else
                                    // Mark for shake when mode becomes 3
                                    islandPill.pendingBadShake = true;
                            }
                        }

                        function onHasPopupChanged() {
                            if (islandContainer.hasPopup && islandContainer.popupType === "bad") {
                                if (islandContainer.mode === 3)
                                    shakeDelayTimer.restart();
                                else
                                    islandPill.pendingBadShake = true;
                            }
                        }

                        function onModeChanged() {
                            // When mode changes TO 3 and we have a pending bad shake
                            if (islandContainer.mode === 3 && islandPill.pendingBadShake) {
                                islandPill.pendingBadShake = false;
                                shakeDelayTimer.restart();
                            }
                        }

                        target: islandContainer
                    }

                    // Island background (Single Shape - Flat Top, Rounded Bottom)
                    Item {
                        id: islandBackground

                        readonly property bool isBadPopup: islandContainer.hasPopup && (islandPill.renderMode === 3 || islandContainer.mode === 3) && (
                            islandContainer.popupType === "bad" ||
                            (islandContainer.popupCategory === "battery" && islandContainer.popupAction === "low") ||
                            (islandContainer.popupCategory === "microphone" && islandContainer.popupAction === "muted") ||
                            (islandContainer.popupCategory === "volume" && islandContainer.popupAction === "muted") ||
                            (islandContainer.popupCategory === "wifi" && islandContainer.popupAction === "disconnected") ||
                            (islandContainer.popupCategory === "bluetooth" && islandContainer.popupAction === "disconnected") ||
                            (islandContainer.popupCategory === "storage" && islandContainer.popupAction === "low")
                        )

                        property color bgColor: isBadPopup ? ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colError, 0.85) : Appearance.colors.colLayer0
                        property real bottomRadius: islandContainer.expanded ? 24 : 16

                        Behavior on bottomRadius {
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }

                        anchors.fill: parent

                        Shape {
                            anchors.fill: parent

                            ShapePath {
                                strokeWidth: 1
                                strokeColor: islandBackground.isBadPopup ? ColorUtils.applyAlpha(Appearance.colors.colError, 0.25) : Appearance.colors.colLayer0Border
                                fillColor: islandBackground.bgColor
                                // Start at top-left corner
                                startX: 0
                                startY: 0

                                // Top edge (straight)
                                PathLine {
                                    x: islandBackground.width
                                    y: 0
                                }

                                // Right edge down to curve start
                                PathLine {
                                    x: islandBackground.width
                                    y: islandBackground.height - islandBackground.bottomRadius
                                }

                                // Bottom-right rounded corner
                                PathArc {
                                    x: islandBackground.width - islandBackground.bottomRadius
                                    y: islandBackground.height
                                    radiusX: islandBackground.bottomRadius
                                    radiusY: islandBackground.bottomRadius
                                    direction: PathArc.Clockwise
                                }

                                // Bottom edge (straight)
                                PathLine {
                                    x: islandBackground.bottomRadius
                                    y: islandBackground.height
                                }

                                // Bottom-left rounded corner
                                PathArc {
                                    x: 0
                                    y: islandBackground.height - islandBackground.bottomRadius
                                    radiusX: islandBackground.bottomRadius
                                    radiusY: islandBackground.bottomRadius
                                    direction: PathArc.Clockwise
                                }

                                // Left edge back to start
                                PathLine {
                                    x: 0
                                    y: 0
                                }

                            }

                        }

                        Behavior on bgColor {
                            ColorAnimation {
                                duration: 200
                            }

                        }

                    }

                    // Collapsed content
                    Item {
                        // anchors.margins: 12

                        id: collapsedContent

                        anchors.fill: parent
                        opacity: ((islandContainer.mode === 0 && !islandContainer.expanded) || islandContainer.mode === 3) ? 1 : 0
                        visible: opacity > 0

                        // Standard Mode Content
                        Loader {
                            // No second separator needed as we are mutually exclusive now

                            active: islandPill.renderActive && islandPill.renderMode === 0 && !islandContainer.expanded
                            anchors.centerIn: parent

                            sourceComponent: RowLayout {
                                // width: parent.width - 24 // Removed to allow true centering
                                spacing: 12
                                anchors.centerIn: parent

                                // Time / Timer / Stopwatch
                                RowLayout {
                                    spacing: 8
                                    Layout.alignment: Qt.AlignVCenter
                                    
                                    CircularProgress {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        Layout.bottomMargin: 2 // Visually bumps the icon up slightly to align with the text baseline
                                        visible: TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)
                                        value: TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration
                                        colPrimary: TimerService.isPomodoroBreak ? Appearance.colors.colOnLayer0 : Appearance.colors.colError
                                        implicitSize: 20
                                        lineWidth: 3
                                    }
                                    
                                    // Icon for Stopwatch (since there is no defined "end" percentage)
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.bottomMargin: 2 // Visually bumps the icon up slightly to align with the text baseline
                                        visible: TimerService.stopwatchRunning && !(TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0))
                                        text: "timer"
                                        iconSize: 18
                                        fill: 1
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        verticalAlignment: Text.AlignVCenter
                                        // Time / Timer / Stopwatch
                                        text: {
                                            if (TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)) {
                                                let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                                                let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                                                return m + ":" + s;
                                            }
                                            if (TimerService.stopwatchRunning) {
                                                let t = TimerService.stopwatchTime / 100;
                                                let m = Math.floor(t / 60).toString().padStart(2, '0');
                                                let s = Math.floor(t % 60).toString().padStart(2, '0');
                                                return m + ":" + s;
                                            }
                                            return islandContainer.currentTime;
                                        }
                                        color: {
                                            if (TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)) {
                                                return TimerService.isPomodoroBreak ? Appearance.colors.colOnLayer0 : Appearance.colors.colError;
                                            }

                                            if (TimerService.stopwatchRunning)
                                                return Appearance.colors.colPrimary;

                                            return Appearance.colors.colOnLayer0;
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Medium
                                    }
                                }

                                // Dot Separator (Material 3 Expressive)
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.leftMargin: 2
                                    Layout.rightMargin: 2
                                    implicitWidth: 4
                                    implicitHeight: 4
                                    radius: 2
                                    color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.4)
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
                                        fill: 1
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        text: Math.round(DownloadService.progress * 100) + "%"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                    }

                                }

                                // Media indicator (collapsed)
                                RowLayout {
                                    visible: islandContainer.hasMedia
                                    spacing: 4 // Reduced from 8 to pull text closer to icon
                                    // Make the layout exactly wide enough for the visualizer + text
                                    Layout.preferredWidth: Math.min(Math.max(titleMetrics.advanceWidth, 40) + 26, 180)

                                    // Music Icon when paused / Visualizer when playing
                                    Item {
                                        Layout.preferredWidth: 18 // Reduced from 32 to exactly match icon width
                                        Layout.preferredHeight: 16
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                                        Layout.bottomMargin: 3 // Visually bumps the icon up slightly to align with the text
                                        visible: islandContainer.hasMedia

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: !MprisController.isPlaying
                                            text: "music_note"
                                            iconSize: 18
                                            fill: 1
                                            color: Appearance.colors.colOnLayer0
                                            opacity: 0.6
                                        }

                                        Row {
                                            id: islandPillVisualizer
                                            anchors.centerIn: parent
                                            visible: MprisController.isPlaying
                                            spacing: 1.5

                                            readonly property var points: islandContainer.visualizerPoints

                                            Repeater {
                                                model: 5
                                                Rectangle {
                                                    required property int index
                                                    width: 2.4
                                                    radius: width / 2
                                                    color: Appearance.colors.colPrimary
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    property real rawVal: {
                                                        const pts = islandPillVisualizer.points
                                                        return (pts && pts.length > 0) ? (pts[1 + (index * 3)] || 0) : 0
                                                    }
                                                    property real normVal: Math.max(0.18, Math.min(1.0, rawVal / 1000))
                                                    height: Math.max(width * 1.3, normVal * 16)
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        id: mediaText
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                                        text: MprisController.activeTrack ? MprisController.activeTrack.title || "" : ""
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                        horizontalAlignment: Text.AlignLeft
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
                                MaterialShapeWrappedMaterialSymbol {
                                    id: popupIconContainer

                                    shape: MaterialShape.Shape.Square
                                    padding: 5
                                    colSymbol: {
                                        if (islandContainer.popupType === "bad")
                                            return Appearance.colors.colError;

                                        switch (islandContainer.popupCategory) {
                                        case "battery":
                                            if (islandContainer.popupAction === "low")
                                                return Appearance.colors.colError;

                                            if (islandContainer.popupAction === "charging")
                                                return Appearance.colors.colPrimary;

                                            return Appearance.colors.colOnLayer0;
                                        case "wifi":
                                        case "bluetooth":
                                        case "microphone":
                                        case "volume":
                                            if (islandContainer.popupAction === "disconnected" || islandContainer.popupAction === "muted")
                                                return Appearance.colors.colError;

                                            return Appearance.colors.colPrimary;
                                        case "storage":
                                            return islandContainer.popupAction === "low" ? Appearance.colors.colError : Appearance.colors.colPrimary;
                                        default:
                                            return Appearance.colors.colPrimary;
                                        }
                                    }
                                    color: ColorUtils.applyAlpha(colSymbol, 0.15)
                                    text: {
                                        switch (islandContainer.popupCategory) {
                                        case "screenshot":
                                            return "screenshot";
                                        case "download":
                                            return islandContainer.popupAction === "complete" ? "download_done" : "download";
                                        case "clipboard":
                                            return "content_paste";
                                        case "media":
                                            return "music_note";
                                        case "microphone":
                                            return islandContainer.popupAction === "muted" ? "mic_off" : "mic";
                                        case "volume":
                                            return islandContainer.popupAction === "muted" ? "volume_off" : "volume_up";
                                        case "wifi":
                                            return islandContainer.popupAction === "disconnected" ? "wifi_off" : "wifi";
                                        case "bluetooth":
                                            if (islandContainer.popupAction === "connected")
                                                return "bluetooth_connected";

                                            if (islandContainer.popupAction === "disconnected")
                                                return "bluetooth_disabled";

                                            return "bluetooth";
                                        case "battery":
                                            if (islandContainer.popupAction === "charging")
                                                return "battery_charging_full";

                                            if (islandContainer.popupAction === "low")
                                                return "battery_alert";

                                            return "battery_std";
                                        case "pomodoro":
                                            if (islandContainer.popupAction === "break")
                                                return "coffee";

                                            if (islandContainer.popupAction === "complete")
                                                return "check_circle";

                                            return "timer";
                                        case "brightness":
                                            return "brightness_6";
                                        case "notification":
                                            return "notifications";
                                        case "message":
                                            return "message";
                                        case "mail":
                                            return "mail";
                                        case "update":
                                            return "update";
                                        case "storage":
                                            return "storage";
                                        case "keyboard":
                                            return "keyboard";
                                        case "notification":
                                            if (islandContainer.popupAction === "pinned")
                                                return "push_pin";

                                            if (islandContainer.popupAction === "unpinned")
                                                return "block";

                                            return "notifications";
                                        case "camera":
                                            return "videocam";
                                        case "file":
                                            return "description";
                                        default:
                                            if (islandContainer.popupType === "bad")
                                                return "warning";

                                            if (islandContainer.popupType === "good")
                                                return "check_circle";

                                            return "info";
                                        }
                                    }
                                    iconSize: 24
                                }

                                // Double Line Layout for ALL Popups
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        text: islandContainer.popupTitle
                                        color: islandBackground.isBadPopup ? (Appearance.m3colors.m3onErrorContainer || Appearance.colors.colOnLayer0) : Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    StyledText {
                                        text: islandContainer.popupMessage
                                        color: islandBackground.isBadPopup ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        opacity: islandBackground.isBadPopup ? 1.0 : 0.7
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                }

                            }

                        }

                    }

                    // Expanded content
                    Loader {
                        // 4. SwipeView for Content (Horizontal & Swipeable)

                        id: expandedContentLoader

                        active: islandPill.renderActive && islandContainer.expanded && islandPill.renderMode === 0
                        visible: islandContainer.expanded && islandContainer.mode === 0
                        anchors.fill: parent
                        anchors.margins: 12

                        sourceComponent: ColumnLayout {
                            id: expandedContent

                            // Dynamic Page List
                            property var activePages: {
                                var pages = [];
                                if (islandContainer.hasMedia)
                                    pages.push({
                                    "key": "media",
                                    "component": mediaPage
                                });

                                if (islandPill.pomodoroActive)
                                    pages.push({
                                    "key": "pomodoro",
                                    "component": pomodoroPage
                                });

                                if (islandPill.stopwatchActive)
                                    pages.push({
                                    "key": "stopwatch",
                                    "component": stopwatchPage
                                });

                                if (islandPill.downloadActive)
                                    pages.push({
                                    "key": "download",
                                    "component": downloadPage
                                });

                                return pages;
                            }

                            function pageIndexForKey(key) {
                                for (var i = 0; i < activePages.length; ++i) {
                                    if (activePages[i].key === key)
                                        return i;

                                }
                                return -1;
                            }

                            function syncSwipeToSavedPage() {
                                if (activePages.length === 0) {
                                    islandContainer.expandedPageKey = "media";
                                    return ;
                                }
                                var targetIndex = pageIndexForKey(islandContainer.expandedPageKey);
                                if (targetIndex < 0)
                                    targetIndex = 0;

                                if (contentSwipe.currentIndex !== targetIndex)
                                    contentSwipe.currentIndex = targetIndex;

                                var resolvedKey = activePages[targetIndex].key;
                                if (resolvedKey !== islandContainer.expandedPageKey)
                                    islandContainer.expandedPageKey = resolvedKey;

                            }

                            spacing: 8
                            onActivePagesChanged: Qt.callLater(syncSwipeToSavedPage)

                            // Top row - Time and Date (Material 3 Expressive Pills)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                // Time Pill
                                Pill {
                                    id: timePill
                                    color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.10)
                                    border.width: 1
                                    border.color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.12)
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: timeContent.width + 20
                                    Layout.alignment: Qt.AlignVCenter

                                    Row {
                                        id: timeContent
                                        anchors.centerIn: parent
                                        spacing: 6

                                        // Mint Circular Clock Badge
                                        Pill {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 20
                                            height: 20
                                            color: Appearance.colors.colPrimary

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "schedule"
                                                iconSize: 13
                                                fill: 1
                                                color: Appearance.colors.colOnPrimary
                                            }
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: 2
                                            text: islandContainer.currentTime
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnLayer0
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                }

                                // Date Pill
                                Pill {
                                    id: datePill
                                    color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.10)
                                    border.width: 1
                                    border.color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.12)
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: dateContent.width + 20
                                    Layout.alignment: Qt.AlignVCenter

                                    Row {
                                        id: dateContent
                                        anchors.centerIn: parent
                                        spacing: 6

                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "calendar_month"
                                            iconSize: 18
                                            fill: 1
                                            color: Appearance.colors.colPrimary
                                        }

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.verticalCenterOffset: 2
                                            text: islandContainer.currentDate
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            color: Appearance.colors.colOnLayer0
                                        }
                                    }
                                }
                            }

                            // Page Components
                            Component {
                                id: mediaPage

                                MediaPage {
                                }

                            }

                            Component {
                                id: pomodoroPage

                                PomodoroPage {
                                }

                            }

                            Component {
                                id: stopwatchPage

                                StopwatchPage {
                                }

                            }

                            Component {
                                id: downloadPage

                                DownloadPage {
                                }

                            }

                            SwipeView {
                                id: contentSwipe

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                interactive: expandedContent.activePages.length > 1
                                Component.onCompleted: expandedContent.syncSwipeToSavedPage()
                                onCountChanged: expandedContent.syncSwipeToSavedPage()
                                onCurrentIndexChanged: {
                                    if (currentIndex < 0 || currentIndex >= expandedContent.activePages.length)
                                        return ;

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

                            // Page Indicator (Workspace Switcher Style: Minimal Dots when idle -> Rich Icon Capsule Pill on Hover)
                            Item {
                                id: islandPageIndicatorContainer
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredHeight: 30
                                implicitHeight: 30
                                Layout.fillWidth: true
                                visible: expandedContent.activePages.length > 1

                                HoverHandler {
                                    id: trackHoverHandler
                                }

                                readonly property bool hovered: trackHoverHandler.hovered || trackHoverArea.containsMouse
                                readonly property int count: expandedContent.activePages.length

                                function getPageIcon(key) {
                                    if (key === "media") return "music_note";
                                    if (key === "pomodoro") return "timer";
                                    if (key === "stopwatch") return "schedule";
                                    if (key === "download") return "download";
                                    return "circle";
                                }

                                MouseArea {
                                    id: trackHoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    propagateComposedEvents: true
                                    onClicked: (mouse) => mouse.accepted = false
                                }

                                Rectangle {
                                    id: islandPageIndicator
                                    anchors.centerIn: parent
                                    height: islandPageIndicatorContainer.hovered ? 26 : 6
                                    width: islandPageIndicatorContainer.hovered ? (dotsRow.implicitWidth + 8) : (islandPageIndicatorContainer.count * 6 + (islandPageIndicatorContainer.count - 1) * 6 + 10)
                                    radius: height / 2
                                    color: islandPageIndicatorContainer.hovered ? ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.12) : "transparent"
                                    border.width: islandPageIndicatorContainer.hovered ? 1 : 0
                                    border.color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.14)

                                    Behavior on height {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                    }
                                    Behavior on width {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }

                                    // Inactive/Occupied Dots & Chips Row
                                    Row {
                                        id: dotsRow
                                        anchors.centerIn: parent
                                        spacing: islandPageIndicatorContainer.hovered ? 4 : 6

                                        Behavior on spacing {
                                            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                                        }

                                        Repeater {
                                            model: expandedContent.activePages

                                            Item {
                                                id: dotItem
                                                readonly property string pageKey: modelData.key || ""
                                                readonly property bool isActive: islandContainer.expandedPageKey === pageKey

                                                implicitWidth: islandPageIndicatorContainer.hovered ? 20 : (isActive ? 16 : 6)
                                                implicitHeight: islandPageIndicatorContainer.hovered ? 20 : 6

                                                Behavior on implicitWidth {
                                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                                }
                                                Behavior on implicitHeight {
                                                    NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                                                }

                                                // Visual Representation
                                                Rectangle {
                                                    id: chipVisual
                                                    anchors.centerIn: parent
                                                    width: parent.width
                                                    height: parent.height
                                                    radius: height / 2

                                                    color: dotItem.isActive
                                                        ? Appearance.colors.colPrimary
                                                        : (islandPageIndicatorContainer.hovered
                                                            ? (dotClickArea.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.20) : ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.08))
                                                            : Appearance.colors.colOnLayer0)

                                                    opacity: dotItem.isActive ? 1.0 : (islandPageIndicatorContainer.hovered ? 1.0 : 0.35)

                                                    Behavior on color {
                                                        ColorAnimation { duration: 180 }
                                                    }
                                                    Behavior on opacity {
                                                        NumberAnimation { duration: 180 }
                                                    }

                                                    // Icon visible when hovered
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        visible: islandPageIndicatorContainer.hovered
                                                        opacity: visible ? 1 : 0
                                                        text: islandPageIndicatorContainer.getPageIcon(dotItem.pageKey)
                                                        iconSize: 12
                                                        fill: 1
                                                        color: dotItem.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0

                                                        Behavior on opacity {
                                                            NumberAnimation { duration: 150 }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: dotClickArea
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (index >= 0 && index < expandedContent.activePages.length) {
                                                            var targetKey = expandedContent.activePages[index].key;
                                                            islandContainer.expandedPageKey = targetKey;
                                                            contentSwipe.currentIndex = index;
                                                        }
                                                    }
                                                }
                                            }
                                        }
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
                        anchors.leftMargin: 12
                        anchors.rightMargin: 16

                        sourceComponent: RowLayout {
                            spacing: 10

                                                        // Tonal Container for Icon
                                                        MaterialShapeWrappedMaterialSymbol {
                                                            id: volumeIcon
                                                            shape: MaterialShape.Shape.Square
                                                            padding: 5
                                                            colSymbol: (Audio.sink && Audio.sink.audio && Audio.sink.audio.muted) ? Appearance.colors.colError : Appearance.colors.colPrimary
                                                            color: ColorUtils.applyAlpha(colSymbol, 0.15)
                                                            text: {
                                                                if (Audio.sink && Audio.sink.audio && Audio.sink.audio.muted) return "volume_off";
                                                                if (Audio.value > 0.5) return "volume_up";
                                                                if (Audio.value > 0) return "volume_down";
                                                                return "volume_mute";
                                                            }
                                                            iconSize: 18
                                                        }

                            // M3 Thick Pill Slider
                            StyledSlider {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                configuration: StyledSlider.Configuration.S
                                stopIndicatorValues: []
                                value: Audio.value || 0
                                onMoved: {
                                    if (Audio.sink && Audio.sink.audio)
                                        Audio.sink.audio.volume = value;

                                }
                                highlightColor: (Audio.sink && Audio.sink.audio && Audio.sink.audio.muted) ? Appearance.colors.colError : Appearance.colors.colPrimary
                            }

                            StyledText {
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
                        anchors.leftMargin: 12
                        anchors.rightMargin: 16

                        sourceComponent: RowLayout {
                            spacing: 10

                                                        // Tonal Container for Icon
                                                        MaterialShapeWrappedMaterialSymbol {
                                                            id: brightnessIcon
                                                            shape: MaterialShape.Shape.Square
                                                            padding: 5
                                                            colSymbol: Appearance.colors.colPrimary
                                                            color: ColorUtils.applyAlpha(colSymbol, 0.15)
                                                            text: {
                                                                var val = 0;
                                                                if (Brightness.monitors.length > 0) val = Brightness.monitors[0].brightness;
                            
                                                                if (val > 0.6) return "brightness_high";
                                                                if (val > 0.3) return "brightness_medium";
                                                                return "brightness_low";
                                                            }
                                                            iconSize: 18
                                                        }

                            // M3 Thick Pill Slider
                            StyledSlider {
                                property var brightnessMonitor: Brightness.monitors.length > 0 ? Brightness.monitors[0] : null

                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                configuration: StyledSlider.Configuration.S
                                stopIndicatorValues: []
                                value: brightnessMonitor ? brightnessMonitor.brightness : 0
                                onMoved: {
                                    if (brightnessMonitor)
                                        brightnessMonitor.setBrightness(value);

                                }
                                highlightColor: Appearance.colors.colPrimary
                            }

                            StyledText {
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
                            MaterialShapeWrappedMaterialSymbol {
                                id: batteryIconContainer

                                shape: MaterialShape.Shape.Square
                                padding: 5
                                colSymbol: islandContainer.isCharging ? Appearance.colors.colPrimary : (islandContainer.batteryPercent < 0.2 ? Appearance.colors.colError : Appearance.colors.colOnLayer0)
                                color: ColorUtils.applyAlpha(colSymbol, 0.15)

                                text: {
                                    if (islandContainer.isCharging)
                                        return "battery_charging_full";

                                    var p = islandContainer.batteryPercent;
                                    if (p >= 0.95)
                                        return "battery_full";

                                    if (p >= 0.85)
                                        return "battery_6_bar";

                                    if (p >= 0.7)
                                        return "battery_5_bar";

                                    if (p >= 0.55)
                                        return "battery_4_bar";

                                    if (p >= 0.4)
                                        return "battery_3_bar";

                                    if (p >= 0.25)
                                        return "battery_2_bar";

                                    if (p >= 0.1)
                                        return "battery_1_bar";

                                    return "battery_0_bar";
                                }
                                iconSize: 24
                            }

                            StyledText {
                                text: Math.round(islandContainer.batteryPercent * 100) + "%"
                                color: (islandContainer.batteryPercent < 0.2 && !islandContainer.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                font.weight: Font.Bold
                                font.pixelSize: Appearance.font.pixelSize.normal
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: islandContainer.batterySource === "custom" ? islandContainer.customBatteryName : (islandContainer.batteryPercent >= 0.99 ? "Fully Charged" : (islandContainer.isCharging ? "Charging" : "On Battery"))
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
                                expandTimer.stop();
                                islandContainer.isHovered = true;
                            } else {
                                expandTimer.start();
                                islandContainer.isHovered = false;
                            }
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            id: pillScaleAnim

                            duration: 400
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.8
                        }

                    }

                    Behavior on width {
                        SpringAnimation {
                            id: pillWidthAnim

                            spring: 2.5
                            damping: 0.4
                            epsilon: 0.5
                            mass: 1
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

                    layer.effect: StyledDropShadow {
                        target: islandPill
                    }

                }

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: {
                        islandContainer.currentTime = Qt.formatTime(new Date(), "h:mm AP");
                        islandContainer.currentTimeWithSeconds = Qt.formatTime(new Date(), "h:mm AP");
                        islandContainer.currentDate = Qt.formatDate(new Date(), "ddd, MMM d");
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 500
                    }

                }

            }

            // Input mask uses a dynamic target to hug the content tightly
            mask: Region {
                item: maskTarget
            }

        }

    }

}
