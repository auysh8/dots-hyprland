import QtQuick
import qs.modules.common

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    signal openAudioOutputDialog(var sourceItem)
    signal openAudioInputDialog(var sourceItem)
    signal openBluetoothDialog(var sourceItem)
    signal openNightLightDialog(var sourceItem)
    signal openWifiDialog(var sourceItem)
}
