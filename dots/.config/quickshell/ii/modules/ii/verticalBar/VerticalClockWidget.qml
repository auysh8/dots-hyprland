import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    implicitHeight: clockPill.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    readonly property string dateTimeString: DateTime.time

    MaterialPill { // Stacked hr/min pill — compact, no date
        id: clockPill
        anchors.centerIn: parent
        vertical: true
        bgColor: Appearance.colors.colTertiaryContainer
        // Match right sidebar button pill: iconSize(19) + 6*2 padding ≈ 31px
        crossAxisSize: Appearance.font.pixelSize.larger + 12
        mainAxisPadding: 8
        contentSpacing: 0
        contentTopMargin: 0

        Column {
            id: timeColumn
            Layout.alignment: Qt.AlignHCenter
            // Fixed width = pill interior so numbers always center properly
            width: clockPill.crossAxisSize - 8
            spacing: -2

            Repeater {
                model: root.dateTimeString.split(/[: ]/).filter(s => !s.match(/am|pm/i))
                delegate: StyledText {
                    required property string modelData
                    width: timeColumn.width
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnTertiaryContainer
                    text: modelData.padStart(2, "0")
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        Bar.ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
