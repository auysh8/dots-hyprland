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

    // Properties & Theming
    readonly property bool isRunning: TimerService.stopwatchRunning
    readonly property bool hasElapsed: TimerService.stopwatchTime > 0
    readonly property color containerColor: Appearance.colors.colTertiaryContainer
    readonly property color onContainerColor: Appearance.colors.colOnTertiaryContainer
    readonly property color accentColor: Appearance.colors.colTertiary
    readonly property color onAccentColor: Appearance.colors.colOnTertiary

    implicitHeight: Math.max(mainRow.implicitHeight + 16, 100)

    RowLayout {
        id: mainRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        // 1. Left Side: Material Shape Hero Container (76x76px Puffy / Cookie)
        Item {
            id: heroContainer
            Layout.preferredWidth: 76
            Layout.preferredHeight: 76
            implicitWidth: 76
            implicitHeight: 76
            Layout.alignment: Qt.AlignVCenter

            MaterialShape {
                id: shapeBackground
                anchors.fill: parent
                implicitSize: 76
                color: root.containerColor
                shape: root.isRunning ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie4Sided
                animation: NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }
            }

            MaterialSymbol {
                id: heroSymbol
                anchors.centerIn: parent
                text: "timer"
                iconSize: 32
                fill: 1
                color: root.onContainerColor

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }
            }
        }

        // 2. Right Side: Time Digits, Lap Chip, and Tactile ButtonGroup
        ColumnLayout {
            id: detailsCol
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // Header Row: Time digits on left, Lap context pill on right
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                Row {
                    spacing: 2
                    Layout.alignment: Qt.AlignBaseline

                    StyledText {
                        id: mainTime
                        text: {
                            let t = Math.floor(TimerService.stopwatchTime / 100);
                            let m = Math.floor(t / 60).toString().padStart(2, '0');
                            let s = Math.floor(t % 60).toString().padStart(2, '0');
                            return m + ":" + s;
                        }
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        anchors.baseline: mainTime.baseline
                        text: "." + Math.floor((TimerService.stopwatchTime % 100)).toString().padStart(2, '0')
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: root.accentColor
                        opacity: 0.9
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Lap Capsule Pill
                Rectangle {
                    implicitHeight: 24
                    implicitWidth: lapRow.implicitWidth + 14
                    radius: 12
                    color: Appearance.colors.colSurfaceContainerHigh

                    Row {
                        id: lapRow
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
                            text: "Lap " + (TimerService.stopwatchLaps ? (TimerService.stopwatchLaps.length + 1) : 1)
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // Controls Row (M3 ButtonGroup with KDEDrawer tactile feedback)
            ButtonGroup {
                id: stopwatchButtonGroup
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 6
                padding: 0

                // Main Play / Pause / Resume Pill Button
                GroupButton {
                    id: playActionBtn
                    Layout.fillWidth: true
                    baseWidth: Math.floor((parent.width - 12) * 0.52)
                    baseHeight: 32
                    clickedWidth: baseWidth + 10
                    buttonRadius: 16
                    buttonRadiusPressed: 11
                    bounce: true

                    colBackground: root.isRunning ? Appearance.colors.colSecondaryContainer : root.accentColor
                    colBackgroundHover: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.88)
                    colBackgroundActive: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.72)

                    onClicked: TimerService.toggleStopwatch()

                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isRunning ? "pause" : "play_arrow"
                            iconSize: 17
                            fill: 1
                            color: root.isRunning ? Appearance.colors.colOnSecondaryContainer : root.onAccentColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isRunning ? "Pause" : (root.hasElapsed ? "Resume" : "Start")
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: root.isRunning ? Appearance.colors.colOnSecondaryContainer : root.onAccentColor
                        }
                    }
                }

                // Lap Button (Always present in layout, disabled/dimmed when paused)
                GroupButton {
                    id: lapBtn
                    Layout.fillWidth: true
                    baseWidth: Math.floor((parent.width - 12) * 0.24)
                    baseHeight: 32
                    clickedWidth: baseWidth + 10
                    buttonRadius: 16
                    buttonRadiusPressed: 11
                    bounce: true
                    enabled: root.isRunning
                    opacity: root.isRunning ? 1.0 : 0.45

                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.88)
                    colBackgroundActive: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.72)

                    onClicked: TimerService.stopwatchRecordLap()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "flag"
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                // Reset Button (Enabled when elapsed)
                GroupButton {
                    id: resetBtn
                    Layout.fillWidth: true
                    baseWidth: Math.floor((parent.width - 12) * 0.24)
                    baseHeight: 32
                    clickedWidth: baseWidth + 10
                    buttonRadius: 16
                    buttonRadiusPressed: 11
                    bounce: true
                    enabled: root.hasElapsed
                    opacity: root.hasElapsed ? 1.0 : 0.45

                    Behavior on opacity {
                        NumberAnimation { duration: 180 }
                    }

                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.88)
                    colBackgroundActive: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.72)

                    onClicked: TimerService.stopwatchReset()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "restart_alt"
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
