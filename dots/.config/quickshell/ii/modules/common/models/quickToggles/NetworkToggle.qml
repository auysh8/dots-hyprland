import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Internet")
    statusText: Network.networkName
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(Network.networkName)
    icon: Network.materialSymbol

    toggled: Network.wifiStatus !== "disabled" || Network.ethernet
    property bool connected: Network.ethernet || Network.wifiStatus === "connected" || Network.wifiStatus === "limited"
    mainAction: () => Network.toggleWifi()
    hasMenu: true
}
