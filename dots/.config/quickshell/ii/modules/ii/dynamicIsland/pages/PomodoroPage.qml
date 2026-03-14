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
        anchors.margins: 16
        implicitHeight: Math.max(infoLayout.implicitHeight, playContainer.height)

        // Left Side: Info & Secondary Controls
        ColumnLayout {
            // Secondary Controls - Removed and moved

            id: infoLayout

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: resetButton.left
            anchors.rightMargin: 16
            spacing: 8

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
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 2
                    color: Appearance.colors.colSubtext
                }

            }

            // Cycle Dots
            Row {
                spacing: 6

                Repeater {
                    model: 4

                    Rectangle {
                        readonly property bool completed: TimerService.pomodoroCycle > index
                        readonly property bool current: TimerService.pomodoroCycle == index

                        width: 6
                        height: 6
                        radius: 3
                        color: completed ? root.accentColor : current ? root.accentColor : ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.15)
                        opacity: current ? 1 : (completed ? 0.6 : 1)

                        // Current dot glow/scale
                        SequentialAnimation on scale {
                            running: current && root.isRunning
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: 1.3
                                duration: 1000
                                easing.type: Easing.InOutQuad
                            }

                            NumberAnimation {
                                to: 1
                                duration: 1000
                                easing.type: Easing.InOutQuad
                            }

                        }

                    }

                }

            }

            Item {
                Layout.fillHeight: true
            }

        }

        // Secondary Button (Reset)
        RippleButton {
            id: resetButton

            anchors.verticalCenter: playContainer.verticalCenter
            anchors.right: playContainer.left
            anchors.rightMargin: 12
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: 18
            colBackground: Appearance.colors.colSecondaryContainer
            colRipple: Appearance.colors.colOnSecondaryContainer
            onClicked: TimerService.resetPomodoro()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "restart_alt"
                iconSize: 18
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
                    color: root.accentColor
                }

            }

        }

    }

}
