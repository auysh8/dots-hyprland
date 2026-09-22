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

    function closeWindow() {
        if (GlobalStates.appDrawerOpen) {
            GlobalStates.appDrawerOpen = false;
        }
    }

    function toggleWindow() {
        GlobalStates.appDrawerOpen = !GlobalStates.appDrawerOpen;
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

            visible: root.showDrawer
            WlrLayershell.namespace: "quickshell:app-drawer"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.showDrawer ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                bottom: true
            }
            margins {
                bottom: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut + 14
            }

            implicitWidth: Math.min((window.screen?.width ?? 1920) * 0.9, 740)
            implicitHeight: Math.min((window.screen?.height ?? 1080) * 0.72, 640)

            mask: Region {
                item: root.showDrawer ? drawerContainer : null
            }

            property bool grabActive: root.showDrawer

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration + 50
                repeat: false
                onTriggered: {
                    if (root.showDrawer) {
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
                    if (root.showDrawer) {
                        root.closeWindow();
                    }
                }
            }

            Shortcut {
                enabled: root.showDrawer
                sequence: "Escape"
                onActivated: root.closeWindow()
            }

            Item {
                id: drawerContainer
                anchors.fill: parent

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
