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
                    property bool isVisualDone: modelData.done
                    property bool isExiting: false
                    property real targetHeight: todoItemRectangle.implicitHeight
                    property real animatedHeight: targetHeight

                    width: taskColumn.width
                    implicitHeight: isExiting ? 0 : animatedHeight
                    height: implicitHeight
                    clip: true

                    Behavior on implicitHeight {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    Behavior on y {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    property bool isRecentlyAdded: (Date.now() - (modelData.createdAt || 0)) < 1500

                    Component.onCompleted: {
                        if (isRecentlyAdded && index === 0 && !modelData.done) {
                            animatedHeight = 0;
                            entryTimer.start();
                        }
                    }

                    Timer {
                        id: entryTimer
                        interval: 16
                        repeat: false
                        onTriggered: {
                            todoItem.animatedHeight = todoItem.targetHeight;
                            entryAnim.start();
                        }
                    }

                    function destroyWithAnimation(callback) {
                        isExiting = true;
                        exitTimer.callback = callback;
                        exitTimer.start();
                    }

                    Timer {
                        id: exitTimer
                        interval: 310
                        repeat: false
                        property var callback
                        onTriggered: {
                            if (callback) callback();
                        }
                    }

                    Timer {
                        id: toggleDelayTimer
                        interval: 250
                        repeat: false
                        onTriggered: {
                            todoItem.destroyWithAnimation(() => {
                                if (!todoItem.modelData.done)
                                    Todo.markDone(todoItem.modelData.originalIndex);
                                else
                                    Todo.markUnfinished(todoItem.modelData.originalIndex);
                            });
                        }
                    }

                    Rectangle {
                        id: todoItemRectangle
                        width: parent.width
                        implicitHeight: todoCardLayout.implicitHeight + 20
                        color: Appearance.colors.colLayer2
                        radius: Appearance.rounding.normal

                        opacity: todoItem.isExiting ? 0 : 1
                        scale: todoItem.isExiting ? 0.85 : 1

                        Behavior on opacity {
                            NumberAnimation { duration: 220; easing.type: Easing.OutQuad }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 220; easing.type: Easing.OutQuad }
                        }

                        ParallelAnimation {
                            id: entryAnim
                            NumberAnimation { target: todoItemRectangle; property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
                            NumberAnimation { target: todoItemRectangle; property: "scale"; from: 0.88; to: 1.0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                        }

                        RowLayout {
                            id: todoCardLayout
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 12

                            // Left Checkbox Button
                            Rectangle {
                                id: checkContainer
                                Layout.alignment: Qt.AlignVCenter
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
                                        if (toggleDelayTimer.running) return;
                                        todoItem.isVisualDone = !todoItem.isVisualDone;
                                        toggleDelayTimer.start();
                                    }
                                }
                            }

                            // Task Content Text
                            Text {
                                id: todoContentText
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: todoItem.modelData.content
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

                            // Right Delete Action
                            Rectangle {
                                id: deleteContainer
                                Layout.alignment: Qt.AlignVCenter
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
                                        todoItem.destroyWithAnimation(() => {
                                            Todo.deleteItem(todoItem.modelData.originalIndex);
                                        });
                                    }
                                }
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
