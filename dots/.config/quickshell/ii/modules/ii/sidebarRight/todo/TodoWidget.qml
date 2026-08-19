import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    property var tabButtonList: [{"icon": "checklist", "name": Translation.tr("Unfinished")}, {"name": Translation.tr("Done"), "icon": "check_circle"}]
    property bool showAddDialog: false
    property int dialogMargins: 20
    property int fabSize: 48
    property int fabMargins: 14

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                tabBar.incrementCurrentIndex();
            } else if (event.key === Qt.Key_PageUp) {
                tabBar.decrementCurrentIndex();
            }
            event.accepted = true;
        }
        else if (event.key === Qt.Key_N) {
            root.showAddDialog = true
            event.accepted = true;
        }
        else if (event.key === Qt.Key_Escape && root.showAddDialog) {
            root.showAddDialog = false
            event.accepted = true;
        }
    }

    ColumnLayout {
        id: mainContentLayout
        anchors.fill: parent
        spacing: 0

        SecondaryTabBar {
            id: tabBar
            currentIndex: swipeView.currentIndex

            Repeater {
                model: root.tabButtonList
                delegate: SecondaryTabButton {
                    buttonText: modelData.name
                    buttonIcon: modelData.icon
                }
            }
        }

        Item {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            property int currentIndex: tabBar.currentIndex

            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "check_circle"
                emptyPlaceholderText: Translation.tr("Nothing here!")
                taskList: Todo.list
                    .map(function(item, i) { return Object.assign({}, item, {originalIndex: i}); })
                    .filter(function(item) { return !item.done; })

                width: parent.width
                height: parent.height
                x: (0 - swipeView.currentIndex) * (parent.width + 30)
                opacity: swipeView.currentIndex === 0 ? 1 : 0
                scale: swipeView.currentIndex === 0 ? 1 : 0.96

                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            }

            TaskList {
                listBottomPadding: root.fabSize + root.fabMargins * 2
                emptyPlaceholderIcon: "checklist"
                emptyPlaceholderText: Translation.tr("Finished tasks will go here")
                taskList: Todo.list
                    .map(function(item, i) { return Object.assign({}, item, {originalIndex: i}); })
                    .filter(function(item) { return item.done; })

                width: parent.width
                height: parent.height
                x: (1 - swipeView.currentIndex) * (parent.width + 30)
                opacity: swipeView.currentIndex === 1 ? 1 : 0
                scale: swipeView.currentIndex === 1 ? 1 : 0.96

                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            }
        }
    }

    StyledRectangularShadow {
        target: fabButton
        radius: fabButton.buttonRadius
        blur: 0.6 * Appearance.sizes.elevationMargin
    }
    FloatingActionButton {
        id: fabButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.fabMargins
        anchors.bottomMargin: root.fabMargins

        onClicked: root.showAddDialog = true
        iconText: "add"
    }

    Item {
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.showAddDialog ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        onVisibleChanged: {
            if (!visible) {
                todoInput.text = ""
                fabButton.focus = true
            }
        }

        // Soft dark translucent scrim overlay with click-outside dismiss
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim

            MouseArea {
                anchors.fill: parent
                onClicked: root.showAddDialog = false
            }
        }

        Rectangle {
            id: dialog
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: root.dialogMargins
            implicitHeight: dialogColumnLayout.implicitHeight

            color: Appearance.m3colors.m3surfaceContainerHigh
            radius: 20
            border.width: 1
            border.color: Appearance.m3colors.m3outlineVariant

            function addTask() {
                if (todoInput.text.length > 0) {
                    Todo.addTask(todoInput.text)
                    todoInput.text = ""
                    root.showAddDialog = false
                    tabBar.setCurrentIndex(0)
                }
            }

            ColumnLayout {
                id: dialogColumnLayout
                anchors.fill: parent
                spacing: 16

                RowLayout {
                    Layout.topMargin: 18
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    spacing: 8

                    MaterialSymbol {
                        text: "task_alt"
                        iconSize: 22
                        fill: 1
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        color: Appearance.m3colors.m3onSurface
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        text: Translation.tr("Add task")
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    implicitHeight: 44
                    radius: 12
                    color: Appearance.m3colors.m3surfaceContainer
                    border.width: todoInput.activeFocus ? 2 : 1
                    border.color: todoInput.activeFocus ? Appearance.colors.colPrimary : Appearance.m3colors.m3outlineVariant

                    StyledTextInput {
                        id: todoInput
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 14
                        color: Appearance.m3colors.m3onSurface
                        clip: true
                        selectByMouse: true
                        selectionColor: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.4)
                        selectedTextColor: Appearance.colors.colOnPrimary
                        focus: root.showAddDialog
                        onAccepted: dialog.addTask()

                        StyledText {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Task description...")
                            font.pixelSize: 14
                            color: Appearance.m3colors.m3outline
                            visible: !todoInput.text && !todoInput.activeFocus
                        }
                    }
                }

                RowLayout {
                    Layout.bottomMargin: 18
                    Layout.leftMargin: 18
                    Layout.rightMargin: 18
                    Layout.alignment: Qt.AlignRight
                    spacing: 8

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        colText: Appearance.m3colors.m3outline
                        onClicked: root.showAddDialog = false
                    }

                    DialogButton {
                        buttonText: Translation.tr("Add")
                        enabled: todoInput.text.length > 0
                        colEnabled: Appearance.colors.colPrimary
                        colDisabled: Appearance.m3colors.m3outline
                        onClicked: dialog.addTask()
                    }
                }
            }
        }
    }
}
