import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitWidth: networkLayout.implicitWidth + 16
    implicitHeight: Appearance.sizes.barHeight
    visible: Config.options.bar.showNetworkSpeed
    property int displayMode: 3 // Default to both

    function formatSpeed(bytesPerSecond) {
        if (bytesPerSecond < 1024) return bytesPerSecond.toFixed(0) + " B/s";
        else if (bytesPerSecond < 1024 * 1024) return (bytesPerSecond / 1024).toFixed(1) + " KB/s";
        else if (bytesPerSecond < 1024 * 1024 * 1024) return (bytesPerSecond / (1024 * 1024)).toFixed(1) + " MB/s";
        else return (bytesPerSecond / (1024 * 1024 * 1024)).toFixed(1) + " GB/s";
    }

    function getDisplayText() {
        var downloadSpeed = ResourceUsage.networkDownloadSpeed;
        var uploadSpeed = ResourceUsage.networkUploadSpeed;
        var totalSpeed = downloadSpeed + uploadSpeed;
        switch (displayMode) {
            case 0: return formatSpeed(totalSpeed); // Total
            case 1: return "↓ " + formatSpeed(downloadSpeed); // Download
            case 2: return "↑ " + formatSpeed(uploadSpeed); // Upload
            case 3: return ""; // Both
            default: return formatSpeed(totalSpeed);
        }
    }

    RowLayout {
        id: networkLayout
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            text: "network_check"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            id: singleLineText
            visible: displayMode !== 3
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            text: getDisplayText()
        }
        RowLayout {
            visible: displayMode === 3
            spacing: 4
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                text: "↓ " + formatSpeed(ResourceUsage.networkDownloadSpeed)
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                text: "↑ " + formatSpeed(ResourceUsage.networkUploadSpeed)
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: { displayMode = (displayMode + 1) % 4; }
    }
}
