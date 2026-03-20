pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    property bool open: false
    readonly property string stateFilePath: "/tmp/quickshell_lyrics_state.json"

    // Shared state between LyricsWindow and MusicPlayerView
    property var model: null
    property int count: 0
    property int currentLine: -1
    property bool loaded: false
    property real position: 0
    property string sourceName: ""
    property int revision: 0
    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    function normalizeWords(words) {
        return typeof words === "string" ? words : JSON.stringify(words || [])
    }

    function createLyricsModel(lines) {
        const model = Qt.createQmlObject("import QtQuick; ListModel {}", root, "LyricsServiceModel")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i] || {}
            model.append({
                time: Number(line.time || 0),
                text: line.text || "",
                words: normalizeWords(line.words),
            })
        }
        return model
    }

    function replaceLyricsModel(lines) {
        const oldModel = root.model
        root.model = createLyricsModel(lines)
        root.revision += 1

        if (oldModel && oldModel.destroy) {
            oldModel.destroy()
        }
    }

    function toggle() {
        open = !open
    }

    function applyState(data) {
        if (!data)
            return

        if (!root.model) {
            root.model = createLyricsModel([])
        }

        root.count = data.count || 0
        root.currentLine = data.currentLine !== undefined ? data.currentLine : -1
        root.loaded = !!data.loaded
        root.position = data.position || 0
        root.sourceName = data.sourceName || ""

        const incomingLyrics = Array.isArray(data.lyrics) ? data.lyrics : []
        let needsModelUpdate = incomingLyrics.length !== root.model.count

        if (!needsModelUpdate) {
            for (let i = 0; i < incomingLyrics.length; i++) {
                const oldLine = root.model.get(i)
                const newLine = incomingLyrics[i] || {}
                if (!oldLine ||
                    oldLine.text !== (newLine.text || "") ||
                    Math.abs(Number(oldLine.time || 0) - Number(newLine.time || 0)) > 0.001 ||
                    (oldLine.words || "[]") !== normalizeWords(newLine.words)) {
                    needsModelUpdate = true
                    break
                }
            }
        }

        if (needsModelUpdate) {
            replaceLyricsModel(incomingLyrics)
        }
    }

    Component.onCompleted: {
        if (!root.model) {
            root.model = createLyricsModel([])
        }
    }

    function refresh() {
        lyricsStateFile.reload()
    }

    Process {
        id: ensureStateFile
        command: ["touch", root.stateFilePath]
        onExited: root.refresh()
    }

    Timer {
        interval: 200
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    FileView {
        id: lyricsStateFile
        path: root.stateFilePath

        onLoaded: {
            const fileContents = lyricsStateFile.text()
            if (!fileContents || fileContents.length === 0)
                return

            try {
                root.applyState(JSON.parse(fileContents))
            } catch (e) {
                console.error("[LyricsService] Failed to parse lyrics state:", e)
            }
        }

        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                ensureStateFile.running = true
            }
        }
    }
}
