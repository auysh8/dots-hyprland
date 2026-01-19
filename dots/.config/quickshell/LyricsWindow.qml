import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

Scope {
    id: root
    property bool showLyrics: false
    property bool closing: false
    
    // --- Backend Communication ---
    Process {
        id: backend
        running: true
        command: ["python3", Qt.resolvedUrl("lyrics_backend.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("RESP:")) {
                    let json = Qt.atob(line.substring(5));
                    let data = JSON.parse(json);
                    // Find the player this data belongs to and update it
                    root.updatePlayerCache(data.id, data.lyrics, data.color);
                }
            }
        }
    }
    
    // Simple cache to store lyrics/colors per song ID (Title + Artist)
    property var contentCache: ({})
    
    function updatePlayerCache(id, lyrics, color) {
        let entry = contentCache[id] || {};
        entry.lyrics = lyrics;
        entry.color = color;
        contentCache[id] = entry;
        contentCache = Object.assign({}, contentCache); // Force QML update
    }

    function requestData(title, artist, artUrl, duration) {
        let id = title + "::" + artist;
        if (contentCache[id]) return; // Already have it
        
        let req = { "id": id, "title": title, "artist": artist, "artUrl": artUrl, "duration": duration };
        let b64 = Qt.btoa(JSON.stringify(req));
        backend.write(b64 + "\n");
    }

    // --- Window State ---
    function toggle() { showLyrics ? closeWindow() : showLyrics = true; }
    function closeWindow() { if(showLyrics) { closing = true; showLyrics = false; } }
    
    IpcHandler {
        target: "lyrics"
        function toggle() { root.toggle() }
        function open() { root.showLyrics = true }
        function close() { root.closeWindow() }
    }

    Variants {
        model: Quickshell.screens
        
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors.fill: parent
            visible: root.showLyrics || root.closing
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "lyrics-layer"
            color: "transparent"

            // --- MAIN CONTAINER ---
            Rectangle {
                id: mainCard
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.85, 950)
                height: Math.min(parent.height * 0.75, 600)
                radius: 24
                clip: true
                
                // Animate entry/exit
                scale: root.showLyrics ? 1 : 0.9
                opacity: root.showLyrics ? 1 : 0
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                
                // Dynamic Background Color (from current SwipeView item)
                color: playerSwipe.currentItem ? playerSwipe.currentItem.dynamicColor : "#222"
                Behavior on color { ColorAnimation { duration: 500 } }

                MouseArea { anchors.fill: parent } // Block clicks

                // --- SWIPE VIEW FOR PLAYERS ---
                SwipeView {
                    id: playerSwipe
                    anchors.fill: parent
                    anchors.bottomMargin: 40 // Space for dots
                    clip: true
                    
                    // Bind to ALL active players
                    model: MprisController.players
                    
                    delegate: Item {
                        id: playerPage
                        required property MprisPlayer modelData
                        
                        // Local State
                        property string songId: modelData.trackTitle + "::" + modelData.trackArtist
                        property var cachedData: root.contentCache[songId] || { lyrics: [], color: "#222" }
                        property color dynamicColor: cachedData.color
                        property int currentLineIndex: -1
                        
                        // Trigger Request when song changes
                        onSongIdChanged: root.requestData(modelData.trackTitle, modelData.trackArtist, modelData.trackArtUrl, modelData.length)
                        Component.onCompleted: root.requestData(modelData.trackTitle, modelData.trackArtist, modelData.trackArtUrl, modelData.length)

                        // Calculate Current Line (Local Sync)
                        Timer {
                            running: playerSwipe.currentItem === playerPage && root.showLyrics && modelData.playbackState === MprisPlaybackState.Playing
                            interval: 200
                            repeat: true
                            onTriggered: {
                                let pos = modelData.position;
                                let lyrics = playerPage.cachedData.lyrics || [];
                                let idx = -1;
                                for(let i=0; i<lyrics.length; i++) {
                                    if(lyrics[i].time <= pos) idx = i;
                                    else break;
                                }
                                if(idx !== currentLineIndex) currentLineIndex = idx;
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 40
                            spacing: 40
                            
                            // LEFT: ART & CONTROLS
                            ColumnLayout {
                                Layout.preferredWidth: 280
                                Layout.fillHeight: true
                                spacing: 20
                                
                                Item { // Album Art
                                    Layout.preferredWidth: 240; Layout.preferredHeight: 240
                                    Layout.alignment: Qt.AlignHCenter
                                    Image { id: art; anchors.fill: parent; source: modelData.trackArtUrl; fillMode: Image.PreserveAspectCrop; visible: false }
                                    Rectangle { id: mask; anchors.fill: parent; radius: 16; visible: false }
                                    OpacityMask { anchors.fill: parent; source: art; maskSource: mask }
                                    
                                    // Player Identity Badge (e.g. Spotify Icon)
                                    Rectangle {
                                        anchors.right: parent.right; anchors.bottom: parent.bottom
                                        width: 32; height: 32; radius: 16
                                        color: "black"; border.color: "white"; border.width: 1
                                        Image { 
                                            anchors.centerIn: parent; width: 20; height: 20
                                            source: "image://icon/" + modelData.identity 
                                            fillMode: Image.PreserveAspectFit
                                        }
                                    }
                                }
                                
                                Text { // Title
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.trackTitle || "Unknown"
                                    color: "white"; font.pixelSize: 22; font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }
                                Text { // Artist
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.trackArtist || "Unknown Artist"
                                    color: "#ccc"; font.pixelSize: 16
                                    elide: Text.ElideRight
                                }
                                
                                Item { Layout.fillHeight: true } // Spacer
                                
                                // CONTROLS
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 15
                                    
                                    // Progress
                                    StyledSlider {
                                        Layout.fillWidth: true
                                        configuration: StyledSlider.Configuration.Wavy
                                        highlightColor: "white"
                                        trackColor: "#44ffffff"
                                        handleColor: "white"
                                        value: modelData.length > 0 ? modelData.position / modelData.length : 0
                                        onMoved: modelData.position = value * modelData.length
                                    }
                                    
                                    RowLayout {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 20
                                        
                                        RippleButton {
                                            implicitWidth: 40; implicitHeight: 40; buttonRadius: 20
                                            colBackground: "#22ffffff"; colRipple: "#44ffffff"
                                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_previous"; color: "white" }
                                            downAction: () => modelData.previous()
                                        }
                                        RippleButton {
                                            implicitWidth: 56; implicitHeight: 56; buttonRadius: 28
                                            colBackground: "white"; colRipple: "#ccc"
                                            contentItem: MaterialSymbol { 
                                                anchors.centerIn: parent; 
                                                text: modelData.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow"
                                                color: "black" 
                                            }
                                            downAction: () => modelData.togglePlaying()
                                        }
                                        RippleButton {
                                            implicitWidth: 40; implicitHeight: 40; buttonRadius: 20
                                            colBackground: "#22ffffff"; colRipple: "#44ffffff"
                                            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "skip_next"; color: "white" }
                                            downAction: () => modelData.next()
                                        }
                                    }
                                }
                            }
                            
                            // SEPARATOR
                            Rectangle { Layout.fillHeight: true; width: 1; color: "white"; opacity: 0.2 }
                            
                            // RIGHT: LYRICS LIST
                            ListView {
                                id: lv
                                Layout.fillWidth: true; Layout.fillHeight: true
                                model: playerPage.cachedData.lyrics
                                clip: true
                                spacing: 18
                                
                                // Auto-scroll
                                currentIndex: playerPage.currentLineIndex
                                highlightRangeMode: ListView.ApplyRange
                                preferredHighlightBegin: height * 0.4
                                preferredHighlightEnd: height * 0.4
                                highlightMoveDuration: 600
                                highlightMoveVelocity: -1
                                
                                delegate: Item {
                                    width: ListView.view.width
                                    height: txt.implicitHeight
                                    property bool isCurrent: index === playerPage.currentLineIndex
                                    
                                    Text {
                                        id: txt
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.text
                                        
                                        // Animations
                                        color: isCurrent ? "white" : "#88ffffff"
                                        font.pixelSize: isCurrent ? 26 : 20
                                        font.weight: isCurrent ? Font.Bold : Font.Normal
                                        opacity: isCurrent ? 1.0 : 0.5
                                        scale: isCurrent ? 1.05 : 1.0
                                        
                                        Behavior on color { ColorAnimation { duration: 400 } }
                                        Behavior on font.pixelSize { NumberAnimation { duration: 400 } }
                                        Behavior on opacity { NumberAnimation { duration: 400 } }
                                        Behavior on scale { NumberAnimation { duration: 400 } }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // --- PAGE INDICATOR (DOTS) ---
                PageIndicator {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 10
                    count: playerSwipe.count
                    currentIndex: playerSwipe.currentIndex
                    
                    delegate: Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: index === playerSwipe.currentIndex ? "white" : "#44ffffff"
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                // Close Button
                RippleButton {
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.margins: 15
                    implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                    colBackground: "#22000000"; colHover: "#44000000"
                    contentItem: Text { anchors.centerIn: parent; text: "✕"; color: "white" }
                    downAction: () => root.closeWindow()
                }
            }
        }
    }
}