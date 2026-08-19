import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    property bool expanded: false
    property color overridePillColor: "transparent"
    property bool useOverrideColors: false
    default property alias data: tabBarColumn.data  
    implicitHeight: tabBarColumn.implicitHeight
    implicitWidth: tabBarColumn.implicitWidth
    Layout.topMargin: 25

    Rectangle {
        property real itemHeight: tabBarColumn.children[0]?.baseSize ?? 54
        property real baseHighlightHeight: tabBarColumn.children[0]?.baseHighlightHeight ?? 32
        anchors {
            top: tabBarColumn.top
            left: tabBarColumn.left
            topMargin: itemHeight * root.currentIndex + (root.expanded ? 0 : 2)
        }
        radius: Appearance.rounding.full
        color: root.useOverrideColors ? root.overridePillColor : Appearance.colors.colSecondaryContainer
        implicitHeight: root.expanded ? itemHeight : baseHighlightHeight
        implicitWidth: tabBarColumn?.children[root.currentIndex]?.visualWidth ?? 54

        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }

    ColumnLayout {
        id: tabBarColumn
        anchors.fill: parent
        spacing: 0
    }
}
