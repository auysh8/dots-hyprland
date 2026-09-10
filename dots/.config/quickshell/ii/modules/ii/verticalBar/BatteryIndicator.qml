import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100

    implicitHeight: batteryProgress.implicitHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    ClippedProgressBar {
        id: batteryProgress
        anchors.centerIn: parent
        vertical: true
        valueBarWidth: Appearance.font.pixelSize.larger + 12  // match clock pill width
        valueBarHeight: 52
        value: percentage
        // value: 1
        // Filled-accent mapping mirroring BatteryPopup: the color doubles as the fill
        // behind the OneUI-style clipped readout, so use the filled accent roles
        // (guaranteed contrast) instead of container/on-container pairs.
        highlightColor: (isLow && !isCharging) ? Appearance.colors.colError
            : (isCharging || percentage >= 1) ? Appearance.colors.colPrimary
            : Appearance.colors.colTertiary

        font {
            pixelSize: 13
            weight: Font.DemiBold
        }

        textMask: Item {
            anchors.centerIn: parent
            width: batteryProgress.valueBarWidth
            height: batteryProgress.valueBarHeight

            StyledText {
                anchors.centerIn: parent
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                text: `${Math.round(root.percentage * 100)}`
            }
        }
    }

    Bar.BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
