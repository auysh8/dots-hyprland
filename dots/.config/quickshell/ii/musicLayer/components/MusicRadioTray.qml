import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var rootContext
    property bool trayVisible: false

    onTrayVisibleChanged: {
        if (trayVisible && rootContext) {
            rootContext.sendCommand({ "command": "get_output_device" })
        }
    }

    anchors.fill: parent
    z: 1000
    visible: overlayRect.opacity > 0 || trayTranslate.y < tray.height + 40

    // Overlay background (dimming)
    Rectangle {
        id: overlayRect
        anchors.fill: parent
        color: ColorUtils.applyAlpha("black", 0.5)
        opacity: root.trayVisible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.trayVisible
            onClicked: rootContext.radioTrayVisible = false
        }
    }

    // Bottom tray
    Rectangle {
        id: tray
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.margins: 16
        width: Math.min(600, parent.width - 32)
        height: trayContent.implicitHeight + 32
        radius: 24
        color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer2

        transform: Translate {
            id: trayTranslate
            y: root.trayVisible ? 0 : tray.height + 60
            Behavior on y {
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.8
                }
            }
        }

        ColumnLayout {
            id: trayContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 16

            // Handle bar
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 4
                Layout.alignment: Qt.AlignHCenter
                color: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer0, 0.3)
                radius: 2
            }

            // Title
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Quick Actions"
                font.pixelSize: 18
                font.bold: true
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer0
            }

            // Action Buttons
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                
                // 1. Start Radio
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 16
                    verticalPadding: 0

                    contentItem: RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "radio"
                            iconSize: 24
                            color: rootContext.contentColor
                        }
                        Label {
                            text: "Start Radio"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: rootContext.contentColor
                            Layout.fillWidth: true
                        }
                    }

                    onClicked: {
                        rootContext.radioTrayVisible = false
                        if (rootContext && rootContext.currentTrack) {
                            rootContext.sendCommand({
                                "command": "populate_radio",
                                "videoId": rootContext.currentTrack.videoId
                            })
                        }
                    }
                }

                // 2. Go to Artist
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 16
                    verticalPadding: 0
                    visible: rootContext.currentTrack && (rootContext.currentTrack.artistId || "").length > 0

                    contentItem: RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "person"
                            iconSize: 24
                            color: rootContext.contentColor
                        }
                        Label {
                            text: "Go to Artist"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: rootContext.contentColor
                            Layout.fillWidth: true
                        }
                    }

                    onClicked: {
                        rootContext.radioTrayVisible = false
                        if (rootContext.currentTrack && rootContext.currentTrack.artistId) {
                            rootContext.openArtist(rootContext.currentTrack.artistId)
                        }
                    }
                }

                // 3. Go to Album
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 16
                    verticalPadding: 0
                    visible: rootContext.currentTrack && (rootContext.currentTrack.albumId || "").length > 0

                    contentItem: RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "album"
                            iconSize: 24
                            color: rootContext.contentColor
                        }
                        Label {
                            text: "Go to Album"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: rootContext.contentColor
                            Layout.fillWidth: true
                        }
                    }

                    onClicked: {
                        rootContext.radioTrayVisible = false
                        if (rootContext.currentTrack && rootContext.currentTrack.albumId) {
                            rootContext.openPlaylist(rootContext.currentTrack.albumId)
                        }
                    }
                }

                // 4. Copy Link
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 16
                    verticalPadding: 0
                    visible: rootContext.currentTrack && (rootContext.currentTrack.videoId || "").length > 0

                    contentItem: RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "content_copy"
                            iconSize: 24
                            color: rootContext.contentColor
                        }
                        Label {
                            id: copyLabel
                            text: "Copy Link"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: rootContext.contentColor
                            Layout.fillWidth: true
                        }
                    }

                    onClicked: {
                        if (rootContext.currentTrack && rootContext.currentTrack.videoId) {
                            let url = "https://music.youtube.com/watch?v=" + rootContext.currentTrack.videoId
                            rootContext.sendCommand({
                                "command": "copy_to_clipboard",
                                "text": url
                            })
                            copyLabel.text = "Copied!"
                            copyResetTimer.restart()
                        }
                    }
                    
                    Timer {
                        id: copyResetTimer
                        interval: 2000
                        onTriggered: {
                            copyLabel.text = "Copy Link"
                            rootContext.radioTrayVisible = false
                        }
                    }
                }

                // 5. Open in Browser
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 16
                    verticalPadding: 0
                    visible: rootContext.currentTrack && (rootContext.currentTrack.videoId || "").length > 0

                    contentItem: RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "open_in_new"
                            iconSize: 24
                            color: rootContext.contentColor
                        }
                        Label {
                            text: "Open in Browser"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: rootContext.contentColor
                            Layout.fillWidth: true
                        }
                    }

                    onClicked: {
                        if (rootContext.currentTrack && rootContext.currentTrack.videoId) {
                            let url = "https://music.youtube.com/watch?v=" + rootContext.currentTrack.videoId
                            Qt.openUrlExternally(url)
                            rootContext.radioTrayVisible = false
                        }
                    }
                }

                // 5.5 Output Device
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 16
                        
                        MaterialSymbol {
                            text: "speaker_group"
                            iconSize: 24
                            color: rootContext.contentColor
                            opacity: 0.6
                        }
                        
                        ColumnLayout {
                            spacing: 0
                            Label {
                                text: "Audio Output"
                                font.pixelSize: 12
                                color: rootContext.contentColor
                                opacity: 0.5
                            }
                            Label {
                                text: rootContext.currentOutputDevice
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: rootContext.contentColor
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // 6. Sleep Timer
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    buttonRadius: 16
                    colBackground: rootContext.sleepTimerActive ? ColorUtils.applyAlpha(rootContext.pillColor, 0.1) : "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 16
                    verticalPadding: 0

                    contentItem: RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "timer"
                            iconSize: 24
                            color: rootContext.sleepTimerActive ? rootContext.pillColor : rootContext.contentColor
                        }
                        Label {
                            text: rootContext.sleepTimerActive 
                                ? "Sleep Timer: " + Math.ceil(rootContext.sleepTimerSeconds / 60) + "m left"
                                : "Sleep Timer"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            color: rootContext.sleepTimerActive ? rootContext.pillColor : rootContext.contentColor
                            Layout.fillWidth: true
                        }
                        MaterialSymbol {
                            text: rootContext.sleepTimerMenuVisible ? "expand_less" : "expand_more"
                            iconSize: 24
                            color: rootContext.contentColor
                            opacity: 0.5
                        }
                    }

                    onClicked: {
                        rootContext.sleepTimerMenuVisible = !rootContext.sleepTimerMenuVisible
                    }
                }
                
                // Sleep Timer Menu (Expanded)
                Rectangle {
                    id: timerMenuRect
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: rootContext.sleepTimerMenuVisible ? 4 : 0
                    Layout.bottomMargin: rootContext.sleepTimerMenuVisible ? 8 : 0
                    Layout.preferredHeight: rootContext.sleepTimerMenuVisible ? 204 : 0
                    
                    visible: rootContext.sleepTimerMenuVisible || opacity > 0
                    opacity: rootContext.sleepTimerMenuVisible ? 1.0 : 0.0
                    clip: true
                    radius: 16
                    color: ColorUtils.applyAlpha(rootContext.contentColor, 0.06)
                    
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    ColumnLayout {
                        id: timerLayout
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        
                        Repeater {
                            model: [
                                { "label": "Off", "value": 0 },
                                { "label": "15 minutes", "value": 15 * 60 },
                                { "label": "30 minutes", "value": 30 * 60 },
                                { "label": "60 minutes", "value": 60 * 60 }
                            ]

                            delegate: RippleButton {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                buttonRadius: 12
                                colBackground: rootContext.sleepTimerSeconds === modelData.value ? rootContext.pillColor : "transparent"
                                colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                                colRipple: rootContext.contentColor
                                
                                contentItem: StyledText {
                                    text: modelData.label
                                    color: rootContext.sleepTimerSeconds === modelData.value ? rootContext.pillContentColor : rootContext.contentColor
                                    font.weight: rootContext.sleepTimerSeconds === modelData.value ? 700 : 500
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                
                                onClicked: {
                                    rootContext.sleepTimerSeconds = modelData.value
                                    rootContext.sleepTimerMenuVisible = false
                                    rootContext.radioTrayVisible = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Keyboard handler
    Shortcut {
        sequence: "Escape"
        enabled: root.trayVisible
        onActivated: rootContext.radioTrayVisible = false
    }
}
