import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FocusScope {
    id: root
    signal closeRequested()

    property var currentNote: NotesService.getSelectedNote()
    property bool showSearch: false
    property string searchQuery: ""
    property bool _switching: false  // Guard against recursive text updates during note switch

    // Refresh current note when selection or notes list changes
    Connections {
        target: NotesService
        function onSelectedNoteIdChanged() {
            root._switching = true
            root.currentNote = NotesService.getSelectedNote()
            Qt.callLater(() => { root._switching = false })
        }
        function onNotesChanged() {
            root.currentNote = NotesService.getSelectedNote()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==================== SIDEBAR ====================
        Rectangle {
            id: sidebar
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // -- Header --
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: Qt.rgba(Appearance.colors.colPrimary.r,
                                       Appearance.colors.colPrimary.g,
                                       Appearance.colors.colPrimary.b, 0.15)

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "note_stack"
                            iconSize: 22
                            color: Appearance.colors.colPrimary
                        }
                    }

                    StyledText {
                        text: "Notes"
                        font.pixelSize: Appearance.font.pixelSize.title
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        Layout.fillWidth: true
                    }

                    // Search toggle
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: 18
                        toggled: root.showSearch
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "search"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                        }
                        onClicked: {
                            root.showSearch = !root.showSearch
                            if (!root.showSearch) root.searchQuery = ""
                        }
                    }
                }

                // -- Search field (animated show/hide) --
                Rectangle {
                    id: searchContainer
                    Layout.fillWidth: true
                    implicitHeight: root.showSearch ? 40 : 0
                    opacity: root.showSearch ? 1 : 0
                    visible: opacity > 0
                    radius: 20
                    color: Appearance.colors.colLayer2
                    clip: true

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutQuad
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        MaterialSymbol {
                            text: "search"
                            iconSize: 18
                            color: Appearance.colors.colSubtext
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.family: Appearance.font.family.main
                            color: Appearance.colors.colOnLayer2
                            clip: true
                            onTextChanged: root.searchQuery = text
                            focus: root.showSearch

                            Text {
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "Search notes..."
                                font: searchInput.font
                                color: Appearance.colors.colSubtext
                                visible: !searchInput.text && !searchInput.activeFocus
                            }
                        }
                    }
                }

                // -- Notes list --
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ListView {
                        id: notesList
                        anchors.fill: parent
                        spacing: 6
                        model: {
                            const sorted = NotesService.getSortedNotes()
                            if (root.searchQuery.length > 0) {
                                const q = root.searchQuery.toLowerCase()
                                return sorted.filter(n =>
                                    n.title.toLowerCase().includes(q) ||
                                    n.content.toLowerCase().includes(q)
                                )
                            }
                            return sorted
                        }

                        delegate: NoteCard {
                            required property var modelData
                            required property int index
                            width: notesList.width

                            noteId: modelData.id
                            noteTitle: modelData.title
                            noteContent: modelData.content
                            noteModified: modelData.modified
                            isSelected: NotesService.selectedNoteId === modelData.id

                            onClicked: {
                                NotesService.selectedNoteId = modelData.id
                            }
                            onDeleteRequested: {
                                NotesService.deleteNote(modelData.id)
                            }
                        }

                        // Empty state
                        Item {
                            anchors.fill: parent
                            visible: notesList.count === 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 12

                                MaterialSymbol {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "note_stack"
                                    iconSize: 48
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.5
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.searchQuery.length > 0 ? "No matching notes" : "No notes yet"
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                }
                            }
                        }
                    }
                }

                // -- FAB (New Note) --
                FloatingActionButton {
                    Layout.alignment: Qt.AlignHCenter
                    iconText: "add"
                    onClicked: {
                        NotesService.createNote()
                        // Focus editor title after creation
                        Qt.callLater(() => { editorTitleInput.forceActiveFocus() })
                    }

                    StyledToolTip {
                        text: "New note"
                    }
                }
            }
        }

        // Divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            Layout.topMargin: 24
            Layout.bottomMargin: 24
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }

        // ==================== EDITOR PANE ====================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            // Empty state (no note selected)
            Item {
                anchors.fill: parent
                visible: !root.currentNote

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    MaterialSymbol {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "edit_note"
                        iconSize: 64
                        color: Appearance.colors.colSubtext
                        opacity: 0.4
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Select or create a note"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.large
                    }
                }
            }

            // Editor content
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0
                visible: !!root.currentNote

                // -- Editor toolbar --
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Editable title
                    TextInput {
                        id: editorTitleInput
                        Layout.fillWidth: true
                        text: root.currentNote?.title ?? ""
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        selectByMouse: true
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        clip: true

                        onTextChanged: {
                            if (!root._switching && root.currentNote && text !== root.currentNote.title) {
                                NotesService.updateNote(root.currentNote.id, text, root.currentNote.content)
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Untitled"
                            font: editorTitleInput.font
                            color: Appearance.colors.colSubtext
                            visible: !editorTitleInput.text && !editorTitleInput.activeFocus
                        }
                    }

                    // Delete button
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: 18
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "delete_outline"
                            iconSize: 20
                            color: Appearance.colors.colError
                        }
                        onClicked: {
                            if (root.currentNote) {
                                NotesService.deleteNote(root.currentNote.id)
                            }
                        }

                        StyledToolTip {
                            text: "Delete note"
                        }
                    }

                    // Close button
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: 18
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                        }
                        onClicked: root.closeRequested()

                        StyledToolTip {
                            text: "Close"
                        }
                    }
                }

                // -- Date chip --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    spacing: 8

                    Rectangle {
                        implicitWidth: dateRow.implicitWidth + 20
                        implicitHeight: 28
                        radius: 14
                        color: Appearance.colors.colSecondaryContainer

                        RowLayout {
                            id: dateRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "schedule"
                                iconSize: 14
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                text: root.currentNote ? NotesService.formatDate(root.currentNote.modified) : ""
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // -- Separator --
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    height: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.2
                }

                // -- Editor body --
                ScrollView {
                    id: editorScrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 8
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea {
                        id: editorTextArea
                        width: editorScrollView.availableWidth
                        text: root.currentNote?.content ?? ""
                        wrapMode: TextEdit.Wrap
                        placeholderText: "Start writing..."
                        selectByMouse: true
                        persistentSelection: true
                        textFormat: TextEdit.PlainText
                        background: null
                        padding: 8
                        font.family: Appearance.font.family.reading
                        font.pixelSize: Appearance.font.pixelSize.normal

                        onTextChanged: {
                            if (!root._switching && root.currentNote && text !== root.currentNote.content) {
                                NotesService.updateNote(root.currentNote.id, root.currentNote.title, text)
                            }
                            updateCopyList()
                        }

                        // Copy buttons for bullet lines
                        property var copyListEntries: []
                        property string lastParsedText: ""

                        function updateCopyList() {
                            const textValue = editorTextArea.text
                            if (!textValue || textValue.length === 0) {
                                copyListEntries = []
                                return
                            }
                            if (textValue === lastParsedText) return
                            lastParsedText = textValue

                            const lineRegex = /(.*?)(\r?\n|$)/g
                            let match = null
                            const parsed = []
                            while ((match = lineRegex.exec(textValue)) !== null) {
                                const lineText = match[1]
                                const newlineText = match[2]
                                const lineStart = match.index
                                const lineEnd = lineStart + lineText.length
                                const bulletMatch = lineText.match(/^\s*-\s+(.*\S)\s*$/)
                                if (bulletMatch) {
                                    const startRect = editorTextArea.positionToRectangle(lineStart)
                                    if (isFinite(startRect.y)) {
                                        let endRect = editorTextArea.positionToRectangle(lineEnd)
                                        if (!isFinite(endRect.y)) endRect = startRect
                                        const lineBottom = endRect.y + endRect.height
                                        const rectHeight = Math.max(lineBottom - startRect.y, editorTextArea.font.pixelSize + 8)
                                        parsed.push({
                                            content: bulletMatch[1].trim(),
                                            y: startRect.y,
                                            height: rectHeight
                                        })
                                    }
                                }
                                if (newlineText === "") break
                            }
                            copyListEntries = parsed
                        }

                        onHeightChanged: updateCopyList()
                        onContentHeightChanged: updateCopyList()
                    }

                    // Copy buttons overlay
                    Item {
                        anchors.fill: parent
                        visible: editorTextArea.copyListEntries.length > 0
                        clip: true

                        Repeater {
                            model: ScriptModel {
                                values: editorTextArea.copyListEntries
                            }
                            delegate: RippleButton {
                                id: copyBtn
                                required property var modelData
                                readonly property real iconSz: Appearance.font.pixelSize.normal
                                property bool justCopied: false

                                implicitHeight: Math.min(modelData.height, 22)
                                implicitWidth: implicitHeight
                                buttonRadius: height / 2
                                y: modelData.y
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                z: 5

                                Timer {
                                    id: resetCopy
                                    interval: 700
                                    onTriggered: copyBtn.justCopied = false
                                }

                                onClicked: {
                                    Quickshell.clipboardText = copyBtn.modelData.content
                                    justCopied = true
                                    resetCopy.start()
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: copyBtn.justCopied ? "check" : "content_copy"
                                    iconSize: copyBtn.iconSz
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }

                // -- Status bar --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 16

                    StyledText {
                        text: NotesService.saving ? "Saving..." : "✓ Saved"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: {
                            if (!root.currentNote) return ""
                            const content = root.currentNote.content || ""
                            const chars = content.length
                            const lines = content.split("\n").length
                            return `${chars} chars · ${lines} lines`
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
