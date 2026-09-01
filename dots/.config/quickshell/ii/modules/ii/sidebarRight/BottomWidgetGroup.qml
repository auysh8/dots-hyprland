pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.todo
import qs.modules.ii.sidebarRight.pomodoro
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true
    property real collapsedHeight: 50
    implicitHeight: collapsed ? root.collapsedHeight : 350
    property int selectedTab: Persistent.states.sidebar.bottomGroup.tab
    property int previousIndex: -1
    property bool collapsed: Persistent.states.sidebar.bottomGroup.collapsed
    property var tabs: [
        {
            "type": "calendar",
            "name": Translation.tr("Calendar"),
            "icon": "calendar_month",
            "widget": "calendar/CalendarWidget.qml"
        },
        {
            "type": "todo",
            "name": Translation.tr("To Do"),
            "icon": "check_circle",
            "widget": "todo/TodoWidget.qml"
        },
        {
            "type": "timer",
            "name": Translation.tr("Timer"),
            "icon": "timer",
            "widget": "pomodoro/PomodoroWidget.qml"
        },
    ]

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutBack
        }
    }

    function setCollapsed(state) {
        Persistent.states.sidebar.bottomGroup.collapsed = state;
    }

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.selectedTab = Math.min(root.selectedTab + 1, root.tabs.length - 1);
            } else if (event.key === Qt.Key_PageUp) {
                root.selectedTab = Math.max(root.selectedTab - 1, 0);
            }
            event.accepted = true;
        }
    }

    RowLayout {
        id: collapsedBottomWidgetGroupRow
        opacity: root.collapsed ? 1 : 0
        scale: root.collapsed ? 1 : 0.85
        visible: opacity > 0
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

        // Left: Calendar Icon + Date
        RowLayout {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter

            MaterialSymbol {
                text: "calendar_month"
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: DateTime.collapsedCalendarFormat
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Right: Tasks Pill
        Pill {
            property int remainingTasks: Todo.list.filter(task => !task.done).length
            color: Appearance.colors.colLayer3
            implicitHeight: 34
            implicitWidth: taskText.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter

            StyledText {
                id: taskText
                anchors.centerIn: parent
                text: Translation.tr("%1 tasks due").arg(parent.remainingTasks)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer3
            }
        }
    }

    MouseArea {
        id: collapsedClickArea
        anchors.fill: parent
        enabled: root.collapsed
        cursorShape: Qt.PointingHandCursor
        onClicked: root.setCollapsed(false)
    }

    RowLayout {
        id: bottomWidgetGroupRow
        anchors.fill: parent
        visible: !root.collapsed
        spacing: 8

        Item {
            Layout.fillHeight: true
            implicitWidth: navRailContainer.implicitWidth

            CalendarHeaderButton {
                anchors.left: parent.left
                anchors.top: parent.top
                forceCircle: true
                downAction: () => root.setCollapsed(true)
                contentItem: MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }

            Pill {
                id: navRailContainer
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                implicitWidth: tabBar.implicitWidth + 14
                implicitHeight: tabBar.implicitHeight + 24
                color: Appearance.colors.colLayer2

                NavigationRailTabArray {
                    id: tabBar
                    anchors.centerIn: parent
                    currentIndex: root.selectedTab
                    expanded: false
                    Repeater {
                        model: root.tabs
                        NavigationRailButton {
                            required property int index
                            required property var modelData
                            showToggledHighlight: false
                            toggled: root.selectedTab == index
                            buttonText: modelData.name
                            buttonIcon: modelData.icon
                            onPressed: {
                                root.selectedTab = index;
                                Persistent.states.sidebar.bottomGroup.tab = index;
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                id: tabStack
                anchors.fill: parent
                transform: Translate { id: tabTranslate }

                Component.onCompleted: {
                    root.previousIndex = root.selectedTab;
                    tabStack.source = root.tabs[root.selectedTab].widget;
                }

                Connections {
                    target: root
                    function onSelectedTabChanged() {
                        if (root.previousIndex !== -1) {
                            tabSwitchBehavior.animation.down = root.selectedTab > root.previousIndex;
                        }
                        tabStack.source = root.tabs[root.selectedTab].widget;
                    }
                }

                Behavior on source {
                    id: tabSwitchBehavior
                    animation: TabSwitchAnim {
                        id: upAnim
                        down: true
                    }
                }
            }
        }
    }

    component TabSwitchAnim: SequentialAnimation {
        id: switchAnim
        property bool down: false
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 0
                duration: 150
                easing.type: Easing.OutCubic
            }
            PropertyAnimation {
                target: tabTranslate
                property: "y"
                to: switchAnim.down ? -40 : 40
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        PropertyAction {
            target: tabStack
            property: "source"
            value: root.tabs[root.selectedTab].widget
        }
        ParallelAnimation {
            PropertyAnimation {
                target: tabTranslate
                property: "y"
                from: switchAnim.down ? 40 : -40
                to: 0
                duration: 200
                easing.type: Easing.OutCubic
            }
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 1
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction {
            script: {
                root.previousIndex = root.selectedTab;
            }
        }
    }
}
