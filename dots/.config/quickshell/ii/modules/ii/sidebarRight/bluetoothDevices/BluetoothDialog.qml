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

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 4

        StyledText {
            text: Translation.tr("Bluetooth devices")
            color: Appearance.colors.colOnSurface
            font {
                family: Appearance.font.family.title
                pixelSize: 22
                weight: Font.Bold
            }
        }

        StyledText {
            text: Translation.tr("Tap to connect or disconnect a device")
            font.pixelSize: 13
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        implicitHeight: 52
        radius: 18
        color: Appearance.colors.colLayer1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Bluetooth")
                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
            }

            StyledSwitch {
                id: bluetoothToggle
                checked: BluetoothStatus.enabled
                scale: 0.9

                onClicked: {
                    BluetoothStatus.toggleBluetooth(checked);
                }
            }
        }
    }
    Loader {
        id: listLoader
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 0
        Layout.leftMargin: 8
        Layout.rightMargin: 8

        active: root.contentReady

        sourceComponent: StyledListView {
            clip: true
            spacing: 8
            animateAppearance: false
            topMargin: 4
            bottomMargin: 4

            model: ScriptModel {
                values: BluetoothStatus.friendlyDeviceList
            }
            delegate: BluetoothDeviceItem {
                required property BluetoothDevice modelData
                device: modelData
                width: ListView.view.width
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
