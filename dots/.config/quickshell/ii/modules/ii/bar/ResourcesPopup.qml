import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    // Derives noticeable tonal depth (lightness + saturation) while preserving the authentic theme hue
    function getMetricShade(col, targetLightness = 0.78, targetSat = 0.45) {
        var c = Qt.color(col);
        return Qt.hsla(c.hslHue, targetSat, targetLightness, c.a);
    }

    GridLayout {
        anchors.centerIn: parent
        columns: 3
        rowSpacing: 10
        columnSpacing: 10

        component ResourceCard: Rectangle {
            id: card
            property string icon: ""
            property var iconShape: MaterialShape.Shape.Circle
            property string label: ""
            property real value: 0
            property string detail: ""

            // Appearance token color roles
            property color colAccent: Appearance.colors.colPrimary
            property color colOnAccent: Appearance.colors.colOnPrimary

            property bool isCritical: value > 0.9

            readonly property color effectiveAccent: isCritical ? Appearance.colors.colError : colAccent
            readonly property color effectiveOnAccent: isCritical ? Appearance.colors.colOnError : colOnAccent
            readonly property color effectiveTrack: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.12)

            Layout.preferredWidth: 104
            Layout.preferredHeight: 140
            radius: Appearance.rounding.large

            // Uniform elevated surface for all containers
            color: cardMouseArea.containsMouse 
                ? Appearance.colors.colLayer2Hover 
                : Appearance.colors.colLayer2

            border.width: 0

            // Micro-interactions
            scale: cardMouseArea.containsMouse ? 1.04 : 1.0
            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutBack }
            }
            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            MouseArea {
                id: cardMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                // Circular Gauge with Tonal Center Disc & M3 Shape
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 62
                    implicitHeight: 62

                    CircularProgress {
                        anchors.fill: parent
                        implicitSize: 62
                        lineWidth: 7
                        value: card.value
                        colPrimary: card.effectiveAccent
                        colSecondary: card.effectiveTrack
                    }

                    // Shared MaterialShape Wrapped Symbol matching ResourcesWidget badge
                    MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        wrappedShape: card.iconShape
                        text: card.icon
                        iconSize: 18
                        fill: 1
                        padding: 6
                        implicitSize: 34
                        color: card.effectiveAccent
                        colSymbol: card.effectiveOnAccent
                    }
                }

                // Value and Label (Material 3 Typography Hierarchy)
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: card.detail
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideNone
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: card.label
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.letterSpacing: 0.8
                        color: card.effectiveAccent
                    }
                }
            }
        }

        ResourceCard {
            icon: "memory"
            iconShape: MaterialShape.Shape.Circle
            label: "RAM"
            value: ResourceUsage.memoryUsedPercentage
            detail: root.formatKB(ResourceUsage.memoryUsed)
            colAccent: root.getMetricShade(Appearance.colors.colSecondary, 0.76, 0.50)
            colOnAccent: Appearance.colors.colOnSecondary
        }

        ResourceCard {
            visible: ResourceUsage.swapTotal > 0
            icon: "swap_horiz"
            iconShape: MaterialShape.Shape.Circle
            label: "SWAP"
            value: ResourceUsage.swapUsedPercentage
            detail: root.formatKB(ResourceUsage.swapUsed)
            colAccent: root.getMetricShade(Appearance.colors.colTertiary, 0.73, 0.42)
            colOnAccent: Appearance.colors.colOnTertiary
        }

        ResourceCard {
            icon: "planner_review"
            iconShape: MaterialShape.Shape.Circle
            label: "CPU"
            value: ResourceUsage.cpuUsage
            detail: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            colAccent: root.getMetricShade(Appearance.colors.colPrimary, 0.84, 0.40)
            colOnAccent: Appearance.colors.colOnPrimary
        }

        ResourceCard {
            visible: ResourceUsage.gpuAvailable
            icon: "developer_board"
            iconShape: MaterialShape.Shape.Circle
            label: "GPU"
            value: ResourceUsage.gpuUsage
            detail: `${Math.round(ResourceUsage.gpuUsage * 100)}%`
            colAccent: root.getMetricShade(Appearance.colors.colPrimary, 0.81, 0.48)
            colOnAccent: Appearance.colors.colOnPrimary
        }

        ResourceCard {
            icon: "device_thermostat"
            iconShape: MaterialShape.Shape.Circle
            label: "TEMP"
            value: ResourceUsage.temperature / 100
            detail: `${Math.round(ResourceUsage.temperature)}°C`
            property bool isHot: ResourceUsage.temperature > 75
            colAccent: isHot ? Appearance.colors.colError : root.getMetricShade(Appearance.colors.colTertiary, 0.77, 0.52)
            colOnAccent: isHot ? Appearance.colors.colOnError : Appearance.colors.colOnTertiary
            isCritical: isHot
        }

        ResourceCard {
            icon: "network_check"
            iconShape: MaterialShape.Shape.Circle
            label: "NET"
            // Cap ring at ~15 MB/s (15 * 1024 * 1024 bytes)
            value: Math.min(ResourceUsage.networkDownloadSpeed / 15728640, 1.0)
            detail: ResourceUsage.formatSpeed(ResourceUsage.networkDownloadSpeed)
            colAccent: root.getMetricShade(Appearance.colors.colSecondary, 0.79, 0.42)
            colOnAccent: Appearance.colors.colOnSecondary
            isCritical: false
        }
    }
}
