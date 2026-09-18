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

    property bool showSpotlight: GlobalStates.spotlightOpen
    property bool closing: false

    onShowSpotlightChanged: {
        if (!showSpotlight) {
            closing = true;
            hideTimer.restart();
        } else {
            closing = false;
            hideTimer.stop();
        }
    }

    function closeWindow() {
        if (GlobalStates.spotlightOpen) {
            closing = true;
            GlobalStates.spotlightOpen = false;
            hideTimer.restart();
        }
    }

    function toggleWindow() {
        if (GlobalStates.spotlightOpen) {
            closeWindow();
        } else if (!closing) {
            GlobalStates.spotlightOpen = true;
        }
    }

    property string initialSearchText: ""

    function openWithPrefix(prefix) {
        if (GlobalStates.spotlightOpen && LauncherSearch.query.startsWith(prefix)) {
            closeWindow();
            return;
        }
        initialSearchText = prefix;
        if (!GlobalStates.spotlightOpen) {
            GlobalStates.spotlightOpen = true;
        } else {
            // Already open, direct update
            LauncherSearch.query = prefix;
        }
    }

    Timer {
        id: hideTimer
        interval: 250
        repeat: false
        onTriggered: root.closing = false
    }

    IpcHandler {
        target: "spotlight"
        function toggle() { root.toggleWindow(); }
        function open() { GlobalStates.spotlightOpen = true; }
        function close() { root.closeWindow(); }
        function clipboardToggle() { root.openWithPrefix(Config.options.search.prefix.clipboard); }
        function emojiToggle() { root.openWithPrefix(Config.options.search.prefix.emojis); }
    }

    GlobalShortcut {
        name: "spotlightToggle"
        description: "Toggle Spotlight search layer"
        onPressed: root.toggleWindow()
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on spotlight"
        onPressed: root.openWithPrefix(Config.options.search.prefix.clipboard)
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on spotlight"
        onPressed: root.openWithPrefix(Config.options.search.prefix.emojis)
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property var modelData
            screen: modelData

            visible: root.showSpotlight || root.closing
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:spotlight"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.showSpotlight && !root.closing) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
            }
            margins {
                top: Math.round((window.screen?.height ?? 1080) * 0.25)
            }

            implicitWidth: searchWidget.implicitWidth
            implicitHeight: searchWidget.implicitHeight

            mask: Region {
                item: (root.showSpotlight || root.closing) ? spotlightContainer : null
            }

            property bool grabActive: root.showSpotlight && !root.closing

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration + 50
                repeat: false
                onTriggered: {
                    if (root.showSpotlight && !root.closing) {
                        GlobalFocusGrab.addDismissable(window);
                    }
                }
            }

            onGrabActiveChanged: {
                if (grabActive) {
                    delayedGrabTimer.restart();
                    Qt.callLater(() => {
                        if (root.initialSearchText !== "") {
                            searchWidget.setSearchingText(root.initialSearchText);
                            root.initialSearchText = "";
                        }
                        searchWidget.focusSearchInput();
                    });
                } else {
                    delayedGrabTimer.stop();
                    GlobalFocusGrab.removeDismissable(window);
                    searchWidget.cancelSearch();
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
                enabled: root.showSpotlight
                sequence: "Escape"
                onActivated: root.closeWindow()
            }

            Item {
                id: spotlightContainer
                anchors.fill: parent

                opacity: root.showSpotlight ? 1 : 0
                scale: root.showSpotlight ? 1 : 0.96
                transformOrigin: Item.Top

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                SearchWidget {
                    id: searchWidget
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
