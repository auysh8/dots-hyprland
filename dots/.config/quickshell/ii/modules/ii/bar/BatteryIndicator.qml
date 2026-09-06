import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    readonly property bool fullyCharged: chargeState == 4

    // M3 filled-accent capsule, mirroring BatteryPopup's state mapping. Filled
    // accent + its on-color guarantees contrast even when the wallpaper generates
    // muddy, low-chroma container pairs.
    readonly property color capsuleColor: {
        if (isLow && !isCharging) return Appearance.colors.colError;
        if (isCharging || fullyCharged) return Appearance.colors.colPrimary;
        return Appearance.colors.colSecondary;
    }
    readonly property color onCapsuleColor: {
        if (isLow && !isCharging) return Appearance.colors.colOnError;
        if (isCharging || fullyCharged) return Appearance.colors.colOnPrimary;
        return Appearance.colors.colOnSecondary;
    }

    implicitWidth: capsule.implicitWidth + 10 * 2
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    Rectangle {
        id: capsule
        anchors.centerIn: parent
        implicitWidth: capsuleRow.implicitWidth + 10 * 2
        implicitHeight: Appearance.sizes.baseBarHeight - 12
        radius: Appearance.rounding.full
        color: root.capsuleColor
        opacity: root.containsMouse || root.containsPress ? 1 : 0.85

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout {
            id: capsuleRow
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                text: root.isCharging ? "battery_charging_full"
                    : root.fullyCharged ? "battery_full"
                    : root.isLow ? "battery_alert"
                    : Icons.getBatteryIcon(root.percentage * 100)
                iconSize: Appearance.font.pixelSize.normal
                fill: 1
                color: root.onCapsuleColor
            }

            StyledText {
                text: `${Math.round(root.percentage * 100)}`
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.onCapsuleColor
            }
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
