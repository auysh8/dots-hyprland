import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    property bool showDrawer: false
    property bool closing: false
    
    function closeWindow() {
        if (root.showDrawer) {
            root.closing = true;
            root.showDrawer = false;
        }
    }

    IpcHandler {
        target: "app-drawer"
        function toggle() { 
            if (root.showDrawer) root.closeWindow();
            else root.showDrawer = true;
        }
        function open() { root.showDrawer = true }
        function close() { root.closeWindow() }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.showDrawer || root.closing
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
                y: root.showDrawer ? (parent.height - height) / 2 : -height
                
                width: parent.width * 0.7
                height: parent.height * 0.8
                expanded: true
                availableWidth: window.width
                availableHeight: window.height
                
                onActiveFocusChanged: {
                    if (!activeFocus && root.showDrawer && !root.closing) {
                        root.closeWindow();
                    }
                }
                
                Behavior on y {
                    NumberAnimation {
                        id: slideAnim
                        duration: root.showDrawer ? 600 : 400
                        easing.type: root.showDrawer ? Easing.OutExpo : Easing.InExpo
                        onRunningChanged: {
                            if (!running && !root.showDrawer) {
                                root.closing = false;
                            }
                        }
                    }
                }
            }
            
            onVisibleChanged: { if (visible) drawer.forceActiveFocus(); }
        }
    }
}
