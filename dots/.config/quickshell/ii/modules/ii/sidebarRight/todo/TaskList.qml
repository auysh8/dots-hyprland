import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 8
    property int listBottomPadding: 80

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: taskColumn.implicitHeight + root.listBottomPadding
        clip: true
        boundsBehavior: Flickable.DragOverBounds
        ScrollBar.vertical: StyledScrollBar {}

        Column {
            id: taskColumn
            width: flickable.width
            spacing: root.todoListItemSpacing

            Repeater {
                model: ScriptModel {
                    values: root.taskList
                }
                delegate: Item {
                    id: todoItem
                    required property int index
                    required property var modelData
                    property string currentItemId: ""
                    property bool isVisualDone: modelData ? modelData.done : false
                    property bool isExiting: false
                    property bool isAnimatingHeight: false
                    property real animHeight: 0
                    property var exitCallback: null

                    width: taskColumn.width
                    implicitHeight: isAnimatingHeight ? animHeight : todoItemRectangle.implicitHeight
                    height: implicitHeight
                    clip: true

                    property bool isRecentlyAdded: (modelData && modelData.createdAt) ? ((Date.now() - modelData.createdAt) < 1500) : false

                    function setupItem(isInitial) {
                        if (!modelData) return;
                        const newId = modelData.id || ("task_" + (modelData.originalIndex !== undefined ? modelData.originalIndex : index));
                        if (currentItemId !== newId) {
                            currentItemId = newId;
                            exitAnim.stop();
                            entryAnim.stop();
                            entryTimer.stop();
                            toggleDelayTimer.stop();
                            exitCallback = null;
                            isExiting = false;
                            isAnimatingHeight = false;
                            animHeight = 0;
                            isVisualDone = modelData.done;

                            if (isRecentlyAdded && index === 0 && !modelData.done) {
                                isAnimatingHeight = true;
                                animHeight = 0;
                                todoItemRectangle.opacity = 0;
                                todoItemRectangle.scale = 0.88;
                                entryTimer.start();
                            } else {
                                todoItemRectangle.opacity = 1;
                                todoItemRectangle.scale = 1;
                            }
                        } else {
                            if (!toggleDelayTimer.running && !isExiting) {
                                isVisualDone = modelData.done;
                            }
                        }
                    }

                    Component.onCompleted: {
                        setupItem(true);
                    }

                    onModelDataChanged: {
                        setupItem(false);
                    }

                    Timer {
                        id: entryTimer
                        interval: 16
                        repeat: false
                        onTriggered: {
                            entryHeightAnim.to = todoItemRectangle.implicitHeight;
                            entryAnim.start();
                        }
                    }

                    ParallelAnimation {
                        id: entryAnim
                        NumberAnimation {
                            id: entryHeightAnim
                            target: todoItem
                            property: "animHeight"
                            from: 0
                            to: todoItemRectangle.implicitHeight
                            duration: 280
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: todoItemRectangle
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: todoItemRectangle
                            property: "scale"
                            from: 0.88
                            to: 1.0
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.15
                        }
                        onFinished: {
                            todoItem.isAnimatingHeight = false;
                            todoItem.animHeight = 0;
                        }
                    }

                    ParallelAnimation {
                        id: exitAnim
                        NumberAnimation {
                            target: todoItem
                            property: "animHeight"
                            to: -root.todoListItemSpacing
                            duration: 280
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: todoItemRectangle
                            property: "opacity"
                            to: 0
                            duration: 220
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: todoItemRectangle
                            property: "scale"
                            to: 0.85
                            duration: 220
                            easing.type: Easing.OutQuad
                        }
                        onFinished: {
                            if (todoItem.exitCallback) {
                                const cb = todoItem.exitCallback;
                                todoItem.exitCallback = null;
                                cb();
                            }
                        }
                    }

                    function destroyWithAnimation(callback) {
                        if (isExiting) return;
                        isExiting = true;
                        exitCallback = callback;
                        animHeight = todoItemRectangle.implicitHeight;
                        isAnimatingHeight = true;
                        exitAnim.start();
                    }

                    Timer {
                        id: toggleDelayTimer
                        interval: 250
                        repeat: false
                        property string targetId: ""
                        property int origIdx: -1
                        property bool wasDone: false
                        onTriggered: {
                            const idToToggle = targetId;
                            const idxToToggle = origIdx;
                            const previousDone = wasDone;
                            todoItem.destroyWithAnimation(() => {
                                if (idToToggle) {
                                    if (!previousDone)
                                        Todo.markDoneById(idToToggle);
                                    else
                                        Todo.markUnfinishedById(idToToggle);
                                } else {
                                    if (!previousDone)
                                        Todo.markDone(idxToToggle);
                                    else
                                        Todo.markUnfinished(idxToToggle);
                                }
                            });
                        }
                    }

                    Rectangle {
                        id: todoItemRectangle
                        width: parent.width
                        implicitHeight: Math.max(52, todoContentText.implicitHeight + 20)
                        height: implicitHeight
                        color: Appearance.colors.colLayer2
                        radius: Appearance.rounding.normal

                        // Left Checkbox Button
                        Rectangle {
                            id: checkContainer
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            radius: 16
                            color: checkMouseArea.containsMouse 
                                ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15) 
                                : "transparent"
                            scale: checkMouseArea.containsMouse ? 1.08 : 1.0

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                radius: 4
                                scale: checkMouseArea.pressed ? 0.88 : 1.0
                                color: todoItem.isVisualDone 
                                    ? Appearance.colors.colPrimary 
                                    : "transparent"
                                border.width: todoItem.isVisualDone ? 0 : 2
                                border.color: todoItem.isVisualDone 
                                    ? Appearance.colors.colPrimary 
                                    : (checkMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext)

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                                Behavior on border.color {
                                    ColorAnimation { duration: 150 }
                                }
                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: todoItem.isVisualDone
                                    text: "check"
                                    iconSize: 14
                                    fill: 1
                                    color: Appearance.colors.colOnPrimary
                                }
                            }

                            MouseArea {
                                id: checkMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (toggleDelayTimer.running || todoItem.isExiting) return;
                                    todoItem.isVisualDone = !todoItem.isVisualDone;
                                    toggleDelayTimer.targetId = todoItem.modelData.id || "";
                                    toggleDelayTimer.origIdx = todoItem.modelData.originalIndex !== undefined ? todoItem.modelData.originalIndex : todoItem.index;
                                    toggleDelayTimer.wasDone = todoItem.modelData.done;
                                    toggleDelayTimer.start();
                                }
                            }
                        }

                        // Right Delete Action
                        Rectangle {
                            id: deleteContainer
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 15
                            color: deleteMouseArea.containsMouse 
                                ? ColorUtils.applyAlpha(Appearance.colors.colError, 0.15) 
                                : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: 18
                                fill: 1
                                color: deleteMouseArea.containsMouse 
                                    ? Appearance.colors.colError 
                                    : Appearance.colors.colSubtext
                            }

                            MouseArea {
                                id: deleteMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (todoItem.isExiting) return;
                                    const idToDelete = todoItem.modelData.id || "";
                                    const idxToDelete = todoItem.modelData.originalIndex !== undefined ? todoItem.modelData.originalIndex : todoItem.index;
                                    todoItem.destroyWithAnimation(() => {
                                        if (idToDelete) {
                                            Todo.deleteItemById(idToDelete);
                                        } else {
                                            Todo.deleteItem(idxToDelete);
                                        }
                                    });
                                }
                            }
                        }

                        // Task Content Text
                        Text {
                            id: todoContentText
                            anchors.left: checkContainer.right
                            anchors.leftMargin: 12
                            anchors.right: deleteContainer.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: (todoItem.modelData && todoItem.modelData.content) ? todoItem.modelData.content : ""
                            wrapMode: Text.Wrap
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            font.strikeout: todoItem.isVisualDone
                            renderType: Text.QtRendering
                            color: todoItem.isVisualDone 
                                ? Appearance.colors.colSubtext 
                                : Appearance.colors.colOnLayer0

                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 64
                height: 64
                radius: 32
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 30
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                    text: emptyPlaceholderIcon
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
