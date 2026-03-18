import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    property var rootContext
    property string title: ""
    property string subtitle: ""

    Layout.fillWidth: true
    spacing: 4

    StyledText {
        text: root.title
        font.pixelSize: 24
        font.weight: 700
        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
    }

    StyledText {
        text: root.subtitle
        font.pixelSize: 14
        color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
        visible: text.length > 0
    }
}
