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



    Item {
        anchors.fill: parent
        clip: true

        NotesGridView {
            width: parent.width
            height: parent.height
            x: root.viewMode === "editor" ? -parent.width * 0.3 : 0
            opacity: root.viewMode === "editor" ? 0 : 1
            visible: opacity > 0

            Behavior on x {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            onAddClicked: {
                root.localSelectedNoteId = NotesService.createNote()
            }
            onNoteClicked: function(noteId) {
                root.localSelectedNoteId = noteId
            }
        }

        NotesEditorView {
            width: parent.width
            height: parent.height
            x: root.viewMode === "editor" ? 0 : parent.width
            opacity: root.viewMode === "editor" ? 1 : 0
            visible: opacity > 0

            Behavior on x {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutCubic
                }
            }

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
