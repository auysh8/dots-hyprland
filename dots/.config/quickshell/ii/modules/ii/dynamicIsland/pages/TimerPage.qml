import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import Quickshell
import Quickshell.Services.Mpris
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root


    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 12
        
        // Timer Icon / Info
        MaterialSymbol {
            text: TimerService.pomodoroRunning ? "timer" : "timer_off"
            iconSize: 32
            color: TimerService.pomodoroRunning ? Appearance.colors.colError : Appearance.colors.colOnLayer0
        }
        
        // Big Time Text
        Text {
            Layout.fillWidth: true
            text: {
                 if (TimerService.pomodoroRunning || (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration && TimerService.pomodoroSecondsLeft > 0)) {
                    let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                    let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                    return m + ":" + s;
                 }
                 if (TimerService.stopwatchRunning) {
                    let t = TimerService.stopwatchTime / 100;
                    let m = Math.floor(t / 60).toString().padStart(2, '0');
                    let s = Math.floor(t % 60).toString().padStart(2, '0');
                    return m + ":" + s;
                 }
                 return "00:00";
            }
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 32
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
        
        // Controls
        RowLayout {
            spacing: 8
            
            // Stop/Reset
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: 20
                colBackground: Appearance.colors.colLayer2
                onClicked: {
                    if (TimerService.pomodoroRunning) TimerService.resetPomodoro();
                    else if (TimerService.stopwatchRunning) TimerService.stopwatchReset();
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "stop"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer2
                }
            }
            
            // Play/Pause
            RippleButton {
                implicitWidth: 48
                implicitHeight: 48
                buttonRadius: 24
                colBackground: Appearance.colors.colPrimary
                onClicked: {
                     if (TimerService.stopwatchRunning) TimerService.toggleStopwatch();
                     else TimerService.togglePomodoro();
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: (TimerService.pomodoroRunning || TimerService.stopwatchRunning) ? "pause" : "play_arrow"
                    iconSize: 24
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
