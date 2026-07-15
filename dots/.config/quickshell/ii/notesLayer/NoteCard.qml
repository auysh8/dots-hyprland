import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A note card for the grid view.
 * Uses themed card colors with luminance-aware foreground.
 * Card accent colors are a documented visual exception (COLOR_RULES §9) —
 * they are fixed design accent hues that remain independent of wallpaper theming.
 */
RippleButton {
    id: root

    property string noteId: ""
    property string noteTitle: ""
    property string noteContent: ""
    property int noteModified: 0
    property int cardIndex: 0

    signal deleteRequested()

    // Documented exception per COLOR_RULES §9: fixed accent palette for visual variety.
    // These are design-intent hues, not theme-derived colors.
    readonly property var cardBgColors: [
        "#674FA3", // Deep violet
        "#825C65", // Mauve
        "#9CEBE1", // Mint
        "#C9B3FF", // Lavender
        "#E8E6EE"  // Pale grey-purple
    ]

    property color bgColor: cardBgColors[cardIndex % cardBgColors.length]

    // Luminance-aware foreground: dark text on light cards, white on dark cards
    property color fgColor: bgColor.hslLightness > 0.55
        ? Appearance.colors.colLayer0Base          // dark text for light cards
        : Qt.rgba(1, 1, 1, 1)                      // white for dark cards

    property color fgSubcolor: ColorUtils.transparentize(fgColor, 0.3)

    // Tag chip background — semi-transparent white overlay
    property color tagBg: bgColor.hslLightness > 0.55
        ? ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.55)
        : Qt.rgba(1, 1, 1, 0.18)

    implicitHeight: 210
    buttonRadius: Appearance.rounding.verylarge

    colBackground: bgColor
    colBackgroundHover: Qt.lighter(bgColor, 1.06)
    colRipple: ColorUtils.transparentize(fgColor, 0.7)

    // Right-click to delete
    altAction: function(event) { root.deleteRequested() }

    contentItem: Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 10

            // Title
            StyledText {
                Layout.fillWidth: true
                text: root.noteTitle || "Untitled"
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.title
                color: root.fgColor
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            // Content preview
            StyledText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: {
                    const content = root.noteContent || ""
                    const lines = content.split("\n").filter(l => l.trim().length > 0)
                    return lines.slice(0, 4).join("\n") || "Empty note..."
                }
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.fgSubcolor
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignTop
                maximumLineCount: 5
            }

            // Tag chips row — placeholder tags based on index
            // In a future update these can be driven by actual note metadata
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                clip: true

                Repeater {
                    model: {
                        const tagSets = [
                            ["Work", "High Priority"],
                            ["Personal"],
                            ["Ideas"],
                            ["Journal"],
                            ["Reading"]
                        ]
                        return tagSets[root.cardIndex % tagSets.length]
                    }

                    Rectangle {
                        implicitHeight: 26
                        implicitWidth: tagLabel.implicitWidth + 20
                        radius: Appearance.rounding.full
                        color: root.tagBg

                        StyledText {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: root.fgColor
                        }
                    }
                }
            }
        }
    }
}
