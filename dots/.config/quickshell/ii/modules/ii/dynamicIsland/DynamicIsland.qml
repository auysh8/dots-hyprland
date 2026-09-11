import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
                readonly property var availablePlayers: MprisController.players
                readonly property var effectiveActivePlayer: {
                    let primary = MprisController.activePlayer;
                    if (primary && (!primary.trackArtUrl || primary.trackArtUrl.length === 0)) {
                        for (let i = 0; i < availablePlayers.length; ++i) {
                            let p = availablePlayers[i];
                            if (p && p.trackArtUrl && p.trackArtUrl.length > 0) {
                                let t1 = (primary.trackTitle || "").toLowerCase();
                                let t2 = (p.trackTitle || "").toLowerCase();
                                if (t1.length > 0 && (t1.includes(t2) || t2.includes(t1) || p.isPlaying)) {
                                    return p;
                                }
                            }
                        }
                    }
                    return primary;
                }
                property var activePlayer: effectiveActivePlayer
                property bool hasMedia: activePlayer !== null

                MediaArtColorContext {
                    id: dynamicMediaColorContext
                    activePlayer: islandContainer.activePlayer
                }

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
                property string expandedPageKey: islandContainer.hasMedia ? "media" : "idle"
                property real lastVolume: Audio.value
                property real lastBrightness: Brightness.monitors.length > 0 ? Brightness.monitors[0].brightness : 0
                // Prevent startup triggers and hide island for 1s
                property bool initialized: false
                property bool manualExpanded: false
                readonly property bool islandHovered: triggerArea.containsMouse || islandHoverTracker.hovered || (islandSatellite && islandSatellite.hovered)
                property bool islandVisible: !GlobalStates.overviewOpen && (islandHovered || hoverExitTimer.running || manualExpanded || (!suppressAutomaticModes && (mode !== 0 || (!hasOpenWindow) || (hasOpenWindow && idleMon.isIdle))))
                property bool expanded: manualExpanded && mode === 0 && !effectiveHasPopup
                property bool storageWarningActive: false
                // Keep the island visually separate from the screen edge.
                property real floatingTopMargin: 12
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
                    if (visualizerActive) CavaService.setIslandActive(islandRoot.screen.name, true);
                    islandContainer.updateHasOpenWindow();
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
                    // When hidden, only mask the trigger area (10px height). When visible, cover both pill and satellite.
                    readonly property real rightExtent: (islandPill.width / 2) + ((islandSatellite && islandSatellite.visible) ? (islandSatellite.anchors.leftMargin + islandSatellite.width) : 0)
                    width: islandContainer.islandVisible ? Math.max(triggerArea.width, rightExtent * 2 * islandPill.targetScale) : triggerArea.width
                    height: islandContainer.islandVisible ? islandContainer.floatingTopMargin + Math.max(islandPill.height, (islandSatellite ? islandSatellite.height : 0)) * islandPill.targetScale + 10 : triggerArea.height
                }

                // Trigger area at the top (Thin strip)
                MouseArea {
                    id: triggerArea

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 300
                    height: 10
                    hoverEnabled: true // Always valid for hover
                    onEntered: hoverExitTimer.stop()
                    onExited: hoverExitTimer.restart()
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

                // Native Quickshell IPC Interface for Dynamic Island
                IpcHandler {
                    target: "dynamicIsland"

                    // Accepts a pipe-delimited payload "type|title|message|category|action" or a single message
                    function show(payload: string): void {
                        if (!payload) return;
                        var parts = payload.split("|");
                        if (parts.length >= 3) {
                            var t = parts[0];
                            var title = parts[1];
                            var msg = parts[2];
                            var cat = parts.length >= 4 ? parts[3] : "generic";
                            var act = parts.length >= 5 ? parts[4] : "";
                            logic.showPopup(t, title, msg, cat, act);
                        } else {
                            logic.showPopup("neutral", "System", payload, "generic", "");
                        }
                    }

                    // Accepts structured JSON: '{"type":"good","title":"Done","message":"Saved","category":"download","action":"complete"}'
                    function showJson(jsonStr: string): void {
                        try {
                            var data = JSON.parse(jsonStr);
                            logic.showPopup(data.type || "neutral", data.title || "", data.message || "", data.category || "generic", data.action || "");
                        } catch (e) {
                            print("DynamicIsland IPC error parsing JSON: " + e);
                        }
                    }

                    function clear(): void {
                        logic.clearQueue();
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
                    id: hoverExitTimer

                    interval: 2000
                    repeat: false
                    onTriggered: islandContainer.manualExpanded = false
                }

                // The Island Pill
                Item {
                    // Scale Logic
                    // Controlled centrally by islandContainer.islandVisible

                    id: islandPill

                    property int renderMode: islandContainer.mode
                    readonly property real targetScale: islandContainer.islandVisible ? (islandContainer.islandHovered && !islandContainer.expanded && renderMode === 0 ? 1.06 : 1) : 0
                    readonly property bool renderActive: islandContainer.islandVisible || pillScaleAnim.running || pillWidthAnim.running || pillHeightAnim.running || scale > 0.01
                    // Track if we need to shake when mode 3 becomes visible
                    property bool pendingBadShake: false
                    // Size Logic
                    TextMetrics {
                        id: titleMetrics
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: MprisController.activeTrack ? MprisController.activeTrack.title || "" : ""
                    }

                    TextMetrics {
                        id: clockMetrics
                        font.family: Appearance.font.family.numbers
                        font.features: { "tnum": 1 }
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: islandContainer.currentTime || ""
                    }
                    
                    // Media (Album Art on left, Visualizer on right): 140
                    property real dynamicMediaWidth: 140
                    
                    // Clock only: Icon (15) + spacing (7) + clockMetrics + padding (32) = clockMetrics + 54
                    property real dynamicIdleWidth: Math.max(clockMetrics.advanceWidth + 54, 115)
                    
                    property real collapsedWidth: islandContainer.hasMedia ? dynamicMediaWidth : dynamicIdleWidth
                    property real collapsedHeight: 36
                    property bool pomodoroActive: TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)
                    property bool stopwatchActive: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0
                    property bool downloadActive: DownloadService.active
                    property bool timerActive: pomodoroActive || stopwatchActive
                    // Mode specific sizes
                    property real expandedWidth: {
                        if (islandPill.renderMode === 1 || islandPill.renderMode === 2)
                            return 280; // Volume/Brightness
                        if (islandPill.renderMode === 3)
                            return 340; // Notification / Popup
                        if (islandPill.renderMode === 4)
                            return 290; // Battery
                        return 370;
                    }
                    property real expandedHeight: {
                        if (islandPill.renderMode === 1 || islandPill.renderMode === 2)
                            return 52; // M3 Pill height
                        if (islandPill.renderMode === 3)
                            return 60; // Popup (M3 Expressive)
                        if (islandPill.renderMode === 4)
                            return 56; // Battery
                        return 165;
                    }

                    readonly property bool contentExpandedReady: islandContainer.expanded
                        && islandPill.renderMode === 0
                        && (islandPill.height >= 90 || !pillHeightAnim.running)

                    anchors.top: parent.top
                    anchors.topMargin: islandContainer.floatingTopMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: 0 // For Shake Animation
                    visible: renderActive
                    enabled: renderActive
                    scale: targetScale
                    transformOrigin: Item.Top
                    width: (islandContainer.expanded || islandPill.renderMode !== 0) ? expandedWidth : collapsedWidth
                    height: (islandContainer.expanded || islandPill.renderMode !== 0) ? expandedHeight : collapsedHeight
                    clip: true
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

                    // Island background
                    Rectangle {
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
                        property real cornerRadius: Math.min(height / 2, islandContainer.expanded ? 24 : 18)

                        Behavior on cornerRadius {
                            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                        }

                        anchors.fill: parent
                        radius: cornerRadius
                        color: bgColor
                        border.width: 1
                        border.color: isBadPopup ? ColorUtils.applyAlpha(Appearance.colors.colError, 0.25) : Appearance.colors.colLayer0Border

                        Behavior on bgColor {
                            ColorAnimation {
                                duration: 200
                            }

                        }

                        // Full-bleed album art ambient background across the entire island
                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: islandBackground.width
                                    height: islandBackground.height
                                    radius: islandBackground.radius
                                }
                            }

                            Image {
                                id: islandFullBgArt
                                anchors.fill: parent
                                source: (islandContainer.hasMedia && islandContainer.expanded && islandContainer.expandedPageKey === "media") ? dynamicMediaColorContext.displayedArtFilePath : ""
                                fillMode: Image.PreserveAspectCrop
                                opacity: (source !== "" && status === Image.Ready) ? 0.35 : 0.0
                                visible: opacity > 0.0
                                asynchronous: true

                                Behavior on opacity {
                                    NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: islandFullBgArt.opacity > 0.0
                                opacity: islandFullBgArt.opacity > 0.0 ? 1.0 : 0.0
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.40) }
                                    GradientStop { position: 0.55; color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.70) }
                                    GradientStop { position: 1.0; color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.92) }
                                }

                                Behavior on opacity {
                                    NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: islandExpandClickArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (islandContainer.mode === 0 && !islandContainer.effectiveHasPopup)
                                islandContainer.manualExpanded = true;
                        }
                    }

                    // Collapsed content
                    Item {
                        // anchors.margins: 12

                        id: collapsedContent

                        readonly property bool showCollapsed: (islandContainer.mode === 3)
                            || (islandContainer.mode === 0 && !islandContainer.expanded && (islandPill.height <= 60 || !pillHeightAnim.running))

                        anchors.fill: parent
                        visible: opacity > 0
                        opacity: showCollapsed ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 80
                                easing.type: Easing.OutQuad
                            }
                        }

                        // Standard Mode Content
                        Loader {
                            // No second separator needed as we are mutually exclusive now

                            active: islandPill.renderActive && islandPill.renderMode === 0 && (collapsedContent.showCollapsed || collapsedContent.opacity > 0)
                            anchors.fill: parent

                            sourceComponent: Item {
                                anchors.fill: parent

                                // Media Layout (Album Art on LEFT end, Visualizer on RIGHT end)
                                Item {
                                    id: mediaLayout
                                    anchors.fill: parent
                                    visible: islandContainer.hasMedia

                                    // Mini Album Art with OpacityMask rounded corners (anchored left)
                                    Item {
                                        id: miniArtWrapper
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        width: 22
                                        height: 22

                                        Rectangle {
                                            id: miniArtContainer
                                            anchors.fill: parent
                                            radius: 6
                                            color: dynamicMediaColorContext.pillColor || Appearance.colors.colPrimaryContainer

                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: miniArtContainer.width
                                                    height: miniArtContainer.height
                                                    radius: miniArtContainer.radius
                                                }
                                            }

                                            Image {
                                                id: miniArtImage
                                                anchors.fill: parent
                                                source: {
                                                    let p = dynamicMediaColorContext.displayedArtFilePath;
                                                    if (!p) return "";
                                                    return (p.startsWith("file://") || p.startsWith("http")) ? p : ("file://" + p);
                                                }
                                                fillMode: Image.PreserveAspectCrop
                                                visible: status === Image.Ready && source != ""
                                                asynchronous: true
                                            }

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                visible: !miniArtImage.visible
                                                text: "music_note"
                                                iconSize: 14
                                                fill: 1
                                                color: dynamicMediaColorContext.pillContentColor || Appearance.colors.colOnPrimaryContainer
                                            }
                                        }
                                    }

                                    // Equalizer Visualizer (anchored right)
                                    Item {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        width: 20
                                        height: 16

                                        Row {
                                            id: islandPillVisualizer
                                            anchors.centerIn: parent
                                            visible: MprisController.isPlaying
                                            spacing: 2

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
                                                        const pts = islandPillVisualizer.points;
                                                        return (pts && pts.length > 0) ? (pts[1 + (index * 3)] || 0) : 0;
                                                    }
                                                    property real normVal: Math.max(0.18, Math.min(1.0, rawVal / 1000))
                                                    height: Math.max(width * 1.3, normVal * 16)
                                                }
                                            }
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: !MprisController.isPlaying
                                            text: "pause"
                                            iconSize: 14
                                            fill: 1
                                            color: Appearance.colors.colOnLayer0
                                            opacity: 0.6
                                        }
                                    }
                                }

                                // Idle Row (Clock Icon + Time)
                                RowLayout {
                                    id: idleRow
                                    anchors.centerIn: parent
                                    visible: !islandContainer.hasMedia
                                    spacing: 7

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "schedule"
                                        iconSize: 15
                                        fill: 1
                                        color: Appearance.colors.colPrimary
                                        opacity: 0.9
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignVCenter
                                        transform: Translate { y: 1 }
                                        text: islandContainer.currentTime
                                        font.family: Appearance.font.family.numbers
                                        font.features: { "tnum": 1 }
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }

                        }

                        // Popup Mode Content (Material 3 Expressive Alert Pill)
                        Loader {
                            active: islandPill.renderActive && islandPill.renderMode === 3
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 14
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8

                            sourceComponent: RowLayout {
                                spacing: 12

                                readonly property bool isBad: islandBackground.isBadPopup

                                // Determine shape based on severity/category
                                readonly property int iconShape: {
                                    if (isBad || islandContainer.popupType === "bad")
                                        return MaterialShape.Shape.Cookie4Sided;
                                    if (islandContainer.popupAction === "complete" || islandContainer.popupType === "good")
                                        return MaterialShape.Shape.VerySunny;
                                    return MaterialShape.Shape.Square; // Squirclish rounded in M3
                                }

                                // Theme colors for Icon container — per-category M3 Fixed color matrix
                                // All badges use light container + dark icon for visual consistency
                                readonly property color containerColor: {
                                    // Error / bad → light pink badge (colError is the semantic accent, bright on surface)
                                    if (isBad || islandContainer.popupType === "bad")
                                        return Appearance.colors.colError;
                                    // Success / good / download / pomodoro → light mint badge
                                    if (islandContainer.popupType === "good" ||
                                        islandContainer.popupCategory === "download" ||
                                        islandContainer.popupCategory === "pomodoro")
                                        return Appearance.m3colors.m3success;
                                    // Bluetooth / wifi → secondary fixed (cool neutral cream)
                                    if (islandContainer.popupCategory === "bluetooth" ||
                                        islandContainer.popupCategory === "wifi")
                                        return Appearance.m3colors.m3secondaryFixed;
                                    // Media / notification / message / mail → primary fixed (warm cream)
                                    if (islandContainer.popupCategory === "media" ||
                                        islandContainer.popupCategory === "notification" ||
                                        islandContainer.popupCategory === "message" ||
                                        islandContainer.popupCategory === "mail")
                                        return Appearance.m3colors.m3primaryFixed;
                                    // Clipboard / screenshot / update / keyboard → tertiary fixed (warm cream)
                                    if (islandContainer.popupCategory === "clipboard" ||
                                        islandContainer.popupCategory === "screenshot" ||
                                        islandContainer.popupCategory === "update" ||
                                        islandContainer.popupCategory === "keyboard")
                                        return Appearance.m3colors.m3tertiaryFixed;
                                    // Battery charging in popup form → light mint
                                    if (islandContainer.popupCategory === "battery" &&
                                        islandContainer.popupAction === "charging")
                                        return Appearance.m3colors.m3success;
                                    // Default → primary fixed (vibrant, always readable)
                                    return Appearance.m3colors.m3primaryFixed;
                                }

                                readonly property color onContainerColor: {
                                    // Dark red icon on light pink badge
                                    if (isBad || islandContainer.popupType === "bad")
                                        return Appearance.colors.colOnError;
                                    // Dark green icon on light mint badge
                                    if (islandContainer.popupType === "good" ||
                                        islandContainer.popupCategory === "download" ||
                                        islandContainer.popupCategory === "pomodoro")
                                        return Appearance.m3colors.m3onSuccess;
                                    if (islandContainer.popupCategory === "bluetooth" ||
                                        islandContainer.popupCategory === "wifi")
                                        return Appearance.m3colors.m3onSecondaryFixed;
                                    if (islandContainer.popupCategory === "media" ||
                                        islandContainer.popupCategory === "notification" ||
                                        islandContainer.popupCategory === "message" ||
                                        islandContainer.popupCategory === "mail")
                                        return Appearance.m3colors.m3onPrimaryFixed;
                                    if (islandContainer.popupCategory === "clipboard" ||
                                        islandContainer.popupCategory === "screenshot" ||
                                        islandContainer.popupCategory === "update" ||
                                        islandContainer.popupCategory === "keyboard")
                                        return Appearance.m3colors.m3onTertiaryFixed;
                                    if (islandContainer.popupCategory === "battery" &&
                                        islandContainer.popupAction === "charging")
                                        return Appearance.m3colors.m3onSuccess;
                                    return Appearance.m3colors.m3onPrimaryFixed;
                                }

                                // Contextual badge string
                                readonly property string badgeText: {
                                    if (islandContainer.popupCategory === "microphone" && islandContainer.popupAction === "muted")
                                        return "MUTED";
                                    if (islandContainer.popupCategory === "battery" && islandContainer.popupAction === "low")
                                        return "LOW";
                                    if (islandContainer.popupCategory === "battery" && islandContainer.popupAction === "charging")
                                        return "CHARGING";
                                    if (islandContainer.popupCategory === "storage" && islandContainer.popupAction === "low")
                                        return "WARNING";
                                    if (islandContainer.popupCategory === "download" && islandContainer.popupAction === "complete")
                                        return "DONE";
                                    if (islandContainer.popupCategory === "screenshot")
                                        return "SAVED";
                                    return "";
                                }

                                // 1. M3 Expressive Icon Container (42x42)
                                Item {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42
                                    Layout.alignment: Qt.AlignVCenter

                                    MaterialShape {
                                        id: m3IconShape
                                        anchors.fill: parent
                                        implicitSize: 42
                                        shape: iconShape
                                        color: containerColor

                                        Behavior on color {
                                            ColorAnimation { duration: 200 }
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 22
                                        fill: 1
                                        color: onContainerColor
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
                                            default:
                                                if (islandContainer.popupType === "bad")
                                                    return "warning";
                                                if (islandContainer.popupType === "good")
                                                    return "check_circle";
                                                return "info";
                                            }
                                        }

                                        Behavior on color {
                                            ColorAnimation { duration: 200 }
                                        }
                                    }
                                }

                                // 2. Metadata & Text Block
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    // Title Row with Contextual Badge
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        StyledText {
                                            text: islandContainer.popupTitle
                                            color: isBad ? (Appearance.m3colors.m3onErrorContainer || Appearance.colors.colOnErrorContainer || Appearance.colors.colOnLayer0) : Appearance.colors.colOnLayer0
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        // Mini Tonal Badge
                                        Rectangle {
                                            visible: badgeText !== ""
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitHeight: 18
                                            implicitWidth: badgeLabel.implicitWidth + 12
                                            radius: 9
                                            color: containerColor

                                            StyledText {
                                                id: badgeLabel
                                                anchors.centerIn: parent
                                                text: badgeText
                                                font.pixelSize: 9
                                                font.weight: Font.Bold
                                                color: onContainerColor
                                            }
                                        }
                                    }

                                    // Subtitle / Message Text
                                    StyledText {
                                        text: islandContainer.popupMessage
                                        color: isBad ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        opacity: isBad ? 0.9 : 0.65
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

                        active: islandPill.renderActive && islandPill.renderMode === 0 && (islandContainer.expanded || opacity > 0)
                        visible: opacity > 0
                        opacity: islandPill.contentExpandedReady ? 1 : 0
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        sourceComponent: ColumnLayout {
                            id: expandedContent

                            // Dynamic Page List
                            property var activePages: {
                                var pages = [];

                                pages.push({
                                    "key": "idle",
                                    "component": idlePage
                                });

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
                                    islandContainer.expandedPageKey = "idle";
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

                            spacing: 6
                            onActivePagesChanged: Qt.callLater(syncSwipeToSavedPage)

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

                            Component {
                                id: idlePage

                                IdlePage {
                                    time: islandContainer.currentTime
                                    date: islandContainer.currentDate
                                }

                            }

                            // Page Indicator (Material Design 3 Expressive Pill Tabs)
                            Item {
                                id: islandPageIndicatorContainer
                                Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
                                Layout.preferredHeight: 26
                                implicitHeight: 26
                                Layout.fillWidth: true
                                visible: true

                                function getPageIcon(key) {
                                    if (key === "idle") return "schedule";
                                    if (key === "media") return "music_note";
                                    if (key === "pomodoro") return "hourglass_top";
                                    if (key === "stopwatch") return "timer";
                                    if (key === "download") return "download";
                                    return "circle";
                                }

                                function getPageLabel(key) {
                                    if (key === "idle") return "Clock";
                                    if (key === "media") return "Media";
                                    if (key === "pomodoro") return "Focus";
                                    if (key === "stopwatch") return "Stopwatch";
                                    if (key === "download") return "Downloads";
                                    return "";
                                }

                                function getPageContainerColor(key) {
                                    if (key === "idle") return Appearance.colors.colPrimaryContainer;
                                    if (key === "media") return dynamicMediaColorContext.pillColor || Appearance.colors.colPrimaryContainer;
                                    if (key === "pomodoro") return TimerService.pomodoroBreak ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer;
                                    if (key === "stopwatch") return Appearance.colors.colTertiaryContainer;
                                    if (key === "download") return Appearance.colors.colSecondaryContainer;
                                    return Appearance.colors.colPrimaryContainer;
                                }

                                function getPageOnContainerColor(key) {
                                    if (key === "idle") return Appearance.colors.colOnPrimaryContainer;
                                    if (key === "media") return dynamicMediaColorContext.pillContentColor || Appearance.colors.colOnPrimaryContainer;
                                    if (key === "pomodoro") return TimerService.pomodoroBreak ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer;
                                    if (key === "stopwatch") return Appearance.colors.colOnTertiaryContainer;
                                    if (key === "download") return Appearance.colors.colOnSecondaryContainer;
                                    return Appearance.colors.colOnPrimaryContainer;
                                }

                                Row {
                                    id: tabsRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Repeater {
                                        model: expandedContent.activePages

                                        Item {
                                            id: tabItem
                                            readonly property string pageKey: modelData.key || ""
                                            readonly property bool isActive: islandContainer.expandedPageKey === pageKey

                                            implicitHeight: 26
                                            height: 26
                                            implicitWidth: isActive ? (tabContentRow.implicitWidth + 20) : 30
                                            width: implicitWidth

                                            Behavior on implicitWidth {
                                                NumberAnimation {
                                                    duration: 240
                                                    easing.type: Easing.OutBack
                                                    easing.overshoot: 1.1
                                                }
                                            }

                                            Rectangle {
                                                id: tabBg
                                                anchors.fill: parent
                                                radius: 13
                                                color: tabItem.isActive
                                                    ? islandPageIndicatorContainer.getPageContainerColor(tabItem.pageKey)
                                                    : (tabMouseArea.containsMouse ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSurfaceContainerHigh)

                                                Behavior on color {
                                                    ColorAnimation { duration: 180 }
                                                }

                                                Row {
                                                    id: tabContentRow
                                                    anchors.centerIn: parent
                                                    spacing: 5

                                                    MaterialSymbol {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: islandPageIndicatorContainer.getPageIcon(tabItem.pageKey)
                                                        iconSize: 14
                                                        fill: 1
                                                        color: tabItem.isActive
                                                            ? islandPageIndicatorContainer.getPageOnContainerColor(tabItem.pageKey)
                                                            : Appearance.colors.colOnSurfaceVariant

                                                        Behavior on color {
                                                            ColorAnimation { duration: 180 }
                                                        }
                                                    }

                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: islandPageIndicatorContainer.getPageLabel(tabItem.pageKey)
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        font.weight: Font.DemiBold
                                                        color: islandPageIndicatorContainer.getPageOnContainerColor(tabItem.pageKey)
                                                        visible: tabItem.isActive
                                                        opacity: tabItem.isActive ? 1 : 0

                                                        Behavior on opacity {
                                                            NumberAnimation { duration: 150 }
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: tabMouseArea
                                                    anchors.fill: parent
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

                        }

                    }

                    // Volume Content (M3 Pill Slider)
                    Loader {
                        active: islandPill.renderActive && islandPill.renderMode === 1
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 14

                        sourceComponent: RowLayout {
                            spacing: 10

                            readonly property bool isMuted: Audio.sink && Audio.sink.audio && Audio.sink.audio.muted
                            readonly property color containerColor: isMuted ? Appearance.colors.colError : Appearance.m3colors.m3primaryFixed
                            readonly property color onContainerColor: isMuted ? Appearance.colors.colOnError : Appearance.m3colors.m3onPrimaryFixed

                            // 1. Tactile Squircle Icon Box (38x38) - Morphs to Cookie when muted
                            Item {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignVCenter

                                MaterialShape {
                                    anchors.fill: parent
                                    implicitSize: 38
                                    shape: isMuted ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Square
                                    color: containerColor

                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    fill: 1
                                    color: onContainerColor
                                    text: {
                                        if (isMuted) return "volume_off";
                                        if (Audio.value > 0.5) return "volume_up";
                                        if (Audio.value > 0) return "volume_down";
                                        return "volume_mute";
                                    }

                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }
                                }
                            }

                            // 2. M3 Thick Pill Slider
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
                                highlightColor: isMuted ? Appearance.colors.colError : Appearance.colors.colPrimary
                            }

                            // 3. Bold Percentage
                            StyledText {
                                text: {
                                    var v = Audio.value;
                                    return (isNaN(v) || v === undefined ? 0 : Math.round(v * 100)) + "%";
                                }
                                color: isMuted ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // Brightness Content (M3 Pill Slider)
                    Loader {
                        active: islandPill.renderActive && islandPill.renderMode === 2
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 14

                        sourceComponent: RowLayout {
                            spacing: 10

                            // 1. Tactile Squircle Icon Box (38x38)
                            Item {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignVCenter

                                MaterialShape {
                                    anchors.fill: parent
                                    implicitSize: 38
                                    shape: MaterialShape.Shape.Square
                                    color: Appearance.m3colors.m3tertiaryFixed

                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    fill: 1
                                    color: Appearance.m3colors.m3onTertiaryFixed
                                    text: {
                                        var val = 0;
                                        if (Brightness.monitors.length > 0) val = Brightness.monitors[0].brightness;
                                        if (val > 0.6) return "brightness_high";
                                        if (val > 0.3) return "brightness_medium";
                                        return "brightness_low";
                                    }
                                }
                            }

                            // 2. M3 Thick Pill Slider
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
                                highlightColor: Appearance.colors.colSecondary
                            }

                            // 3. Bold Percentage
                            StyledText {
                                text: {
                                    if (Brightness.monitors.length > 0)
                                        return Math.round(Brightness.monitors[0].brightness * 100) + "%";
                                    return "0%";
                                }
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                Layout.preferredWidth: 38
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    // Battery Content (M3 Expressive HUD)
                    Loader {
                        active: islandPill.renderActive && islandPill.renderMode === 4
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        anchors.topMargin: 7
                        anchors.bottomMargin: 7

                        sourceComponent: RowLayout {
                            spacing: 12

                            readonly property bool isCharging: islandContainer.isCharging
                            readonly property bool isLow: islandContainer.batteryPercent < 0.2 && !isCharging
                            readonly property bool isFull: islandContainer.batteryPercent >= 0.99

                            // Shape: VerySunny when charging, Cookie when low, Squircle when normal
                            readonly property int iconShape: {
                                if (isCharging) return MaterialShape.Shape.VerySunny;
                                if (isLow) return MaterialShape.Shape.Cookie4Sided;
                                return MaterialShape.Shape.Square;
                            }

                            readonly property color containerColor: {
                                if (isCharging) return Appearance.m3colors.m3success;
                                if (isLow) return Appearance.colors.colError;
                                return Appearance.m3colors.m3secondaryFixed;
                            }

                            readonly property color onContainerColor: {
                                if (isCharging) return Appearance.m3colors.m3onSuccess;
                                if (isLow) return Appearance.colors.colOnError;
                                return Appearance.m3colors.m3onSecondaryFixed;
                            }

                            readonly property string badgeText: {
                                if (isCharging) return isFull ? "FULL" : "CHARGING";
                                if (isLow) return "LOW";
                                return "BATTERY";
                            }

                            readonly property string subText: {
                                if (islandContainer.batterySource === "custom") return islandContainer.customBatteryName;
                                if (isCharging) return isFull ? "Fully charged • Plugged in" : "Fast Charging active";
                                if (isLow) return "Plug in charger soon";
                                return "Discharging on battery";
                            }

                            // 1. M3 Expressive Icon Container (40x40)
                            Item {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                Layout.alignment: Qt.AlignVCenter

                                MaterialShape {
                                    anchors.fill: parent
                                    implicitSize: 40
                                    shape: iconShape
                                    color: containerColor

                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 22
                                    fill: 1
                                    color: onContainerColor
                                    text: {
                                        if (isCharging) return "battery_charging_full";
                                        var p = islandContainer.batteryPercent;
                                        if (p >= 0.95) return "battery_full";
                                        if (p >= 0.85) return "battery_6_bar";
                                        if (p >= 0.7) return "battery_5_bar";
                                        if (p >= 0.55) return "battery_4_bar";
                                        if (p >= 0.4) return "battery_3_bar";
                                        if (p >= 0.25) return "battery_2_bar";
                                        if (p >= 0.1) return "battery_1_bar";
                                        return "battery_alert";
                                    }

                                    Behavior on color {
                                        ColorAnimation { duration: 200 }
                                    }
                                }
                            }

                            // 2. Battery Info Column (Pct + Tonal Badge + Subtext)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledText {
                                        text: Math.round(islandContainer.batteryPercent * 100) + "%"
                                        color: isLow ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                        font.weight: Font.Bold
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        Layout.fillWidth: true
                                    }

                                    // Mini Tonal Badge
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitHeight: 18
                                        implicitWidth: bBadgeLabel.implicitWidth + 12
                                        radius: 9
                                        color: containerColor

                                        StyledText {
                                            id: bBadgeLabel
                                            anchors.centerIn: parent
                                            text: badgeText
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: onContainerColor
                                        }
                                    }
                                }

                                StyledText {
                                    text: subText
                                    color: isLow ? Appearance.colors.colError : Appearance.colors.colOnLayer0
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    opacity: isLow ? 0.9 : 0.65
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Passive hover tracker keeps the compact pill available while moving from the trigger.
                    HoverHandler {
                        id: islandHoverTracker

                        margin: 0
                        blocking: false
                        onHoveredChanged: {
                            if (hovered) {
                                hoverExitTimer.stop();
                                islandContainer.isHovered = true;
                            } else {
                                hoverExitTimer.restart();
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

                // Island Satellite (Concept 3: Dynamic Glass Split Satellite)
                Item {
                    id: islandSatellite

                    readonly property var activeSatellitePages: {
                        var pages = [];
                        if (islandPill.pomodoroActive) pages.push("pomodoro");
                        if (islandPill.stopwatchActive) pages.push("stopwatch");
                        if (islandPill.downloadActive) pages.push("download");
                        return pages;
                    }

                    property int flipIndex: 0
                    readonly property string currentSatellitePage: activeSatellitePages.length > 0
                        ? activeSatellitePages[flipIndex % activeSatellitePages.length]
                        : "none"

                    property string lastActivePage: "pomodoro"
                    onCurrentSatellitePageChanged: {
                        if (currentSatellitePage !== "none") {
                            lastActivePage = currentSatellitePage;
                        }
                    }

                    readonly property bool satelliteActive: islandContainer.mode === 0
                        && !islandContainer.expanded
                        && islandContainer.islandVisible
                        && activeSatellitePages.length > 0

                    readonly property string displayedPage: satelliteActive ? currentSatellitePage : lastActivePage

                    function syncLayoutStates() {
                        var cur = displayedPage;
                        if (typeof pomodoroLayout !== "undefined" && pomodoroLayout) {
                            enterAnimPomo.stop();
                            exitAnimPomo.stop();
                            pomodoroLayout.opacity = (cur === "pomodoro") ? 1.0 : 0.0;
                            transPomo.y = 0;
                        }
                        if (typeof stopwatchLayout !== "undefined" && stopwatchLayout) {
                            enterAnimStopwatch.stop();
                            exitAnimStopwatch.stop();
                            stopwatchLayout.opacity = (cur === "stopwatch") ? 1.0 : 0.0;
                            transStopwatch.y = 0;
                        }
                        if (typeof downloadLayout !== "undefined" && downloadLayout) {
                            enterAnimDl.stop();
                            exitAnimDl.stop();
                            downloadLayout.opacity = (cur === "download") ? 1.0 : 0.0;
                            transDl.y = 0;
                        }
                    }

                    onSatelliteActiveChanged: {
                        if (satelliteActive) {
                            syncLayoutStates();
                        }
                    }

                    onActiveSatellitePagesChanged: {
                        if (flipIndex >= activeSatellitePages.length) {
                            flipIndex = 0;
                        }
                        if (satelliteActive) {
                            syncLayoutStates();
                        }
                    }

                    Timer {
                        id: satelliteFlipTimer
                        interval: 3500
                        running: islandSatellite.satelliteActive && islandSatellite.activeSatellitePages.length > 1 && !satelliteArea.containsMouse
                        repeat: true
                        onTriggered: {
                            islandSatellite.flipIndex = (islandSatellite.flipIndex + 1) % islandSatellite.activeSatellitePages.length;
                        }
                    }

                    readonly property real activeWidth: {
                        if (displayedPage === "download") return 78;
                        return 92;
                    }

                    readonly property bool hovered: satelliteArea.containsMouse

                    anchors.verticalCenter: islandPill.verticalCenter
                    anchors.left: islandPill.right
                    height: 36
                    visible: false

                    Behavior on width {
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            id: satelliteScaleAnim
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    states: [
                        State {
                            name: "active"
                            when: islandSatellite.satelliteActive
                            PropertyChanges {
                                target: islandSatellite
                                width: islandSatellite.activeWidth
                                scale: islandSatellite.hovered ? 1.08 : 1.0
                                opacity: 1.0
                                anchors.leftMargin: 8
                                visible: true
                            }
                        },
                        State {
                            name: "inactive"
                            when: !islandSatellite.satelliteActive
                            PropertyChanges {
                                target: islandSatellite
                                width: 0
                                scale: 0.8
                                opacity: 0.0
                                anchors.leftMargin: 0
                                visible: false
                            }
                        }
                    ]

                    transitions: [
                        Transition {
                            from: "active"; to: "inactive"
                            SequentialAnimation {
                                PropertyAction { target: islandSatellite; property: "visible"; value: true }
                                ParallelAnimation {
                                    NumberAnimation { target: islandSatellite; property: "width"; duration: 320; easing.type: Easing.InOutCubic }
                                    NumberAnimation { target: islandSatellite; property: "anchors.leftMargin"; duration: 300; easing.type: Easing.InOutCubic }
                                    NumberAnimation { target: islandSatellite; property: "scale"; duration: 320; easing.type: Easing.InCubic }
                                    SequentialAnimation {
                                        PauseAnimation { duration: 120 }
                                        NumberAnimation { target: islandSatellite; property: "opacity"; duration: 200; easing.type: Easing.OutQuad }
                                    }
                                }
                                PropertyAction { target: islandSatellite; property: "visible"; value: false }
                            }
                        },
                        Transition {
                            from: "inactive"; to: "active"
                            SequentialAnimation {
                                ScriptAction { script: islandSatellite.syncLayoutStates() }
                                PropertyAction { target: islandSatellite; property: "visible"; value: true }
                                ParallelAnimation {
                                    NumberAnimation { target: islandSatellite; property: "width"; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                                    NumberAnimation { target: islandSatellite; property: "anchors.leftMargin"; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                                    NumberAnimation { target: islandSatellite; property: "scale"; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                                    NumberAnimation { target: islandSatellite; property: "opacity"; duration: 240; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    ]

                    // Background glass capsule
                    Rectangle {
                        id: satelliteBackground
                        anchors.fill: parent
                        radius: height / 2
                        color: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.88)
                        border.width: 1
                        border.color: islandSatellite.hovered
                            ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.35)
                            : ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.15)

                        Behavior on border.color {
                            ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                    }

                    // Satellite Contents with smooth flip transition
                    Item {
                        anchors.fill: parent
                        clip: true

                        // 1. Pomodoro
                        RowLayout {
                            id: pomodoroLayout
                            anchors.centerIn: parent
                            spacing: 6
                            opacity: 0.0
                            visible: opacity > 0.001

                            readonly property bool isCurrent: islandSatellite.displayedPage === "pomodoro"
                            onIsCurrentChanged: {
                                if (!islandSatellite.satelliteActive) {
                                    opacity = isCurrent ? 1.0 : 0.0;
                                    transPomo.y = 0;
                                    return;
                                }
                                if (isCurrent) {
                                    exitAnimPomo.stop();
                                    enterAnimPomo.restart();
                                } else {
                                    enterAnimPomo.stop();
                                    exitAnimPomo.restart();
                                }
                            }

                            Connections {
                                target: islandSatellite
                                function onSatelliteActiveChanged() {
                                    if (islandSatellite.satelliteActive && pomodoroLayout.isCurrent) {
                                        exitAnimPomo.stop();
                                        enterAnimPomo.stop();
                                        pomodoroLayout.opacity = 1.0;
                                        transPomo.y = 0;
                                    }
                                }
                            }

                            Component.onCompleted: {
                                opacity = isCurrent ? 1.0 : 0.0;
                                transPomo.y = 0;
                            }

                            transform: Translate {
                                id: transPomo
                                y: 0
                            }

                            ParallelAnimation {
                                id: enterAnimPomo
                                NumberAnimation { target: transPomo; property: "y"; from: 14; to: 0; duration: 360; easing.type: Easing.OutCubic }
                                NumberAnimation { target: pomodoroLayout; property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                            }

                            ParallelAnimation {
                                id: exitAnimPomo
                                NumberAnimation { target: transPomo; property: "y"; from: 0; to: -14; duration: 280; easing.type: Easing.InCubic }
                                NumberAnimation { target: pomodoroLayout; property: "opacity"; from: 1.0; to: 0.0; duration: 220; easing.type: Easing.OutQuad }
                            }

                            CircularProgress {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                value: TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration
                                colPrimary: TimerService.isPomodoroBreak ? Appearance.colors.colOnLayer0 : Appearance.colors.colError
                                implicitSize: 16
                                lineWidth: 2
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: {
                                    let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                                    let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                                    return m + ":" + s;
                                }
                                color: TimerService.isPomodoroBreak ? Appearance.colors.colOnLayer0 : Appearance.colors.colError
                                font.family: Appearance.font.family.monospace
                                font.features: { "tnum": 1 }
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                        }

                        // 2. Stopwatch / Timer
                        RowLayout {
                            id: stopwatchLayout
                            anchors.centerIn: parent
                            spacing: 6
                            opacity: 0.0
                            visible: opacity > 0.001

                            readonly property bool isCurrent: islandSatellite.displayedPage === "stopwatch"
                            onIsCurrentChanged: {
                                if (!islandSatellite.satelliteActive) {
                                    opacity = isCurrent ? 1.0 : 0.0;
                                    transStopwatch.y = 0;
                                    return;
                                }
                                if (isCurrent) {
                                    exitAnimStopwatch.stop();
                                    enterAnimStopwatch.restart();
                                } else {
                                    enterAnimStopwatch.stop();
                                    exitAnimStopwatch.restart();
                                }
                            }

                            Connections {
                                target: islandSatellite
                                function onSatelliteActiveChanged() {
                                    if (islandSatellite.satelliteActive && stopwatchLayout.isCurrent) {
                                        exitAnimStopwatch.stop();
                                        enterAnimStopwatch.stop();
                                        stopwatchLayout.opacity = 1.0;
                                        transStopwatch.y = 0;
                                    }
                                }
                            }

                            Component.onCompleted: {
                                opacity = isCurrent ? 1.0 : 0.0;
                                transStopwatch.y = 0;
                            }

                            transform: Translate {
                                id: transStopwatch
                                y: 0
                            }

                            ParallelAnimation {
                                id: enterAnimStopwatch
                                NumberAnimation { target: transStopwatch; property: "y"; from: 14; to: 0; duration: 360; easing.type: Easing.OutCubic }
                                NumberAnimation { target: stopwatchLayout; property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                            }

                            ParallelAnimation {
                                id: exitAnimStopwatch
                                NumberAnimation { target: transStopwatch; property: "y"; from: 0; to: -14; duration: 280; easing.type: Easing.InCubic }
                                NumberAnimation { target: stopwatchLayout; property: "opacity"; from: 1.0; to: 0.0; duration: 220; easing.type: Easing.OutQuad }
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "timer"
                                iconSize: 16
                                fill: 1
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: {
                                    let t = TimerService.stopwatchTime / 100;
                                    let m = Math.floor(t / 60).toString().padStart(2, '0');
                                    let s = Math.floor(t % 60).toString().padStart(2, '0');
                                    return m + ":" + s;
                                }
                                color: Appearance.colors.colPrimary
                                font.family: Appearance.font.family.monospace
                                font.features: { "tnum": 1 }
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                        }

                        // 3. Download
                        RowLayout {
                            id: downloadLayout
                            anchors.centerIn: parent
                            spacing: 4
                            opacity: 0.0
                            visible: opacity > 0.001

                            readonly property bool isCurrent: islandSatellite.displayedPage === "download"
                            onIsCurrentChanged: {
                                if (!islandSatellite.satelliteActive) {
                                    opacity = isCurrent ? 1.0 : 0.0;
                                    transDl.y = 0;
                                    return;
                                }
                                if (isCurrent) {
                                    exitAnimDl.stop();
                                    enterAnimDl.restart();
                                } else {
                                    enterAnimDl.stop();
                                    exitAnimDl.restart();
                                }
                            }

                            Connections {
                                target: islandSatellite
                                function onSatelliteActiveChanged() {
                                    if (islandSatellite.satelliteActive && downloadLayout.isCurrent) {
                                        exitAnimDl.stop();
                                        enterAnimDl.stop();
                                        downloadLayout.opacity = 1.0;
                                        transDl.y = 0;
                                    }
                                }
                            }

                            Component.onCompleted: {
                                opacity = isCurrent ? 1.0 : 0.0;
                                transDl.y = 0;
                            }

                            transform: Translate {
                                id: transDl
                                y: 0
                            }

                            ParallelAnimation {
                                id: enterAnimDl
                                NumberAnimation { target: transDl; property: "y"; from: 14; to: 0; duration: 360; easing.type: Easing.OutCubic }
                                NumberAnimation { target: downloadLayout; property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                            }

                            ParallelAnimation {
                                id: exitAnimDl
                                NumberAnimation { target: transDl; property: "y"; from: 0; to: -14; duration: 280; easing.type: Easing.InCubic }
                                NumberAnimation { target: downloadLayout; property: "opacity"; from: 1.0; to: 0.0; duration: 220; easing.type: Easing.OutQuad }
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "download"
                                iconSize: 15
                                fill: 1
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: Math.round(DownloadService.progress * 100) + "%"
                                font.family: Appearance.font.family.monospace
                                font.features: { "tnum": 1 }
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // Mouse Area for Satellite interactions
                    MouseArea {
                        id: satelliteArea
                        anchors.fill: parent
                        enabled: islandSatellite.satelliteActive
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (islandSatellite.currentSatellitePage === "pomodoro") {
                                islandContainer.expandedPageKey = "pomodoro";
                                islandContainer.manualExpanded = true;
                            } else if (islandSatellite.currentSatellitePage === "stopwatch") {
                                islandContainer.expandedPageKey = "stopwatch";
                                islandContainer.manualExpanded = true;
                            } else if (islandSatellite.currentSatellitePage === "download") {
                                islandContainer.expandedPageKey = "download";
                                islandContainer.manualExpanded = true;
                            }
                        }
                        onWheel: (wheel) => {
                            if (islandSatellite.activeSatellitePages.length > 1) {
                                if (wheel.angleDelta.y > 0) {
                                    islandSatellite.flipIndex = (islandSatellite.flipIndex + 1) % islandSatellite.activeSatellitePages.length;
                                } else {
                                    islandSatellite.flipIndex = (islandSatellite.flipIndex - 1 + islandSatellite.activeSatellitePages.length) % islandSatellite.activeSatellitePages.length;
                                }
                            }
                        }
                        onEntered: hoverExitTimer.stop()
                        onExited: hoverExitTimer.restart()
                    }

                    layer.enabled: true
                    layer.effect: StyledDropShadow {
                        target: islandSatellite
                    }
                }

                function updateClockStrings() {
                    var now = new Date();
                    islandContainer.currentTime = Qt.formatTime(now, "h:mm AP");
                    islandContainer.currentTimeWithSeconds = Qt.formatTime(now, "h:mm:ss AP");
                    islandContainer.currentDate = Qt.formatDate(now, "ddd, MMM d");
                }

                Timer {
                    interval: 1000
                    running: islandContainer.islandVisible
                    repeat: true
                    onTriggered: islandContainer.updateClockStrings()
                }

                Connections {
                    target: islandContainer
                    function onIslandVisibleChanged() {
                        if (islandContainer.islandVisible) {
                            islandContainer.updateClockStrings();
                        }
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
