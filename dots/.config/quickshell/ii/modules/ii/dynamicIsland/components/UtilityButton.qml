import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property string icon: ""
    property string command: ""
    property bool isActive: false
    property color activeColor: Appearance.colors.colPrimary
    
    Layout.fillWidth: true
    Layout.preferredHeight: 40
    
    Process { id: proc }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: {
            if (root.isActive) return root.activeColor;
            if (ma.containsMouse) return Qt.rgba(Appearance.colors.colOnLayer0.r, Appearance.colors.colOnLayer0.g, Appearance.colors.colOnLayer0.b, 0.2);
            return Qt.rgba(Appearance.colors.colOnLayer0.r, Appearance.colors.colOnLayer0.g, Appearance.colors.colOnLayer0.b, 0.1);
        }
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.icon
            iconSize: 20
            color: root.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
        }
        
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (root.command) {
                    // Force reset to ensure triggering even if previously true (though it should auto-reset on exit)
                    proc.running = false 
                    proc.command = ["sh", "-c", root.command]
                    proc.running = true
                }
            }
        }
    }
}
