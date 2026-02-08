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
    property string todosSection: getUpcomingTodos()

    function getUpcomingTodos() {
        const unfinishedTodos = Todo.list.filter(function (item) {
            return !item.done;
        });
        if (unfinishedTodos.length === 0) {
            return Translation.tr("No pending tasks");
        }

        // Limit to first 5 todos to keep popup manageable
        const limitedTodos = unfinishedTodos.slice(0, 5);
        let todoText = limitedTodos.map(function (item, index) {
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
        spacing: 12
        Layout.preferredWidth: 200

        Column {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                text: {
                    const hour = DateTime.clock.date.getHours();
                    if (hour < 12) return Translation.tr("Good Morning");
                    if (hour < 18) return Translation.tr("Good Afternoon");
                    return Translation.tr("Good Evening");
                }
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Black
                color: Appearance.m3colors.m3primary
                opacity: 1.0
            }
            StyledText {
                text: root.formattedDate
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.5
        }

        StyledPopupValueRow {
            icon: "timelapse"
            label: Translation.tr("System uptime:")
            value: root.formattedUptime
            bold: true
        }

        // Tasks Section
        ColumnLayout {
            spacing: 8
            Layout.fillWidth: true
            Layout.topMargin: 4

            RowLayout {
                spacing: 6
                MaterialSymbol {
                    iconSize: 20
                    text: "checklist"
                    color: Appearance.m3colors.m3secondary
                }
                StyledText {
                    text: Translation.tr("Upcoming Tasks")
                    font.weight: Font.Black
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                }
            }

            StyledText {
                id: todoTextItem
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                text: root.todosSection
                lineHeight: 1.3
            }
        }
    }
}
