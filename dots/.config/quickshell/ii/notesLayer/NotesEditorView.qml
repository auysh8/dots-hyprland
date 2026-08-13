import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * M3 Expressive Notes Editor View.
 *
 * Surface: Inherits deep tonal background from parent window.
 * Typography: Display scale (32px DemiBold) for title input, bodyLarge for content.
 * Header actions: Secondary container for Back/Options, Primary container for Save.
 * Footer metadata: Tonal pill chips with subtle leading icons.
 */
Item {
    id: root

    property string noteId: ""
    property string initialTitle: ""
    property string initialContent: ""
    property int initialModified: 0
    property bool initialPinned: false
    property string initialColor: "default"
    property bool isSaving: NotesService.saving
    property bool pinned: false
    property string activeColor: "default"
    property string editedLabel: ""

    // ── Overflow menu ────────────────────────────────────────────────────────
    property bool menuOpen: false
    property bool showDeleteDialog: false
    property point menuPosition: Qt.point(0, 0)
    property var menuItems: [{
        "id": "pin",
        "label": "Pin note",
        "icon": "push_pin",
        "action": function() {
            root.pinned = !root.pinned;
            NotesService.setPinned(root.noteId, root.pinned);
        }
    }, {
        "id": "delete",
        "label": "Delete note",
        "icon": "delete",
        "action": function() {
            root.showDeleteDialog = true;
        }
    }, {
        "id": "duplicate",
        "label": "Duplicate note",
        "icon": "file_copy",
        "action": function() {
            const newId = NotesService.createNote(titleInput.text, contentInput.text, root.pinned);
            NotesService.setNoteColor(newId, root.activeColor);
        }
    }, {
        "id": "copy",
        "label": "Copy to clipboard",
        "icon": "content_copy",
        "action": function() {
            Quickshell.clipboardText = contentInput.text;
        }
    }]

    signal cancelClicked()
    signal saveClicked(string title, string content)

    function formatEdited() {
        if (root.initialModified <= 0)
            return "";
        const diff = Math.max(0, Math.floor(Date.now() / 1000) - root.initialModified);
        if (diff < 60) return "Edited just now";
        if (diff < 3600) return "Edited " + Math.floor(diff / 60) + "m ago";
        if (diff < 86400) return "Edited " + Math.floor(diff / 3600) + "h ago";
        if (diff < 604800) return "Edited " + Math.floor(diff / 86400) + "d ago";
        return "Edited " + NotesService.formatDate(root.initialModified);
    }

    function menuLabel(item) {
        if (item.id === "pin")
            return root.pinned ? "Unpin note" : "Pin note";
        return item.label;
    }

    function updateMenuPosition() {
        const pos = moreButton.mapToItem(root, 0, 0);
        root.menuPosition = Qt.point(pos.x, pos.y);
    }

    function formatStats() {
        const text = ((titleInput ? titleInput.text : "") + " " + (contentInput ? contentInput.text : "")).trim();
        if (!text) return "0 words • 0 chars";
        const words = text.split(/\s+/).filter(w => w.length > 0).length;
        const chars = text.length;
        return words + (words === 1 ? " word" : " words") + " • " + chars + " chars";
    }

    onNoteIdChanged: {
        titleInput.text = root.initialTitle;
        contentInput.text = root.initialContent;
        root.pinned = root.initialPinned;
        root.activeColor = root.initialColor;
        root.editedLabel = root.formatEdited();
    }

    onInitialPinnedChanged: root.pinned = root.initialPinned
    onInitialColorChanged: root.activeColor = root.initialColor
    onInitialTitleChanged: titleInput.text = initialTitle
    onInitialContentChanged: contentInput.text = initialContent
    onInitialModifiedChanged: editedLabel = formatEdited()

    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
            root.saveClicked(titleInput.text, contentInput.text);
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.saveClicked(titleInput.text, contentInput.text);
            root.cancelClicked();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (root.menuOpen) {
                root.menuOpen = false;
            } else if (root.showDeleteDialog) {
                root.showDeleteDialog = false;
            } else {
                root.cancelClicked();
            }
            event.accepted = true;
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.noteId.length > 0) {
                NotesService.updateNote(root.noteId, titleInput.text, contentInput.text);
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.initialModified > 0
        onTriggered: editedLabel = root.formatEdited()
    }

    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        z: 10
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.menuOpen = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Header (M3 Expressive: primary save action, subtle secondary buttons) ─────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Back button — subtle tonal container
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                onClicked: root.cancelClicked()

                StyledToolTip { text: "Discard changes and return" }

                contentItem: MaterialSymbol {
                    anchors.fill: parent
                    text: "arrow_back"
                    iconSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnSurface
                }
            }

            Item { Layout.fillWidth: true }

            // More options — subtle tonal container
            RippleButton {
                id: moreButton
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                onClicked: {
                    root.menuOpen = !root.menuOpen;
                    if (root.menuOpen) root.updateMenuPosition();
                }

                StyledToolTip { text: "More options" }

                contentItem: MaterialSymbol {
                    anchors.fill: parent
                    text: "more_vert"
                    iconSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnSurface
                }
            }

            // Save button — prominent primary action with accent container
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colOnPrimaryContainer
                onClicked: root.saveClicked(titleInput.text, contentInput.text)

                StyledToolTip { text: root.isSaving ? "Saving..." : "Save Note" }

                contentItem: MaterialSymbol {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.isSaving ? "sync" : "save"
                    iconSize: 22
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        // ── Editor ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // Title — M3 Expressive display scale typography
            StyledTextInput {
                id: titleInput
                Layout.fillWidth: true
                text: root.initialTitle
                font.pixelSize: 32
                font.family: Appearance.font.family.title
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                selectByMouse: true
                clip: true
                onTextChanged: autoSaveTimer.restart()

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Untitled"
                    font: titleInput.font
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.5
                    visible: !titleInput.text && !titleInput.activeFocus
                }
            }

            // Content — M3 bodyLarge plain text
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 64
                clip: true

                StyledTextArea {
                    id: contentInput
                    width: parent.width
                    text: root.initialContent
                    wrapMode: TextEdit.WrapAnywhere
                    placeholderText: "Start typing your thoughts here..."
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.PlainText
                    background: null
                    padding: 0
                    font.family: Appearance.font.family.reading
                    font.pixelSize: Appearance.font.pixelSize.large // ~17px ≈ bodyLarge
                    color: Appearance.colors.colOnSurface
                    onTextChanged: autoSaveTimer.restart()
                }

                ScrollBar.vertical: StyledScrollBar {}
            }
        }
    }

    // ── Overflow menu popup ──────────────────────────────────────────────────
    Item {
        id: overflowMenuOverlay
        visible: root.menuOpen || overflowMenu.opacity > 0
        z: 11
        anchors.fill: parent

        Rectangle {
            id: overflowMenu
            property real revealProgress: root.menuOpen ? 1 : 0

            x: Math.max(8, Math.min(root.menuPosition.x + moreButton.width - width, parent.width - width - 8))
            y: Math.max(8, Math.min(root.menuPosition.y + moreButton.height + 8 + (1 - overflowMenu.revealProgress) * 10, parent.height - height - 8))
            width: 200
            implicitHeight: overflowMenuColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            // Use the opaque M3 source token: derived surface colors may
            // inherit the shell's content-transparency setting.
            color: Appearance.m3colors.m3surfaceContainerHighest
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            opacity: overflowMenu.revealProgress
            scale: 0.96 + overflowMenu.revealProgress * 0.04
            transformOrigin: Item.TopRight
            visible: opacity > 0

            StyledRectangularShadow {
                target: overflowMenu
                opacity: overflowMenu.revealProgress
                visible: opacity > 0
            }

            ColumnLayout {
                id: overflowMenuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: root.menuItems

                    MenuButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 44
                        buttonRadius: Appearance.rounding.small
                        iconText: modelData.icon
                        buttonText: root.menuLabel(modelData)
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                        onClicked: {
                            root.menuOpen = false;
                            modelData.action();
                        }
                    }
                }

            }

            Behavior on revealProgress {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }

    // ── Delete confirmation modal ─────────────────────────────────────────────
    WindowDialog {
        id: deleteConfirmDialog
        anchors.fill: parent
        z: 20
        show: root.showDeleteDialog
        animationsEnabled: true
        backgroundWidth: 360
        backgroundHeight: 240
        onDismiss: root.showDeleteDialog = false

        Connections {
            function onShowChanged() {
                if (deleteConfirmDialog.show)
                    deleteConfirmDialog.forceActiveFocus();
            }
            target: deleteConfirmDialog
        }

        WindowDialogTitle {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Delete note?")
        }

        WindowDialogParagraph {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("This will permanently delete this note. This action cannot be undone.")
        }

        WindowDialogButtonRow {
            Layout.alignment: Qt.AlignRight

            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: root.showDeleteDialog = false
            }

            DialogButton {
                buttonText: Translation.tr("Delete")
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colText: Appearance.colors.colOnError
                onClicked: {
                    root.showDeleteDialog = false;
                    NotesService.deleteNote(root.noteId);
                }
            }
        }
    }

    // ── Footer Stats (M3 tonal pill chips) ───────────────────────────────────
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.rightMargin: 36
        anchors.bottomMargin: 16
        spacing: 12

        // Timestamp chip
        Rectangle {
            implicitHeight: 28
            implicitWidth: timestampRow.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHigh
            visible: root.editedLabel.length > 0

            Row {
                id: timestampRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "schedule"
                    iconSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.7
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.editedLabel
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.8
                }
            }
        }

        // Word/character count chip
        Rectangle {
            implicitHeight: 28
            implicitWidth: statsRow.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHigh

            Row {
                id: statsRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "short_text"
                    iconSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.7
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatStats()
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.8
                }
            }
        }
    }
}
