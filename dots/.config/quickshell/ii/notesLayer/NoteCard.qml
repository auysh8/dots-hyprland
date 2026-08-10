import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * A note card for the grid view (MD3 note card).
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
    // Accent stripe color follows the card's accent hue (fixed design hues,
    // COLOR_RULES §9 exception). Default-colored notes use the subtext tone so
    // the accent stays subtle.
    readonly property color accentColor: root.noteColor === "default" ? Appearance.colors.colSubtext : NotesService.noteColorFor(root.noteColor).color

    signal moreClicked()
    signal deleteRequested()
    signal heightReported(string noteId, real height)

    property real targetX: 0
    property real targetY: 0
    property bool isInitialized: false

    x: root.targetX
    y: root.targetY

    Behavior on x {
        enabled: root.isInitialized
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Behavior on y {
        enabled: root.isInitialized
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    onImplicitHeightChanged: {
        if (implicitHeight > 60 && cardLayout.implicitHeight > 0 && noteId.length > 0) {
            heightReported(noteId, implicitHeight);
        }
    }

    Component.onCompleted: initTimer.start()

    Timer {
        id: initTimer
        interval: 50
        repeat: false
        onTriggered: root.isInitialized = true
    }

    // Google Keep-style dynamic sizing: the card height derives from its
    // content (title + preview), so short notes stay small and long notes grow.
    // The +48 accounts for the cardLayout's 24px top and bottom margins.
    implicitHeight: cardLayout.implicitHeight + 48
    buttonRadius: Appearance.rounding.large // MD3 card shape: large shape scale
    colBackground: root.notePinned ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    colBackgroundHover: root.notePinned ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1Hover
    colRipple: root.notePinned ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

    // Right-click to delete (fast path alongside the more_vert menu)
    altAction: function(event) {
        root.deleteRequested();
    }

    contentItem: Item {
        anchors.fill: parent

        // Accent stripe on the left edge when the note has a color.
        // Pinned notes replace the stripe with the elevated container + pin
        // icon (per the notes design directive: replace_left_accent_bar), so
        // the stripe is suppressed for them.
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
            // title/preview clear of the more_vert button in the top-right corner.
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 24
            anchors.leftMargin: root.noteColor !== "default" ? 30 : 24
            anchors.rightMargin: root.notePinned ? 80 : 44
            spacing: 10

            // Title row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.noteTitle || "Untitled"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }

            }

            // Content preview — rendered as clean plain text so body text is never bolded.
            Text {
                Layout.fillWidth: true
                text: {
                    const content = root.noteContent || "";
                    // Strip markdown formatting headers (#), bold (**), and code blocks for clean preview
                    const cleanText = content
                        .replace(/^#+\s+/gm, "")
                        .replace(/\*\*(.*?)\*\*/g, "$1")
                        .replace(/__(.*?)__/g, "$1")
                        .replace(/`(.*?)`/g, "$1");
                    const lines = cleanText.split("\n").filter((l) => {
                        return l.trim().length > 0;
                    });
                    return lines.slice(0, 6).join("\n") || "Empty note...";
                }
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                font.family: Appearance.font.family.reading
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Normal
                color: Appearance.colors.colSubtext // on-surface-variant (secondary muted text)
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignTop
                maximumLineCount: 6
                elide: Text.ElideRight
            }

        }

        // Top-Right Header Action Cluster (Pushpin Icon + 3-Dot Menu)
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            spacing: 4

            // Pushpin badge aligned directly next to 3-dot menu
            Item {
                width: 32
                height: 32
                visible: root.notePinned
                anchors.verticalCenter: parent.verticalCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "push_pin"
                    iconSize: 18
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
            }

            // Overflow menu button (MD3 note card action: more_vert)
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
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
                    color: Appearance.colors.colSubtext
                }
            }
        }

    }

}
