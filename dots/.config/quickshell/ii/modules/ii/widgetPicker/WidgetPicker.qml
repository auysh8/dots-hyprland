pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Scope {
    id: root

    readonly property var allWidgets: [
        {
            key: "media",
            name: Translation.tr("Media Player"),
            description: Translation.tr("Desktop player with album art & controls"),
            icon: "music_note",
            category: Translation.tr("Entertainment")
        },
        {
            key: "resources",
            name: Translation.tr("System Resources"),
            description: Translation.tr("Live CPU, RAM, GPU and hardware monitor"),
            icon: "monitor_heart",
            category: Translation.tr("System")
        },
        {
            key: "notes",
            name: Translation.tr("Sticky Notes"),
            description: Translation.tr("Pinned desktop reminders and notes"),
            icon: "note_stack_add",
            category: Translation.tr("Productivity")
        },
        {
            key: "visualizer",
            name: Translation.tr("Audio Visualizer"),
            description: Translation.tr("Real-time audio spectrum waveform"),
            icon: "graphic_eq",
            category: Translation.tr("Entertainment")
        },
        {
            key: "calendar",
            name: Translation.tr("Monthly Calendar"),
            description: Translation.tr("Full monthly date & week layout"),
            icon: "calendar_month",
            category: Translation.tr("Time")
        },
        {
            key: "todo",
            name: Translation.tr("To-Do Tasks"),
            description: Translation.tr("Checklist for daily priorities"),
            icon: "add_task",
            category: Translation.tr("Productivity")
        },
        {
            key: "userCard",
            name: Translation.tr("User Profile"),
            description: Translation.tr("Avatar, hostname, distro & weather quip"),
            icon: "person",
            category: Translation.tr("Personal")
        },
        {
            key: "worldClock",
            name: Translation.tr("World Clock"),
            description: Translation.tr("Dot matrix map & multi-city clocks"),
            icon: "public",
            category: Translation.tr("Time")
        },
        {
            key: "timers",
            name: Translation.tr("Timer & Stopwatch"),
            description: Translation.tr("Desktop countdown and stopwatch"),
            icon: "timer",
            category: Translation.tr("Time")
        },
        {
            key: "clock",
            name: Translation.tr("Clock"),
            description: Translation.tr("Digital, Cookie, and Pixel styles"),
            icon: "schedule",
            category: Translation.tr("Time")
        },
        {
            key: "weather",
            name: Translation.tr("Weather Forecast"),
            description: Translation.tr("Live temperature & condition card"),
            icon: "partly_cloudy_day",
            category: Translation.tr("Information")
        },
        {
            key: "customImage",
            name: Translation.tr("Photo Frame"),
            description: Translation.tr("Pinned stickers and polaroid images"),
            icon: "image",
            category: Translation.tr("Personal")
        }
    ]

    property string searchFilter: ""

    readonly property var filteredWidgets: {
        const query = root.searchFilter.trim().toLowerCase()
        if (query.length === 0) return root.allWidgets
        return root.allWidgets.filter(w => 
            w.name.toLowerCase().includes(query) ||
            w.description.toLowerCase().includes(query) ||
            w.category.toLowerCase().includes(query)
        )
    }

    Loader {
        active: GlobalStates.widgetPickerOpen
        sourceComponent: PanelWindow {
            id: pickerWindow

            screen: GlobalStates.desktopMenuScreen ? GlobalStates.desktopMenuScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:widgetPicker"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Scrim (dark overlay)
            Rectangle {
                id: scrim
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
                opacity: 0

                Component.onCompleted: opacity = 1.0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: GlobalStates.widgetPickerOpen = false
                }
            }

            // Bottom Drawer Sheet
            Rectangle {
                id: drawerCard
                width: Math.min(pickerWindow.width - 40, 1280)
                height: Math.min(pickerWindow.height * 0.52, 420)
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 20
                }
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer0

                transform: Translate {
                    id: drawerAnim
                    y: drawerCard.height + 40
                    Behavior on y {
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                    }
                }

                Component.onCompleted: {
                    drawerAnim.y = 0
                }

                StyledRectangularShadow {
                    target: drawerCard
                    z: -1
                    opacity: 0.5
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // Top Bar / Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            implicitWidth: 40
                            implicitHeight: 40
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "widgets"
                                iconSize: 22
                                color: Appearance.colors.colPrimary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: Translation.tr("Desktop Widgets")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer0
                            }

                            StyledText {
                                text: Translation.tr("Drag any widget onto the wallpaper or toggle switches to enable")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        // Search Input
                        Rectangle {
                            implicitWidth: 240
                            implicitHeight: 38
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer1
                            border.color: searchInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 6

                                MaterialSymbol {
                                    text: "search"
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }

                                StyledTextInput {
                                    id: searchInput
                                    Layout.fillWidth: true
                                    text: root.searchFilter
                                    onTextChanged: root.searchFilter = text

                                    StyledText {
                                        anchors.fill: parent
                                        visible: !searchInput.text
                                        text: Translation.tr("Search widgets...")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }

                                RippleButton {
                                    visible: searchInput.text.length > 0
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    onClicked: {
                                        searchInput.text = ""
                                        root.searchFilter = ""
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 14
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        // Lock / Unlock Toggle Button
                        RippleButton {
                            implicitHeight: 38
                            implicitWidth: 140
                            buttonRadius: Appearance.rounding.full
                            colBackground: Config.options.background.widgetsLocked ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer2
                            onClicked: Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked

                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: Config.options.background.widgetsLocked ? "lock" : "lock_open"
                                    iconSize: 18
                                    color: Config.options.background.widgetsLocked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    text: Config.options.background.widgetsLocked ? Translation.tr("Locked") : Translation.tr("Unlocked")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Config.options.background.widgetsLocked ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                                }
                            }
                        }

                        // Close Button
                        RippleButton {
                            implicitWidth: 38
                            implicitHeight: 38
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer2
                            onClicked: GlobalStates.widgetPickerOpen = false

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colOutlineVariant
                        opacity: 0.3
                    }

                    // Horizontal Scrollable Cards Area
                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: cardRow.implicitWidth
                        contentHeight: flick.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        RowLayout {
                            id: cardRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 14

                            Repeater {
                                model: root.filteredWidgets
                                delegate: WidgetPickerCard {
                                    required property var modelData
                                    widgetKey: modelData.key
                                    name: modelData.name
                                    description: modelData.description
                                    icon: modelData.icon
                                    category: modelData.category
                                }
                            }
                        }
                    }
                }
            }

            // Keyboard shortcut (Escape to close)
            Item {
                focus: true
                Keys.onEscapePressed: GlobalStates.widgetPickerOpen = false
            }
        }
    }
}
