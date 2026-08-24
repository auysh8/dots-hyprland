import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? (dragFloatIcon.visible ? panelWindow.contentItem : columnLayout) : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    GlobalFocusGrab.dismiss();
                    panelWindow.searchingText = "";
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                GlobalStates.overviewOpen = false;
            }
        }
        implicitWidth: columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight

        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        Column {
            id: columnLayout
            visible: GlobalStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }
            spacing: 8

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    GlobalStates.overviewOpen = false;
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
                Synchronizer on searchingText {
                    property alias source: panelWindow.searchingText
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                sourceComponent: OverviewWidget {
                    screen: panelWindow.screen
                    visible: (panelWindow.searchingText == "")
                }
            }

            Loader {
                id: dockedAppDrawerLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && (panelWindow.searchingText == "")
                visible: active
                sourceComponent: ApplicationDrawer {
                    id: dockedAppDrawer
                    dockedInOverview: true
                    width: overviewLoader.item ? overviewLoader.item.width : 1000
                    implicitWidth: width
                    availableWidth: width
                    availableHeight: panelWindow.height
                }
            }
        }

        // Floating drag preview icon
        Rectangle {
            id: dragFloatIcon
            z: 9999
            visible: false
            width: 56
            height: 56
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSecondaryContainer
            opacity: 0.92
            property var app: null

            IconImage {
                anchors.centerIn: parent
                visible: dragFloatIcon.app !== null
                source: dragFloatIcon.app
                    ? Quickshell.iconPath(dragFloatIcon.app.icon || dragFloatIcon.app.id, "application-x-executable")
                    : ""
                implicitSize: 40
            }
        }

        Connections {
            target: dockedAppDrawerLoader.item

            function onAppDragStarted(app, sceneX, sceneY) {
                dragFloatIcon.app = app;
                dragFloatIcon.x = sceneX - dragFloatIcon.width / 2;
                dragFloatIcon.y = sceneY - dragFloatIcon.height / 2;
                dragFloatIcon.visible = true;
            }

            function onAppDragUpdate(sceneX, sceneY) {
                dragFloatIcon.x = sceneX - dragFloatIcon.width / 2;
                dragFloatIcon.y = sceneY - dragFloatIcon.height / 2;
                const ws = overviewLoader.item
                    ? overviewLoader.item.workspaceAtScenePoint(sceneX, sceneY)
                    : -1;
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = ws;
            }

            function onAppDropped(app, sceneX, sceneY) {
                dragFloatIcon.visible = false;
                dragFloatIcon.app = null;
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = -1;

                const ws = overviewLoader.item
                    ? overviewLoader.item.workspaceAtScenePoint(sceneX, sceneY)
                    : -1;
                if (ws <= 0 || !app) return;

                function dispatchExec(parts) {
                    if (!parts || parts.length === 0) return;
                    const cmd = parts.map(p => p.includes(" ") ? `"${p}"` : p).join(" ");
                    const lua = cmd.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
                    Hyprland.dispatch(`hl.dsp.exec_cmd("${lua}", { workspace = "${ws} silent" })`);
                }

                if (app._isFolder === true) {
                    const ids = app.appIds || [];
                    for (let i = 0; i < ids.length; i++) {
                        const entry = AppSearch.guessDesktopEntry(ids[i]);
                        dispatchExec(entry ? entry.command : null);
                    }
                    return;
                }

                dispatchExec(app.command);
            }

            function onAppDragCancelled() {
                dragFloatIcon.visible = false;
                dragFloatIcon.app = null;
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = -1;
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
