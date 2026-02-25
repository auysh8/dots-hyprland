import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool shown: false
    property bool closing: false
    property string layerNamespace: "music-layer"

    signal closeRequested()

    default property alias contentData: contentRoot.data

    anchors { top: true; bottom: true; left: true; right: true }
    visible: shown || closing
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    Item {
        anchors.fill: parent
        focus: root.shown

        Shortcut {
            enabled: root.shown
            sequence: "Escape"
            onActivated: root.closeRequested()
        }
    }

    MouseArea {
        anchors.fill: parent
        scrollGestureEnabled: false
        onClicked: root.closeRequested()
    }

    Item {
        id: contentRoot
        anchors.fill: parent
    }
}
