pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root

    required property string widgetKey
    required property string name
    required property string description
    required property string icon
    required property string category
    property string previewType: widgetKey

    readonly property bool isEnabled: (Config.options && Config.options.background && Config.options.background.widgets && Config.options.background.widgets[root.widgetKey] && Config.options.background.widgets[root.widgetKey].enable) ? true : false

    implicitWidth: 280
    implicitHeight: 240
    radius: Appearance.rounding.large
    color: cardMouseArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    border.color: isEnabled ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    border.width: isEnabled ? 2 : 1

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: root
        z: -1
        opacity: cardMouseArea.containsMouse ? 0.35 : 0.15
    }

    Item {
        id: dragGhost
        width: 140
        height: 90
        visible: false
        Drag.active: dragMouseArea.drag.active
        Drag.source: root
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        Drag.mimeData: { "application/x-widget-key": root.widgetKey }
        Drag.dragType: Drag.Automatic

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.medium
            color: Appearance.colors.colPrimaryContainer
            border.color: Appearance.colors.colPrimary
            border.width: 2
            opacity: 0.85

            RowLayout {
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    text: root.icon
                    iconSize: 24
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: root.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header: Icon + Title + Category Badge + Switch
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: Appearance.rounding.small
                color: isEnabled ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: 20
                    color: isEnabled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.category
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                checked: root.isEnabled
                onCheckedChanged: {
                    if (Config.options && Config.options.background && Config.options.background.widgets && Config.options.background.widgets[root.widgetKey]) {
                        Config.options.background.widgets[root.widgetKey].enable = checked
                    }
                }
            }
        }

        // Preview Box (Visual representation)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.medium
            color: Appearance.colors.colLayer0
            clip: true

            // Mini Mockup representation
            Item {
                anchors.fill: parent
                anchors.margins: 8

                // Clock Preview
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.widgetKey === "clock" || root.widgetKey === "worldClock" || root.widgetKey === "timers"
                    spacing: 2
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.widgetKey === "timers" ? "05:00" : "12:45"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.widgetKey === "timers" ? "Timer" : "Tuesday, Sep 1"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                // Weather Preview
                RowLayout {
                    anchors.centerIn: parent
                    visible: root.widgetKey === "weather"
                    spacing: 8
                    MaterialSymbol {
                        text: "sunny"
                        iconSize: 28
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: "24°C"
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: "Partly Cloudy"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Media Preview
                RowLayout {
                    anchors.centerIn: parent
                    visible: root.widgetKey === "media"
                    spacing: 8
                    Rectangle {
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: 6
                        color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "music_note"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: "Track Title"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: "Artist Name"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Resources Preview
                RowLayout {
                    anchors.centerIn: parent
                    visible: root.widgetKey === "resources"
                    spacing: 12
                    ColumnLayout {
                        spacing: 2
                        StyledText { text: "CPU"; font.pixelSize: 10; color: Appearance.colors.colSubtext }
                        StyledText { text: "24%"; font.pixelSize: 14; font.weight: Font.Bold; color: Appearance.colors.colPrimary }
                    }
                    ColumnLayout {
                        spacing: 2
                        StyledText { text: "RAM"; font.pixelSize: 10; color: Appearance.colors.colSubtext }
                        StyledText { text: "5.2G"; font.pixelSize: 14; font.weight: Font.Bold; color: Appearance.colors.colSecondary }
                    }
                    ColumnLayout {
                        spacing: 2
                        StyledText { text: "GPU"; font.pixelSize: 10; color: Appearance.colors.colSubtext }
                        StyledText { text: "12%"; font.pixelSize: 14; font.weight: Font.Bold; color: Appearance.colors.colTertiary }
                    }
                }

                // Visualizer Preview
                RowLayout {
                    anchors.centerIn: parent
                    visible: root.widgetKey === "visualizer"
                    spacing: 4
                    Repeater {
                        model: [12, 28, 42, 30, 55, 38, 22, 48, 16]
                        delegate: Rectangle {
                            required property int modelData
                            implicitWidth: 6
                            implicitHeight: modelData
                            radius: 3
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                // Generic / Other Widgets Preview
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: ["clock", "worldClock", "timers", "weather", "media", "resources", "visualizer"].indexOf(root.widgetKey) === -1
                    spacing: 4
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.icon
                        iconSize: 26
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.description
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Footer: Drag & Drop handle
        Rectangle {
            id: dragBar
            Layout.fillWidth: true
            implicitHeight: 32
            radius: Appearance.rounding.small
            color: dragMouseArea.containsMouse ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: "drag_indicator"
                    iconSize: 16
                    color: dragMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    opacity: 0.8
                }
                StyledText {
                    text: Translation.tr("Drag to place on desktop")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Medium
                    color: dragMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }

            MouseArea {
                id: dragMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: dragGhost

                onPressed: {
                    dragGhost.x = mouse.x
                    dragGhost.y = mouse.y
                }

                onReleased: {
                    if (dragGhost.Drag.active) {
                        dragGhost.Drag.drop()
                    }
                }
            }
        }
    }

    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        z: -1
        hoverEnabled: true
    }
}
