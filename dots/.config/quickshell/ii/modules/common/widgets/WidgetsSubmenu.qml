pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    readonly property var widgetList: [
        { key: "visualizer",  icon: "graphic_eq",         name: Translation.tr("Visualizer") },
        { key: "customImage", icon: "image",              name: Translation.tr("Custom Image") },
        { key: "weather",     icon: "partly_cloudy_day",  name: Translation.tr("Weather") },
        { key: "clock",       icon: "schedule",           name: Translation.tr("Clock") },
        { key: "media",       icon: "music_note",         name: Translation.tr("Media") },
        { key: "images",      icon: "photo_library",      name: Translation.tr("Image Converter") },
        { key: "resources",   icon: "monitor_heart",      name: Translation.tr("Resources") },
        { key: "calendar",    icon: "calendar_month",     name: Translation.tr("Calendar") },
        { key: "worldClock",  icon: "public",             name: Translation.tr("World Clock") },
        { key: "userCard",    icon: "person",             name: Translation.tr("User Card") },
        { key: "notes",       icon: "note_stack_add",     name: Translation.tr("Notes") },
        { key: "timers",      icon: "timer",              name: Translation.tr("Timers") },
        { key: "todo",        icon: "add_task",           name: Translation.tr("To-Do") },
    ]

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "lock"
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        Repeater {
            model: root.widgetList
            delegate: ColumnLayout {
                id: delegateCol
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: delegateCol.modelData.icon
                    text: delegateCol.modelData.name
                    checked: (Config.options && Config.options.background && Config.options.background.widgets && Config.options.background.widgets[delegateCol.modelData.key]) ? Config.options.background.widgets[delegateCol.modelData.key].enable : false
                    onCheckedChanged: {
                        if (Config.options && Config.options.background && Config.options.background.widgets && Config.options.background.widgets[delegateCol.modelData.key]) {
                            Config.options.background.widgets[delegateCol.modelData.key].enable = checked
                        }
                    }
                }

                // Quick style selector for Clock
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 36
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 4
                    spacing: 6
                    visible: delegateCol.modelData.key === "clock" && (Config.options.background.widgets.clock ? Config.options.background.widgets.clock.enable : false)

                    Repeater {
                        model: [
                            { label: "Cookie", value: "cookie" },
                            { label: "Pixel", value: "pixel" },
                            { label: "Digital", value: "digital" }
                        ]
                        delegate: Rectangle {
                            id: pill
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: Appearance.rounding.small
                            readonly property bool isSelected: Config.options.background.widgets.clock && Config.options.background.widgets.clock.style === modelData.value
                            color: isSelected
                                ? Appearance.colors.colPrimary
                                : (pillMouse.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: pill.modelData.label
                                font.pixelSize: 11
                                font.weight: pill.isSelected ? 700 : 400
                                color: pill.isSelected
                                    ? Appearance.colors.colOnPrimary
                                    : Appearance.colors.colOnLayer0
                            }

                            MouseArea {
                                id: pillMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (Config.options.background.widgets.clock) {
                                        Config.options.background.widgets.clock.style = pill.modelData.value
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}