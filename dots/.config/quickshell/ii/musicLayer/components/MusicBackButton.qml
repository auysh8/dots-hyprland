import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButtonWithIcon {
    id: root

    property var rootContext

    Layout.preferredWidth: 40
    Layout.preferredHeight: 40
    buttonRadius: 20
    materialIcon: "arrow_back"
    materialIconFill: false
    mainText: ""
    colBackground: rootContext ? ColorUtils.transparentize(rootContext.contentColor, 0.9) : "transparent"
    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.2)

    mainContentComponent: Component {
        Item {}
    }
}