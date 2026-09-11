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
    anchors.fill: parent

    // M3 Color Mapping (Secondary Tonal Container paired with OnSecondaryContainer)
    readonly property color containerColor: Appearance.colors.colSecondaryContainer
    readonly property color onContainerColor: Appearance.colors.colOnSecondaryContainer
    readonly property color accentColor: Appearance.colors.colSecondary

    // Progress (0.0 -> 1.0)
    readonly property real progress: DownloadService.progress || 0
    readonly property bool isCompleted: DownloadService.status === "completed"
    readonly property bool isInterrupted: DownloadService.status === "interrupted"
    readonly property bool isPaused: !DownloadService.active && !isCompleted

    // Filename for display
    readonly property string displayFilename: {
        let name = DownloadService.filename || "No active download";
        return decodeURIComponent(name);
    }

    implicitHeight: Math.max(mainRow.implicitHeight + 20, 100)

    RowLayout {
        id: mainRow
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 14

        // 1. Left Side: Material Shape Hero Container with Percentage & Status Symbol
        Item {
            id: heroContainer
            Layout.preferredWidth: 84
            Layout.preferredHeight: 84
            implicitWidth: 84
            implicitHeight: 84
            Layout.alignment: Qt.AlignVCenter

            MaterialShape {
                id: shapeBackground
                anchors.fill: parent
                implicitSize: 84
                color: root.containerColor
                shape: {
                    if (root.isCompleted) return MaterialShape.Shape.VerySunny;
                    if (root.isInterrupted) return MaterialShape.Shape.Boom;
                    return MaterialShape.Shape.Cookie4Sided;
                }

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isCompleted ? "100%" : Math.round(root.progress * 100) + "%"
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colOnSecondaryContainer

                    Behavior on color {
                        ColorAnimation { duration: 250 }
                    }
                }

                MaterialSymbol {
                    id: heroSymbol
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        if (root.isCompleted) return "check_circle";
                        if (root.isInterrupted) return "error";
                        if (root.isPaused) return "pause";
                        return "downloading";
                    }
                    iconSize: 18
                    fill: 1
                    color: Appearance.colors.colOnSecondaryContainer

                    Behavior on color {
                        ColorAnimation { duration: 250 }
                    }
                }
            }
        }

        // 2. Right Side: Metadata Stack & M3 Expressive Progress Bar
        ColumnLayout {
            id: detailsCol
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 6

            // File Name
            StyledText {
                Layout.fillWidth: true
                text: root.displayFilename
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Status Capsule Pill + Counter
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    implicitHeight: 24
                    implicitWidth: statusRow.implicitWidth + 16
                    radius: 12
                    color: Appearance.colors.colSurfaceContainerHigh

                    Row {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.isCompleted) return "check";
                                if (root.isInterrupted) return "warning";
                                if (root.isPaused) return "pause";
                                return "bolt";
                            }
                            iconSize: 13
                            fill: 1
                            color: root.accentColor
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.isCompleted) return "Completed";
                                if (root.isInterrupted) return "Interrupted";
                                if (root.isPaused) return "Paused";
                                if (DownloadService.speed && DownloadService.speed !== "Unknown")
                                    return DownloadService.speed;
                                return "Downloading";
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: {
                        if (DownloadService.count > 1) {
                            return DownloadService.count + " active";
                        }
                        return root.isCompleted ? "Finished" : "1 active";
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurfaceVariant
                    Layout.alignment: Qt.AlignRight
                }
            }

            // Material 3 Styled Progress Bar
            StyledProgressBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                valueBarHeight: 6
                valueBarWidth: 160
                value: root.progress
                highlightColor: root.accentColor
                trackColor: Appearance.colors.colSurfaceContainerHighest
                wavy: DownloadService.active && !root.isCompleted
                animateWave: wavy
            }
        }
    }
}
