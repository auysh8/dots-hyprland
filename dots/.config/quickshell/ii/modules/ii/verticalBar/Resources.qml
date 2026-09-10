import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    property bool alwaysShowAllResources: false
    implicitHeight: columnLayout.implicitHeight
    implicitWidth: columnLayout.implicitWidth
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    ColumnLayout {
        id: columnLayout
        spacing: 10
        anchors.fill: parent

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
            accentColor: Appearance.colors.colPrimary // M3 triad: memory = primary
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
            accentColor: Appearance.colors.colSecondary // M3 triad: swap = secondary
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
            accentColor: Appearance.colors.colTertiary // M3 triad: CPU = tertiary
        }

        Resource {
            visible: ResourceUsage.gpuAvailable
            Layout.alignment: Qt.AlignHCenter
            iconName: "developer_board"
            percentage: ResourceUsage.gpuUsage
            warningThreshold: 90
            accentColor: Appearance.colors.colPrimary // M3 triad cycle: GPU = primary again
        }
    }

    Bar.ResourcesPopup {
        hoverTarget: root
    }
}
