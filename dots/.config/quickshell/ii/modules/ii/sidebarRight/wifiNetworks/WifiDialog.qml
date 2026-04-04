import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600
    readonly property bool showWifiList: Network.wifiStatus !== "disabled"

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
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
                text: Translation.tr("Tap a network to connect")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 160
                height: 4

                WindowDialogSeparator {
                    anchors.centerIn: parent
                    width: parent.width
                    height: 2
                    visible: !Network.wifiScanning
                }

                StyledIndeterminateProgressBar {
                    // Only show scanning if content is initialized to prevent early visual updates
                    visible: root.contentReady && Network.wifiScanning
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
                    text: Translation.tr("Wi-Fi")
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.normal
                }

                StyledSwitch {
                    id: wifiToggle
                    checked: Network.wifiStatus !== "disabled"
                    scale: 0.9

                    onClicked: Network.enableWifi(checked)
                }
            }
        }
    }
    Loader {
        id: listLoader
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -6
        Layout.bottomMargin: -8
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        
        active: root.contentReady && root.showWifiList
        
        sourceComponent: StyledListView {
            clip: true
            spacing: 8
            animateAppearance: false
            topMargin: 6
            bottomMargin: 6

            model: ScriptModel {
                values: Network.friendlyWifiNetworks
            }
            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                width: ListView.view.width
            }
        }
    }
    WindowDialogButtonRow {
        Layout.margins: 4
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
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
