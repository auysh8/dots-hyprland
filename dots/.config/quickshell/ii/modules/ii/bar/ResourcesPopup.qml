import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Helper function to format KB to GB
    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    Flow {
        anchors.centerIn: parent
        width: 320 // Set a max width to force multi-row layout (e.g. 3 cards per row)
        spacing: 16

        component ResourceCircle: Rectangle {
            id: cardRect
            width: 96
            height: 130
            radius: 12

            // Scale on hover/press
            property real targetScale: mouseArea.pressed ? 0.95 : (mouseArea.containsMouse ? 1.02 : 1.0)
            scale: targetScale
            Behavior on scale {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                }
            }

            property string icon: ""
            property string label: ""
            property real value: 0
            property string primaryValue: ""
            property string unit: ""
            property color highlightColor: Appearance.colors.colPrimary

            property bool isAlert: value > 0.9

            color: isAlert ? Appearance.m3colors.m3errorContainer : ColorUtils.mix(Appearance.colors.colLayer1, highlightColor, 0.95)
            border.color: Appearance.colors.colOutlineVariant
            border.width: 1

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
            }

            Column {
                anchors.centerIn: parent
                spacing: 12

                Item {
                    width: 56
                    height: 56
                    anchors.horizontalCenter: parent.horizontalCenter

                    CircularProgress {
                        anchors.fill: parent
                        implicitSize: 56
                        lineWidth: 5
                        value: cardRect.value
                        colPrimary: cardRect.isAlert ? Appearance.m3colors.m3error : cardRect.highlightColor
                        colSecondary: ColorUtils.transparentize(cardRect.isAlert ? Appearance.m3colors.m3error : cardRect.highlightColor, 0.8)
                    }

                    MaterialSymbol {
                        id: metricIcon
                        anchors.centerIn: parent
                        text: cardRect.icon
                        iconSize: 24
                        color: cardRect.isAlert ? Appearance.m3colors.m3error : cardRect.highlightColor
                        opacity: 0.9

                        scale: mouseArea.pressed ? 0.9 : (cardRect.isAlert ? 1.1 : 1.0)
                        Behavior on scale {
                            SpringAnimation {
                                spring: 2
                                damping: 0.2
                            }
                        }

                        SequentialAnimation on opacity {
                            running: cardRect.isAlert
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.5; duration: 800; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 0.9; duration: 800; easing.type: Easing.InOutQuad }
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cardRect.label
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.letterSpacing: 1.5
                        font.capitalization: Font.AllUppercase
                        color: cardRect.isAlert ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSurface
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2

                        StyledText {
                            anchors.baseline: parent.bottom
                            text: cardRect.primaryValue
                            font.weight: Font.Black
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: cardRect.isAlert ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSurface
                        }

                        StyledText {
                            anchors.baseline: parent.bottom
                            text: cardRect.unit
                            font.weight: Font.Medium
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: cardRect.isAlert ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }

        ResourceCircle {
            icon: "memory"
            label: "RAM"
            value: ResourceUsage.memoryUsedPercentage
            // Helper parsing for primaryValue and unit based on detailed text.
            primaryValue: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1)
            unit: "GB"
            highlightColor: Appearance.m3colors.m3primary
        }

        ResourceCircle {
            visible: ResourceUsage.swapTotal > 0
            icon: "swap_horiz"
            label: "SWAP"
            value: ResourceUsage.swapUsedPercentage
            primaryValue: (ResourceUsage.swapUsed / (1024 * 1024)).toFixed(1)
            unit: "GB"
            highlightColor: Appearance.m3colors.m3tertiary
        }

        ResourceCircle {
            icon: "planner_review"
            label: "CPU"
            value: ResourceUsage.cpuUsage
            primaryValue: Math.round(ResourceUsage.cpuUsage * 100).toString()
            unit: "%"
            highlightColor: Appearance.m3colors.m3secondary
        }

        ResourceCircle {
            visible: ResourceUsage.hasGpu
            icon: "memory_alt"
            label: "GPU"
            value: ResourceUsage.gpuUsage
            primaryValue: Math.round(ResourceUsage.gpuUsage * 100).toString()
            unit: "%"
            highlightColor: Appearance.m3colors.m3secondaryContainer
        }

        ResourceCircle {
            icon: "device_thermostat"
            label: "TEMP"
            value: ResourceUsage.temperature / 100
            primaryValue: Math.round(ResourceUsage.temperature).toString()
            unit: "°C"
            highlightColor: Appearance.m3colors.m3error
        }

        ResourceCircle {
            icon: "network_check"
            label: "NET"
            // Cap ring at ~15 MB/s (15 * 1024 * 1024 bytes)
            value: Math.min(ResourceUsage.networkDownloadSpeed / 15728640, 1.0)

            // Format logic based on formatSpeed string return
            property string speedStr: ResourceUsage.formatSpeed(ResourceUsage.networkDownloadSpeed)
            property var speedParts: speedStr.split(" ")
            primaryValue: speedParts.length > 0 ? speedParts[0] : "0"
            unit: speedParts.length > 1 ? speedParts[1] : "B/s"
            highlightColor: Appearance.m3colors.m3primaryContainer
        }
    }
}
