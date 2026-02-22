pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    minimumWidth: 300
    minimumHeight: 200
    property list<var> resources: [
        {
            "icon": "planner_review",
            "name": Translation.tr("CPU"),
            "history": ResourceUsage.cpuUsageHistory,
            "maxAvailableString": ResourceUsage.maxAvailableCpuString
        },
        {
            "icon": "memory",
            "name": Translation.tr("RAM"),
            "history": ResourceUsage.memoryUsageHistory,
            "maxAvailableString": ResourceUsage.maxAvailableMemoryString
        },
        {
            "icon": "swap_horiz",
            "name": Translation.tr("Swap"),
            "history": ResourceUsage.swapUsageHistory,
            "maxAvailableString": ResourceUsage.maxAvailableSwapString
        },
        {
            "icon": "wifi", // Ensure "wifi" icon exists in your icon set or use a standard one
            "name": Translation.tr("Network"),
            "type": "network"
        },
    ]

    contentItem: OverlayBackground {
        id: contentItem
        radius: root.contentRadius
        property real padding: 4
        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: parent.padding
            }
            spacing: 8

            SecondaryTabBar {
                id: tabBar

                currentIndex: Persistent.states.overlay.resources.tabIndex
                onCurrentIndexChanged: {
                    Persistent.states.overlay.resources.tabIndex = tabBar.currentIndex;
                }

                Repeater {
                    model: root.resources.length
                    delegate: SecondaryTabButton {
                        required property int index
                        property var modelData: root.resources[index]
                        buttonIcon: modelData.icon
                        buttonText: modelData.name
                    }
                }
            }

            StackLayout {
                currentIndex: root.resources[tabBar.currentIndex]?.type === "network" ? 1 : 0
                Layout.fillWidth: true
                Layout.fillHeight: true

                ResourceSummary {
                    Layout.margins: 8
                    // Safe fallback for when we are on the Network tab (which has no history)
                    history: (root.resources[tabBar.currentIndex]?.type === "network") 
                             ? [0.0] 
                             : (root.resources[tabBar.currentIndex]?.history ?? [0.0])
                    maxAvailableString: root.resources[tabBar.currentIndex]?.maxAvailableString ?? "--"
                }

                NetworkSummary {
                    Layout.margins: 8
                }
            }
        }
    }

    component NetworkSummary: RowLayout {
        spacing: 20
        Layout.fillWidth: true
        Layout.fillHeight: true
        
        // Helper to calculate percentage based on a max speed (e.g. 100 Mbps = 12.5 MB/s)
        // Adjust maxSpeed (in bytes) as needed for your connection. 
        // 12500000 = 100 Mbps, 125000000 = 1 Gbps
        readonly property real maxSpeed: 12500000 

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            
            CircularProgress {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: 80
                lineWidth: 8
                value: Math.min(ResourceUsage.networkDownloadSpeed / parent.parent.maxSpeed, 1.0)
                colPrimary: Appearance.colors.colPrimary
                colSecondary: Appearance.colors.colSecondaryContainer
                
                StyledText {
                    anchors.centerIn: parent
                    text: "↓"
                    font.pixelSize: 24
                    color: Appearance.colors.colPrimary
                }
            }
            
            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignHCenter
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ResourceUsage.formatSpeed(ResourceUsage.networkDownloadSpeed).value
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.bold: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ResourceUsage.formatSpeed(ResourceUsage.networkDownloadSpeed).unit
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            
            CircularProgress {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: 80
                lineWidth: 8
                value: Math.min(ResourceUsage.networkUploadSpeed / parent.parent.maxSpeed, 1.0)
                colPrimary: Appearance.colors.colError // Different color for upload? Or keep primary
                colSecondary: Appearance.colors.colSecondaryContainer

                StyledText {
                    anchors.centerIn: parent
                    text: "↑"
                    font.pixelSize: 24
                    color: Appearance.colors.colError
                }
            }
            
            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignHCenter
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ResourceUsage.formatSpeed(ResourceUsage.networkUploadSpeed).value
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.bold: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ResourceUsage.formatSpeed(ResourceUsage.networkUploadSpeed).unit
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    component ResourceSummary: RowLayout {
        id: resourceSummary
        required property list<real> history
        required property string maxAvailableString
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        ColumnLayout {
            spacing: 2
            StyledText {
                text: (resourceSummary.history[resourceSummary.history.length - 1] * 100).toFixed(1) + "%"
                font {
                    family: Appearance.font.family.numbers
                    variableAxes: Appearance.font.variableAxes.numbers
                    pixelSize: Appearance.font.pixelSize.huge
                }
            }
            StyledText {
                text: Translation.tr("of %1").arg(resourceSummary.maxAvailableString)
                font {
                    // family: Appearance.font.family.numbers
                    // variableAxes: Appearance.font.variableAxes.numbers
                    pixelSize: Appearance.font.pixelSize.smallie
                }
                color: Appearance.colors.colSubtext
            }
            Item {
                Layout.fillHeight: true
            }
        }
        Rectangle {
            id: graphBg
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: graphBg.width
                    height: graphBg.height
                    radius: graphBg.radius
                }
            }
            Graph {
                anchors.fill: parent
                values: root.resources[tabBar.currentIndex]?.history ?? []
                points: ResourceUsage.historyLength
                alignment: Graph.Alignment.Right
            }
        }
    }
}
