import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool showNotes: NotesService.open

    function closeWindow() {
        NotesService.open = false;
    }

    function toggleWindow() {
        NotesService.toggle();
    }

    IpcHandler {
        target: "notes"
        function toggle() { root.toggleWindow(); }
        function open() { NotesService.open = true; }
        function close() { root.closeWindow(); }
    }

    GlobalShortcut {
        name: "notesToggle"
        description: "Toggle Notes layer"
        onPressed: root.toggleWindow()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            visible: root.showNotes
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:notes"
            WlrLayershell.keyboardFocus: root.showNotes ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            implicitWidth: Math.min((window.screen?.width ?? 1920) * 0.85, 1100)
            implicitHeight: Math.min((window.screen?.height ?? 1080) * 0.85, 750)

            mask: Region {
                item: root.showNotes ? notesDialog : null
            }

            property bool grabActive: root.showNotes

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration + 50
                repeat: false
                onTriggered: {
                    if (root.showNotes) {
                        GlobalFocusGrab.addDismissable(window);
                    }
                }
            }

            onGrabActiveChanged: {
                if (grabActive) {
                    delayedGrabTimer.restart();
                } else {
                    delayedGrabTimer.stop();
                    GlobalFocusGrab.removeDismissable(window);
                }
            }

            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(window);
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (root.showNotes) {
                        root.closeWindow();
                    }
                }
            }

            Shortcut {
                enabled: root.showNotes
                sequence: "Escape"
                onActivated: root.closeWindow()
            }

            Rectangle {
                id: notesDialog
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.verylarge
                clip: true

                NotesPanel {
                    anchors.fill: parent
                    onCloseRequested: root.closeWindow()
                }
            }
        }
    }
}
