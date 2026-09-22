import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root
    property bool showSettings: false

    function openWindow() {
        root.showSettings = true;
    }

    function closeWindow() {
        root.showSettings = false;
    }

    function toggleWindow() {
        root.showSettings = !root.showSettings;
    }

    IpcHandler {
        target: "settings"
        function toggle() { root.toggleWindow(); }
        function open() { root.openWindow(); }
        function close() { root.closeWindow(); }
    }

    GlobalShortcut {
        name: "settingsToggle"
        description: "Toggles settings layer"
        onPressed: root.toggleWindow()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            visible: root.showSettings
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:settings"
            WlrLayershell.keyboardFocus: root.showSettings ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            implicitWidth: Math.min((window.screen?.width ?? 1920) * 0.85, 1150)
            implicitHeight: Math.min((window.screen?.height ?? 1080) * 0.85, 800)

            mask: Region {
                item: root.showSettings ? settingsDialog : null
            }

            property bool grabActive: root.showSettings

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration + 50
                repeat: false
                onTriggered: {
                    if (root.showSettings) {
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
                    if (root.showSettings) {
                        root.closeWindow();
                    }
                }
            }

            Shortcut {
                enabled: root.showSettings
                sequence: "Escape"
                onActivated: root.closeWindow()
            }

            Rectangle {
                id: settingsDialog
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.verylarge
                clip: true

                Loader {
                    id: settingsLoader
                    anchors.fill: parent
                    active: root.showSettings

                    sourceComponent: SettingsContent {
                        anchors.fill: parent
                        onCloseRequested: root.closeWindow()
                    }

                    onLoaded: {
                        if (window.visible && item) {
                            item.forceActiveFocus();
                        }
                    }
                }
            }

            onVisibleChanged: {
                if (visible && settingsLoader.item) {
                    settingsLoader.item.forceActiveFocus();
                }
            }
        }
    }
}
