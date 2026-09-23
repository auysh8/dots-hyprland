import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services

Item {
    id: pomodoroPageRoot
    anchors.fill: parent

    // Color Logic
    readonly property bool isBreak: TimerService.pomodoroBreak
    readonly property bool isRunning: TimerService.pomodoroRunning

    // M3 Color Pairs (Tonal Container + OnContainer)
    readonly property color containerColor: isBreak ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer
    readonly property color onContainerColor: isBreak ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer
    readonly property color accentColor: isBreak ? Appearance.colors.colSecondary : Appearance.colors.colError
    readonly property color onAccentColor: isBreak ? Appearance.colors.colOnSecondary : Appearance.colors.colOnError

    // Constants
    readonly property int focusDuration: 25 * 60
    readonly property int shortBreakDuration: 5 * 60
    readonly property int longBreakDuration: 15 * 60
    property int currentMaxDuration: {
        if (TimerService.pomodoroLongBreak)
            return longBreakDuration;

        if (TimerService.pomodoroBreak)
            return shortBreakDuration;

        return focusDuration;
    }
    // 1.0 -> 0.0 (Depletes)
    property real progress: TimerService.pomodoroSecondsLeft / currentMaxDuration

    implicitHeight: Math.max(mainRow.implicitHeight + 10, 100)

    RowLayout {
        id: mainRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        // 1. Left Side: Material Shape Hero Container (Clover4Leaf)
        Item {
            id: heroContainer
            Layout.preferredWidth: 78
            Layout.preferredHeight: 78
            implicitWidth: 78
            implicitHeight: 78
            Layout.alignment: Qt.AlignVCenter

            MaterialShape {
                id: shapeBackground
                anchors.fill: parent
                implicitSize: 78
                color: pomodoroPageRoot.containerColor
                shape: pomodoroPageRoot.isRunning
                    ? MaterialShape.Shape.Sunny
                    : (pomodoroPageRoot.isBreak ? MaterialShape.Shape.Cookie4Sided : MaterialShape.Shape.Clover4Leaf)
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
                text: pomodoroPageRoot.isBreak ? "coffee" : "local_fire_department"
                iconSize: 30
                fill: 1
                color: pomodoroPageRoot.isBreak ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer
            }
        }

        // 2. Right Side: Digits, Header Pill, and M3 ButtonGroup Controls
        ColumnLayout {
            id: detailsCol
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // Header Row: Timer digits on left, Round context pill on right
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: timeText
                    text: {
                        let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                        let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                        return m + ":" + s;
                    }
                    font.pixelSize: 30
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }

                Item {
                    Layout.fillWidth: true
                }

                // Subtitle Chip (M3 Capsule Pill aligned top-right)
                Rectangle {
                    implicitHeight: 30
                    implicitWidth: subtitleRow.implicitWidth + 20
                    radius: 15
                    color: Appearance.colors.colSurfaceContainerHigh

                    Row {
                        id: subtitleRow
                        anchors.centerIn: parent
                        spacing: 7

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pomodoroPageRoot.isBreak ? "free_breakfast" : "self_improvement"
                            iconSize: 15
                            fill: 1
                            color: pomodoroPageRoot.isBreak ? Appearance.colors.colSecondary : Appearance.colors.colError
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (TimerService.pomodoroLongBreak)
                                    return "Long Break";
                                if (TimerService.pomodoroBreak)
                                    return "Short Break";
                                let cycle = (TimerService.pomodoroCycle || 0) + 1;
                                let total = TimerService.cyclesBeforeLongBreak || 4;
                                return "Round " + cycle + " of " + total;
                            }
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // Controls Row (M3 ButtonGroup with responsive bounciness & tactile feedback like KDEDrawer)
            ButtonGroup {
                id: pomodoroButtonGroup
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 6
                padding: 0

                // Main Play / Pause / Resume Action Pill
                GroupButton {
                    id: playActionBtn
                    Layout.fillWidth: true
                    baseWidth: Math.floor((parent.width - 12) * 0.52)
                    baseHeight: 32
                    clickedWidth: baseWidth + 14
                    buttonRadius: 16
                    buttonRadiusPressed: 11
                    bounce: true

                    colBackground: pomodoroPageRoot.isRunning
                        ? (pomodoroPageRoot.isBreak ? Appearance.colors.colSecondary : Appearance.colors.colError)
                        : (pomodoroPageRoot.isBreak ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer)
                    colBackgroundHover: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.88)
                    colBackgroundActive: ColorUtils.mix(colBackground, Appearance.colors.colOnSurface, 0.72)

                    onClicked: TimerService.togglePomodoro()

                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pomodoroPageRoot.isRunning ? "pause" : "play_arrow"
                            iconSize: 17
                            fill: 1
                            color: pomodoroPageRoot.isRunning
                                ? (pomodoroPageRoot.isBreak ? Appearance.colors.colOnSecondary : Appearance.colors.colOnError)
                                : (pomodoroPageRoot.isBreak ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer)
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pomodoroPageRoot.isRunning ? "Pause" : (TimerService.pomodoroSecondsLeft < pomodoroPageRoot.currentMaxDuration ? "Resume" : "Start")
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: pomodoroPageRoot.isRunning
                                ? (pomodoroPageRoot.isBreak ? Appearance.colors.colOnSecondary : Appearance.colors.colOnError)
                                : (pomodoroPageRoot.isBreak ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer)
                        }
                    }
                }

                // Reset Button (Dynamic Tonal Container)
                GroupButton {
                    id: resetBtn
                    Layout.fillWidth: true
                    baseWidth: Math.floor((parent.width - 12) * 0.24)
                    baseHeight: 32
                    clickedWidth: baseWidth + 10
                    buttonRadius: 16
                    buttonRadiusPressed: 11
                    bounce: true

                    colBackground: pomodoroPageRoot.containerColor
                    colBackgroundHover: ColorUtils.mix(pomodoroPageRoot.containerColor, Appearance.colors.colOnSurface, 0.88)
                    colBackgroundActive: ColorUtils.mix(pomodoroPageRoot.containerColor, Appearance.colors.colOnSurface, 0.72)

                    onClicked: TimerService.resetPomodoro()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "restart_alt"
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Skip / Advance Button (Dynamic Tonal Container)
                GroupButton {
                    id: skipBtn
                    Layout.fillWidth: true
                    baseWidth: Math.floor((parent.width - 12) * 0.24)
                    baseHeight: 32
                    clickedWidth: baseWidth + 10
                    buttonRadius: 16
                    buttonRadiusPressed: 11
                    bounce: true

                    colBackground: pomodoroPageRoot.containerColor
                    colBackgroundHover: ColorUtils.mix(pomodoroPageRoot.containerColor, Appearance.colors.colOnSurface, 0.88)
                    colBackgroundActive: ColorUtils.mix(pomodoroPageRoot.containerColor, Appearance.colors.colOnSurface, 0.72)

                    onClicked: {
                        Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
                        Persistent.states.timer.pomodoro.start = TimerService.getCurrentTimeInSeconds();
                        TimerService.refreshPomodoro();
                    }

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "skip_next"
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }
}
