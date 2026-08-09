import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    signal addClicked()
    signal noteClicked(string noteId)

    property string searchQuery: ""

    // Google Keep-style masonry settings
    property int columnCount: 3

    // Notes visible in the current view (sorted, then filtered by search).
    // Single source of truth for the header count, the masonry columns and the
    // empty state.
    function visibleNotes() {
        const sorted = NotesService.getSortedNotes()
        if (root.searchQuery.length > 0) {
            const q = root.searchQuery.toLowerCase()
            return sorted.filter(n =>
                n.title.toLowerCase().includes(q) ||
                n.content.toLowerCase().includes(q))
        }
        return sorted
    }

    // Rough content-derived height estimate, used only to balance the masonry
    // columns (Keep fills the currently-shortest column). Needs to be roughly
    // monotonic with the card's real content height; exactness isn't required.
    function predictedNoteHeight(note) {
        const title = note.title || "Untitled"
        const content = (note.content || "").split("\n").filter(l => l.trim().length > 0).join("\n")
        const titleLines = Math.min(2, Math.max(1, Math.ceil(title.length / 30)))
        const previewLines = Math.min(6, Math.max(1, Math.ceil(content.length / 48)))
        return 40 + titleLines * 22 + 10 + previewLines * 18
    }

    // Split visible notes across the columns by shortest-column.
    function columnNotes(column) {
        const list = root.visibleNotes()
        const heights = []
        const cols = []
        for (let i = 0; i < root.columnCount; i++) {
            heights.push(0)
            cols.push([])
        }
        for (const n of list) {
            let c = 0
            for (let i = 1; i < root.columnCount; i++) {
                if (heights[i] < heights[c]) c = i
            }
            cols[c].push(n)
            heights[c] += root.predictedNoteHeight(n)
        }
        return cols[column]
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Title + count
            ColumnLayout {
                spacing: 2

                StyledText {
                    text: "Notes"
                    font.pixelSize: Appearance.font.pixelSize.huge * 1.8
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    text: {
                        const total = NotesService.notes.length
                        const shown = root.visibleNotes().length
                        if (root.searchQuery.length > 0)
                            return shown + " of " + total + (total === 1 ? " note" : " notes")
                        return total + (total === 1 ? " note" : " notes")
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            Item { Layout.fillWidth: true }

            ToolbarTextField {
                id: searchInput
                Layout.preferredWidth: 250
                Layout.preferredHeight: 40
                Layout.fillHeight: false
                placeholderText: "Search notes..."
                onTextChanged: root.searchQuery = text
            }


        }

        // ── Notes Grid ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledFlickable {
                id: gridScroll
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: masonryRow.implicitHeight + 100 // Extra room above FAB
                // topMargin gives the first row's rounded corners room to breathe
                // so they aren't cut off by the flickable's clip boundary
                topMargin: Appearance.rounding.verylarge
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                // Google Keep-style masonry: cards keep their content-derived
                // heights and are distributed into fixed columns by
                // shortest-column, so cards don't align to a uniform row height.
                Row {
                    id: masonryRow
                    width: gridScroll.width
                    spacing: 16

                    Repeater {
                        model: root.columnCount

                        // Column (positioner), not ColumnLayout — QtQuick
                        // positioners lay out Repeater delegates as their own
                        // children (the Layouts family does not).
                        delegate: Column {
                            id: noteColumn
                            required property int modelData // column index
                            width: (masonryRow.width - masonryRow.spacing * (root.columnCount - 1)) / root.columnCount
                            spacing: 16

                            Repeater {
                                model: root.columnNotes(modelData)

                                delegate: NoteCard {
                                    // `parent` inside a Repeater delegate is
                                    // the Repeater (0x0), not the positioner,
                                    // so bind to the column delegate by id.
                                    width: noteColumn.width

                                    noteId: modelData.id
                                    noteTitle: modelData.title
                                    noteContent: modelData.content
                                    noteModified: modelData.modified
                                    noteColor: modelData.color
                                    notePinned: modelData.pinned
                                    cardIndex: index

                                    onClicked: root.noteClicked(modelData.id)
                                    onDeleteRequested: NotesService.deleteNote(modelData.id)
                                }
                            }
                        }
                    }
                }

                // Empty state
                PagePlaceholder {
                    shown: root.visibleNotes().length === 0
                    icon: "note_stack"
                    title: root.searchQuery.length > 0
                        ? "No notes match your search."
                        : "No notes yet. Tap + to create one!"
                }
            }
        }
    }

    // ── Floating Action Button ───────────────────────────────────────────────
    // Use the shared FloatingActionButton component (qs.modules.common.widgets)
    FloatingActionButton {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 32
        }
        iconText: "add"
        onClicked: root.addClicked()
        StyledToolTip { text: "New note" }
    }
}
