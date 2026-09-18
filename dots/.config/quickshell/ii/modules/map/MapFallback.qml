import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string message: Translation.tr("Map temporarily unavailable")
    property bool loading: false

    signal retryRequested

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer1
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 280)
        spacing: 12

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: root.loading
            loading: visible
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading
            text: "map"
            iconSize: 40
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            visible: !root.loading
            text: root.message
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading
            mainText: Translation.tr("Retry")
            materialIcon: "refresh"
            colBackground: Appearance.colors.colLayer2
            onClicked: root.retryRequested()
        }
    }
}
