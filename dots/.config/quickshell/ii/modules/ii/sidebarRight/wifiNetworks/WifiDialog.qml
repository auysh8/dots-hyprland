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

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 4

        StyledText {
            text: Translation.tr("Connect to Wi-Fi")
            color: Appearance.colors.colOnSurface
            font {
                family: Appearance.font.family.title
                pixelSize: 22
                weight: Font.Bold
            }
        }

        StyledText {
            text: Translation.tr("Tap a network to connect")
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
                text: Translation.tr("Wi-Fi")
                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
            }

            StyledSwitch {
                id: wifiToggle
                checked: Network.wifiStatus !== "disabled"
                scale: 0.9

                onClicked: Network.enableWifi(checked)
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
        
        active: root.contentReady && root.showWifiList
        
        sourceComponent: StyledListView {
            clip: true
            spacing: 8
            animateAppearance: false
            topMargin: 4
            bottomMargin: 4

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
