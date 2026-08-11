import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string noteId: ""
    property string initialTitle: ""
    property string initialContent: ""
    property int initialModified: 0 // unix seconds; 0 = brand-new note
    property bool initialPinned: false
    property string initialColor: "default"
    property bool isSaving: NotesService.saving
    // Single source of truth: synced from the note via the initial* props
    // (handlers re-fire on note switch; manual toggles in the ⋮ menu override)
    property bool pinned: false
    property string activeColor: "default"
    // Relative "Edited X ago" label, refreshed every minute
    property string editedLabel: ""
    // ── Overflow menu ────────────────────────────────────────────────────────
    // Config-driven action list: easy to extend by pushing {label, icon, action}.
    // Items with id "pin" have a dynamic label handled in the delegate.
    // Delete opens a shared WindowDialog confirmation modal instead of
    // deleting inline (consistent with the shell's dialog conventions).
    property bool menuOpen: false
    property bool showDeleteDialog: false
    property point menuPosition: Qt.point(0, 0) // Position of the ⋮ button, in root coords
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
            // Menu closes first (delegate), then the modal confirm appears
            root.showDeleteDialog = true;
        }
    }, {
        "id": "duplicate",
        "label": "Duplicate note",
        "icon": "file_copy",
        "action": function() {
            // Duplicate what's currently on screen (including unsaved edits),
            // preserving pin state and accent color
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
        if (diff < 60)
            return "Edited just now";

        if (diff < 3600)
            return "Edited " + Math.floor(diff / 60) + "m ago";

        if (diff < 86400)
            return "Edited " + Math.floor(diff / 3600) + "h ago";

        if (diff < 604800)
            return "Edited " + Math.floor(diff / 86400) + "d ago";

        return "Edited " + NotesService.formatDate(root.initialModified);
    }

    // A pin action also needs to update the label of the ⋮ button itself
    function menuLabel(item) {
        if (item.id === "pin")
            return root.pinned ? "Unpin note" : "Pin note";

        return item.label;
    }

    // Measure the trigger button's position (in root coordinates) so the menu
    // can be placed directly beneath it. Mirrors ApplicationDrawer's approach.
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

    function insertMarkdown(prefix, suffix) {
        const start = contentInput.selectionStart;
        const end = contentInput.selectionEnd;
        const text = contentInput.text;
        if (start !== end) {
            const sel = text.substring(start, end);
            contentInput.remove(start, end);
            contentInput.insert(start, prefix + sel + suffix);
        } else {
            const pos = contentInput.cursorPosition;
            contentInput.insert(pos, prefix + suffix);
            contentInput.cursorPosition = pos + prefix.length;
        }
        contentInput.forceActiveFocus();
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

    // Clicking outside the menu closes it (WindowDialog dismissal pattern)
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
        spacing: 24

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Cancel
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.cancelClicked()

                StyledToolTip {
                    text: "Discard changes and return"
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer0
                }

            }

            Item {
                Layout.fillWidth: true
            }

            // More options (overflow menu)
            RippleButton {
                id: moreButton

                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: root.menuOpen ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: {
                    root.menuOpen = !root.menuOpen;
                    if (root.menuOpen)
                        root.updateMenuPosition();

                }

                StyledToolTip {
                    text: "More options"
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "more_vert"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer0
                }

            }

            // Save Note
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85)
                onClicked: root.saveClicked(titleInput.text, contentInput.text)

                StyledToolTip {
                    text: root.isSaving ? "Saving..." : "Save Note"
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.isSaving ? "sync" : "save"
                    iconSize: 24
                    fill: 1 // Filled (rounded) variant
                    color: Appearance.colors.colOnPrimary
                    // Spin the icon while a save is in flight
                    rotation: 0

                    RotationAnimator on rotation {
                        running: root.isSaving
                        from: 0
                        to: 360
                        duration: 800
                        loops: Animation.Infinite
                    }

                }

            }

        }

        // ── Editor ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Title — use StyledTextInput for consistent font/colors/selection
            StyledTextInput {
                id: titleInput

                Layout.fillWidth: true
                text: root.initialTitle
                font.pixelSize: Appearance.font.pixelSize.huge * 1.8
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
                selectByMouse: true
                clip: true
                onTextChanged: autoSaveTimer.restart()

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Untitled"
                    font: titleInput.font
                    color: Appearance.colors.colSubtext
                    opacity: 0.5
                    visible: !titleInput.text && !titleInput.activeFocus
                }

            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.4
            }

            // Content — RichText for visual bold/italic/underline formatting
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Keep the last line clear of the bottom-left "Edited" label
                Layout.bottomMargin: 48
                clip: true

                StyledTextArea {
                    id: contentInput

                    width: parent.width
                    text: root.initialContent
                    wrapMode: TextEdit.WrapAnywhere
                    placeholderText: "Start typing your thoughts here..."
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.MarkdownText
                    background: null
                    padding: 0
                    font.family: Appearance.font.family.reading
                    font.pixelSize: Appearance.font.pixelSize.large
                    onTextChanged: autoSaveTimer.restart()
                }

                ScrollBar.vertical: StyledScrollBar {
                }

            }

        }

    }

    // ── Overflow menu popup ──────────────────────────────────────────────────
    // Positioned via measured coordinates (ApplicationDrawer pattern): placed
    // just below the ⋮ button, right-aligned to it, clamped to stay on-screen.            // Visuals + reveal animation match the shell's context menus (DockContextMenu):
    // fade + scale + slide with elementMoveFast easing, shadow fading in with it.
    // Surface color follows the notes design directive (refine_floating_surface):
    // elevated floater -> colLayer3Base with a subtle outline border for contrast.
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
            color: Appearance.colors.colLayer3Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
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

                    // Shared MenuButton (extended with optional iconText)
                    MenuButton {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 44 // Standard MD3 menu item height
                        buttonRadius: Appearance.rounding.small
                        iconText: modelData.icon
                        buttonText: root.menuLabel(modelData)
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: {
                            root.menuOpen = false;
                            modelData.action();
                        }
                    }

                }

                // ── Note color section ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    Layout.topMargin: 6
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.3
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: "Color"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8

                    Repeater {
                        model: NotesService.noteColors

                        delegate: RippleButton {
                            required property var modelData

                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.full
                            colBackground: modelData.color
                            colBackgroundHover: modelData.color
                            colRipple: ColorUtils.transparentize(modelData.color, 0.5)
                            onClicked: {
                                root.activeColor = modelData.id;
                                NotesService.setNoteColor(root.noteId, modelData.id);
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 14
                                fill: 1
                                // Contrast-aware check: light check on dark swatches (e.g. "default"),
                                // dark check on the pastel accent swatches
                                color: root.activeColor === modelData.id ? (ColorUtils.isDark(modelData.color) ? Qt.lighter(modelData.color, 2.5) : Qt.darker(modelData.color, 3)) : "transparent"
                            }

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
    // Reuses the shell's shared WindowDialog component (same as the WiFi / BT /
    // NightLight dialogs): title + warning message + Cancel / destructive Delete.
    WindowDialog {
        id: deleteConfirmDialog

        anchors.fill: parent
        z: 20 // Above the menu overlay (11) and its scrim (10)
        show: root.showDeleteDialog
        animationsEnabled: true
        // Explicit deterministic size (like the sidebar dialogs): centering
        // never depends on content-layout timing, and text wraps instead of
        // overflowing at the window edges.
        backgroundWidth: 360
        backgroundHeight: 240
        // NOTE: never add `onShowChanged` at this level — an instance-level
        // handler shadows the component's internal show logic (opacity,
        // frozenHeight, open/close timers) and breaks the morph + sizing,
        // clipping the dialog. Focus is handled via Connections instead.
        onDismiss: root.showDeleteDialog = false

        Connections {
            // QML property-change signals don't carry the new value as an
            // argument, so read the property directly here.
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

            // Destructive action — styled per COLOR_RULES §5 (colError family)
            DialogButton {
                buttonText: Translation.tr("Delete")
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colText: Appearance.colors.colOnError
                onClicked: {
                    root.showDeleteDialog = false;
                    // NotesPanel's onNotesChanged detects the missing note and
                    // automatically returns to the grid view.
                    NotesService.deleteNote(root.noteId);
                }
            }

        }

    }

    // ── Markdown Formatting Toolbar & Footer Stats ─────────────────────────
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.rightMargin: 36
        anchors.bottomMargin: 28
        spacing: 16

        // Timestamp & Word Count
        RowLayout {
            spacing: 8

            StyledText {
                text: root.editedLabel
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                opacity: 0.7
            }

            StyledText {
                text: "•"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                opacity: 0.4
                visible: root.editedLabel.length > 0
            }

            StyledText {
                text: root.formatStats()
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                opacity: 0.7
            }
        }

        Item { Layout.fillWidth: true }

        // Floating Markdown Toolbar Pill
        Rectangle {
            implicitHeight: 36
            implicitWidth: markdownRow.implicitWidth + 16
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            RowLayout {
                id: markdownRow
                anchors.centerIn: parent
                spacing: 4

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: root.insertMarkdown("**", "**")
                    StyledToolTip { text: "Bold (**text**)" }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "format_bold"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: root.insertMarkdown("*", "*")
                    StyledToolTip { text: "Italic (*text*)" }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "format_italic"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: root.insertMarkdown("\n- ", "")
                    StyledToolTip { text: "Bullet list (- item)" }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "format_list_bulleted"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: root.insertMarkdown("\n- [ ] ", "")
                    StyledToolTip { text: "Todo checkbox (- [ ] task)" }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check_box"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: root.insertMarkdown("`", "`")
                    StyledToolTip { text: "Code (`code`)" }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "code"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }

}
