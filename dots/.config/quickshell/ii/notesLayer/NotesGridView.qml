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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Title
            StyledText {
                text: "Notes"
                font.pixelSize: Appearance.font.pixelSize.huge * 1.8
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
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
                contentHeight: notesFlow.implicitHeight + 100 // Extra room above FAB
                // topMargin gives the first row's rounded corners room to breathe
                // so they aren't cut off by the flickable's clip boundary
                topMargin: Appearance.rounding.verylarge
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                Flow {
                    id: notesFlow
                    width: gridScroll.width
                    spacing: 16

                    Repeater {
                        id: notesRepeater
                        model: {
                            const sorted = NotesService.getSortedNotes()
                            if (root.searchQuery.length > 0) {
                                const q = root.searchQuery.toLowerCase()
                                return sorted.filter(n =>
                                    n.title.toLowerCase().includes(q) ||
                                    n.content.toLowerCase().includes(q))
                            }
                            return sorted
                        }

                        delegate: NoteCard {
                            // 3-column layout, with spacing
                            width: Math.floor((notesFlow.width - 32) / 3)

                            noteId: modelData.id
                            noteTitle: modelData.title
                            noteContent: modelData.content
                            noteModified: modelData.modified
                            cardIndex: index

                            onClicked: root.noteClicked(modelData.id)
                            onDeleteRequested: NotesService.deleteNote(modelData.id)
                        }
                    }
                }

                // Empty state
                PagePlaceholder {
                    shown: notesRepeater.count === 0
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
