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

    anchors.fill: parent
    z: 1000
    visible: trayVisible  // Only visible when tray is shown

    // Overlay background (dimming)
    Rectangle {
        anchors.fill: parent
        color: ColorUtils.applyAlpha("black", 0.5)
        opacity: root.trayVisible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.trayVisible
            onClicked: root.trayVisible = false
        }
    }

    // Bottom tray
    Rectangle {
        id: tray
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        height: trayContent.implicitHeight + 32
        radius: 24
        color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer2

        y: root.trayVisible ? 0 : height + 24

        Behavior on y {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
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

            // Radio button
            RippleButton {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 48
                Layout.alignment: Qt.AlignHCenter
                buttonRadius: 24
                rippleEnabled: true
                colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colSecondaryContainer
                colBackgroundHover: rootContext ? rootContext.pillColorHover : Appearance.colors.colSecondaryContainer
                colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer, 0.3)
                horizontalPadding: 16
                verticalPadding: 0

                contentItem: RowLayout {
                    spacing: 12

                    MaterialSymbol {
                        text: "queue_music"
                        iconSize: 24
                        fill: 1
                        color: rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer
                    }

                    Label {
                        text: "Start Radio"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer
                    }
                }

                onClicked: {
                    root.trayVisible = false
                    if (rootContext && rootContext.currentTrack) {
                        rootContext.sendCommand({
                            "command": "populate_radio",
                            "videoId": rootContext.currentTrack.videoId
                        })
                    }
                }
            }
        }
    }

    // Keyboard handler
    Shortcut {
        sequence: "Escape"
        enabled: root.trayVisible
        onActivated: root.trayVisible = false
    }
}
