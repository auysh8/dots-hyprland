import QtQuick
import qs.modules.common

Item {
    id: root

    required property real temperatureC
    required property real domainMinimumC
    required property real domainMaximumC
    required property real chartTop
    required property real chartBottom
    required property string temperatureText
    property string normalText: qsTr("Normal")
    property string numericFontFamily: Appearance.font.family.numbers ?? "sans-serif"
    property string uiFontFamily: Appearance.font.family.main ?? "sans-serif"
    property color lineColor: Appearance.colors.colOutlineVariant
    property color labelColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
    readonly property real lineY: (domainMaximumC > domainMinimumC) 
        ? chartBottom - (temperatureC - domainMinimumC) / (domainMaximumC - domainMinimumC) * (chartBottom - chartTop)
        : chartBottom

    y: lineY
    height: 1
    enabled: false
    Accessible.name: temperatureText + " " + qsTr("1991–2020 climate normal")

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: root.lineColor
        opacity: 0.6
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.bottom: parent.top
        anchors.bottomMargin: 3
        text: root.temperatureText
        color: root.labelColor
        font.family: Appearance.font.family.main
        font.pixelSize: 11
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.top
        anchors.bottomMargin: 3
        text: root.normalText
        color: root.labelColor
        font.family: Appearance.font.family.main
        font.pixelSize: 11
        font.bold: true
    }
}
