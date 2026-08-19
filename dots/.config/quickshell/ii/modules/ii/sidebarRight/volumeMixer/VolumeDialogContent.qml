import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

ColumnLayout {
    id: root
    required property bool isSink
    readonly property list<var> appPwNodes: isSink ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property list<var> devices: isSink ? Audio.outputDevices : Audio.inputDevices
    readonly property bool hasApps: appPwNodes.length > 0
    spacing: 16

    DialogSectionListView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 2
        Layout.bottomMargin: 0

        model: ScriptModel {
            values: root.appPwNodes
        }
        delegate: VolumeMixerEntry {
            required property var modelData
            node: modelData
            width: ListView.view.width
        }
        PagePlaceholder {
            icon: "widgets"
            title: Translation.tr("No applications")
            shown: !root.hasApps
            shape: MaterialShape.Shape.Cookie7Sided
        }
    }

    StyledComboBox {
        id: deviceSelector
        Layout.fillHeight: false
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 4
        model: root.devices.map(node => Audio.friendlyDeviceName(node))
        currentIndex: root.devices.findIndex(item => {
            if (root.isSink) {
                return item.id === Pipewire.defaultAudioSink?.id
            } else {
                return item.id === Pipewire.defaultAudioSource?.id
            }
        })
        onActivated: (index) => {
            print(index)
            const item = root.devices[index]
            if (root.isSink) {
                Audio.setDefaultSink(item)
            } else {
                Audio.setDefaultSource(item)
            }
        }
    }

    component DialogSectionListView: StyledListView {
        clip: true
        spacing: 8
        animateAppearance: false
        topMargin: 4
        bottomMargin: 4
    }

    Component {
        id: listElementComp
        ListElement {}
    }
}
