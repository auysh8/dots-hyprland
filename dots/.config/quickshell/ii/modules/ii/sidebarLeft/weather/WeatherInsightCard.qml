import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property color iconColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
    property color titleColor: Appearance.colors.colOnSurface ?? Appearance.m3colors.m3onSurface
    property int headerLeftMargin: 18
    property int headerTopMargin: 16
    property int headerSpacing: 6
    property bool circular: false
    property int shapeId: 0
    property real shapeInset: 0
    property color shapeColor: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
    property alias cardColor: root.shapeColor
    default property alias content: contentLayer.data

    radius: circular ? Math.round(Math.min(width, height) / 2) : (Appearance.rounding.normal ?? 18)
    color: shapeColor
    border.width: 1
    border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42)
    clip: true

    Item {
        id: contentLayer
        anchors.fill: parent
    }

    Row {
        id: headerRow
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: root.headerLeftMargin
        anchors.topMargin: root.headerTopMargin
        spacing: root.headerSpacing
        visible: root.icon.length > 0 || root.title.length > 0
        z: 2

        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            color: root.iconColor
            iconSize: 20
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            visible: root.title.length > 0
            text: root.title
            color: root.titleColor
            font.pixelSize: 16
            font.weight: Font.Bold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
