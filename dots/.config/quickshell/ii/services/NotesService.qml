pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Notes service: manages a collection of notes stored as JSON.
 * Each note: { id, title, content, created, modified, color }
 */
Singleton {
    id: root

    property bool open: false
    property var notes: []
    property bool saving: false
    property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/notes_collection.json`)

    function toggle() {
        open = !open
    }

    // Generate a simple unique ID
    function generateId(): string {
        return Date.now().toString(36) + Math.random().toString(36).substring(2, 8)
    }

    function createNote(title = "", content = ""): string {
        const now = Math.floor(Date.now() / 1000)
        const note = {
            "id": generateId(),
            "title": title,
            "content": content,
            "created": now,
            "modified": now,
            "color": "default"
        }
        notes.push(note)
        root.notes = notes.slice(0) // trigger change
        save()
        return note.id
    }

    function updateNote(id: string, title: string, content: string) {
        for (let i = 0; i < notes.length; i++) {
            if (notes[i].id === id) {
                notes[i].title = title
                notes[i].content = content
                notes[i].modified = Math.floor(Date.now() / 1000)
                root.notes = notes.slice(0)
                root.saving = true
                saveDebounce.restart()
                return
            }
        }
    }

    function deleteNote(id: string) {
        root.notes = notes.filter(n => n.id !== id)
        save()
    }

    function getNote(id: string) {
        return notes.find(n => n.id === id) || null
    }

    function setNoteColor(id: string, color: string) {
        for (let i = 0; i < notes.length; i++) {
            if (notes[i].id === id) {
                notes[i].color = color
                root.notes = notes.slice(0)
                save()
                return
            }
        }
    }

    function save() {
        notesFileView.setText(JSON.stringify(root.notes, null, 2))
        root.saving = false
    }

    function refresh() {
        notesFileView.reload()
    }

    // Sort notes by most recently modified
    function getSortedNotes() {
        return notes.slice(0).sort((a, b) => b.modified - a.modified)
    }

    function formatDate(timestamp) {
        const d = new Date(timestamp * 1000)
        const now = new Date()
        const diff = now - d

        // Today
        if (diff < 86400000 && d.getDate() === now.getDate()) {
            return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
        }
        // Yesterday
        const yesterday = new Date(now)
        yesterday.setDate(yesterday.getDate() - 1)
        if (d.getDate() === yesterday.getDate() && d.getMonth() === yesterday.getMonth()) {
            return "Yesterday"
        }
        // This year
        if (d.getFullYear() === now.getFullYear()) {
            return d.toLocaleDateString([], { month: 'short', day: 'numeric' })
        }
        return d.toLocaleDateString([], { year: 'numeric', month: 'short', day: 'numeric' })
    }

    Component.onCompleted: {
        refresh()
    }

    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: root.save()
    }

    FileView {
        id: notesFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            try {
                const fileContents = notesFileView.text()
                root.notes = JSON.parse(fileContents)
                console.log("[Notes] Loaded", root.notes.length, "notes")
            } catch (e) {
                console.log("[Notes] Parse error:", e)
                root.notes = []
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                console.log("[Notes] File not found, creating with welcome note.")
                root.notes = []
                // Create a welcome note
                root.createNote("Welcome to Notes", "Write anything here...\n\nUse the + button to create new notes.\n\n- Bullet points are copyable\n- Click a note on the left to switch\n- Notes auto-save as you type")
            } else {
                console.log("[Notes] Error loading file:", error)
            }
        }
    }
}
