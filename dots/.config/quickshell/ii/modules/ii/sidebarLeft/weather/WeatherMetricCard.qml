import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property string icon: "info"
    property string label: ""
    property string value: "--"
    property string detail: ""
    property color accent: Appearance.colors.colSecondary

    radius: 24
    color: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
    border.width: 1
    border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42)

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42
            radius: 21
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.accent
                font.family: Appearance.font.family.iconMaterial
                font.pixelSize: 22
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text: root.label
                color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                font.family: Appearance.font.family.main
                font.pixelSize: 11
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: root.value
                color: Appearance.colors.colOnSurface
                font.family: Appearance.font.family.main
                font.bold: true
                font.pixelSize: 14
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: root.detail
                visible: root.detail.length > 0
                color: Appearance.colors.colOutline
                font.family: Appearance.font.family.main
                font.pixelSize: 10
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}
