//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import "modules/common"
import "modules/common/functions"
import "services"
import "modules/common/widgets"
import "musicLayer"

ApplicationWindow {
    id: root
    visible: true
    onClosing: Qt.quit()
    title: "YouTube Music"

    minimumWidth: 800
    minimumHeight: 600
    width: 1100
    height: 800
    color: musicApp.backgroundColor || Appearance.colors.colLayer0Base

    Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
    }

    readonly property real contentPadding: 8

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)

            WindowDialogTitle {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: musicApp.contentColor || Appearance.colors.colOnLayer0
                text: Translation.tr("Music")
            }

            WindowDialogButtonRow { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    padding: 0
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(musicApp.contentColor || Appearance.colors.colOnLayer0, 0.1)
                    colRipple: ColorUtils.applyAlpha(musicApp.contentColor || Appearance.colors.colOnLayer0, 0.2)
                    onClicked: root.close()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: 20
                        color: musicApp.contentColor || Appearance.colors.colOnLayer0
                    }
                }
            }
        }

        MusicApp {
            id: musicApp
            Layout.fillWidth: true
            Layout.fillHeight: true
            isAppMode: true

            onCloseRequested: root.close()
        }
    }
}
