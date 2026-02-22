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

    Row {
        anchors.centerIn: parent
        spacing: 28

        component ResourceCircle: Column {
            spacing: 12
            property string icon: ""
            property string label: ""
            property real value: 0
            property string detail: ""
            property color highlightColor: Appearance.colors.colPrimary

            Item {
                width: 76
                height: 76
                anchors.horizontalCenter: parent.horizontalCenter

                CircularProgress {
                    anchors.fill: parent
                    implicitSize: 76
                    lineWidth: 6
                    value: parent.parent.value
                    colPrimary: parent.parent.value > 0.9 ? Appearance.m3colors.m3error : parent.parent.highlightColor
                    colSecondary: Appearance.colors.colLayer1
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: parent.parent.icon
                    iconSize: 30
                    color: parent.parent.value > 0.9 ? Appearance.m3colors.m3error : parent.parent.highlightColor
                    opacity: 0.9
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.parent.label
                    font.weight: Font.Black
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.parent.detail
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.8
                }
            }
        }

        ResourceCircle {
            icon: "memory"
            label: "RAM"
            value: ResourceUsage.memoryUsedPercentage
            detail: root.formatKB(ResourceUsage.memoryUsed)
            highlightColor: Appearance.m3colors.m3primary
        }

        ResourceCircle {
            visible: ResourceUsage.swapTotal > 0
            icon: "swap_horiz"
            label: "SWAP"
            value: ResourceUsage.swapUsedPercentage
            detail: root.formatKB(ResourceUsage.swapUsed)
            highlightColor: Appearance.m3colors.m3tertiary
        }

        ResourceCircle {
            icon: "planner_review"
            label: "CPU"
            value: ResourceUsage.cpuUsage
            detail: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            highlightColor: Appearance.m3colors.m3secondary
        }

        ResourceCircle {
            icon: "device_thermostat"
            label: "TEMP"
            value: ResourceUsage.temperature / 100
            detail: `${Math.round(ResourceUsage.temperature)}°C`
            highlightColor: Appearance.m3colors.m3error
        }

        ResourceCircle {
            icon: "network_check"
            label: "NET"
            // Cap ring at ~15 MB/s (15 * 1024 * 1024 bytes)
            value: Math.min(ResourceUsage.networkDownloadSpeed / 15728640, 1.0)
            detail: ResourceUsage.formatSpeed(ResourceUsage.networkDownloadSpeed)
            highlightColor: Appearance.m3colors.m3primary
        }
    }
}
