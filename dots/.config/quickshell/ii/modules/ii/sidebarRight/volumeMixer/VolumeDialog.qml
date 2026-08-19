pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

WindowDialog {
    id: root
    property bool isSink: true
    backgroundHeight: 600

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 4
        spacing: 4

        StyledText {
            text: root.isSink ? Translation.tr("Audio output") : Translation.tr("Audio input")
            color: Appearance.colors.colOnSurface
            font {
                family: Appearance.font.family.title
                pixelSize: 22
                weight: Font.Bold
            }
        }

        StyledText {
            text: root.isSink ? Translation.tr("Control application volume levels") : Translation.tr("Control application microphone levels")
            font.pixelSize: 13
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    VolumeDialogContent {
        isSink: root.isSink
    }

    WindowDialogButtonRow {
        Layout.margins: 4
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.volumeMixer}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
            colBackground: Appearance.colors.colPrimary
            colText: Appearance.colors.colOnPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
        }
    }
}
