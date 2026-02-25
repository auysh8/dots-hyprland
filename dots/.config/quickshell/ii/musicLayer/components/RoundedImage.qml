import QtQuick
import Qt5Compat.GraphicalEffects

Image {
    id: root
    property real radius: 0

    layer.enabled: radius > 0
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
        }
    }
}
