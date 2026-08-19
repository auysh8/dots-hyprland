import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.services.network
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property WifiAccessPoint wifiNetwork
    readonly property bool actionEnabled: !(Network.wifiConnectTarget === root.wifiNetwork && !wifiNetwork?.active)
    readonly property bool isConnected: root.wifiNetwork?.active ?? false
    readonly property bool isConnectTarget: Network.wifiConnectTarget === root.wifiNetwork
    readonly property bool isBusyConnecting: root.isConnectTarget && !root.isConnected
    readonly property bool isHighlighted: (root.wifiNetwork?.askingPassword ?? false) || root.isConnected || root.isBusyConnecting
    readonly property bool showsSecondaryText: root.secondaryText.length > 0
    readonly property string secondaryText: root.isConnected
            ? Translation.tr("Connected")
        : root.isBusyConnecting
            ? Translation.tr("Connecting...")
            : ""
    enabled: root.actionEnabled
    opacity: (!root.actionEnabled && !root.isHighlighted) ? 0.4 : 1

    active: root.isHighlighted
    buttonRadius: 18
    horizontalPadding: 14
    verticalPadding: root.isConnected ? 14 : 10
    colBackground: root.isConnected
        ? Appearance.colors.colPrimaryContainer
        : Appearance.colors.colLayer1
    colBackgroundHover: root.isConnected
        ? Appearance.colors.colPrimaryContainerHover
        : Appearance.colors.colLayer1Hover
    colRipple: root.isConnected
        ? Appearance.colors.colPrimaryContainerActive
        : Appearance.colors.colLayer1Active
    onClicked: {
        Network.connectToWifiNetwork(wifiNetwork);
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // Left Icon Badge Container
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 36
                height: 36
                radius: 12
                color: root.isConnected ? Appearance.colors.colPrimary : Appearance.colors.colLayer2

                MaterialSymbol {
                    property int strength: root.wifiNetwork?.strength ?? 0
                    anchors.centerIn: parent
                    iconSize: 20
                    fill: 1
                    text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                    color: root.isConnected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                }
            }

            // Middle SSID & Subtitle
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    color: root.isConnected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                    renderType: Text.QtRendering
                    font.pixelSize: 14
                    font.weight: root.isConnected ? Font.Bold : Font.Medium
                    text: root.wifiNetwork?.ssid ?? Translation.tr("Unknown")
                    textFormat: Text.PlainText
                }

                StyledText {
                    visible: root.showsSecondaryText
                    Layout.fillWidth: true
                    color: root.isConnected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    renderType: Text.QtRendering
                    font.pixelSize: 12
                    text: root.secondaryText
                    textFormat: Text.PlainText
                }
            }

            // Right Status Icon (Checkmark for connected, Lock for secure)
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.isConnected
                text: "check"
                iconSize: 20
                fill: 1
                color: Appearance.colors.colOnPrimaryContainer
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: (root.wifiNetwork?.isSecure ?? false) && !root.isConnected
                text: "lock"
                iconSize: 18
                fill: 1
                color: Appearance.colors.colSubtext
            }
        }

        ColumnLayout { // Password
            id: passwordPrompt
            Layout.topMargin: 10
            visible: root.wifiNetwork?.askingPassword ?? false

            MaterialTextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Password")

                // Password
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData

                onAccepted: {
                    Network.changePassword(root.wifiNetwork, passwordField.text);
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: {
                        root.wifiNetwork.askingPassword = false;
                    }
                }

                DialogButton {
                    buttonText: Translation.tr("Connect")
                    onClicked: {
                        Network.changePassword(root.wifiNetwork, passwordField.text);
                    }
                }
            }
        }

        ColumnLayout { // Public wifi login page
            id: publicWifiPortal
            Layout.topMargin: 10
            visible: (root.wifiNetwork?.active && (root.wifiNetwork?.security ?? "").trim().length === 0) ?? false

            RowLayout {
                DialogButton {
                    Layout.fillWidth: true
                    buttonText: Translation.tr("Open network portal")
                    colBackground: Appearance.colors.colLayer4
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: {
                        Network.openPublicWifiPortal()
                        GlobalStates.sidebarRightOpen = false
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
