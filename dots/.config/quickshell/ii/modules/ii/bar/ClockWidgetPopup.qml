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
    property var unfinishedTodos: Todo.list ? Todo.list.filter(item => !item.done) : []

    popupBackgroundMargin: 4

    Rectangle {
        id: container
        implicitWidth: 320
        implicitHeight: mainLayout.implicitHeight + 36

        color: Appearance.colors.colLayer0
        radius: 30
        border.width: 1
        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.75)

        ColumnLayout {
            id: mainLayout
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 18
            }
            spacing: 16

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

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
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Black
                        color: Appearance.m3colors.m3primary
                    }

                    StyledText {
                        text: root.formattedDate
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    width: 42
                    height: 42
                    radius: 21
                    color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.88)
                    border.width: 1
                    border.color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.7)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "schedule"
                        iconSize: 22
                        color: Appearance.m3colors.m3primary
                    }
                }
            }

            // System Uptime Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 24
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.85)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        color: ColorUtils.transparentize(Appearance.m3colors.m3secondary, 0.85)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "timelapse"
                            iconSize: 18
                            color: Appearance.m3colors.m3secondary
                        }
                    }

                    StyledText {
                        text: Translation.tr("System uptime")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: root.formattedUptime
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.m3colors.m3primary
                    }
                }
            }

            // Upcoming Tasks Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "checklist"
                        iconSize: 20
                        color: Appearance.m3colors.m3secondary
                    }

                    StyledText {
                        text: Translation.tr("Upcoming Tasks")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.unfinishedTodos.length > 0
                        implicitWidth: taskCountText.implicitWidth + 12
                        implicitHeight: 20
                        radius: 10
                        color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.85)

                        StyledText {
                            id: taskCountText
                            anchors.centerIn: parent
                            text: root.unfinishedTodos.length.toString()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.m3colors.m3primary
                        }
                    }
                }

                // Task List / Cards
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: root.unfinishedTodos.slice(0, 4)

                        delegate: Rectangle {
                            id: taskCard
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: 46
                            radius: 18
                            color: mouseArea.containsMouse ? ColorUtils.mix(Appearance.colors.colLayer1, Appearance.m3colors.m3primary, 0.92) : Appearance.colors.colLayer1
                            border.width: 1
                            border.color: mouseArea.containsMouse ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.6) : ColorUtils.transparentize(Appearance.colors.colOutline, 0.85)

                            scale: mouseArea.pressed ? 0.97 : (mouseArea.containsMouse ? 1.01 : 1.0)

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.2
                                }
                            }

                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                // Number badge ("01", "02")
                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.85)

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: (index + 1 < 10 ? "0" : "") + (index + 1)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Black
                                        color: Appearance.m3colors.m3primary
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.content
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    // Empty State Card
                    Rectangle {
                        visible: root.unfinishedTodos.length === 0
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 18
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.85)

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: "check_circle"
                                iconSize: 20
                                color: Appearance.m3colors.m3primary
                                opacity: 0.7
                            }

                            StyledText {
                                text: Translation.tr("No pending tasks")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // More tasks label
                    StyledText {
                        visible: root.unfinishedTodos.length > 4
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        text: Translation.tr("... and %1 more").arg(root.unfinishedTodos.length - 4)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }
}
