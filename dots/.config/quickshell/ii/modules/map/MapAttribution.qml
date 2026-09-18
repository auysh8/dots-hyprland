import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property string baseProvider: "openfreemap"

    implicitWidth: contentRow.implicitWidth + 16
    implicitHeight: 24
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer3Base
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            text: "© OpenFreeMap"
            font.pixelSize: 10
            color: Appearance.colors.colOnLayer1
            opacity: 1.0

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("https://openfreemap.org/")
            }
        }

        StyledText {
            text: "·"
            font.pixelSize: 10
            color: Appearance.colors.colOnLayer1
            opacity: 1.0
        }

        StyledText {
            text: "© OpenStreetMap"
            font.pixelSize: 10
            color: Appearance.colors.colOnLayer1
            opacity: 1.0

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("https://www.openstreetmap.org/copyright")
            }
        }
    }
}
