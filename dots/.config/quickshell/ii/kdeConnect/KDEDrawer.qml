import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common.widgets
import qs.modules.common
import qs.modules.common.functions

Scope {
    id: kdeRoot

    // --- State ---
    property bool isOpen: false
    property bool userActive: false
    property string activeDeviceId: ""
    property string deviceName: "Searching..."
    property int batteryPercent: -1
    property bool batteryCharging: false
    property bool deviceOnline: false
    property var availableDevices: []

    // Cursor-based corner trigger (for non-drag case)
    property int cursorX: -1
    property int cursorY: -1
    property bool drawerHovered: false
    property bool openedFromCorner: false  // Track if opened from corner
    property bool isTransferring: false     // Track file transfer in progress vs edge
    property bool isPillVisible: false      // Autohide state
    property bool isDragging: false         // Global drag state tracking
    property bool closeBlockedByTransfer: false
    property int transferPendingCount: 0
    property int transferSuccessCount: 0
    property int transferFailureCount: 0
    property string transferStatusText: ""
    property string currentTransferFile: ""
    property var transferQueue: []
    property int slowCornerPollMs: 900
    property int fastCornerPollMs: 250
    property int nearCornerThresholdPx: 180

    function canCloseDrawer() {
        return !isTransferring && !transferProcess.running && transferQueue.length === 0;
    }

    function requestCloseDrawer() {
        if (canCloseDrawer()) {
            isOpen = false;
            openedFromCorner = false;
            userActive = false;
            return true;
        }
        closeBlockedByTransfer = true;
        closeBlockedTimer.restart();
        return false;
    }

    function deviceNameForId(deviceId) {
        for (const dev of availableDevices) {
            if (dev.id === deviceId) return dev.name;
        }
        return "";
    }

    function selectedDeviceIndex() {
        for (let i = 0; i < availableDevices.length; i++) {
            if (availableDevices[i].id === activeDeviceId) return i;
        }
        return availableDevices.length > 0 ? 0 : -1;
    }

    function urlsToPaths(urls) {
        const paths = [];
        for (const rawUrl of urls) {
            const asString = rawUrl.toString();
            if (asString.startsWith("file://")) paths.push(asString.replace("file://", ""));
        }
        return paths;
    }

    function startTransfers(paths) {
        if (!activeDeviceId || paths.length === 0) return;
        if (isTransferring || transferProcess.running || transferQueue.length > 0) {
            transferQueue = transferQueue.concat(paths);
            transferPendingCount += paths.length;
            transferStatusText = "";
            return;
        }

        transferQueue = paths.slice();
        transferPendingCount = transferQueue.length;
        transferSuccessCount = 0;
        transferFailureCount = 0;
        transferStatusText = "";
        isTransferring = true;
        isOpen = true;
        userActive = true;
        closeBlockedByTransfer = false;
        closeTimer.stop();
        runNextTransfer();
    }

    function handleEdgeDragEnter(drag) {
        if (!drag.hasUrls) return;
        kdeRoot.isDragging = true;
        openedFromCorner = false;
        isOpen = true;
        isPillVisible = true;
        userActive = true;
        closeTimer.stop();
    }

    function handleEdgeDragExit() {
        kdeRoot.isDragging = false;
        if (!drawerHovered && !isTransferring) {
            userActive = false;
            closeTimer.restart();
        }
    }

    function handleEdgeDrop(drop) {
        kdeRoot.isDragging = false;
        const paths = drop.hasUrls ? urlsToPaths(drop.urls) : [];
        if (paths.length > 0) {
            startTransfers(paths);
            return;
        }
        if (!drawerHovered && !isTransferring) {
            userActive = false;
            closeTimer.restart();
        }
    }

    function runNextTransfer() {
        if (transferQueue.length === 0) {
            isTransferring = false;
            currentTransferFile = "";
            transferStatusText = transferFailureCount > 0
                ? `Sent ${transferSuccessCount}/${transferPendingCount} file(s), failed ${transferFailureCount}`
                : `Sent ${transferSuccessCount} file(s)`;
            transferStatusTimer.restart();
            if (!drawerHovered && !isDragging) {
                userActive = false;
                closeTimer.interval = 1200;
                closeTimer.restart();
            }
            return;
        }

        currentTransferFile = transferQueue[0];
        transferProcess.command = [
            "kdeconnect-cli",
            "--share",
            currentTransferFile,
            "--device",
            activeDeviceId
        ];
        transferProcess.running = true;
    }

    // --- Colors ---
    // --- Colors ---
    // Use transparent layer color for blur effect support
    property color backgroundColor: Appearance.colors.colLayer0
    property color cardColor: Appearance.colors.colLayer2
    property color textColor: Appearance.colors.colOnSurface
    property color textSecondary: Appearance.colors.colSubtext
    property color accentColor: Appearance.colors.colPrimary
    property color successColor: Appearance.m3colors.m3success
    property color warningColor: Appearance.m3colors.m3tertiary  // Warm/alert action
    
    // Material 3 Expressive colors
    property color m3PrimaryContainer: Appearance.m3colors.m3primaryContainer
    property color m3OnPrimaryContainer: Appearance.m3colors.m3onPrimaryContainer
    property color m3SecondaryContainer: Appearance.m3colors.m3secondaryContainer
    property color m3SurfaceContainerHigh: Appearance.m3colors.m3surfaceContainerHigh
    property color m3SurfaceContainerHighest: Appearance.m3colors.m3surfaceContainerHighest
    property color m3SurfaceContainer: Appearance.m3colors.m3surfaceContainer
    property color m3SurfaceVariant: Appearance.m3colors.m3surfaceVariant
    property color m3OnSurfaceVariant: Appearance.m3colors.m3onSurfaceVariant
    property color m3Outline: Appearance.m3colors.m3outline
    property color m3SuccessContainer: Appearance.m3colors.m3successContainer
    property color m3OnSuccessContainer: Appearance.m3colors.m3onSuccessContainer

    /* --- CLOSE TIMER (shared) --- */
    Timer {
        id: closeTimer
        interval: 500
        onTriggered: {
            // Close only when nothing is interacting with the drawer/hot-corner AND not transferring
            if (!userActive && canCloseDrawer()) {
                console.log(`KDE Debug: Closing drawer (timeout: ${interval}ms)`)
                isOpen = false
                openedFromCorner = false  // Reset flag when closing
            }
        }
    }

    Timer {
        id: closeBlockedTimer
        interval: 1400
        onTriggered: closeBlockedByTransfer = false
    }

    Timer {
        id: edgeOpenTimer
        interval: 140
        repeat: false
        onTriggered: {
            if (isOpen) return;
            openedFromCorner = false;
            isPillVisible = true;
            isOpen = true;
            userActive = true;
            closeTimer.stop();
        }
    }

    Timer {
        id: transferStatusTimer
        interval: 3500
        onTriggered: transferStatusText = ""
    }

    /* --- AUTOHIDE TIMER --- */
    Timer {
        id: autohideTimer
        interval: 3000
        running: isPillVisible && !isOpen && !drawerHovered
        onTriggered: {
            console.log("KDE: Autohiding pill due to inactivity")
            isPillVisible = false
        }
    }

    /* --- HOT CORNER POLL (Hyprland) --- */
    Timer {
        id: cornerPoll
        interval: slowCornerPollMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cursorPosProc.running) cursorPosProc.running = true;
        }
    }

    Process {
        id: cursorPosProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (!out.includes(",")) return
                const parts = out.split(",")
                cursorX = parseInt(parts[0])
                cursorY = parseInt(parts[1])

                // Compute the bottom-right corner across all screens
                let right = 0
                let bottom = 0
                for (const s of Quickshell.screens) {
                    const sx = (s.x ?? 0)
                    const sy = (s.y ?? 0)
                    right = Math.max(right, sx + s.width)
                    bottom = Math.max(bottom, sy + s.height)
                }

                // Only open at exact corner (no edge detection)
                const inCorner = cursorX >= right - 5 && cursorY >= bottom - 5
                const inPillZone = cursorX >= right - 72 && cursorX <= right - 12
                    && cursorY >= bottom - 72 && cursorY <= bottom - 12
                const nearCorner = cursorX >= right - nearCornerThresholdPx && cursorY >= bottom - nearCornerThresholdPx
                cornerPoll.interval = (nearCorner || isOpen || isDragging || isTransferring) ? fastCornerPollMs : slowCornerPollMs;

                if (inCorner) {
                    // Wake up the pill
                    isPillVisible = true
                    autohideTimer.restart()
                    edgeOpenTimer.stop()
                } else if (inPillZone && isPillVisible) {
                    if (!isOpen && !edgeOpenTimer.running) edgeOpenTimer.start()
                } else if (!drawerHovered && !isTransferring && !isDragging) {
                    edgeOpenTimer.stop()
                    // Don't close during file transfers - let transferCompleteTimer handle it
                    // Corner-opened drawers get extended timeout for file dropping
                    closeTimer.interval = 2000  // 2 seconds for corner-opened drawers
                    if (isOpen) {  // Only set inactive if currently open
                        userActive = false
                        closeTimer.start()
                    }
                }
            }
        }
    }

    /* --- BACKEND --- */
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (statusScript.running) return;
            const bridgeScript = Qt.resolvedUrl("kde_bridge.py").toString().replace("file://", "");
            statusScript.command = activeDeviceId
                ? ["python3", bridgeScript, activeDeviceId]
                : ["python3", bridgeScript];
            statusScript.running = true;
        }
    }

    Process {
        id: statusScript
        command: ["python3", Qt.resolvedUrl("kde_bridge.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: (data) => {
                if (data.trim() === "") return
                try {
                    const res = JSON.parse(data)
                    availableDevices = res.devices ?? []
                    deviceOnline = Boolean(res.found)
                    if (res.id) activeDeviceId = res.id
                    deviceName = res.name ?? "No Device"
                    batteryPercent = (res.battery ?? -1)
                    batteryCharging = Boolean(res.charging)
                } catch (e) {
                    console.log("KDE Bridge JSON Error:", e)
                }
            }
        }
    }


    Timer {
        id: delayedTransferTimer
        interval: 800 // Give the UI 800ms to show the spinner per file
        onTriggered: runNextTransfer()
    }

    Process {
        id: transferProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) transferSuccessCount += 1;
            else {
                transferFailureCount += 1;
                console.log("KDE: Transfer failed for", currentTransferFile, "exit", exitCode, exitStatus);
            }
            transferQueue = transferQueue.slice(1);
            // Delay the next transfer loop to ensure the UI progress is visible
            delayedTransferTimer.start();
        }
    }

    /* --- WINDOW --- */
    Variants {
        model: Quickshell.screens

        /* --- DEBUG CORNER AREA (shows trigger zone) ---
           Using console logging instead of visual window since PanelWindow positioning is limited
        */

        PanelWindow {
            id: dragTriggerPanel
            required property var modelData
            screen: modelData
            anchors { right: true; bottom: true }
            visible: isOpen || isPillVisible

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "kde-connect-drawer-drag-trigger"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            color: "transparent"
            implicitWidth: 96
            implicitHeight: 96

            DropArea {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 20
                anchors.bottomMargin: 20
                width: 56
                height: 56
                enabled: isPillVisible
                onEntered: drag => handleEdgeDragEnter(drag)
                onExited: handleEdgeDragExit()
                onDropped: drop => handleEdgeDrop(drop)
            }
        }

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            anchors { right: true; bottom: true }

            // Only exist as a surface while open or actively in use
            // This prevents it from blocking clicks when the drawer is "closed"
            // Unmap the layer when idle to avoid constant compositor work.
            visible: isOpen || isPillVisible

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "kde-connect-drawer"
            WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            color: "transparent"
            implicitWidth: 420
            implicitHeight: 620

            // Mask the window to the drawer shape (pill or full) so clicks pass through empty space
            mask: Region { item: drawer }

            // NOTE: Quickshell's `Region.fromRect(...)` isn't available here; keep mask simple.
            // If you want a shape-limited mask later, we can switch to `mask: Region { item: drawer }`.

/* --- CORNER MOUSE TRIGGER handled by hotCornerPanel --- */
            /* --- DRAWER --- */
            Item {
                anchors.fill: parent

                // Robust hover tracking that ignores child event stealing
                HoverHandler {
                    id: drawerHoverTracker
                    blocking: false
                    // We don't use onHoveredChanged because it fires falsely when children take focus.
                    // Instead, we just let it passively track the hovered state.
                }

                Timer {
                    id: hoverDebounceTimer
                    interval: 100
                    running: true
                    repeat: true
                    onTriggered: {
                        // If the drawer or the extended area is hovered, stay open
                        if (drawerHoverTracker.hovered || (openedFromCorner && extendedHoverTracker.hovered)) {
                            drawerHovered = true
                            userActive = true
                            closeTimer.stop()
                        } else {
                            if (drawerHovered) { // Transitioning from hovered to not hovered
                                drawerHovered = false
                                userActive = false
                                closeTimer.interval = openedFromCorner ? 2000 : 1200
                                closeTimer.restart()
                            }
                        }
                    }
                }

                // Extended hover area when opened from corner (for file dropping)
                Item {
                    anchors.fill: parent
                    anchors.margins: openedFromCorner ? -100 : 0
                    visible: openedFromCorner

                    HoverHandler {
                        id: extendedHoverTracker
                        blocking: false
                    }
                }

                Rectangle {
                    id: drawer
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        rightMargin: 20
                        bottomMargin: 20
                    }
                    width: isOpen ? 380 : (isPillVisible ? 48 : 0)
                    height: isOpen ? 600 : (isPillVisible ? 48 : 0)
                    radius: isOpen ? 32 : 24
                    color: backgroundColor
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    clip: true // Prevents content from spilling during animation
                    
                    layer.enabled: true
                    layer.effect: StyledDropShadow {
                        target: drawer
                    }

                    Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                    Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                    focus: isOpen
                    activeFocusOnTab: isOpen

                    Keys.onEscapePressed: event => {
                        requestCloseDrawer()
                        event.accepted = true
                    }
                    
                    // Open on Hover (only active when pill is shown)
                    MouseArea {
                        anchors.fill: parent
                        visible: !isOpen  // Hide completely when open so clicks pass through
                        enabled: isPillVisible
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                             isOpen = true
                             openedFromCorner = true
                             userActive = true
                             closeTimer.stop()
                             isPillVisible = true // Keep it visible
                        }
                        // Also wake up if clicked (fallback)
                        onClicked: {
                             isOpen = true
                             openedFromCorner = true
                             userActive = true
                             closeTimer.stop()
                        }
                    }

                    // Pill Icon (Visible only when closed)
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "smartphone"
                        color: accentColor
                        iconSize: 24
                        fill: 1  // Filled variant
                        opacity: (isOpen || !isPillVisible) ? 0 : 1 // Hide if open OR autohidden
                        scale: (isOpen || !isPillVisible) ? 0.5 : 1
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack } }
                    }

                    transformOrigin: Item.BottomRight
                    // Visible if: Online AND (Open OR PillVisible)
                    // We animate opacity for smooth toggle, but toggle visible to release input mask when hidden
                    opacity: (isOpen || isPillVisible || isDragging) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Behavior on scale {
                        NumberAnimation { duration: 450; easing.type: Easing.OutExpo }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16
                        opacity: isOpen ? 1 : 0 // Fade content out when closing
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Header - Redesigned with squircle icon and unified connection badge
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            // Device icon - squircle with soft lavender/purple container
                            Rectangle {
                                implicitWidth: 48
                                implicitHeight: 48
                                radius: 12
                                color: m3PrimaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "smartphone"
                                    color: m3OnPrimaryContainer
                                    iconSize: 24
                                    fill: 1  // Filled variant
                                }
                            }

                            // Device details column
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Device title
                                StyledText {
                                    text: deviceName
                                    color: textColor
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    Layout.fillWidth: true
                                }

                                // Connection badge - unified pill
                                Rectangle {
                                    implicitWidth: connectedRow.implicitWidth + 20
                                    implicitHeight: 24
                                    radius: 12
                                    color: m3SuccessContainer
                                    visible: deviceOnline

                                    RowLayout {
                                        id: connectedRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        // Vibrant emerald green dot
                                        Rectangle {
                                            implicitWidth: 8
                                            implicitHeight: 8
                                            radius: 4
                                            color: successColor
                                        }

                                        // "Connected" text
                                        StyledText {
                                            text: "Connected"
                                            color: m3OnSuccessContainer
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                            }

                            // Expand button - circular with chevron
                            RippleButton {
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: 18
                                colBackground: "transparent"
                                colBackgroundHover: ColorUtils.applyAlpha(textColor, 0.08)

                                onClicked: {
                                    requestCloseDrawer()
                                }

                                contentItem: Item {
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "expand_more"
                                        color: textSecondary
                                        iconSize: 20
                                        fill: 1  // Filled variant
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: closeBlockedByTransfer
                            text: "Transfer in progress. Please wait before closing."
                            color: warningColor
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // Battery Card - Material 3 Expressive design
                        Rectangle {
                            Layout.fillWidth: true
                            height: 60
                            radius: 28
                            color: m3SurfaceContainerHigh

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 0

                                // Leading icon badge - 40dp squircle with secondary-container for depth
                                Rectangle {
                                    implicitWidth: 40
                                    implicitHeight: 40
                                    radius: 14
                                    color: m3SecondaryContainer

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: batteryCharging
                                            ? "battery_charging_full"
                                            : batteryPercent == -1
                                                ? "battery_unknown"
                                                : batteryPercent >= 90
                                                    ? "battery_full"
                                                    : batteryPercent >= 50
                                                        ? "battery_4_bar"
                                                        : "battery_2_bar"
                                        color: m3OnSurfaceVariant
                                        iconSize: 24
                                        fill: 1  // Filled variant
                                    }
                                }

                                // Percentage label - headline-small with weight 700
                                StyledText {
                                    text: batteryPercent >= 0 ? batteryPercent + "%" : "--%"
                                    font.pixelSize: 24
                                    font.weight: Font.Bold // Weight 700 for prominent numbers
                                    color: textColor
                                    Layout.leftMargin: 12
                                    Layout.rightMargin: 16
                                }

                                // Expressive progress bar - 12dp segmented pill with mint accent
                                StyledProgressBar {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    valueBarHeight: 12
                                    value: Math.max(batteryPercent, 0) / 100
                                    highlightColor: accentColor
                                    trackColor: m3SurfaceVariant
                                    // Remove gap to eliminate right-side dot artifact
                                    valueBarGap: 0
                                }

                                // Trailing status icon - bold bolt in mint accent
                                MaterialSymbol {
                                    visible: batteryCharging
                                    text: "bolt"
                                    iconSize: 20
                                    color: accentColor
                                    fill: 1  // Filled variant
                                    Layout.leftMargin: 12
                                }
                            }
                        }

                        // Quick Actions - Material 3 ButtonGroup with GroupButtons
                        ButtonGroup {
                             Layout.fillWidth: true
                             spacing: 12
                             padding: 0
                             visible: deviceOnline

                             // Ring - Warning/Orange (alert action)
                             GroupButton {
                                 id: ringBtn
                                 Layout.fillWidth: true
                                 baseWidth: Math.floor((parent.width - 24) / 3)
                                 baseHeight: 56
                                 clickedWidth: baseWidth + 16
                                 buttonRadius: 18
                                 buttonRadiusPressed: 14
                                 bounce: true

                                 colBackground: m3SecondaryContainer
                                 colBackgroundHover: ColorUtils.applyAlpha(m3SecondaryContainer, 0.8)
                                 colBackgroundActive: ColorUtils.applyAlpha(m3SecondaryContainer, 0.6)

                                 onClicked: {
                                     if (!activeDeviceId) return
                                     Quickshell.execDetached(["kdeconnect-cli", "--ring", "--device", activeDeviceId])
                                 }

                                 contentItem: MaterialSymbol {
                                     horizontalAlignment: Text.AlignHCenter
                                     verticalAlignment: Text.AlignVCenter
                                     text: "notifications_active"  // Ring icon
                                     color: textColor
                                     iconSize: 28
                                     fill: 1  // Filled variant
                                 }

                                 StyledToolTip {
                                     text: "Ring phone"
                                 }
                             }

                             // Ping - Success/Green (confirmation)
                             GroupButton {
                                 id: pingBtn
                                 Layout.fillWidth: true
                                 baseWidth: Math.floor((parent.width - 24) / 3)
                                 baseHeight: 56
                                 clickedWidth: baseWidth + 16
                                 buttonRadius: 18
                                 buttonRadiusPressed: 14
                                 bounce: true

                                 colBackground: m3SecondaryContainer
                                 colBackgroundHover: ColorUtils.applyAlpha(m3SecondaryContainer, 0.8)
                                 colBackgroundActive: ColorUtils.applyAlpha(m3SecondaryContainer, 0.6)

                                 onClicked: {
                                     if (!activeDeviceId) return
                                     Quickshell.execDetached(["kdeconnect-cli", "--ping", "--device", activeDeviceId])
                                 }

                                 contentItem: MaterialSymbol {
                                     horizontalAlignment: Text.AlignHCenter
                                     verticalAlignment: Text.AlignVCenter
                                     text: "pan_tool"  // Ping icon
                                     color: textColor
                                     iconSize: 28
                                     fill: 1  // Filled variant
                                 }

                                 StyledToolTip {
                                     text: "Ping phone"
                                 }
                             }

                             // Mirror - Primary/Accent (main feature)
                             GroupButton {
                                 id: mirrorBtn
                                 Layout.fillWidth: true
                                 baseWidth: Math.floor((parent.width - 24) / 3)
                                 baseHeight: 56
                                 clickedWidth: baseWidth + 16
                                 buttonRadius: 18
                                 buttonRadiusPressed: 14
                                 bounce: true

                                 colBackground: m3SecondaryContainer
                                 colBackgroundHover: ColorUtils.applyAlpha(m3SecondaryContainer, 0.8)
                                 colBackgroundActive: ColorUtils.applyAlpha(m3SecondaryContainer, 0.6)

                                 onClicked: {
                                     Quickshell.execDetached(["bash", Qt.resolvedUrl("mirror_phone.sh").toString().replace("file://", "")])
                                 }

                                 contentItem: MaterialSymbol {
                                     horizontalAlignment: Text.AlignHCenter
                                     verticalAlignment: Text.AlignVCenter
                                     text: "screen_share"  // Mirror icon
                                     color: textColor
                                     iconSize: 28
                                     fill: 1  // Filled variant
                                 }

                                 StyledToolTip {
                                     text: "Mirror screen (scrcpy)"
                                 }
                             }
                        }

                        // Drop Zone - Material 3 styling
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 24
                            color: m3SurfaceContainer
                            border.width: 1.5
                            border.color: fileDropArea.containsDrag ? accentColor : m3Outline

                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            // Visual Content (Icon + Text)
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 16
                                visible: !isTransferring // Hide when sharing starts

                                // Center badge - rounded squircle action badge
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 56
                                    implicitHeight: 56
                                    radius: 16
                                    color: m3PrimaryContainer

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "upload_file"
                                        color: m3OnPrimaryContainer
                                        iconSize: 32
                                        fill: 1  // Filled variant
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: fileDropArea.containsDrag ? "Drop to share!" : "Drop files to send"
                                    color: textSecondary
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                            }

                            // Loading overlay during file transfer
                            Rectangle {
                                anchors.fill: parent
                                radius: 24
                                color: ColorUtils.applyAlpha(m3SurfaceContainer, 0.95)
                                z: 100

                                // Animate visibility
                                opacity: isTransferring ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                
                                scale: isTransferring ? 1 : 0.9
                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: `Sending ${transferSuccessCount + transferFailureCount + (transferProcess.running ? 1 : 0)}/${transferPendingCount}`
                                    color: textColor
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }
                            }

                            DropArea {
                                id: fileDropArea
                                anchors.fill: parent
                                enabled: deviceOnline
                                onEntered: (drag) => {
                                    // Keep drawer open when dragging inside
                                    kdeRoot.isDragging = true
                                    isOpen = true
                                    userActive = true
                                    closeTimer.stop()
                                }
                                onExited: {
                                    // Allow close if dragging out
                                    kdeRoot.isDragging = false
                                    userActive = false
                                    closeTimer.restart()
                                }

                                onDropped: (drop) => {
                                    kdeRoot.isDragging = false
                                    if (!drop.hasUrls || !activeDeviceId) return

                                    startTransfers(urlsToPaths(drop.urls))
                                }
                            }
                        }
                    }
                }
            }

        }
    }
}
