//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "modules/ii/sysmon"

ApplicationWindow {
    id: root
    visible: true
    onClosing: Qt.quit()
    title: "System Monitor"

    minimumWidth: 800
    minimumHeight: 600
    width: 1000
    height: 700
    color: Appearance.m3colors.m3background

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        anchors.topMargin: 8
        spacing: 8

        Item { // Titlebar
            visible: Config.options && Config.options.windows ? Config.options.windows.showTitlebar : true
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: titleText
                anchors {
                    left: (Config.options && Config.options.windows && Config.options.windows.centerTitle) ? undefined : parent.left
                    horizontalCenter: (Config.options && Config.options.windows && Config.options.windows.centerTitle) ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("System Monitor")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: -8
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    padding: 0
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        SystemMonitor {
            Layout.fillWidth: true
            Layout.fillHeight: true
            isAppMode: true
            
            onCloseRequested: root.close()
        }
    }
}
