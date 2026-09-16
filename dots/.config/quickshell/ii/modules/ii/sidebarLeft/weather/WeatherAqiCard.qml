import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property real aqiValue: NaN
    property string levelText: "--"
    property color accent: "#00e59b"
    property bool animationEnabled: false
    property bool animationActive: true

    readonly property real cardSize: Math.min(width, height)
    readonly property color ink: Appearance.colors.colOnSurface
    readonly property color mutedInk: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
    readonly property color cardFill: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
    readonly property color trackTint: Appearance.colors.colLayer2 ?? Qt.rgba(0.5, 0.5, 0.5, 0.18)

    WeatherAnimatedValue {
        id: aqiAnimation
        targetValue: root.aqiValue
        enabled: root.animationEnabled
        active: root.animationActive
    }

    Item {
        id: card
        width: root.cardSize
        height: root.cardSize
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.cardFill
            border.width: 1
            border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42)
        }

        WeatherArcGauge {
            width: parent.width * 0.88
            height: width
            anchors.centerIn: parent
            value: isNaN(aqiAnimation.currentValue) ? 0 : aqiAnimation.currentValue
            maximum: 250
            progressColor: root.accent
            trackColor: root.trackTint
            thickness: 9
            startAngle: 70
            sweepAngle: -140
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(parent.width * 0.16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            z: 2

            Row {
                spacing: 6

                MaterialSymbol {
                    text: "scatter_plot"
                    color: root.mutedInk
                    iconSize: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: qsTr("Air quality")
                    color: root.mutedInk
                    font.family: Appearance.font.family.main
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: isNaN(aqiAnimation.currentValue) ? "--" : Math.round(aqiAnimation.currentValue)
                color: root.ink
                font.pixelSize: Math.round(parent.width * 0.28)
                font.weight: Font.Bold
                lineHeight: 0.95
            }

            StyledText {
                text: root.levelText
                color: root.accent
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }
}
