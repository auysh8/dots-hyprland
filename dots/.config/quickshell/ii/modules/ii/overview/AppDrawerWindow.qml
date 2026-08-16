import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool showDrawer: GlobalStates.appDrawerOpen
    property bool closing: false

    onShowDrawerChanged: {
        if (!showDrawer) {
            closing = true;
            hideTimer.restart();
        } else {
            closing = false;
            hideTimer.stop();
        }
    }

    function closeWindow() {
        if (GlobalStates.appDrawerOpen) {
            closing = true;
            GlobalStates.appDrawerOpen = false;
            hideTimer.restart();
        }
    }

    function toggleWindow() {
        if (GlobalStates.appDrawerOpen) {
            closeWindow();
        } else {
            GlobalStates.appDrawerOpen = true;
        }
    }

    Timer {
        id: hideTimer
        interval: 300
        repeat: false
        onTriggered: root.closing = false
    }

    IpcHandler {
        target: "app-drawer"
        function toggle() { root.toggleWindow() }
        function open() { GlobalStates.appDrawerOpen = true }
        function close() { root.closeWindow() }
    }

    GlobalShortcut {
        name: "appDrawerToggle"
        description: "Toggle App Drawer layer"

        onPressed: root.toggleWindow()
    }

    Variants {
        model: Quickshell.screens

        LayerManagedPanelWindow {
            id: window
            required property var modelData
            screen: modelData
            
            shown: root.showDrawer
            closing: root.closing
            layerNamespace: "app-drawer"
            keyboardFocusMode: WlrKeyboardFocus.OnDemand
            
            onCloseRequested: root.closeWindow()

            Item {
                id: drawerContainer
                anchors.centerIn: parent
                width: Math.min(window.width * 0.85, 1250)
                height: Math.min(window.height * 0.85, 850)

                opacity: root.showDrawer ? 1 : 0
                scale: root.showDrawer ? 1 : 0.95
                transformOrigin: Item.Center

                Behavior on opacity {
                    NumberAnimation { 
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Behavior on scale {
                    NumberAnimation { 
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                // Prevent clicks on the panel from bubbling to the backdrop MouseArea
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    hoverEnabled: true
                }

                ApplicationDrawer {
                    id: drawer
                    anchors.fill: parent
                    expanded: true
                    availableWidth: drawerContainer.width
                    availableHeight: drawerContainer.height
                    onCloseRequested: root.closeWindow()
                }
            }

            onShownChanged: {
                if (shown) {
                    drawer.focusSearchField();
                }
            }
        }
    }
}
