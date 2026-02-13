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
        if (!showNotes) closing = true;
    }

    function closeWindow() {
        if (root.showNotes) {
            closing = true
            NotesService.open = false
        }
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

            // Scrim background (invisible)
            Rectangle {
                id: scrim
                anchors.fill: parent
                color: "transparent"

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.closeWindow()
                }
            }

            Rectangle {
                id: notesPanel
                anchors.horizontalCenter: parent.horizontalCenter

                readonly property real floatingHeight: Math.min(parent.height * 0.8, 650)
                readonly property real floatingY: (parent.height - floatingHeight) / 2

                y: floatingY
                width: Math.min(parent.width * 0.75, 900)
                height: floatingHeight
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                clip: true
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                opacity: root.showNotes ? 1 : 0
                scale: root.showNotes ? 1 : 0.9

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                        onRunningChanged: if (!running && !root.showNotes) root.closing = false
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }

                // Prevent click-through to scrim
                MouseArea { anchors.fill: parent; onClicked: {} }

                // Keyboard handling
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        root.closeWindow()
                        event.accepted = true
                    }
                }

                NotesPanel {
                    anchors.fill: parent
                    onCloseRequested: root.closeWindow()
                }
            }
        }
    }
}
