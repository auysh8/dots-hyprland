import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    property bool showMonitor: false
    property bool closing: false
    
    function closeWindow() {
        if (root.showMonitor) {
            root.closing = true;
            root.showMonitor = false;
        }
    }

    IpcHandler {
        target: "system-monitor"
        function toggle() { 
            if (root.showMonitor) root.closeWindow();
            else root.showMonitor = true;
        }
        function open() { root.showMonitor = true; }
        function close() { root.closeWindow(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.showMonitor || root.closing
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "system-monitor"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            
            MouseArea {
                id: backgroundClickArea
                anchors.fill: parent
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
                
                width: parent.width * 0.8
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
                            }
                        }
                    }
                }
            }
            
            onVisibleChanged: { if (visible) monitor.forceActiveFocus(); }
        }
    }
}
