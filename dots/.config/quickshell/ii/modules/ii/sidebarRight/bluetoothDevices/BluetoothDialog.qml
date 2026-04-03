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
        anchors.horizontalCenter: parent.horizontalCenter
    }
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1

        property bool isDiscovering: root.contentReady ? (Bluetooth.defaultAdapter?.discovering ?? false) : false

        Text {
            id: infoText
            text: Translation.tr("Tap to connect or disconnect a device")
            font.pixelSize: Appearance.font.pixelSize.smaller
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: -8
            color: Appearance.colors.colOnSurface
        }

        StyledIndeterminateProgressBar {
            Layout.maximumWidth: 160
            visible: Bluetooth.defaultAdapter?.discovering ?? false
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: infoText.bottom
            anchors.topMargin: 16
        }
    }
    Loader {
        id: listLoader
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: 18

        active: root.contentReady

        sourceComponent: StyledListView {
            clip: true
            spacing: 8
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
    WindowDialogButtonRow {
        Layout.margins: 4
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
            colBackground: Appearance.colors.colPrimary
            colText: Appearance.colors.colOnPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
        }
    }
}
