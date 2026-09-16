import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

ScrollBar {
    id: root

    property real minimumThumbLength: 44

    policy: ScrollBar.AsNeeded
    minimumSize: Math.min(1, minimumThumbLength / Math.max(1, (orientation === Qt.Vertical ? height - topPadding - bottomPadding : width - leftPadding - rightPadding)))
    topPadding: orientation === Qt.Vertical ? Appearance.rounding.normal : 0
    bottomPadding: orientation === Qt.Vertical ? Appearance.rounding.normal : 0
    leftPadding: orientation === Qt.Horizontal ? Appearance.rounding.normal : 0
    rightPadding: orientation === Qt.Horizontal ? Appearance.rounding.normal : 0
    active: hovered || pressed

    contentItem: Rectangle {
        implicitWidth: root.orientation === Qt.Vertical ? 4 : root.visualSize
        implicitHeight: root.orientation === Qt.Vertical ? root.visualSize : 4
        radius: (root.orientation === Qt.Vertical ? width : height) / 2
        color: Appearance.colors.colOnSurfaceVariant
        
        opacity: root.policy === ScrollBar.AlwaysOn || (root.active && root.size < 1.0) ? 0.5 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }
}
