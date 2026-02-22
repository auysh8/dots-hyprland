import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common.widgets
import qs.modules.common

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
    property color warningColor: "#fab387"  // Warm orange for Ring (alert action)

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

    Process { id: actionProcess }

    Process {
        id: transferProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) transferSuccessCount += 1;
            else {
                transferFailureCount += 1;
                console.log("KDE: Transfer failed for", currentTransferFile, "exit", exitCode, exitStatus);
            }
            transferQueue = transferQueue.slice(1);
            runNextTransfer();
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
            // Always visible if device is online (pill mode), or if active/open
            visible: true // We manage opacity/visibility of inner items now

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

                // Regular hover handler for the drawer
                HoverHandler {
                    onHoveredChanged: {
                        drawerHovered = hovered
                        userActive = hovered
                        if (hovered)
                            closeTimer.stop()
                        else
                            closeTimer.start()
                    }
                }

                // Extended hover area when opened from corner (for file dropping)
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: openedFromCorner ? -100 : 0  // Extend hover area by 100px when opened from corner
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    visible: openedFromCorner  // Only active when opened from corner

                    onEntered: {
                        if (openedFromCorner) {
                            drawerHovered = true
                            userActive = true
                            closeTimer.stop()
                        }
                    }

                    onExited: {
                        if (openedFromCorner) {
                            drawerHovered = false
                            userActive = false
                            closeTimer.interval = 2000  // Extended timeout for file dropping
                            closeTimer.start()
                        }
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
                        anchors.margins: 32
                        spacing: 28
                        opacity: isOpen ? 1 : 0 // Fade content out when closing
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Header - Refined with phone icon and status
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            // Phone icon with online indicator
                            Rectangle {
                                width: 40
                                height: 40
                                radius: 12
                                color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.15)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "smartphone"
                                    color: accentColor
                                    iconSize: 22
                                }

                                // Online dot
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: -2
                                    width: 12
                                    height: 12
                                    radius: 6
                                    color: deviceOnline ? successColor : "#f38ba8"
                                    border.width: 2
                                    border.color: cardColor

                                    // Pulse animation when online
                                    SequentialAnimation on scale {
                                        loops: Animation.Infinite
                                        running: deviceOnline
                                        NumberAnimation { to: 1.2; duration: 800; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            // Device name
                            Text {
                                text: deviceName
                                color: textColor
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                Layout.fillWidth: true
                            }

                            // Minimize button
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: minimizeArea.containsMouse ? Qt.rgba(textColor.r, textColor.g, textColor.b, 0.1) : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "keyboard_arrow_down"
                                    color: textSecondary
                                    iconSize: 24
                                }
                                
                                MouseArea {
                                    id: minimizeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        requestCloseDrawer()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: 14
                            color: cardColor
                            visible: availableDevices.length > 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                Text {
                                    text: "Device"
                                    color: textSecondary
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }

                                ComboBox {
                                    id: deviceSelector
                                    Layout.fillWidth: true
                                    enabled: !isTransferring
                                    model: availableDevices.map(dev => dev.reachable ? dev.name : `${dev.name} (offline)`)
                                    currentIndex: selectedDeviceIndex()
                                    onActivated: index => {
                                        if (index < 0 || index >= availableDevices.length) return
                                        activeDeviceId = availableDevices[index].id
                                        deviceName = availableDevices[index].name
                                        batteryPercent = availableDevices[index].battery ?? -1
                                        batteryCharging = Boolean(availableDevices[index].charging)
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: closeBlockedByTransfer
                            text: "Transfer in progress. Please wait before closing."
                            color: warningColor
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        // Battery Card - Compact horizontal design
                        Rectangle {
                            Layout.fillWidth: true
                            height: 70
                            radius: 20
                            color: cardColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 14

                                // Battery icon with circle background
                                Rectangle {
                                    width: 38
                                    height: 38
                                    radius: 12
                                    color: batteryCharging 
                                        ? Qt.rgba(successColor.r, successColor.g, successColor.b, 0.2)
                                        : (batteryPercent != -1 && batteryPercent < 20 
                                            ? Qt.rgba(1, 0.4, 0.4, 0.2) 
                                            : Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.15))

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        iconSize: 22
                                        color: batteryCharging
                                            ? successColor
                                            : (batteryPercent != -1 && batteryPercent < 20 ? "#f38ba8" : accentColor)
                                        text: batteryCharging
                                            ? "battery_charging_full"
                                            : batteryPercent == -1
                                                ? "battery_unknown"
                                                : batteryPercent >= 90
                                                    ? "battery_full"
                                                    : batteryPercent >= 50
                                                        ? "battery_4_bar"
                                                        : "battery_2_bar"
                                    }
                                }

                                // Percentage
                                Text {
                                    text: batteryPercent >= 0 ? batteryPercent + "%" : "--%"
                                    font.pixelSize: 24
                                    font.weight: Font.Bold
                                    color: textColor
                                }

                                // Progress bar - takes remaining space
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 10
                                    radius: 5
                                    color: Qt.rgba(1, 1, 1, 0.08)

                                    Rectangle {
                                        height: 10
                                        radius: 5
                                        width: parent.width * Math.max(batteryPercent, 0) / 100
                                        
                                        // Gradient fill
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { 
                                                position: 0.0
                                                color: batteryCharging ? successColor : accentColor
                                            }
                                            GradientStop { 
                                                position: 1.0
                                                color: batteryCharging 
                                                    ? Qt.lighter(successColor, 1.3) 
                                                    : Qt.lighter(accentColor, 1.2)
                                            }
                                        }

                                        Behavior on width {
                                            NumberAnimation { duration: 500; easing.type: Easing.OutQuad }
                                        }
                                    }
                                }

                                // Charging indicator text
                                Text {
                                    visible: batteryCharging
                                    text: "⚡"
                                    font.pixelSize: 16
                                }
                            }
                        }

                        // Actions Row - Icon-only with tooltips
                        RowLayout {
                             Layout.fillWidth: true
                             spacing: 12
                             visible: deviceOnline

                             // Ring - Warning/Orange (alert action)
                             Rectangle {
                                 id: ringBtn
                                 Layout.fillWidth: true
                                 Layout.preferredWidth: ringArea.pressed ? 110 : 100 
                                 height: ringArea.pressed ? 52 : 48
                                 radius: ringArea.pressed ? 12 : 16
                                 color: ringArea.containsMouse 
                                     ? warningColor 
                                     : cardColor
                                 border.width: ringArea.activeFocus ? 2 : 0
                                 border.color: accentColor
                                 
                                 // Property for StyledToolTip
                                 property bool hovered: ringArea.containsMouse
                                 
                                 Behavior on Layout.preferredWidth { 
                                     NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                 }
                                 Behavior on height { 
                                     NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                 }
                                 Behavior on radius { NumberAnimation { duration: 200 } }
                                 Behavior on color { ColorAnimation { duration: 150 } }

                                 MaterialSymbol {
                                     anchors.centerIn: parent
                                     text: "ring_volume"
                                     color: ringArea.containsMouse ? Appearance.m3colors.m3onPrimary : textColor
                                     iconSize: 24
                                     Behavior on color { ColorAnimation { duration: 150 } }
                                 }

                                 StyledToolTip {
                                     text: "Ring Phone"
                                 }

                                 MouseArea {
                                     id: ringArea
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     activeFocusOnTab: true
                                     cursorShape: Qt.PointingHandCursor
                                     Keys.onPressed: event => {
                                         if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                             if (!activeDeviceId) return
                                             actionProcess.command = ["kdeconnect-cli", "--ring", "--device", activeDeviceId]
                                             actionProcess.running = true
                                             event.accepted = true
                                         }
                                     }
                                     onClicked: {
                                         if(!activeDeviceId) return
                                         actionProcess.command = ["kdeconnect-cli", "--ring", "--device", activeDeviceId]
                                         actionProcess.running = true
                                     }
                                 }
                             }

                             // Ping - Success/Green (confirmation)
                             Rectangle {
                                 id: pingBtn
                                 Layout.fillWidth: true
                                 Layout.preferredWidth: pingArea.pressed ? 110 : 100 
                                 height: pingArea.pressed ? 52 : 48
                                 radius: pingArea.pressed ? 12 : 16
                                 color: pingArea.containsMouse 
                                     ? successColor 
                                     : cardColor
                                 border.width: pingArea.activeFocus ? 2 : 0
                                 border.color: accentColor
                                 
                                 // Property for StyledToolTip
                                 property bool hovered: pingArea.containsMouse
                                 
                                 Behavior on Layout.preferredWidth { 
                                     NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                 }
                                 Behavior on height { 
                                     NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                 }
                                 Behavior on radius { NumberAnimation { duration: 200 } }
                                 Behavior on color { ColorAnimation { duration: 150 } }

                                 MaterialSymbol {
                                     anchors.centerIn: parent
                                     text: "touch_app"
                                     color: pingArea.containsMouse ? Appearance.m3colors.m3onPrimary : textColor
                                     iconSize: 24
                                     Behavior on color { ColorAnimation { duration: 150 } }
                                 }

                                 StyledToolTip {
                                     text: "Ping"
                                 }

                                 MouseArea {
                                     id: pingArea
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     activeFocusOnTab: true
                                     cursorShape: Qt.PointingHandCursor
                                     Keys.onPressed: event => {
                                         if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                             if (!activeDeviceId) return
                                             actionProcess.command = ["kdeconnect-cli", "--ping", "--device", activeDeviceId]
                                             actionProcess.running = true
                                             event.accepted = true
                                         }
                                     }
                                     onClicked: {
                                         if(!activeDeviceId) return
                                         actionProcess.command = ["kdeconnect-cli", "--ping", "--device", activeDeviceId]
                                         actionProcess.running = true
                                     }
                                 }
                             }

                             // Mirror - Primary/Accent (main feature)
                             Rectangle {
                                 id: mirrorBtn
                                 Layout.fillWidth: true
                                 Layout.preferredWidth: mirrorArea.pressed ? 110 : 100 
                                 height: mirrorArea.pressed ? 52 : 48
                                 radius: mirrorArea.pressed ? 12 : 16
                                 color: mirrorArea.containsMouse 
                                     ? accentColor 
                                     : cardColor
                                 border.width: mirrorArea.activeFocus ? 2 : 0
                                 border.color: accentColor
                                 
                                 // Property for StyledToolTip
                                 property bool hovered: mirrorArea.containsMouse
                                 
                                 Behavior on Layout.preferredWidth { 
                                     NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                 }
                                 Behavior on height { 
                                     NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                 }
                                 Behavior on radius { NumberAnimation { duration: 200 } }
                                 Behavior on color { ColorAnimation { duration: 150 } }

                                 MaterialSymbol {
                                     anchors.centerIn: parent
                                     text: "screen_share"
                                     color: mirrorArea.containsMouse ? Appearance.m3colors.m3onPrimary : textColor
                                     iconSize: 24
                                     Behavior on color { ColorAnimation { duration: 150 } }
                                 }

                                 StyledToolTip {
                                     text: "Mirror Screen"
                                 }

                                 MouseArea {
                                     id: mirrorArea
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     activeFocusOnTab: true
                                     cursorShape: Qt.PointingHandCursor
                                     Keys.onPressed: event => {
                                         if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                                             actionProcess.command = ["bash", Qt.resolvedUrl("mirror_phone.sh").toString().replace("file://", "")]
                                             actionProcess.running = true
                                             event.accepted = true
                                         }
                                     }
                                     onClicked: {
                                         actionProcess.command = ["bash", Qt.resolvedUrl("mirror_phone.sh").toString().replace("file://", "")]
                                         actionProcess.running = true
                                     }
                                 }
                             }
                        }

                        // Drop Zone
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 28
                            color: "transparent"

                            Canvas {
                                anchors.fill: parent
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    // Highlight border on drag
                                    ctx.strokeStyle = fileDropArea.containsDrag ? accentColor : Qt.rgba(textColor.r, textColor.g, textColor.b, 0.2)
                                    ctx.lineWidth = 2
                                    ctx.setLineDash([12, 12]) // Larger dashes
                                    ctx.beginPath()
                                    // Inset slightly to avoid clipping
                                    ctx.roundedRect(2, 2, width-4, height-4, 26, 26)
                                    ctx.stroke()
                                }
                            }

                            // Visual Content (Icon + Text)
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 20
                                visible: !isTransferring // Hide when sharing starts

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 64
                                    height: 64
                                    radius: 32
                                    color: fileDropArea.containsDrag ? accentColor : Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.5)

                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "upload_file"
                                        iconSize: 32
                                        color: fileDropArea.containsDrag ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnSurface
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: fileDropArea.containsDrag ? "Drop to share!" : "Drop files to send"
                                    color: textSecondary
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                }
                            }

                            // Loading overlay during file transfer
                            Rectangle {
                                anchors.fill: parent
                                radius: 28
                                color: Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.95)
                                z: 100

                                // Animate visibility
                                opacity: isTransferring ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                                
                                scale: isTransferring ? 1 : 0.9
                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                                Item {
                                    anchors.fill: parent

                                    // Morphing Spinner
                                    Item {
                                        id: loaderContainer
                                        anchors.centerIn: parent
                                        width: 64
                                        height: 64
                                        visible: isTransferring
                                        
                                        // Light background circle
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 56
                                            height: 56
                                            radius: 28
                                            color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.2)
                                        }

                                        MaterialCookie {
                                            id: loadingCookie
                                            anchors.fill: parent
                                            anchors.margins: 4
                                            color: accentColor
                                            sides: 12 
                                            Behavior on sides { NumberAnimation { duration: 0 } }
                                        }

                                        RotationAnimator {
                                            target: loadingCookie
                                            from: 0; to: 360
                                            duration: 2000
                                            loops: Animation.Infinite
                                            running: loaderContainer.visible
                                        }

                                        Timer {
                                            interval: 800
                                            running: loaderContainer.visible
                                            repeat: true
                                            triggeredOnStart: true
                                            onTriggered: {
                                                const shapes = [0, 4, 5, 6, 12]
                                                let next = shapes[Math.floor(Math.random() * shapes.length)]
                                                while (next === loadingCookie.sides) {
                                                    next = shapes[Math.floor(Math.random() * shapes.length)]
                                                }
                                                loadingCookie.sides = next
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: loaderContainer.bottom
                                        anchors.topMargin: 18
                                        text: `Sending ${transferSuccessCount + transferFailureCount + (transferProcess.running ? 1 : 0)}/${transferPendingCount}`
                                        color: textColor
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            DropArea {
                                id: fileDropArea
                                anchors.fill: parent
                                enabled: deviceOnline
                                onEntered: (drag) => {
                                    parent.children[0].requestPaint()
                                    // Keep drawer open when dragging inside
                                    kdeRoot.isDragging = true
                                    isOpen = true
                                    userActive = true
                                    closeTimer.stop()
                                }
                                onExited: {
                                    parent.children[0].requestPaint()
                                    // Allow close if dragging out
                                    kdeRoot.isDragging = false
                                    userActive = false
                                    closeTimer.restart()
                                }

                                onDropped: (drop) => {
                                    kdeRoot.isDragging = false
                                    parent.children[0].requestPaint() // Reset canvas
                                    if (!drop.hasUrls || !activeDeviceId) return

                                    startTransfers(urlsToPaths(drop.urls))
                                }
                            }
                        }

                        // Status Pill - Floating style
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: statusRow.width + 20
                            height: 28
                            radius: 14
                            color: "transparent"

                            RowLayout {
                                id: statusRow
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: deviceOnline ? successColor : "#f38ba8"

                                    // Pulse animation when online
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        running: deviceOnline
                                        NumberAnimation { to: 0.4; duration: 1000 }
                                        NumberAnimation { to: 1.0; duration: 1000 }
                                    }
                                }

                                Text {
                                    text: transferStatusText !== "" ? transferStatusText : (deviceOnline ? "Connected" : "Offline")
                                    color: transferStatusText !== "" ? (transferFailureCount > 0 ? warningColor : successColor) : textSecondary
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                            }
                        }
                    }
                }
            }

        }
    }
}
