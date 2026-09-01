import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent

    // Properties
    readonly property bool isRunning: TimerService.stopwatchRunning
    readonly property color accentColor: Appearance.colors.colTertiary
    readonly property color onAccentColor: Appearance.colors.colOnTertiary

    implicitHeight: Math.max(infoLayout.implicitHeight + 32, 112)

    // Background
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    Item {
        id: mainContainer

        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16

        // 1. Right: Play/Pause Button (Centered Vertically)
        Item {
            id: playContainer

            width: 80
            height: 80
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            // Main Play Button
            RippleButton {
                anchors.centerIn: parent
                implicitWidth: 56
                implicitHeight: 56
                buttonRadius: 28
                colBackground: root.isRunning ? Appearance.colors.colSecondaryContainer : root.accentColor
                colRipple: root.isRunning ? Appearance.colors.colOnSecondaryContainer : root.onAccentColor
                onClicked: TimerService.toggleStopwatch()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isRunning ? "pause" : "play_arrow"
                    iconSize: 32
                    fill: 1
                    color: root.isRunning ? Appearance.colors.colOnSecondaryContainer : root.onAccentColor
                }
            }
        }

        // Left Side: Time & Info
        ColumnLayout {
            id: infoLayout

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: buttonsRow.left
            anchors.rightMargin: 16
            spacing: 6

            // Time Display Group
            ColumnLayout {
                spacing: 0

                Row {
                    spacing: 2

                    StyledText {
                        id: mainTime

                        text: {
                            let t = Math.floor(TimerService.stopwatchTime / 100);
                            let m = Math.floor(t / 60).toString().padStart(2, '0');
                            let s = Math.floor(t % 60).toString().padStart(2, '0');
                            return m + ":" + s;
                        }
                        font.pixelSize: 48
                        font.weight: Font.Bold
                        color: root.accentColor
                    }

                    StyledText {
                        anchors.baseline: mainTime.baseline
                        text: "." + Math.floor((TimerService.stopwatchTime % 100)).toString().padStart(2, '0')
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                        color: root.accentColor
                        opacity: 0.6
                    }
                }

                // Lap Capsule Pill
                Pill {
                    id: lapPill
                    visible: root.isRunning || TimerService.stopwatchTime > 0
                    implicitHeight: 24
                    implicitWidth: lapContent.width + 16
                    color: ColorUtils.applyAlpha(root.accentColor, 0.20)
                    Layout.topMargin: 4

                    Row {
                        id: lapContent
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "flag"
                            iconSize: 13
                            fill: 1
                            color: root.accentColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1
                            text: "Lap " + (TimerService.stopwatchLaps ? (TimerService.stopwatchLaps.length + 1) : 1)
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: root.accentColor
                        }
                    }
                }
            }
        }

        // Secondary Buttons Row (Reset & Lap with Animated Reveal/Slide)
        RowLayout {
            id: buttonsRow

            anchors.verticalCenter: playContainer.verticalCenter
            anchors.right: playContainer.left
            anchors.rightMargin: 12
            spacing: (resetRevealer.reveal && lapRevealer.reveal) ? 8 : 0

            Behavior on spacing {
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            // Reset Button (Reveals when time > 0, smoothly slides to play button when lap hides)
            Revealer {
                id: resetRevealer
                reveal: TimerService.stopwatchTime > 0
                Layout.alignment: Qt.AlignVCenter

                RippleButton {
                    id: resetButton
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: 20
                    colBackground: Appearance.colors.colSecondaryContainer
                    colRipple: Appearance.colors.colOnSecondaryContainer
                    onClicked: TimerService.stopwatchReset()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "restart_alt"
                        iconSize: 18
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }

            // Lap Button (Reveals while running)
            Revealer {
                id: lapRevealer
                reveal: root.isRunning
                Layout.alignment: Qt.AlignVCenter

                RippleButton {
                    id: lapButton
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: 20
                    colBackground: Appearance.colors.colSecondaryContainer
                    colRipple: Appearance.colors.colOnSecondaryContainer
                    onClicked: TimerService.stopwatchRecordLap()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "flag"
                        iconSize: 18
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }

    }

}
