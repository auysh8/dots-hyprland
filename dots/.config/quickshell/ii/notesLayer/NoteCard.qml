import qs.modules.common
import qs.modules.common.widgets
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A sidebar note card showing title, preview, and date.
 * Selected state uses primaryContainer colors with a left accent border.
 */
RippleButton {
    id: root

    property string noteId: ""
    property string noteTitle: ""
    property string noteContent: ""
    property int noteModified: 0
    property bool isSelected: false

    signal deleteRequested()

    implicitHeight: cardContent.implicitHeight + 24
    buttonRadius: Appearance.rounding.small

    // Colors based on selection state
    colBackground: isSelected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: isSelected ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: isSelected ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer1Active

    // Right-click to delete
    altAction: function(event) {
        root.deleteRequested()
    }

    contentItem: Item {
        anchors.fill: parent

        // Left accent border when selected
        Rectangle {
            id: accentBorder
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            width: root.isSelected ? 3 : 0
            radius: 2
            color: Appearance.colors.colPrimary
            opacity: root.isSelected ? 1 : 0

            Behavior on width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutQuad
                }
            }
        }

        ColumnLayout {
            id: cardContent
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.isSelected ? 16 : 12
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Behavior on anchors.leftMargin {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            // Title
            StyledText {
                Layout.fillWidth: true
                text: root.noteTitle || "Untitled"
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: root.isSelected ?
                    Appearance.colors.colOnPrimaryContainer :
                    Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Content preview
            StyledText {
                Layout.fillWidth: true
                text: {
                    const content = root.noteContent || ""
                    // Show first 2 non-empty lines as preview
                    const lines = content.split("\n").filter(l => l.trim().length > 0)
                    return lines.slice(0, 2).join(" · ") || "Empty note"
                }
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.isSelected ?
                    Qt.rgba(Appearance.colors.colOnPrimaryContainer.r,
                            Appearance.colors.colOnPrimaryContainer.g,
                            Appearance.colors.colOnPrimaryContainer.b, 0.7) :
                    Appearance.colors.colSubtext
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }

            // Date
            StyledText {
                text: root.noteModified > 0 ? NotesService.formatDate(root.noteModified) : ""
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.isSelected ?
                    Qt.rgba(Appearance.colors.colOnPrimaryContainer.r,
                            Appearance.colors.colOnPrimaryContainer.g,
                            Appearance.colors.colOnPrimaryContainer.b, 0.5) :
                    Qt.rgba(Appearance.colors.colSubtext.r,
                            Appearance.colors.colSubtext.g,
                            Appearance.colors.colSubtext.b, 0.7)
            }
        }
    }
}
