import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.shapes
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    property string formattedDate: Qt.locale().toString(DateTime.clock.date, "dddd, MMMM dd, yyyy")
    property string formattedTime: DateTime.time
    property string formattedUptime: DateTime.uptime
    readonly property int hour24: DateTime.hour24
    readonly property int pendingCount: Todo.list.filter(item => !item.done).length

    function timeOfDayIcon() {
        if (hour24 < 18)
            return "wb_sunny";
        return "bedtime";
    }

    function timeOfDayShape() {
        if (hour24 < 12)
            return MaterialShape.Shape.Sunny;
        if (hour24 < 18)
            return MaterialShape.Shape.Burst;
        return MaterialShape.Shape.Cookie4Sided;
    }

    function timeOfDayContainerColor() {
        if (hour24 < 12)
            return Appearance.colors.colPrimaryContainer;
        if (hour24 < 18)
            return Appearance.colors.colTertiaryContainer;
        return Appearance.colors.colSecondaryContainer;
    }

    function timeOfDayOnContainerColor() {
        if (hour24 < 12)
            return Appearance.colors.colOnPrimaryContainer;
        if (hour24 < 18)
            return Appearance.colors.colOnTertiaryContainer;
        return Appearance.colors.colOnSecondaryContainer;
    }

    function greeting() {
        if (hour24 < 12)
            return Translation.tr("Good Morning");
        if (hour24 < 18)
            return Translation.tr("Good Afternoon");
        return Translation.tr("Good Evening");
    }

    ColumnLayout {
        id: columnLayout

        anchors.centerIn: parent
        spacing: 10

        // ── Hero Header Card (colLayer2, elevated above the tasks card) ──────
        Rectangle {
            id: heroCard

            Layout.fillWidth: true
            implicitWidth: 280
            implicitHeight: heroLayout.implicitHeight + 14 * 2
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: heroLayout

                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Dynamic M3 Expressive badge: shape + tone morph organically with time of day
                    MaterialShapeWrappedMaterialSymbol {
                        id: timeOfDayBadge

                        implicitSize: 48
                        wrappedShape: root.timeOfDayShape()
                        text: root.timeOfDayIcon()
                        iconSize: 24
                        fill: 1
                        padding: 12
                        color: root.timeOfDayContainerColor()
                        colSymbol: root.timeOfDayOnContainerColor()
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: root.greeting()
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            text: root.formattedTime
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.Black
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.formattedDate
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                // Uptime chip (colLayer3, elevated above the hero card)
                Rectangle {
                    id: uptimeChip

                    Layout.alignment: Qt.AlignLeft
                    implicitWidth: uptimeRow.implicitWidth + 10 * 2
                    implicitHeight: uptimeRow.implicitHeight + 6 * 2
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer3

                    Row {
                        id: uptimeRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "timelapse"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.formattedUptime
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        // ── Tasks Card (colLayer1 card with colLayer2 interactive rows) ──────
        Rectangle {
            id: tasksCard

            Layout.fillWidth: true
            implicitHeight: tasksLayout.implicitHeight + 12 * 2
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: tasksLayout

                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialSymbol {
                        text: "checklist"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSecondary
                    }

                    StyledText {
                        text: Translation.tr("Upcoming Tasks")
                        font.weight: Font.Black
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurface
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Pending count chip (colPrimaryContainer with correct on-pairing)
                    Rectangle {
                        id: pendingChip

                    implicitWidth: pendingChipText.implicitWidth + 12 * 2
                    implicitHeight: pendingChipText.implicitHeight + 5 * 2
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        visible: root.pendingCount > 0

                        StyledText {
                            id: pendingChipText

                            anchors.centerIn: parent
                        text: `${root.pendingCount} ${Translation.tr("pending")}`
                        font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                StyledListView {
                    id: tasksListView

                    // Hug the content, capped at 140px so long lists still scroll
                    property real targetHeight: Math.min(contentHeight, 140)

                    Layout.fillWidth: true
                    Layout.preferredHeight: targetHeight
                    Behavior on targetHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    visible: root.pendingCount > 0
                    clip: true
                    spacing: 6
                    model: Todo.list
                        .map(function(item, i) {
                            return Object.assign({}, item, { originalIndex: i });
                        })
                        .filter(function(item) {
                            return !item.done;
                        })

                    delegate: RippleButton {
                        id: taskButton

                        required property int index
                        required property var modelData

                        width: tasksListView.width
                        implicitHeight: taskRow.implicitHeight + 10 * 2
                        buttonRadius: Appearance.rounding.small
                        // Interactive task card: colLayer2 resting, colLayer2Hover on hover
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.85)

                        onClicked: Todo.markDone(taskButton.modelData.originalIndex)

                        contentItem: RowLayout {
                            id: taskRow

                            anchors {
                                verticalCenter: parent.verticalCenter
                                left: parent.left
                                right: parent.right
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "radio_button_unchecked"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOutline
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: taskButton.modelData.content
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Empty state: everything is done
                Item {
                    id: emptyState

                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    visible: root.pendingCount === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "task_alt"
                            iconSize: 28
                            fill: 1
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("All caught up for today!")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
