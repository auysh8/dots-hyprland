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
    property string localSelectedNoteId: ""

    onLocalSelectedNoteIdChanged: {
        root.currentNote = NotesService.getNote(root.localSelectedNoteId)
        root.viewMode = (root.localSelectedNoteId !== "") ? "editor" : "grid"
    }

    Connections {
        target: NotesService
        function onNotesChanged() {
            if (root.localSelectedNoteId !== "") {
                let note = NotesService.getNote(root.localSelectedNoteId)
                if (!note) {
                    root.localSelectedNoteId = ""
                } else {
                    root.currentNote = note
                }
            }
        }
    }



    StackLayout {
        anchors.fill: parent
        currentIndex: root.viewMode === "grid" ? 0 : 1

        NotesGridView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            onAddClicked: {
                root.localSelectedNoteId = NotesService.createNote()
            }
            onNoteClicked: function(noteId) {
                root.localSelectedNoteId = noteId
            }
        }

        NotesEditorView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            noteId: root.currentNote ? root.currentNote.id : ""
            initialTitle: root.currentNote ? root.currentNote.title : ""
            initialContent: root.currentNote ? root.currentNote.content : ""
            initialModified: root.currentNote ? root.currentNote.modified : 0
            initialPinned: root.currentNote ? root.currentNote.pinned : false
            initialColor: root.currentNote ? root.currentNote.color : "default"

            onCancelClicked: {
                root.localSelectedNoteId = ""
            }

            onSaveClicked: function(title, content) {
                if (root.currentNote) {
                    NotesService.updateNote(root.currentNote.id, title, content)
                }
                root.localSelectedNoteId = ""
            }
        }
    }
}
