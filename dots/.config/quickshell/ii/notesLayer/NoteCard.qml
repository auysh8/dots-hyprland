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

    implicitHeight: 210
    buttonRadius: Appearance.rounding.verylarge

    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer2

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
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
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
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignTop
                maximumLineCount: 5
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
