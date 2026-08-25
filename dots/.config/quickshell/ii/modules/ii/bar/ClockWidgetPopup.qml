import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    property string formattedDate: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM dd, yyyy")
    property string formattedTime: DateTime.time
    property string formattedUptime: DateTime.uptime
    property var unfinishedTodos: Todo.list.filter(item => !item.done)
    
    // Material 3 Expressive dusk-inspired color palette
    property color duskSurface: "#1a1620"
    property color duskSurfaceContainer: "#25202e"
    property color duskSurfaceContainerElevated: "#2d2838"
    property color duskPrimary: "#d4c5e8"
    property color duskPrimaryContainer: "#3d3450"
    property color duskOnPrimary: "#1a1424"
    property color duskOnSurface: "#e8e2eb"
    property color duskOnSurfaceVariant: "#b8afc0"
    property color duskOutline: "#5a5266"
    property color duskBadge: "#4a405c"
    property color duskBadgeOn: "#f0ebf5"

    function getUpcomingTodos() {
        if (unfinishedTodos.length === 0) {
            return Translation.tr("No pending tasks");
        }

        const limitedTodos = unfinishedTodos.slice(0, 5);
        let todoText = limitedTodos.map((item, index) => {
            return `  ${index + 1}. ${item.content}`;
        }).join('\n');

        if (unfinishedTodos.length > 5) {
            todoText += `\n  ${Translation.tr("... and %1 more").arg(unfinishedTodos.length - 5)}`;
        }

        return todoText;
    }

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 16
        Layout.preferredWidth: 280

        // Header Section with elevated container
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerContent.implicitHeight + 24
            color: duskSurfaceContainerElevated
            radius: 20
            border.width: 1
            border.color: Qt.rgba(duskOutline.r, duskOutline.g, duskOutline.b, 0.3)

            Column {
                id: headerContent
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 6

                RowLayout {
                    width: parent.width
                    spacing: 10

                    // Tonal icon badge
                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 12
                        color: duskPrimaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 20
                            text: "light_mode"
                            color: duskPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: {
                                const hour = DateTime.clock.date.getHours();
                                if (hour < 12) return Translation.tr("Good Morning");
                                if (hour < 18) return Translation.tr("Good Afternoon");
                                return Translation.tr("Good Evening");
                            }
                            font.pixelSize: Appearance.font.pixelSize.normal + 2
                            font.weight: Font.Black
                            font.family: Appearance.font.family.expressive
                            color: duskPrimary
                            horizontalAlignment: Text.AlignLeft
                        }

                        StyledText {
                            text: root.formattedDate
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small + 1
                            font.weight: Font.Medium
                            color: duskOnSurfaceVariant
                            horizontalAlignment: Text.AlignLeft
                        }
                    }
                }
            }
        }

        // System Uptime - Pill-shaped card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: uptimeContent.implicitHeight + 16
            color: duskSurfaceContainer
            radius: 14
            border.width: 1
            border.color: Qt.rgba(duskOutline.r, duskOutline.g, duskOutline.b, 0.2)

            RowLayout {
                id: uptimeContent
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 12

                // Static timer icon
                MaterialSymbol {
                    iconSize: 22
                    text: "timer"
                    color: duskOnSurfaceVariant
                    opacity: 0.9
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("System uptime:")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: duskOnSurfaceVariant
                        opacity: 0.85
                    }

                    StyledText {
                        text: root.formattedUptime
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.numbers
                        color: duskOnSurface
                    }
                }
            }
        }

        // Tasks Section
        ColumnLayout {
            spacing: 10
            Layout.fillWidth: true

            // Section header
            RowLayout {
                spacing: 8

                Rectangle {
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 8
                    color: duskBadge

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 18
                        text: "checklist"
                        color: duskBadgeOn
                    }
                }

                StyledText {
                    text: Translation.tr("Upcoming Tasks")
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: duskOnSurface
                }
            }

            // Task cards
            Repeater {
                model: Math.min(unfinishedTodos.length, 5)
                delegate: Rectangle {
                    id: taskCard
                    Layout.fillWidth: true
                    implicitHeight: taskContent.implicitHeight + 16
                    color: duskSurfaceContainer
                    radius: 18
                    border.width: 1
                    border.color: Qt.rgba(duskOutline.r, duskOutline.g, duskOutline.b, 0.15)

                    property int taskIndex: index

                    Behavior on scale {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutQuad
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onEntered: taskCard.scale = 1.02
                        onExited: taskCard.scale = 1.0
                        onPressed: taskCard.scale = 0.98
                        onReleased: taskCard.scale = 1.02
                    }

                    RowLayout {
                        id: taskContent
                        anchors.centerIn: parent
                        width: parent.width - 20
                        spacing: 12

                        // Expressive numbered badge
                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 10
                            color: duskPrimaryContainer

                            StyledText {
                                anchors.centerIn: parent
                                text: String(index + 1).padStart(2, '0')
                                font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.numbers
                                color: duskBadgeOn
                            }
                        }

                        // Task content
                        StyledText {
                            Layout.fillWidth: true
                            text: unfinishedTodos[index].content
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Normal
                            color: duskOnSurface
                            lineHeight: 1.35
                        }
                    }
                }
            }

            // No tasks message
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: noTasksContent.implicitHeight + 16
                visible: unfinishedTodos.length === 0
                color: duskSurfaceContainer
                radius: 14
                border.width: 1
                border.color: Qt.rgba(duskOutline.r, duskOutline.g, duskOutline.b, 0.2)

                RowLayout {
                    id: noTasksContent
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 10

                    MaterialSymbol {
                        iconSize: 20
                        text: "task_alt"
                        color: duskPrimary
                        opacity: 0.8
                    }

                    StyledText {
                        text: root.getUpcomingTodos()
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: duskOnSurfaceVariant
                    }
                }
            }

            // More tasks indicator
            StyledText {
                visible: unfinishedTodos.length > 5
                text: Translation.tr("... and %1 more").arg(unfinishedTodos.length - 5)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: duskOnSurfaceVariant
                opacity: 0.7
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignRight
            }
        }
    }
}
