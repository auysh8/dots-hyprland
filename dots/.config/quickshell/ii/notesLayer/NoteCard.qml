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
    property string noteColor: "default"
    property bool notePinned: false

    // Accent stripe + pin badge colors follow the card's accent hue
    // (fixed design hues, COLOR_RULES §9 exception). Default-colored notes
    // use the subtext tone so the pin badge stays visible.
    readonly property color accentColor: root.noteColor === "default"
        ? Appearance.colors.colSubtext
        : NotesService.noteColorFor(root.noteColor).color

    signal deleteRequested()

    // Google Keep-style dynamic sizing: the card height derives from its
    // content (title + preview), so short notes stay small and long notes grow.
    // The +40 accounts for the cardLayout's 20px top and bottom margins.
    implicitHeight: cardLayout.implicitHeight + 40
    buttonRadius: Appearance.rounding.verylarge

    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer2

    // Right-click to delete
    altAction: function(event) { root.deleteRequested() }

    contentItem: Item {
        anchors.fill: parent

        // Accent stripe on the left edge when the note has a color
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            width: 4
            radius: 2
            visible: root.noteColor !== "default"
            color: root.accentColor
        }

        ColumnLayout {
            id: cardLayout
            // Top/left/right anchored with margins; the height follows the
            // content so the card grows to fit. The right margin keeps the
            // title/preview clear of the delete button in the top-right corner.
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            anchors.leftMargin: root.noteColor !== "default" ? 26 : 20
            anchors.rightMargin: 40
            spacing: 10

            // Title row: pin badge + title
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // Pin badge — kept BEFORE the title in a fixed left position.
                // (Previously it sat after the fillWidth title, i.e. at the
                // title row's right end, which put it directly underneath the
                // delete button at the card's top-right corner, making the two
                // glyphs overlap on pinned notes.)
                MaterialSymbol {
                    visible: root.notePinned
                    text: "push_pin"
                    iconSize: 16
                    fill: 1
                    color: root.accentColor
                    Layout.alignment: Qt.AlignTop
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.noteTitle || "Untitled"
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }

            // Content preview — since the card grows with its content, show a
            // fuller preview (up to 6 lines) so card sizes vary like Keep's.
            StyledText {
                Layout.fillWidth: true
                text: {
                    const content = root.noteContent || ""
                    const lines = content.split("\n").filter(l => l.trim().length > 0)
                    return lines.slice(0, 6).join("\n") || "Empty note..."
                }
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignTop
                maximumLineCount: 6
            }


        }

        // Delete button
        RippleButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "delete"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }

            onClicked: root.deleteRequested()
        }
    }
}
