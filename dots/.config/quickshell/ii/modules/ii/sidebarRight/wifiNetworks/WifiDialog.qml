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

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
        anchors.horizontalCenter: parent.horizontalCenter
    }
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 1

        WindowDialogSeparator {
            anchors.fill: parent
            visible: !Network.wifiScanning
        }
        StyledIndeterminateProgressBar {
            // Only show scanning if content is initialized to prevent early visual updates
            visible: root.contentReady && Network.wifiScanning
            Layout.maximumWidth: 160
            anchors.horizontalCenter: parent.horizontalCenter
            Layout.bottomMargin: -8
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
        
        sourceComponent: ListView {
            clip: true
            spacing: 0

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