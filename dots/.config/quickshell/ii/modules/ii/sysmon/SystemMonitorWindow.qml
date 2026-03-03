import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

Scope {
    id: root
    property bool showMonitor: false
    property bool closing: false
    property bool barWasOpen: false

    function openWindow() {
        if (root.showMonitor || root.closing) return;
        root.barWasOpen = GlobalStates.barOpen;
        GlobalStates.barOpen = false;
        root.showMonitor = true;
    }
    
    function closeWindow() {
        if (root.showMonitor) {
            root.closing = true;
            root.showMonitor = false;
        }
    }

    function restorePanels() {
        if (root.barWasOpen) {
            GlobalStates.barOpen = true;
            root.barWasOpen = false;
        }
    }

    IpcHandler {
        target: "system-monitor"
        function toggle() { 
            if (root.showMonitor) root.closeWindow();
            else root.openWindow();
        }
        function open() { root.openWindow(); }
        function close() { root.closeWindow(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.showMonitor || root.closing
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "system-monitor"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.showMonitor ? 0.35 : 0
                z: 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.showMonitor ? 220 : 140
                        easing.type: root.showMonitor ? Easing.OutQuad : Easing.InQuad
                    }
                }
            }
            
            MouseArea {
                id: backgroundClickArea
                anchors.fill: parent
                z: 1
                onClicked: (mouse) => {
                    const monitorBounds = monitor.mapToItem(backgroundClickArea, 0, 0, monitor.width, monitor.height);
                    const clickInMonitor = mouse.x >= monitorBounds.x && mouse.x <= monitorBounds.x + monitorBounds.width &&
                                          mouse.y >= monitorBounds.y && mouse.y <= monitorBounds.y + monitorBounds.height;
                    if (!clickInMonitor) root.closeWindow();
                }
            }

            SystemMonitor {
                id: monitor
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.showMonitor ? (parent.height - height) / 2 : -height
                z: 2
                
                width: Math.min(parent.width * 0.92, 1560)
                height: parent.height * 0.85
                
                onActiveFocusChanged: {
                    if (!activeFocus && root.showMonitor && !root.closing) {
                        root.closeWindow();
                    }
                }
                
                Behavior on y {
                    NumberAnimation {
                        id: slideAnim
                        duration: root.showMonitor ? 600 : 400
                        easing.type: root.showMonitor ? Easing.OutExpo : Easing.InExpo
                        onRunningChanged: {
                            if (!running && !root.showMonitor) {
                                root.closing = false;
                                root.restorePanels();
                            }
                        }
                    }
                }
            }
            
            onVisibleChanged: { if (visible) monitor.forceActiveFocus(); }
        }
    }

    Component.onDestruction: root.restorePanels()
}
