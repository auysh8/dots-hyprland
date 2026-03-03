import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property string icon: ""
    property string command: ""
    property bool isActive: false
    property color activeColor: Appearance.colors.colPrimary
    
    Layout.fillWidth: true
    Layout.preferredHeight: 40
    buttonRadius: 12
    toggled: root.isActive

    colBackground: Qt.rgba(Appearance.colors.colOnLayer0.r, Appearance.colors.colOnLayer0.g, Appearance.colors.colOnLayer0.b, 0.1)
    colBackgroundToggled: root.activeColor
    colRipple: Appearance.colors.colOnLayer0
    colRippleToggled: Appearance.colors.colOnPrimary

    onClicked: {
        if (root.command) {
            proc.running = false
            proc.command = ["sh", "-c", root.command]
            proc.running = true
        }
    }
    
    Process { id: proc }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 20
        color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
    }
}
