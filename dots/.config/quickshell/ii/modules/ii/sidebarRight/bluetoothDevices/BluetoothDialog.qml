import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// import Qt5Compat.GraphicalEffects  // Removed - not used and heavy to load
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

WindowDialog {
    id: root
    backgroundHeight: 600

    WindowDialogTitle {
        text: Translation.tr("Bluetooth devices")
    }
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        
        // Delay reading Bluetooth state to avoid jitter during animation
        // Delay reading Bluetooth state to avoid jitter during animation
        property bool isDiscovering: root.contentReady ? (Bluetooth.defaultAdapter?.discovering ?? false) : false
        
        WindowDialogSeparator {
            anchors.fill: parent
            visible: !parent.isDiscovering
        }
        StyledIndeterminateProgressBar {
            visible: parent.isDiscovering
            anchors.fill: parent
            anchors.leftMargin: -Appearance.rounding.large
            anchors.rightMargin: -Appearance.rounding.large
        }
    }
    Loader {
        id: listLoader
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
        
        active: root.contentReady
        
        sourceComponent: StyledListView {
            clip: true
            spacing: 0
            animateAppearance: false

            model: ScriptModel {
                values: BluetoothStatus.friendlyDeviceList
            }
            delegate: BluetoothDeviceItem {
                required property BluetoothDevice modelData
                device: modelData
                anchors {
                    left: parent?.left
                    right: parent?.right
                }
            }
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
