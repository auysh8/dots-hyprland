import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: root
    signal closeRequested()

    property var currentNote: null
    property string viewMode: "grid" // "grid" or "editor"

    Connections {
        target: NotesService
        function onSelectedNoteIdChanged() {
            // Use getNote(id) NOT getSelectedNote() — the latter has a side effect
            // that forcibly sets selectedNoteId back to notes[0].id when it's "",
            // which would trap the user in the editor forever.
            root.currentNote = NotesService.getNote(NotesService.selectedNoteId)
            root.viewMode = (NotesService.selectedNoteId !== "") ? "editor" : "grid"
        }
        function onNotesChanged() {
            if (NotesService.selectedNoteId !== "")
                root.currentNote = NotesService.getNote(NotesService.selectedNoteId)
        }
    }



    StackLayout {
        anchors.fill: parent
        currentIndex: root.viewMode === "grid" ? 0 : 1

        NotesGridView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            onAddClicked: {
                NotesService.createNote()
            }
            onNoteClicked: function(noteId) {
                NotesService.selectedNoteId = noteId
            }
        }

        NotesEditorView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            initialTitle: root.currentNote ? root.currentNote.title : ""
            initialContent: root.currentNote ? root.currentNote.content : ""

            onCancelClicked: {
                NotesService.selectedNoteId = ""
            }

            onSaveClicked: function(title, content) {
                if (root.currentNote) {
                    NotesService.updateNote(root.currentNote.id, title, content)
                }
                NotesService.selectedNoteId = ""
            }
        }
    }
}
