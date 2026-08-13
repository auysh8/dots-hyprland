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

    // FIX: Use a string ID instead of object reference to avoid binding loop.
    // The previous `property var currentNote: null` with direct binding caused
    // "Binding loop detected for property currentNote" because getNote() returns
    // an object from the notes array, and QML tried to re-evaluate the binding
    // whenever the array changed (which happens on every save).
    property string selectedNoteId: ""
    property string viewMode: "grid" // "grid" or "editor"

    // Derived read-only properties — no binding loop possible since they're
    // computed imperatively via the Connections handler below.
    readonly property var currentNote: root.selectedNoteId !== "" ? NotesService.getNote(root.selectedNoteId) : null

    onSelectedNoteIdChanged: {
        root.viewMode = (root.selectedNoteId !== "") ? "editor" : "grid"
    }

    Connections {
        target: NotesService
        function onNotesChanged() {
            if (root.selectedNoteId !== "") {
                let note = NotesService.getNote(root.selectedNoteId)
                if (!note) {
                    root.selectedNoteId = ""
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
                root.selectedNoteId = NotesService.createNote()
            }
            onNoteClicked: function(noteId) {
                root.selectedNoteId = noteId
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
                root.selectedNoteId = ""
            }

            onSaveClicked: function(title, content) {
                if (root.currentNote) {
                    NotesService.updateNote(root.currentNote.id, title, content)
                }
                root.selectedNoteId = ""
            }
        }
    }
}
