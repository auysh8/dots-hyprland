import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets

Item {
    id: root

    property var rootContext: null
    property color contentColor: rootContext ? rootContext.contentColor : "#ffffff"
    property color pillColor: rootContext ? rootContext.pillColor : "#cba6f7"
    property color subtleColor: Qt.rgba(contentColor.r, contentColor.g, contentColor.b, 0.45)

    signal navigateTo(string view)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // Header
        StyledText {
            text: "Settings"
            font.pixelSize: 22
            font.weight: Font.Medium
            color: root.contentColor
        }

        // Settings entries
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            // Cache entry
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 60
                buttonRadius: 14
                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.10)
                colRipple: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.20)
                
                onClicked: root.navigateTo("cache")
                
                contentItem: RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 14

                    Rectangle {
                        width: 36; height: 36
                        radius: 10
                        color: Qt.rgba(root.pillColor.r, root.pillColor.g, root.pillColor.b, 0.15)
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "database"
                            iconSize: 18
                            color: root.pillColor
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: "Cache"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: "Manage downloaded audio, art & canvas"
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }

                    Item { Layout.fillWidth: true }

                    MaterialSymbol {
                        text: "chevron_right"
                        iconSize: 20
                        color: root.subtleColor
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
