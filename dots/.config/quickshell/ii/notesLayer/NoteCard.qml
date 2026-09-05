import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * M3 Expressive note card for the grid view.
 *
 * Surface hierarchy:
 *   - Pinned cards: primaryContainer or tertiaryContainer tonal fill
 *     (alternating by index for visual variety)
 *   - Standard cards: surfaceContainerHigh with subtle border
 *
 * Shape: Extra-large rounded corners (28px) for organic M3 Expressive feel.
 * Typography: titleMedium for card titles, bodySmall for preview.
 * Pinned indicator: Soft pill badge with filled pin icon instead of accent bar.
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

    // Pinned cards alternate secondaryContainer / tertiaryContainer by index.
    // In dark mode, ensure tertiary container maintains a matching dark depth
    // so that the lighter text color has crisp contrast (> 4.5:1).
    readonly property bool usesSecondaryTone: root.cardIndex % 2 === 0
    readonly property color pinnedFill: {
        if (root.usesSecondaryTone) {
            return Appearance.colors.colSecondaryContainer;
        }
        const tert = Appearance.colors.colTertiaryContainer;
        if (Appearance.m3colors.darkmode && tert.hslLightness > 0.35) {
            return ColorUtils.colorWithLightness(tert, Appearance.colors.colSecondaryContainer.hslLightness);
        }
        return tert;
    }

    // Both odd and even cards use the same lighter text color
    readonly property color pinnedContentColor: Appearance.colors.colOnSecondaryContainer

    // Both odd and even cards use the same lighter action button background
    readonly property color actionContainerColor: root.notePinned
        ? Appearance.colors.colOnSecondaryContainer
        : Appearance.colors.colSurfaceContainerHighest
    readonly property color actionContainerHoverColor: root.notePinned
        ? ColorUtils.mix(Appearance.colors.colOnSecondaryContainer, Appearance.colors.colSecondaryContainer, 0.90)
        : Appearance.colors.colSurfaceContainerHighestHover

    // Both odd and even cards use the same icon color
    readonly property color actionIconColor: root.notePinned
        ? Appearance.colors.colSecondaryContainer
        : Appearance.colors.colOnSurface

    signal moreClicked()
    signal deleteRequested()
    signal heightReported(string noteId, real height)

    property real targetX: 0
    property real targetY: 0
    property real cardWidth: 200
    property bool animateMovement: true

    x: targetX
    y: targetY
    width: cardWidth

    Behavior on x {
        enabled: root.animateMovement && root.opacity > 0.05
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Behavior on y {
        enabled: root.animateMovement && root.opacity > 0.05
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    onImplicitHeightChanged: {
        if (implicitHeight > 50 && noteId.length > 0) {
            root.heightReported(noteId, implicitHeight);
        }
    }

    // Dynamic sizing: card height derives from content
    implicitHeight: cardLayout.implicitHeight + 48

    // M3 Expressive: extra-large rounded corners (28px)
    buttonRadius: 28

    // M3 Expressive surface hierarchy
    colBackground: root.notePinned
        ? root.pinnedFill
        : Appearance.colors.colSurfaceContainerHigh
    colBackgroundHover: root.notePinned
        ? (root.usesSecondaryTone
            ? Appearance.colors.colSecondaryContainerHover
            : ColorUtils.mix(root.pinnedFill, Appearance.colors.colOnSurface, 0.92))
        : Appearance.colors.colSurfaceContainerHighestHover
    colRipple: root.notePinned
        ? root.pinnedContentColor
        : Appearance.colors.colOnSurface

    // Right-click to delete
    altAction: function(event) {
        root.deleteRequested();
    }

    contentItem: Item {
        anchors.fill: parent

        ColumnLayout {
            id: cardLayout

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            anchors.rightMargin: 84
            spacing: 10

            // Title row with M3 titleMedium typography
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.noteTitle || "Untitled"
                    font.pixelSize: Appearance.font.pixelSize.large // ~17px ≈ titleMedium
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.title
                    color: root.notePinned ? root.pinnedContentColor : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }

            // Content preview — plain text, M3 bodySmall
            StyledText {
                Layout.fillWidth: true
                text: {
                    const content = root.noteContent || "";
                    const lines = content.split("\n").filter((l) => {
                        return l.trim().length > 0;
                    });
                    return lines.slice(0, 6).join("\n") || "Empty note...";
                }
                textFormat: Text.PlainText
                font.family: Appearance.font.family.reading
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Normal
                color: root.notePinned ? root.pinnedContentColor : Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignTop
                maximumLineCount: 6
                elide: Text.ElideRight
            }
        }

        // Top-Right Action Cluster: Circular icon button containers
        // Both buttons use 32px circular M3 tonal containers for clear touch targets
        // and visual contrast against the card surface.
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 6

            // Pin action button — circular tonal container with pin icon.
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                visible: true
                colBackground: root.actionContainerColor
                colBackgroundHover: root.actionContainerHoverColor
                colRipple: root.actionIconColor
                onClicked: NotesService.setPinned(root.noteId, !root.notePinned)

                StyledToolTip {
                    text: root.notePinned ? "Unpin note" : "Pin note"
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "push_pin"
                    iconSize: 16
                    fill: root.notePinned ? 1 : 0
                    color: root.actionIconColor
                }
            }

            // Overflow menu button — circular tonal container
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: root.actionContainerColor
                colBackgroundHover: root.actionContainerHoverColor
                colRipple: root.actionIconColor
                onClicked: root.moreClicked()

                StyledToolTip {
                    text: "More options"
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "more_vert"
                    iconSize: 18
                    color: root.actionIconColor
                }
            }
        }

    }
}
