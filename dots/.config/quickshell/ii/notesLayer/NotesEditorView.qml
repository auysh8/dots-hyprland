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
    property bool renderMarkdown: false

    // Track active selection so clicking a toolbar button doesn't lose the range
    property int lastSelectionStart: 0
    property int lastSelectionEnd: 0

    function wrapSelection(prefix, suffix, allowToggle) {
        if (allowToggle === undefined) allowToggle = true;
        if (!suffix) suffix = prefix;
        // If in preview mode, switch back to edit mode first
        if (root.renderMarkdown) {
            root.renderMarkdown = false;
        }

        let start = contentInput.selectionStart;
        let end = contentInput.selectionEnd;

        if (start === end && root.lastSelectionStart !== root.lastSelectionEnd) {
            start = root.lastSelectionStart;
            end = root.lastSelectionEnd;
        }

        const text = contentInput.text;

        if (start === end) {
            const newText = text.substring(0, start) + prefix + suffix + text.substring(end);
            contentInput.text = newText;
            contentInput.cursorPosition = start + prefix.length;
        } else {
            let minPos = Math.min(start, end);
            let maxPos = Math.max(start, end);

            // Trim leading/trailing whitespace and newlines from the selection range
            while (minPos < maxPos && (text[minPos] === '\n' || text[minPos] === '\r' || text[minPos] === ' ' || text[minPos] === '\t')) {
                minPos++;
            }
            while (maxPos > minPos && (text[maxPos - 1] === '\n' || text[maxPos - 1] === '\r' || text[maxPos - 1] === ' ' || text[maxPos - 1] === '\t')) {
                maxPos--;
            }

            if (minPos === maxPos) {
                const newText = text.substring(0, start) + prefix + suffix + text.substring(end);
                contentInput.text = newText;
                contentInput.cursorPosition = start + prefix.length;
            } else {
                const selected = text.substring(minPos, maxPos);
                // Smart code block: if prefix is backtick and selection spans multiple lines, wrap with fenced code block
                let effectivePrefix = prefix;
                let effectiveSuffix = suffix;
                if (prefix === "`" && suffix === "`" && selected.includes("\n")) {
                    effectivePrefix = "```\n";
                    effectiveSuffix = "\n```";
                }

                // Check if already wrapped by prefix/suffix, toggle it off if allowToggle is true
                if (allowToggle && minPos >= effectivePrefix.length && maxPos + effectiveSuffix.length <= text.length &&
                    text.substring(minPos - effectivePrefix.length, minPos) === effectivePrefix &&
                    text.substring(maxPos, maxPos + effectiveSuffix.length) === effectiveSuffix) {
                    const newText = text.substring(0, minPos - effectivePrefix.length) + selected + text.substring(maxPos + effectiveSuffix.length);
                    contentInput.text = newText;
                    contentInput.select(minPos - effectivePrefix.length, maxPos - effectivePrefix.length);
                } else {
                    const newText = text.substring(0, minPos) + effectivePrefix + selected + effectiveSuffix + text.substring(maxPos);
                    contentInput.text = newText;
                    contentInput.select(minPos + effectivePrefix.length, maxPos + effectivePrefix.length);
                }
            }
        }
        contentInput.forceActiveFocus();
    }

    function toggleLinePrefix(prefix) {
        if (root.renderMarkdown) {
            root.renderMarkdown = false;
        }
        let start = contentInput.selectionStart;
        let end = contentInput.selectionEnd;
        if (start === end && root.lastSelectionStart !== root.lastSelectionEnd) {
            start = root.lastSelectionStart;
            end = root.lastSelectionEnd;
        }
        const text = contentInput.text;
        const minPos = Math.min(start, end);
        const maxPos = Math.max(start, end);

        const firstLineStart = text.lastIndexOf('\n', minPos - 1) + 1;
        let lastLineEnd = text.indexOf('\n', maxPos);
        if (lastLineEnd === -1) lastLineEnd = text.length;

        const targetBlock = text.substring(firstLineStart, lastLineEnd);
        const lines = targetBlock.split('\n');

        const allHavePrefix = lines.every(line => line.trim().length === 0 || line.startsWith(prefix));

        const modifiedLines = lines.map(line => {
            if (line.trim().length === 0) return line;
            if (allHavePrefix) {
                return line.startsWith(prefix) ? line.substring(prefix.length) : line;
            } else {
                if (prefix === "- [ ] " && line.match(/^-\s(?!\[)/)) {
                    return line.replace(/^-\s/, "- [ ] ");
                } else if (prefix === "- " && line.match(/^-\s\[[ xX]\]\s/)) {
                    return line.replace(/^-\s\[[ xX]\]\s/, "- ");
                } else if (!line.startsWith(prefix)) {
                    return prefix + line;
                }
                return line;
            }
        });

        const newBlock = modifiedLines.join('\n');
        contentInput.text = text.substring(0, firstLineStart) + newBlock + text.substring(lastLineEnd);
        contentInput.select(firstLineStart, firstLineStart + newBlock.length);
        contentInput.forceActiveFocus();
    }

    function exportNoteToFile() {
        const title = (titleInput.text || "Untitled").trim();
        const sanitized = title.replace(/[^a-zA-Z0-9_\-\u00C0-\u024F\u1E00-\u1EFF ]/g, "").trim().replace(/\s+/g, "_") || "note";
        const notesDir = FileUtils.trimFileProtocol(`${Directories.documents}/Notes`);
        const targetPath = `${notesDir}/${sanitized}.md`;
        const payload = `# ${title}\n\n${contentInput.text}`;
        Quickshell.execDetached(["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(notesDir)}' && printf '%s' '${StringUtils.shellSingleQuoteEscape(payload)}' > '${StringUtils.shellSingleQuoteEscape(targetPath)}' && notify-send 'Note Exported' 'Saved to ${targetPath}' -i text-x-generic`]);
    }

    function formatMarkdownForPreview(raw) {
        if (!raw) return "";
        const parts = raw.split("```");
        for (let i = 0; i < parts.length; i += 2) {
            // 1. Preserve empty lines (2 or more newlines) with &nbsp; paragraph spacers
            parts[i] = parts[i].replace(/\n\n+/g, function(match) {
                const count = match.length - 1;
                let res = "\n\n";
                for (let j = 0; j < count; j++) {
                    res += "&nbsp;\n\n";
                }
                return res;
            });
            // 2. Preserve single line breaks (GFM hard break style) so single Enters don't collapse
            parts[i] = parts[i].replace(/([^\n])\n(?!\n)/g, "$1  \n");
        }
        return parts.join("```");
    }

    // ── Overflow menu ────────────────────────────────────────────────────────
    property bool menuOpen: false
    property bool showDeleteDialog: false
    property point menuPosition: Qt.point(0, 0)
    property var menuItems: [{
        "id": "pin",
        "label": "Pin note",
        "icon": "push_pin",
        "isDestructive": false,
        "action": function() {
            root.pinned = !root.pinned;
            NotesService.setPinned(root.noteId, root.pinned);
        }
    }, {
        "id": "duplicate",
        "label": "Duplicate note",
        "icon": "file_copy",
        "isDestructive": false,
        "action": function() {
            const newId = NotesService.createNote(titleInput.text, contentInput.text, root.pinned);
            NotesService.setNoteColor(newId, root.activeColor);
        }
    }, {
        "id": "copy",
        "label": "Copy to clipboard",
        "icon": "content_copy",
        "isDestructive": false,
        "action": function() {
            Quickshell.clipboardText = contentInput.text;
        }
    }, {
        "id": "export",
        "label": "Export to .md",
        "icon": "download",
        "isDestructive": false,
        "action": function() {
            root.exportNoteToFile();
        }
    }, {
        "id": "divider",
        "label": "",
        "icon": "",
        "isDestructive": false,
        "action": function() {}
    }, {
        "id": "delete",
        "label": "Delete note",
        "icon": "delete",
        "isDestructive": true,
        "action": function() {
            root.showDeleteDialog = true;
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
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_B) {
            root.wrapSelection("**", "**");
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_I) {
            root.wrapSelection("*", "*");
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_X) {
            root.wrapSelection("~~", "~~");
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K) {
            root.wrapSelection("[", "](url)");
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
            root.renderMarkdown = !root.renderMarkdown;
            if (!root.renderMarkdown) {
                contentInput.forceActiveFocus();
            }
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

            // Markdown Quick Formatting Toolbar
            RowLayout {
                spacing: 4
                Layout.alignment: Qt.AlignVCenter

                // Bold
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.wrapSelection("**", "**")

                    StyledToolTip { text: "Bold (**text**) • Ctrl+B" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "format_bold"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Italic
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.wrapSelection("*", "*")

                    StyledToolTip { text: "Italic (*text*) • Ctrl+I" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "format_italic"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Inline code
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.wrapSelection("`", "`")

                    StyledToolTip { text: "Code (`code`)" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "code"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Link
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.wrapSelection("[", "](url)")

                    StyledToolTip { text: "Link ([text](url)) • Ctrl+K" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "link"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Strikethrough
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.wrapSelection("~~", "~~")

                    StyledToolTip { text: "Strikethrough (~~text~~) • Ctrl+Shift+X" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "format_strikethrough"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Checklist
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.toggleLinePrefix("- [ ] ")

                    StyledToolTip { text: "Checklist (- [ ])" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "check_box"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Bullet list
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    enabled: !root.renderMarkdown
                    opacity: root.renderMarkdown ? 0.38 : 1
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.toggleLinePrefix("- ")

                    StyledToolTip { text: "Bullet list (- )" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: "format_list_bulleted"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnSurface
                    }
                }

                // Preview Markdown Toggle
                RippleButton {
                    implicitWidth: 38
                    implicitHeight: 38
                    focusPolicy: Qt.NoFocus
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.renderMarkdown ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.renderMarkdown ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: {
                        root.renderMarkdown = !root.renderMarkdown;
                        if (!root.renderMarkdown) {
                            contentInput.forceActiveFocus();
                        }
                    }

                    StyledToolTip { text: root.renderMarkdown ? "Edit mode" : "Preview Markdown" }

                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        text: root.renderMarkdown ? "edit" : "visibility"
                        iconSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: root.renderMarkdown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                    }
                }
            }

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

            // Content — M3 bodyLarge plain text / markdown preview
            ScrollView {
                id: contentScrollView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 64
                clip: true

                Item {
                    id: contentContainer
                    width: contentScrollView.availableWidth
                    implicitHeight: Math.max(contentInput.implicitHeight, previewContainer.implicitHeight)

                    StyledTextArea {
                        id: contentInput
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        visible: !root.renderMarkdown
                        text: root.initialContent
                        readOnly: false
                        wrapMode: TextEdit.WrapAnywhere
                        placeholderText: "Start typing your thoughts here..."
                        selectByMouse: true
                        persistentSelection: true
                        font.hintingPreference: Font.PreferNoHinting
                        textFormat: TextEdit.PlainText
                        background: null
                        padding: 0
                        font.family: Appearance.font.family.reading
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurface

                        onSelectionStartChanged: {
                            if (selectionStart !== selectionEnd) {
                                root.lastSelectionStart = selectionStart;
                                root.lastSelectionEnd = selectionEnd;
                            }
                        }
                        onSelectionEndChanged: {
                            if (selectionStart !== selectionEnd) {
                                root.lastSelectionStart = selectionStart;
                                root.lastSelectionEnd = selectionEnd;
                            }
                        }

                        onTextChanged: {
                            autoSaveTimer.restart()
                        }

                        Keys.onPressed: (event) => {
                            // 1. Tab indentation handling
                            if (event.key === Qt.Key_Tab) {
                                const text = contentInput.text;
                                const cursor = contentInput.cursorPosition;
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Dedent: remove up to 2 leading spaces from line
                                    const lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
                                    if (text.startsWith("  ", lineStart)) {
                                        contentInput.text = text.substring(0, lineStart) + text.substring(lineStart + 2);
                                        contentInput.cursorPosition = Math.max(lineStart, cursor - 2);
                                    } else if (text.startsWith(" ", lineStart)) {
                                        contentInput.text = text.substring(0, lineStart) + text.substring(lineStart + 1);
                                        contentInput.cursorPosition = Math.max(lineStart, cursor - 1);
                                    }
                                } else {
                                    // Indent: insert 2 spaces
                                    contentInput.text = text.substring(0, cursor) + "  " + text.substring(cursor);
                                    contentInput.cursorPosition = cursor + 2;
                                }
                                event.accepted = true;
                                return;
                            }

                            // 2. Auto-continue lists on Enter
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier)) {
                                const text = contentInput.text;
                                const cursor = contentInput.cursorPosition;
                                const lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
                                const currentLine = text.substring(lineStart, cursor);

                                // Checklist: - [ ] or - [x]
                                const checkMatch = currentLine.match(/^(\s*)-\s\[([ xX])\]\s(.*)$/);
                                if (checkMatch) {
                                    if (checkMatch[3].trim().length === 0) {
                                        // Empty item: exit checklist
                                        contentInput.text = text.substring(0, lineStart) + checkMatch[1] + text.substring(cursor);
                                        contentInput.cursorPosition = lineStart + checkMatch[1].length;
                                    } else {
                                        // Continue checklist
                                        const insertText = "\n" + checkMatch[1] + "- [ ] ";
                                        contentInput.text = text.substring(0, cursor) + insertText + text.substring(cursor);
                                        contentInput.cursorPosition = cursor + insertText.length;
                                    }
                                    event.accepted = true;
                                    return;
                                }

                                // Bullet list: - or *
                                const bulletMatch = currentLine.match(/^(\s*)[-\*]\s(.*)$/);
                                if (bulletMatch) {
                                    if (bulletMatch[2].trim().length === 0) {
                                        // Empty bullet: exit list
                                        contentInput.text = text.substring(0, lineStart) + bulletMatch[1] + text.substring(cursor);
                                        contentInput.cursorPosition = lineStart + bulletMatch[1].length;
                                    } else {
                                        const insertText = "\n" + bulletMatch[1] + "- ";
                                        contentInput.text = text.substring(0, cursor) + insertText + text.substring(cursor);
                                        contentInput.cursorPosition = cursor + insertText.length;
                                    }
                                    event.accepted = true;
                                    return;
                                }

                                // Numbered list: 1.
                                const numMatch = currentLine.match(/^(\s*)(\d+)\.\s(.*)$/);
                                if (numMatch) {
                                    if (numMatch[3].trim().length === 0) {
                                        // Empty numbered item: exit list
                                        contentInput.text = text.substring(0, lineStart) + numMatch[1] + text.substring(cursor);
                                        contentInput.cursorPosition = lineStart + numMatch[1].length;
                                    } else {
                                        const nextNum = parseInt(numMatch[2], 10) + 1;
                                        const insertText = "\n" + numMatch[1] + nextNum + ". ";
                                        contentInput.text = text.substring(0, cursor) + insertText + text.substring(cursor);
                                        contentInput.cursorPosition = cursor + insertText.length;
                                    }
                                    event.accepted = true;
                                    return;
                                }
                            }

                            // 3. Auto-Pairing on Selected Text
                            if (contentInput.selectionStart !== contentInput.selectionEnd && event.text && event.text.length === 1 && !(event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.AltModifier)) {
                                const charMap = {
                                    "*": ["*", "*"],
                                    "_": ["_", "_"],
                                    "`": ["`", "`"],
                                    "~": ["~", "~"],
                                    "[": ["[", "]"],
                                    "(": ["(", ")"],
                                    "{": ["{", "}"],
                                    "\"": ["\"", "\""],
                                    "'": ["'", "'"]
                                };
                                if (event.text in charMap) {
                                    root.wrapSelection(charMap[event.text][0], charMap[event.text][1], false);
                                    event.accepted = true;
                                    return;
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: previewContainer
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        visible: root.renderMarkdown
                        spacing: 12

                        StyledText {
                            visible: root.renderMarkdown && (!contentInput.text || contentInput.text.trim().length === 0)
                            Layout.fillWidth: true
                            text: "Empty note..."
                            font.family: Appearance.font.family.reading
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }

                        Repeater {
                            id: previewRepeater
                            model: root.renderMarkdown ? StringUtils.splitMarkdownBlocks(contentInput.text) : []

                            Item {
                                id: blockItem
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: blockLoader.implicitHeight

                                Loader {
                                    id: blockLoader
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    sourceComponent: (blockItem.modelData && blockItem.modelData.type === "code") ? codeComponent : textComponent

                                    Component {
                                        id: codeComponent
                                        NoteCodeBlock {
                                            segmentContent: blockItem.modelData ? blockItem.modelData.content : ""
                                            segmentLang: blockItem.modelData ? (blockItem.modelData.lang || "") : ""
                                        }
                                    }

                                    Component {
                                        id: textComponent
                                        StyledTextArea {
                                            width: parent.width
                                            text: root.formatMarkdownForPreview(blockItem.modelData ? blockItem.modelData.content : "")
                                            readOnly: true
                                            wrapMode: TextEdit.WrapAnywhere
                                            selectByMouse: true
                                            persistentSelection: true
                                            font.hintingPreference: Font.PreferNoHinting
                                            textFormat: TextEdit.MarkdownText
                                            background: null
                                            padding: 0
                                            font.family: Appearance.font.family.reading
                                            font.pixelSize: Appearance.font.pixelSize.large
                                            color: Appearance.colors.colOnSurface

                                            onLinkActivated: (link) => {
                                                Qt.openUrlExternally(link)
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                acceptedButtons: Qt.NoButton
                                                hoverEnabled: true
                                                cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
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
            width: 220
            implicitHeight: overflowMenuColumn.implicitHeight + 16
            radius: 18 // M3 Expressive large rounded corners (16-20px)
            // Elevated surface container background for natural visual separation
            color: Appearance.m3colors.m3surfaceContainerHighest
            border.width: 0 // Remove hard boundary stroke - use elevation instead
            opacity: overflowMenu.revealProgress
            scale: 0.96 + overflowMenu.revealProgress * 0.04
            transformOrigin: Item.TopRight
            visible: opacity > 0

            // M3 elevation shadow for surface depth
            StyledRectangularShadow {
                target: overflowMenu
                opacity: overflowMenu.revealProgress
                visible: opacity > 0
            }

            ColumnLayout {
                id: overflowMenuColumn
                anchors.fill: parent
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 0

                Repeater {
                    model: root.menuItems

                    Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.id === "divider" ? 9 : 40

                        // Section divider
                        Rectangle {
                            visible: modelData.id === "divider"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: 0.3
                        }

                        MenuButton {
                            visible: modelData.id !== "divider"
                            anchors.fill: parent
                            buttonRadius: 8
                            iconText: modelData.icon || ""
                            buttonText: root.menuLabel(modelData)
                            property bool isDestructive: modelData.isDestructive || false
                            colBackgroundHover: isDestructive ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHigh
                            onClicked: {
                                root.menuOpen = false;
                                modelData.action();
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

    // ── Delete confirmation modal (Shared ConfirmationDialog) ──────────────
    ConfirmationDialog {
        show: root.showDeleteDialog
        title: Translation.tr("Delete note?")
        text: Translation.tr("This will permanently delete this note. This action cannot be undone.")
        confirmText: Translation.tr("Delete")
        cancelText: Translation.tr("Cancel")
        isDestructive: true
        onCanceled: root.showDeleteDialog = false
        onConfirmed: {
            root.showDeleteDialog = false;
            NotesService.deleteNote(root.noteId);
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
        Pill {
            implicitHeight: 28
            implicitWidth: timestampRow.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter
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
        Pill {
            implicitHeight: 28
            implicitWidth: statsRow.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter
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
