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
    property bool closing: false

    onShowNotesChanged: {
        if (!showNotes) {
            closing = true;
            hideTimer.restart();
        }
    }

    function closeWindow() {
        if (root.showNotes) {
            closing = true
            NotesService.open = false
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 300 // Match WindowDialog closeDuration + padding
        repeat: false
        onTriggered: root.closing = false
    }

    IpcHandler {
        target: "notes"
        function toggle(): void {
            NotesService.toggle()
        }
        function open(): void {
            NotesService.open = true
        }
        function close(): void {
            root.closeWindow()
        }
    }

    GlobalShortcut {
        name: "notesToggle"
        description: "Toggle Notes layer"

        onPressed: NotesService.toggle()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.showNotes || root.closing
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:notes"
            WlrLayershell.keyboardFocus: root.showNotes ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onPressed: root.closeWindow()

                Rectangle {
                    id: notesDialog
                    width: Math.min(window.width * 0.85, 1100)
                    height: Math.min(window.height * 0.85, 750)
                    anchors.centerIn: parent
                    color: Appearance.m3colors.m3surfaceContainer
                    radius: Appearance.rounding.large
                    clip: true
                    
                    opacity: root.showNotes ? 1 : 0
                    scale: root.showNotes ? 1 : 0.95
                    transformOrigin: Item.Center
                    
                    Behavior on opacity {
                        NumberAnimation { 
                            duration: 250
                            easing.type: root.showNotes ? Easing.OutCubic : Easing.InCubic
                        }
                    }
                    
                    Behavior on scale {
                        NumberAnimation { 
                            duration: 350
                            easing.type: root.showNotes ? Easing.OutBack : Easing.InCubic
                            easing.overshoot: root.showNotes ? 0.8 : 0
                        }
                    }

                    // Prevent clicks on the panel from closing the window
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        hoverEnabled: true
                    }

                    NotesPanel {
                        anchors.fill: parent
                        onCloseRequested: root.closeWindow()
                    }
                }
            }
        }
    }
}
