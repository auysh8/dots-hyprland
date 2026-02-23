import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.classicStyle

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing: 5
        padding: 5
        color: Appearance.colors.colLayer1

        NetworkToggle {
            id: networkToggle
            altAction: () => {
                root.openWifiDialog(networkToggle);
            }
        }
        BluetoothToggle {
            id: bluetoothToggle
            altAction: () => {
                root.openBluetoothDialog(bluetoothToggle);
            }
        }
        NightLight {}
        GameMode {}
        IdleInhibitor {}
        EasyEffectsToggle {}
        CloudflareWarp {}
    }
}
