pragma Singleton
import QtQuick

QtObject {
    property bool open: false
    
    // Shared state between LyricsWindow and MusicPlayerView
    property var model: null
    property int count: 0
    property int currentLine: -1
    property bool loaded: false
    property real position: 0
    property string sourceName: ""
    property var activePlayer: null

    function toggle() {
        open = !open
    }
}
