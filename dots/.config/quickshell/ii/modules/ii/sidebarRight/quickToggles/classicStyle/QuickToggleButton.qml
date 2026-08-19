import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

GroupButton {
    id: button
    property string buttonIcon
    property int iconFill: 1
    Layout.fillWidth: true
    baseWidth: 40
    baseHeight: 40
    clickedWidth: baseWidth + 16
    toggled: false
    buttonRadius: (altAction && toggled) ? Appearance?.rounding.normal : Math.min(baseHeight, baseWidth) / 2
    buttonRadiusPressed: 14
    bounce: true

    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.colors.colPrimary
    colBackgroundToggledHover: Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: Appearance.colors.colPrimaryActive
    property color colIcon: toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: button.iconFill
        color: button.colIcon
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
