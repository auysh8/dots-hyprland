import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property string iconName
    required property double percentage
    property int warningThreshold: 100
    // M3 triad accent — each ring gets its own hue so metrics are distinguishable
    property color accentColor: Appearance.colors.colOnSecondaryContainer
    implicitHeight: resourceProgress.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    property bool warning: percentage * 100 >= warningThreshold

    ClippedFilledCircularProgress {
        id: resourceProgress
        anchors.centerIn: parent
        value: percentage
        enableAnimation: true // Smooth 800ms OutCubic sweep as the value changes
        colPrimary: root.warning ? Appearance.colors.colError : root.accentColor
        accountForLightBleeding: !root.warning

        MaterialSymbol {
            font.weight: Font.Medium
            fill: 1
            text: root.iconName
            iconSize: 13
            color: root.warning ? Appearance.colors.colError : root.accentColor
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        enabled: root.visible
    }
}
