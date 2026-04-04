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
        id: headerArea
        Layout.fillWidth: true
        Layout.preferredHeight: headerContent.implicitHeight + 2

        ColumnLayout {
            id: headerContent
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            width: parent.width
            spacing: 10

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Tap to connect or disconnect a device")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurface
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 160
                height: 4

                WindowDialogSeparator {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 2
                    visible: !(Bluetooth.defaultAdapter?.discovering ?? false)
                }

                StyledIndeterminateProgressBar {
                    visible: Bluetooth.defaultAdapter?.discovering ?? false
                    anchors.centerIn: parent
                    width: parent.width
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 0
                Layout.leftMargin: 18
                Layout.rightMargin: 18

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Bluetooth")
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.normal
                }

                StyledSwitch {
                    id: bluetoothToggle
                    checked: Bluetooth.defaultAdapter?.enabled ?? false
                    scale: 0.9

                    onClicked: {
                        if (!Bluetooth.defaultAdapter) return;
                        Bluetooth.defaultAdapter.enabled = checked;
                        Bluetooth.defaultAdapter.discovering = checked;
                    }
                }
            }
        }
    }
    Loader {
        id: listLoader
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -6

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
