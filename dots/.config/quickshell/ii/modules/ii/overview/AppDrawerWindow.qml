import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

Scope {
    id: root
    property bool closing: false
    
    function closeWindow() {
        if (GlobalStates.appDrawerOpen) {
            root.closing = true;
            GlobalStates.appDrawerOpen = false;
        }
    }

    IpcHandler {
        target: "app-drawer"
        function toggle() { 
            if (GlobalStates.appDrawerOpen) root.closeWindow();
            else GlobalStates.appDrawerOpen = true;
        }
        function open() { GlobalStates.appDrawerOpen = true }
        function close() { root.closeWindow() }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: GlobalStates.appDrawerOpen || root.closing
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "app-drawer"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            
            MouseArea {
                id: backgroundClickArea
                anchors.fill: parent
                onClicked: (mouse) => {
                    const drawerBounds = drawer.mapToItem(backgroundClickArea, 0, 0, drawer.width, drawer.height);
                    const clickInDrawer = mouse.x >= drawerBounds.x && mouse.x <= drawerBounds.x + drawerBounds.width &&
                                         mouse.y >= drawerBounds.y && mouse.y <= drawerBounds.y + drawerBounds.height;
                    if (!clickInDrawer) root.closeWindow();
                }
            }

            ApplicationDrawer {
                id: drawer
                anchors.horizontalCenter: parent.horizontalCenter
                y: GlobalStates.appDrawerOpen ? (parent.height - height) / 2 : -height
                
                width: parent.width * 0.7
                height: parent.height * 0.8
                expanded: true
                availableWidth: window.width
                availableHeight: window.height
                
                onActiveFocusChanged: {
                    if (!activeFocus && GlobalStates.appDrawerOpen && !root.closing) {
                        root.closeWindow();
                    }
                }
                
                Behavior on y {
                    NumberAnimation {
                        id: slideAnim
                        duration: GlobalStates.appDrawerOpen ? 600 : 400
                        easing.type: GlobalStates.appDrawerOpen ? Easing.OutExpo : Easing.InExpo
                        onRunningChanged: {
                            if (!running && !GlobalStates.appDrawerOpen) {
                                root.closing = false;
                            }
                        }
                    }
                }
            }
            
            onVisibleChanged: { if (visible) drawer.focusSearchField(); }
        }
    }
}
