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

    // Color Logic
    readonly property bool isBreak: TimerService.pomodoroBreak
    readonly property bool isRunning: TimerService.pomodoroRunning
    // Accent Color based on state
    readonly property color accentColor: isBreak ? Appearance.colors.colSecondaryContainer : Appearance.colors.colErrorContainer
    readonly property color onAccentColor: isBreak ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnErrorContainer
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

    implicitHeight: mainLayout.implicitHeight + 32

    // Background (Dark)
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    Item {
        id: mainLayout

        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        implicitHeight: Math.max(infoLayout.implicitHeight, playContainer.height)

        // Left Side: Info & Status
        ColumnLayout {
            id: infoLayout

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: resetButton.left
            anchors.rightMargin: 16
            spacing: 6

            // Timer + Status Group
            ColumnLayout {
                id: timerGroup
                spacing: 0

                StyledText {
                    id: timeText

                    text: {
                        let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                        let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                        return m + ":" + s;
                    }
                    font.pixelSize: 48
                    font.weight: Font.Bold
                    font.family: "monospace" // Prevents number jitter natively
                    color: root.accentColor
                    horizontalAlignment: Text.AlignLeft
                }

                StyledText {
                    text: {
                        if (TimerService.pomodoroLongBreak)
                            return "Long Break";

                        if (TimerService.pomodoroBreak)
                            return "Short Break";

                        return "Focus Session";
                    }
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 2
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                }
            }

            // Cycle Dashes (Stadium Pills)
            Row {
                spacing: 5

                Repeater {
                    model: 4

                    Rectangle {
                        readonly property bool completed: TimerService.pomodoroCycle > index
                        readonly property bool current: TimerService.pomodoroCycle == index

                        width: 16
                        height: 4
                        radius: 2
                        color: (completed || current) ? root.accentColor : ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.18)
                        opacity: current ? 1.0 : (completed ? 0.9 : 0.6)

                        // Current dash pulse animation when running
                        SequentialAnimation on opacity {
                            running: current && root.isRunning
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: 0.45
                                duration: 800
                                easing.type: Easing.InOutQuad
                            }

                            NumberAnimation {
                                to: 1.0
                                duration: 800
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
            }
        }

        // Secondary Button (Reset)
        RippleButton {
            id: resetButton

            anchors.verticalCenter: playContainer.verticalCenter
            anchors.right: playContainer.left
            anchors.rightMargin: 12
            implicitWidth: 42
            implicitHeight: 42
            buttonRadius: 21
            colBackground: Appearance.colors.colSecondaryContainer
            colRipple: Appearance.colors.colOnSecondaryContainer
            onClicked: TimerService.resetPomodoro()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "restart_alt"
                iconSize: 20
                fill: 1
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        // Right Side: Circular Progress + Play Button
        Item {
            id: playContainer

            width: 80
            height: 80
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            // 2. Circular Progress Ring (Reuse Component)
            CircularProgress {
                anchors.centerIn: parent
                implicitSize: 80
                lineWidth: 6
                value: root.progress
                colPrimary: root.accentColor
                colSecondary: ColorUtils.applyAlpha(root.accentColor, 0.2)
                enableAnimation: true
            }

            // 3. Play/Pause Button (Center)
            RippleButton {
                anchors.centerIn: parent
                implicitWidth: 56
                implicitHeight: 56
                buttonRadius: 28
                colBackground: "transparent"
                colRipple: root.accentColor
                onClicked: TimerService.togglePomodoro()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isRunning ? "pause" : "play_arrow"
                    iconSize: 32
                    fill: 1
                    color: root.accentColor
                }
            }
        }

    }

}
