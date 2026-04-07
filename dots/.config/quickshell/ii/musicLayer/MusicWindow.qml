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

Scope {
    id: root
    property bool showMusic: MusicService.open
    property bool closing: false

    onShowMusicChanged: {
        if (!showMusic) closing = true;
    }

    function closeWindow() {
        if (root.showMusic) {
            closing = true
            MusicService.open = false
        }
    }

    IpcHandler {
        target: "music"
        function toggle(): void {
            MusicService.toggle()
        }
        function open(): void {
            MusicService.open = true
        }
        function close(): void {
            root.closeWindow()
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.showMusic || root.closing
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:music"
            WlrLayershell.keyboardFocus: root.showMusic ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Appearance.colors.colScrim
                opacity: root.showMusic ? 0.5 : 0

                Behavior on opacity {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                    }
                }

                MouseArea {
                    id: backgroundClickArea
                    anchors.fill: parent
                    scrollGestureEnabled: false
                    onClicked: (mouse) => {
                        const panelBounds = musicPanel.mapToItem(backgroundClickArea, 0, 0, musicPanel.width, musicPanel.height);
                        const clickInPanel = mouse.x >= panelBounds.x && mouse.x <= panelBounds.x + panelBounds.width &&
                                             mouse.y >= panelBounds.y && mouse.y <= panelBounds.y + panelBounds.height;
                        if (!clickInPanel)
                            root.closeWindow();
                    }
                }
            }

            Item {
                id: musicPanel
                anchors.horizontalCenter: parent.horizontalCenter

                readonly property real floatingHeight: Math.min(parent.height * 0.85, 800)
                readonly property real floatingY: (parent.height - floatingHeight) / 2

                y: floatingY
                width: Math.min(parent.width * 0.7, 1100)
                height: floatingHeight

                opacity: root.showMusic ? 1 : 0
                scale: root.showMusic ? 1 : 0.9

                Behavior on opacity {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.easing
                        onRunningChanged: if (!running && !root.showMusic) root.closing = false
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.easing
                    }
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        root.closeWindow()
                        event.accepted = true
                    }
                }

                Item {
                    id: panelContent
                    anchors.fill: parent
                    layer.enabled: !musicApp.isLayoutTransitioning
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: panelContent.width
                            height: panelContent.height
                            radius: Appearance.rounding.large
                        }
                    }

                    MusicApp {
                        id: musicApp
                        anchors.fill: parent
                        isAppMode: false
                        showMusic: root.showMusic
                        closing: root.closing
                        onCloseRequested: root.closeWindow()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.large
                    color: "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                }
            }
        }
    }
}
