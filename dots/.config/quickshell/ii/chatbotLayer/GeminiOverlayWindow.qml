import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "../modules/common" as Common
import "../modules/common/widgets" as CommonWidgets
import qs

Scope {
    id: root

    // ── Exit-animation gate ────────────────────────────────────────────
    // Keeps the PanelWindow alive long enough for the close animation to
    // finish before the surface is actually destroyed.
    property bool actuallyVisible: GlobalStates.geminiOverlayOpen

    Timer {
        id: exitTimer
        // Slightly longer than the exit transition so the surface doesn't
        // vanish mid-animation. Tweak alongside the Transition duration.
        interval: 220
        onTriggered: root.actuallyVisible = false
    }

    Connections {
        target: GlobalStates
        function onGeminiOverlayOpenChanged() {
            if (GlobalStates.geminiOverlayOpen) {
                exitTimer.stop();
                root.actuallyVisible = true;
            } else {
                exitTimer.restart();
            }
        }
    }

    Process {
        id: geminiServerProcess
        running: true
        command: [
            Quickshell.shellPath("../scripts/venv/bin/python3").replace("file://", ""),
            "-u",
            Quickshell.shellPath("../scripts/gemini_server.py").replace("file://", "")
        ]
        
        stdout: SplitParser {
            onRead: data => console.log("[Gemini Server] " + data.trim())
        }
        stderr: SplitParser {
            onRead: data => console.log("[Gemini Server ERROR] " + data.trim())
        }
    }

    PanelWindow {
        id: panelWindow
        // Stay visible while either open OR animating closed.
        visible: root.actuallyVisible
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        WlrLayershell.namespace: "quickshell:geminichat"
        WlrLayershell.layer: WlrLayer.Overlay
        // Release keyboard focus immediately on close, even while exit anim plays.
        WlrLayershell.keyboardFocus: GlobalStates.geminiOverlayOpen
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.geminiOverlayOpen = false; }
        }

        Shortcut {
            sequence: "Escape"
            onActivated: GlobalStates.geminiOverlayOpen = false
        }

        // ── Scrim ─────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: Common.Appearance.colors.colScrim
            opacity: GlobalStates.geminiOverlayOpen ? 0.45 : 0

            // Enter: OutQuad (decelerate in). Exit: InQuad (accelerate out).
            Behavior on opacity {
                NumberAnimation {
                    duration: GlobalStates.geminiOverlayOpen
                        ? Common.Appearance.animation.elementMoveFast.duration
                        : 180
                    easing.type: GlobalStates.geminiOverlayOpen
                        ? Easing.OutQuad
                        : Easing.InQuad
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: GlobalStates.geminiOverlayOpen = false
            }
        }

        // ── Panel container ───────────────────────────────────────────
        Item {
            id: panelContainer
            width: 800

            // Bottom-docked. Height is animated to expand upwards.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24

            height: chatUI.implicitHeight

            transform: Translate { id: panelTranslate }

            // Animate height changes (chat expand / collapse)
            Behavior on height {
                NumberAnimation {
                    duration: Common.Appearance.animation.elementMove.duration
                    easing.type: Common.Appearance.animation.elementMove.type
                    easing.bezierCurve: Common.Appearance.animation.elementMove.bezierCurve
                }
            }

            // ── Asymmetric enter / exit animation ─────────────────────
            // M3 motion: enter decelerates (OutExpo — snappy arrival),
            //            exit accelerates  (InCubic — confident departure).
            states: [
                State {
                    name: "open"
                    PropertyChanges { target: panelContainer; opacity: 1.0 }
                    PropertyChanges { target: panelTranslate; y: 0 }
                },
                State {
                    name: "closed"
                    PropertyChanges { target: panelContainer; opacity: 0.0 }
                    PropertyChanges { target: panelTranslate; y: panelContainer.height + 50 }
                }
            ]
            
            state: GlobalStates.geminiOverlayOpen ? "open" : "closed"

            transitions: [
                // Enter — slide up and fade in
                Transition {
                    to: "open"
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            duration: Common.Appearance.animation.elementMoveEnter.duration
                            easing.type: Common.Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Common.Appearance.animation.elementMoveEnter.bezierCurve
                        }
                        NumberAnimation {
                            target: panelTranslate
                            property: "y"
                            duration: Common.Appearance.animation.elementMoveEnter.duration
                            easing.type: Common.Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Common.Appearance.animation.elementMoveEnter.bezierCurve
                        }
                    }
                },
                // Exit — slide down and fade out
                Transition {
                    to: "closed"
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            duration: 160
                            easing.type: Easing.InCubic
                        }
                        NumberAnimation {
                            target: panelTranslate
                            property: "y"
                            duration: 200
                            easing.type: Easing.InCubic
                        }
                    }
                }
            ]

            // ── Drop shadow ───────────────────────────────────────────
            CommonWidgets.StyledRectangularShadow {
                target: panelSurface
                anchors.fill: undefined
                blur: 28
                spread: 3
                offset: Qt.vector2d(0, 6)
                color: Common.Appearance.colors.colShadow
            }

            // ── Surface ───────────────────────────────────────────────
            Rectangle {
                id: panelSurface
                anchors.fill: parent
                color: Common.Appearance.colors.colLayer0
                radius: Common.Appearance.rounding.screenRounding
                border.width: 1
                border.color: Common.Appearance.colors.colLayer0Border
                clip: true

                // Prevent click-through to scrim
                MouseArea { anchors.fill: parent; onClicked: {} }

                GeminiChat {
                    id: chatUI
                    anchors.fill: parent
                }
            }
        }
    }
}
