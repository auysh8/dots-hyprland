import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

import QtQuick
import Quickshell
import Quickshell.Widgets
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
        } else if (!closing) {
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

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            visible: root.showDrawer || root.closing
            WlrLayershell.namespace: "quickshell:app-drawer"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: (root.showDrawer && !root.closing) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {
                item: (root.showDrawer || root.closing) ? drawerContainer : null
            }

            property bool grabActive: root.showDrawer && !root.closing

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration + 50
                repeat: false
                onTriggered: {
                    if (root.showDrawer && !root.closing) {
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
                    root.closeWindow();
                }
            }

            Shortcut {
                enabled: root.showDrawer
                sequence: "Escape"
                onActivated: root.closeWindow()
            }

            Item {
                id: drawerContainer
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut + 14
                width: Math.min(window.width * 0.9, 740)
                height: Math.min(window.height * 0.72, 640)

                opacity: root.showDrawer ? 1 : 0
                scale: root.showDrawer ? 1 : 0.97
                transformOrigin: Item.Bottom

                transform: Translate {
                    y: root.showDrawer ? 0 : 44
                    Behavior on y {
                        NumberAnimation { 
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }

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

                ApplicationDrawer {
                    id: drawer
                    anchors.fill: parent
                    expanded: true
                    availableWidth: drawerContainer.width
                    availableHeight: drawerContainer.height
                    onCloseRequested: root.closeWindow()
                }
            }

            Connections {
                target: root
                function onShowDrawerChanged() {
                    if (root.showDrawer) {
                        drawer.focusSearchField();
                    }
                }
            }
        }
    }
}
