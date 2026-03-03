import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    // Accent Color
    readonly property color accentColor: Appearance.colors.colPrimaryContainer
    readonly property color onAccentColor: Appearance.colors.colOnPrimaryContainer
    // Progress (0.0 -> 1.0)
    readonly property real progress: DownloadService.progress || 0
    // Shortened filename for display
    readonly property string displayFilename: {
        let name = DownloadService.filename || "No active download";
        // Remove common URL encoding and clean up
        name = decodeURIComponent(name);
        // Truncate if too long
        if (name.length > 35) {
            let ext = name.lastIndexOf('.') > name.length - 8 ? name.slice(name.lastIndexOf('.')) : "";
            return name.slice(0, 32 - ext.length) + "..." + ext;
        }
        return name;
    }

    implicitHeight: mainLayout.implicitHeight + 32

    // Background (Dark)
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
    }

    Item {
        id: mainLayout

        anchors.fill: parent
        anchors.margins: 16
        implicitHeight: Math.max(infoLayout.implicitHeight, progressContainer.height)

        // Left Side: Info
        ColumnLayout {
            id: infoLayout

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: progressContainer.left
            anchors.rightMargin: 16
            spacing: 4

            // Large Percentage Display
            ColumnLayout {
                spacing: 0

                StyledText {
                    id: percentText

                    text: Math.round(root.progress * 100) + "%"
                    font.pixelSize: 48
                    font.weight: Font.Bold
                    font.family: "monospace" // Prevents number jitter natively
                    color: root.accentColor
                    horizontalAlignment: Text.AlignLeft
                }

                // Filename
                StyledText {
                    Layout.fillWidth: true
                    text: root.displayFilename
                    font.pixelSize: 14 // Increased from 12
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

            }

            // Status Row
            Row {
                spacing: 6

                StyledText {
                    text: {
                        if (!DownloadService.active)
                            return "PAUSED";

                        if (DownloadService.speed && DownloadService.speed !== "Unknown")
                            return DownloadService.speed;

                        return "DOWNLOADING";
                    }
                    font.pixelSize: 13 // Increased from 11
                    font.weight: Font.Bold // Bolder for readability
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2
                    color: Appearance.colors.colSubtext
                }

            }

            Item {
                Layout.fillHeight: true
            }

        }

        // Right Side: Circular Progress + Icon
        Item {
            id: progressContainer

            width: 80
            height: 80
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            // Circular Progress Ring
            CircularProgress {
                anchors.centerIn: parent
                implicitSize: 80
                lineWidth: 6
                value: root.progress
                colPrimary: root.accentColor
                colSecondary: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2)
                enableAnimation: true
            }

            // Download Icon (Center)
            Item {
                anchors.centerIn: parent
                width: 56
                height: 56

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "download"
                    iconSize: 32
                    color: root.accentColor
                }

            }

        }

    }

}
