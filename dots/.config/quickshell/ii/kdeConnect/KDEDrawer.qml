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

    // Cursor-based corner trigger (for non-drag case)
    property int cursorX: -1
    property int cursorY: -1
    property bool drawerHovered: false
    property bool openedFromCorner: false  // Track if opened from corner
    property bool isTransferring: false     // Track file transfer in progress vs edge


    // --- Colors ---
    // --- Colors ---
    // Use Opaque Base colors to avoid transparency issues
    property color backgroundColor: Appearance.colors.colLayer0Base
    property color cardColor: Appearance.colors.colLayer1Base
    property color textColor: Appearance.colors.colOnSurface
    property color textSecondary: Appearance.colors.colSubtext
    property color accentColor: Appearance.colors.colPrimary
    property color successColor: Appearance.m3colors.m3success

    /* --- CLOSE TIMER (shared) --- */
    Timer {
        id: closeTimer
        interval: 500
        onTriggered: {
            // Close only when nothing is interacting with the drawer/hot-corner AND not transferring
            if (!userActive && !isTransferring) {
                console.log(`KDE Debug: Closing drawer (timeout: ${interval}ms)`)
                isOpen = false
                openedFromCorner = false  // Reset flag when closing
            }
        }
    }

    /* --- TRANSFER COMPLETE TIMER --- */
    Timer {
        id: transferCompleteTimer
        interval: 10000  // Give it 10 seconds for user to see the status
        onTriggered: {
            console.log("KDE: Transfer complete timer triggered, setting isTransferring = false")
            isTransferring = false
            // Now allow the drawer to close if user isn't active
            // We don't force userActive = false here, strictly rely on hover status
            if (!drawerHovered) {
                userActive = false
                closeTimer.restart()
            }
        }
    }

    /* --- HOT CORNER POLL (Hyprland) --- */
    Timer {
        id: cornerPoll
        interval: 150
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: cursorPosProc.running = true
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

                if (inCorner) {
                    isOpen = true
                    userActive = true
                    openedFromCorner = true  // Always true since only corner opens it
                    closeTimer.stop()
                } else if (!drawerHovered && !isTransferring) {
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
        onTriggered: statusScript.running = true
    }

    Process {
        id: statusScript
        command: ["python3", Qt.resolvedUrl("kde_bridge.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: (data) => {
                if (data.trim() === "") return
                try {
                    const res = JSON.parse(data)
                    deviceOnline = res.found
                    if (res.found) {
                        activeDeviceId = res.id
                        deviceName = res.name
                        batteryPercent = res.battery
                        batteryCharging = res.charging
                    }
                } catch (e) {
                    console.log("KDE Bridge JSON Error:", e)
                }
            }
        }
    }

    Process { id: sendProcess }

    /* --- WINDOW --- */
    Variants {
        model: Quickshell.screens

        /* --- DEBUG CORNER AREA (shows trigger zone) ---
           Using console logging instead of visual window since PanelWindow positioning is limited
        */

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            anchors { right: true; bottom: true }

            // Only exist as a surface while open or actively in use
            // This prevents it from blocking clicks when the drawer is "closed"
            visible: isOpen || userActive

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            color: "transparent"
            implicitWidth: 420
            implicitHeight: 620

            DropArea {
    anchors.fill: parent
    // This catches files anywhere on the right side of the screen
    onEntered: (drag) => {
        if (drag.hasUrls) {
            isOpen = true
            userActive = true
            closeTimer.stop()
        }
    }
}

            // NOTE: Quickshell's `Region.fromRect(...)` isn't available here; keep mask simple.
            // If you want a shape-limited mask later, we can switch to `mask: Region { item: drawer }`.

/* --- DRAG TRIGGER (Anywhere on the right edge) --- */
DropArea {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 10 

    onEntered: (drag) => {
        if (!drag.hasUrls) return
        isOpen = true
        userActive = true // Mark as active so it stays open
        closeTimer.stop()
    }

    onExited: {
        userActive = false // No longer active if the file leaves the area
        closeTimer.restart()
    }

    onDropped: {
        userActive = false
        closeTimer.restart()
        // ... (your existing drop logic for kdeconnect-cli)
    }
}

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
                    width: 380
                    height: 600
                    radius: 32
                    color: backgroundColor

                    transformOrigin: Item.BottomRight
                    scale: isOpen ? 1.0 : 1.0   // always present
                    opacity: isOpen ? 1.0 : 0.0
                    visible: opacity > 0
                    DropArea {
        anchors.fill: parent
        enabled: deviceOnline

        onDropped: (drop) => {
            if (!drop.hasUrls || !activeDeviceId) return

            console.log("KDE: Starting file transfer, setting isTransferring = true")
            isTransferring = true  // Show loading indicator
            transferCompleteTimer.restart()  // Start transfer completion timer

            // Process the files
            for (const url of drop.urls) {
                const filePath = url.toString().replace("file://","")
                console.log("KDE: Processing file:", filePath)
                sendProcess.command = [
                    "kdeconnect-cli",
                    "--share",
                    filePath,
                    "--device",
                    activeDeviceId
                ]
                sendProcess.running = true
            }

            // Keep drawer open during transfer - don't close immediately
            // The transferCompleteTimer will handle hiding the loading indicator
            // and only then will we allow the drawer to close
        }
    }


                    Behavior on scale {
                        NumberAnimation { duration: 450; easing.type: Easing.OutExpo }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 300 }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 32
                        spacing: 28

                        // Header
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: deviceName
                                color: textColor
                                font.pixelSize: 24
                                font.weight: Font.Bold
                                Layout.fillWidth: true
                            }
                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                color: textSecondary
                                iconSize: 24
                                
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        isOpen = false
                                        openedFromCorner = false
                                        userActive = false
                                    }
                                }
                            }
                        }

                        // Battery Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 130
                            radius: 24
                            color: cardColor

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: batteryPercent >= 0 ? batteryPercent + "%" : "--%"
                                        font.pixelSize: 38
                                        font.weight: Font.Bold
                                        color: textColor
                                    }
                                    Text {
                                        text: "Battery"
                                        color: textSecondary
                                        font.pixelSize: 16
                                        Layout.leftMargin: 8
                                    }
                                    Item { Layout.fillWidth: true }
                                    MaterialSymbol {
                                        iconSize: 28
                                        color: batteryCharging
                                            ? successColor
                                            : (batteryPercent < 20 ? "#f38ba8" : textSecondary)
                                        text: batteryCharging
                                            ? "battery_charging_full"
                                            : batteryPercent >= 90
                                                ? "battery_full"
                                                : batteryPercent >= 50
                                                    ? "battery_4_bar"
                                                    : "battery_2_bar"
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 8
                                    radius: 4
                                    color: Qt.rgba(1, 1, 1, 0.1)

                                    Rectangle {
                                        height: 8
                                        radius: 4
                                        color: batteryCharging ? successColor : accentColor
                                        width: parent.width * Math.max(batteryPercent, 0) / 100
                                        Behavior on width {
                                            NumberAnimation { duration: 500; easing.type: Easing.OutQuad }
                                        }
                                    }
                                }
                            }
                        }

                        // Actions Row
                        RowLayout {
                             Layout.fillWidth: true
                             spacing: 12
                             visible: deviceOnline

                             // Find My Phone
                             Rectangle {
                                 Layout.fillWidth: true
                                 height: 50
                                 radius: 16
                                 color: ringArea.containsMouse ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.15) : cardColor
                                 Behavior on color { ColorAnimation { duration: 150 } }

                                 RowLayout {
                                     anchors.centerIn: parent
                                     spacing: 8
                                     MaterialSymbol {
                                         text: "notifications_active"
                                         color: accentColor
                                         iconSize: 20
                                     }
                                     Text {
                                         text: "Ring"
                                         color: textColor
                                         font.pixelSize: 14
                                         font.weight: Font.Medium
                                     }
                                 }

                                 MouseArea {
                                     id: ringArea
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: Qt.PointingHandCursor
                                     onClicked: {
                                         if(!activeDeviceId) return
                                         sendProcess.command = ["kdeconnect-cli", "--ring", "--device", activeDeviceId]
                                         sendProcess.running = true
                                     }
                                 }
                             }

                             // Ping
                             Rectangle {
                                 Layout.fillWidth: true
                                 height: 50
                                 radius: 16
                                 color: pingArea.containsMouse ? Qt.rgba(successColor.r, successColor.g, successColor.b, 0.15) : cardColor
                                 Behavior on color { ColorAnimation { duration: 150 } }

                                 RowLayout {
                                     anchors.centerIn: parent
                                     spacing: 8
                                     MaterialSymbol {
                                         text: "touch_app"
                                         color: successColor
                                         iconSize: 20
                                     }
                                     Text {
                                         text: "Ping"
                                         color: textColor
                                         font.pixelSize: 14
                                         font.weight: Font.Medium
                                     }
                                 }

                                 MouseArea {
                                     id: pingArea
                                     anchors.fill: parent
                                     hoverEnabled: true
                                     cursorShape: Qt.PointingHandCursor
                                     onClicked: {
                                         if(!activeDeviceId) return
                                         sendProcess.command = ["kdeconnect-cli", "--ping", "--device", activeDeviceId]
                                         sendProcess.running = true
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
                                        color: fileDropArea.containsDrag ? Appearance.m3colors.m3onPrimary : accentColor
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
                                // Use themed color instead of hardcoded black
                                color: Qt.rgba(cardColor.r, cardColor.g, cardColor.b, 0.9)
                                visible: isTransferring
                                z: 100

                                Item {
                                    anchors.fill: parent

                                    Text {
                                        id: sharingText
                                        text: "Sharing..."
                                        color: textColor
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: -40
                                    }

                                    // Morphing Spinner
                                    Item {
                                        id: loaderContainer
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: 10
                                        width: 48
                                        height: 48
                                        visible: isTransferring
                                        
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
                                }
                            }

                            DropArea {
                                id: fileDropArea
                                anchors.fill: parent
                                enabled: deviceOnline
                                onEntered: parent.children[0].requestPaint() // Repaint canvas on enter
                                onExited: parent.children[0].requestPaint() // Repaint canvas on exit

                                onDropped: (drop) => {
                                    parent.children[0].requestPaint() // Reset canvas
                                    if (!drop.hasUrls || !activeDeviceId) return

                                    console.log("KDE: Starting file transfer from inner DropArea")
                                    isTransferring = true
                                    transferCompleteTimer.restart()

                                    for (const url of drop.urls) {
                                        sendProcess.command = [
                                            "kdeconnect-cli",
                                            "--share",
                                            url.toString().replace("file://",""),
                                            "--device",
                                            activeDeviceId
                                        ]
                                        sendProcess.running = true
                                    }
                                }
                            }
                        }

                        // Status
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 10
                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: deviceOnline ? successColor : "#f38ba8"
                            }
                            Text {
                                text: deviceOnline ? "CONNECTED VIA WI-FI" : "DISCONNECTED"
                                color: textSecondary
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2
                            }
                        }
                    }
                }
            }

        }
    }
}
