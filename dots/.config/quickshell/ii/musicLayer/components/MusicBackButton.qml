import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root

    property var rootContext

    Layout.preferredWidth: 40
    Layout.preferredHeight: 40
    buttonRadius: 20
    colBackground: rootContext ? ColorUtils.transparentize(rootContext.contentColor, 0.9) : "transparent"
    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.contentColor, 0.8) : "transparent"
    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.2)

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: "arrow_back"
        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
        iconSize: 24
    }
}