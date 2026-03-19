import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    
    property bool isFullscreen: false
    property color contentColor: "white"
    property color secondaryContentColor: "gray"
    property color pillColor: "white"
    property color pillContentColor: "black"
    property color loaderColor: "white"
    
    property var activePlayer: null
    property ListModel lyricsModel: ListModel {}
    property int lyricsCount: 0
    readonly property int resolvedLyricsCount: (
        lyricsModel && lyricsModel.count !== undefined
            ? lyricsModel.count
            : lyricsCount
    )
    property bool isPlaying: false
    property bool lyricsLoaded: false
    property int currentLine: -1
    property bool isResizing: false
    property real position: 0
    property string lyricsSource: ""
    property bool showWindowControls: true
    
    signal fullscreenToggled()
    signal closeRequested()
    
    // Prettify provider names for display
    function providerDisplayName(source) {
        if (!source) return ""
        var names = {
            "betterlyrics": "Better Lyrics",
            "lrclib": "LRCLIB",
            "kugou": "KuGou",
        }
        return names[source] || source
    }
    
    // Internal scrolling logic
    property bool manualScrollMode: false
    
    // Auto-scroll when currentLine changes
    onCurrentLineChanged: {
        if (!manualScrollMode && currentLine >= 0 && currentLine < resolvedLyricsCount && lyricsLoaded) {
             lyricsView.positionViewAtIndex(currentLine, ListView.Center)
        }
    }
    
    // Auto-scroll when lyrics load
    onLyricsLoadedChanged: {
        if (lyricsLoaded && currentLine >= 0) {
            lyricsView.positionViewAtIndex(currentLine, ListView.Center)
        }
    }

    // Window Controls (Top-Right)
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: 8
        z: 10
        visible: root.showWindowControls
        
        // Fullscreen / View Mode Button
        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: 18
            padding: 0
            
            colBackground: ColorUtils.applyAlpha(root.contentColor, 0.1)
            colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.2)
            colRipple: root.contentColor
            
            onClicked: root.fullscreenToggled()
            
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.isFullscreen ? "branding_watermark" : "crop_free"
                iconSize: 20
                color: root.contentColor
            }
        }

        // Close Button
        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: 18
            padding: 0
            
            colBackground: ColorUtils.applyAlpha(root.contentColor, 0.1)
            colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.2)
            colRipple: root.contentColor
            
            onClicked: root.closeRequested()
            
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "close"
                iconSize: 20
                color: root.contentColor
            }
        }
    }
    
    // Detect if lyrics have word-level sync
    property bool hasWordSync: {
        if (!lyricsModel || lyricsModel.count === 0) return false
        // Check all lines: some tracks have intros with no word timings.
        for (var i = 0; i < lyricsModel.count; i++) {
            var item = lyricsModel.get(i)
            if (item && item.words) {
                try {
                    var w = JSON.parse(item.words)
                    if (w && w.length > 0) return true
                } catch(e) {}
            }
        }
        return false
    }
    
    // Lyrics provider label — always visible when lyrics are loaded
    Row {
        id: providerLabel
        anchors.top: parent.top
        anchors.topMargin: 48
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6
        opacity: 0.4
        visible: root.lyricsSource !== "" && root.resolvedLyricsCount > 0
        
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hasWordSync ? "lyrics" : "music_note"
            iconSize: 16
            color: root.secondaryContentColor
        }
        
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.providerDisplayName(root.lyricsSource) + "  ·  " + (root.hasWordSync ? "Word Sync" : "Line Sync")
            color: root.secondaryContentColor
            font.pixelSize: 14
            font.weight: Font.Medium
            font.family: "Inter, Segoe UI, sans-serif"
            font.letterSpacing: 0.5
        }
    }
    
    Item {
        anchors.fill: parent
        anchors.topMargin: root.lyricsSource !== "" && root.resolvedLyricsCount > 0 ? 68 : 48
        anchors.bottomMargin: 16
        clip: true

        // VISIBLE: Only while actively waiting for data OR recognizing
        MaterialLoadingIndicator {
            id: loaderContainer
            anchors.centerIn: parent
            implicitSize: 64

            property bool isLoading: root.resolvedLyricsCount === 0 && (root.isPlaying && !root.lyricsLoaded)

            loading: isLoading
            opacity: isLoading ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

            color: ColorUtils.applyAlpha(root.loaderColor, 0.2)
            shapeColor: root.loaderColor
        }

        // 2. The Status Text
        // VISIBLE: If we are paused OR if we finished loading and found nothing
        StyledText {
            anchors.centerIn: parent
            
            // Dynamic text based on state
            text: root.isPlaying ? "No lyrics found" : "♪ Play some music ♪"
            
            color: root.secondaryContentColor
            opacity: 0.6
            font.pixelSize: 18
            font.family: "Inter, Segoe UI, sans-serif"
            
            // Show if (Recognizing) OR (Lyrics Empty AND (Not Playing OR Loaded))
            visible: (root.resolvedLyricsCount === 0 && (!root.isPlaying || root.lyricsLoaded))
        }

        // 3. The Lyrics List
        StyledListView {
            id: lyricsView
            visible: root.resolvedLyricsCount > 0
            anchors.fill: parent
            anchors.margins: 16
            model: root.lyricsModel
            spacing: 16
            clip: true
            animateAppearance: false
            animateMovement: false
            popin: false
            
            // Performance optimizations for large lyrics models
            cacheBuffer: 600
            reuseItems: true
            
            // Manual scroll tracking
            onFlickStarted: {
                root.manualScrollMode = true
                manualScrollTimer.restart()
            }
            
            onDraggingChanged: {
                if (dragging) {
                    root.manualScrollMode = true
                    manualScrollTimer.stop()
                } else {
                    manualScrollTimer.restart()
                }
            }
            
            // Timer to reset manual mode after inactivity
            Timer {
                id: manualScrollTimer
                interval: 3000
                onTriggered: root.manualScrollMode = false
            }
            
            // Function to re-sync to current line
            function resync() {
                root.manualScrollMode = false
                manualScrollTimer.stop()
                positionViewAtIndex(root.currentLine, ListView.Center)
            }
            
            // Highlight configuration
            highlightRangeMode: root.manualScrollMode ? ListView.NoHighlightRange : ListView.ApplyRange
            preferredHighlightBegin: height * 0.25
            preferredHighlightEnd: height * 0.25
            highlightMoveDuration: root.isResizing ? 0 : 600 
            highlightResizeDuration: root.isResizing ? 0 : 600// Controls the slide speed (vertical)
            highlightMoveVelocity: -1
            
            // --- NEW: The Sliding Pill ---
            highlight: Item {
                // This Item automatically moves to cover the current lyric line
                
                Rectangle {
                    anchors.centerIn: parent
                    // Match height of delegate minus spacing/padding
                    height: parent.height - 12
                    
                    // Bind width to the specific text width of the current line
                    width: lyricsView.currentItem ? lyricsView.currentItem.pillWidth : 0
                    
                    radius: height / 2
                    color: root.pillColor
                    opacity: 1.0
                    border.color: ColorUtils.applyAlpha(root.contentColor, 0.15)
                    border.width: 1
                    
                    // Animate the width resizing as it slides
                    Behavior on width { 
                        // DISABLE animation when resizing window so it stays locked to text
                        enabled: !root.isResizing
                        NumberAnimation { duration: 500; easing.type: Easing.OutCubic } 
                    }
                    Behavior on height { 
                        NumberAnimation { duration: 500; easing.type: Easing.OutCubic } 
                    }
                }
            }

            currentIndex: root.currentLine
            
            delegate: Item {
                id: lyricItem
                width: ListView.view.width
                height: lyricText.implicitHeight + (isCurrent ? 32 : 16)
                
                readonly property bool isCurrent: ListView.isCurrentItem
                readonly property int distance: Math.abs(index - ListView.view.currentIndex)
                
                // --- NEW: Expose width for the highlight to read ---
                property real pillWidth: Math.min(lyricText.implicitWidth + 48, width - 16)
                
                // Hover and click state
                property bool isHovered: lyricMouseArea.containsMouse
                property bool isPressed: lyricMouseArea.pressed
                
                // Click feedback scale
                property real clickScale: 1.0
                
                transform: Scale {
                    origin.x: lyricItem.width / 2
                    origin.y: lyricItem.height / 2
                    xScale: lyricItem.clickScale
                    yScale: lyricItem.clickScale
                }
                
                Behavior on clickScale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                // Click to seek to this lyric's timestamp
                MouseArea {
                    id: lyricMouseArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    scrollGestureEnabled: false
                    onClicked: {
                        if (root.activePlayer && model.time !== undefined) {
                            console.log("[Lyrics] Seeking to:", model.time)
                            // Click feedback animation
                            lyricItem.clickScale = 0.95
                            clickResetTimer.start()
                            root.activePlayer.position = model.time
                        }
                    }
                    
                    Timer {
                        id: clickResetTimer
                        interval: 100
                        onTriggered: lyricItem.clickScale = 1.0
                    }
                }
                
                // Hover highlight background
                Rectangle {
                    anchors.centerIn: parent
                    width: lyricText.implicitWidth + 24
                    height: lyricText.implicitHeight + 8
                    radius: 8
                    color: root.contentColor
                    opacity: lyricItem.isHovered && !lyricItem.isCurrent ? 0.1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                
                StyledText {
                    id: lyricText
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    
                    // KARAOKE LOGIC
                    property var wordList: {
                        if (!model.words) return []
                        try { return JSON.parse(model.words) } catch(e) { return [] }
                    }
                    
                    property bool hasWords: wordList && wordList.length > 0

                    textFormat: (lyricItem.isCurrent && hasWords) ? Text.RichText : Text.PlainText
                    
                    // Helper: convert 0-255 int to 2-digit hex
                    function toHex2(val) {
                        var h = Math.round(Math.max(0, Math.min(255, val))).toString(16)
                        return h.length < 2 ? "0" + h : h
                    }
                    
                    text: {
                        if (lyricItem.isCurrent && hasWords) {
                            const pos = root.position
                            const c = root.pillContentColor
                            const r = toHex2(c.r * 255)
                            const g = toHex2(c.g * 255)
                            const b = toHex2(c.b * 255)
                            
                            let html = ""
                            for (let i = 0; i < wordList.length; i++) {
                                let w = wordList[i]
                                let alpha
                                
                                if (pos + 0.03 >= w.time) {
                                    // Make activation snappy even for long words in slow songs.
                                    let endTime = w.end || (w.time + 0.3)
                                    let dur = Math.max(0.06, endTime - w.time)
                                    let fadeInDur = Math.min(0.22, dur * 0.45)
                                    let progress = Math.min(1.0, Math.max(0.0, (pos - w.time) / fadeInDur))
                                    alpha = 0.55 + 0.45 * progress
                                } else {
                                    alpha = 0.25
                                }
                                
                                let a = toHex2(alpha * 255)
                                html += `<font color="#${a}${r}${g}${b}">${w.text} </font>`
                            }
                            return html
                        }
                        return model.text
                    }

                    z: 2
                    
                    color: lyricItem.isCurrent ? root.pillContentColor : root.secondaryContentColor

                    Behavior on color { 
                        ColorAnimation { duration: 400; easing.type: Easing.InOutQuad } 
                    }
                    
                    font.pixelSize: lyricItem.isCurrent ? (root.isFullscreen ? 42 : 26) : (root.isFullscreen ? 32 : 20)
                    font.weight: lyricItem.isCurrent ? Font.Bold : Font.Normal
                    font.family: "Inter, Segoe UI, sans-serif"
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    
                    opacity: {
                        if (lyricItem.isCurrent) return 1.0
                        if (lyricItem.distance === 1) return 0.6
                        if (lyricItem.distance === 2) return 0.35
                        return 0.15
                    }
                    
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }
                    Behavior on font.pixelSize { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                }
            }
        }
        
        // Floating re-sync button
        Rectangle {
            id: resyncButton
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.manualScrollMode ? 20 : -60
            width: 140
            height: 44
            radius: 22
            color: root.pillColor
            opacity: root.manualScrollMode ? 1.0 : 0
            visible: opacity > 0
            
            Behavior on anchors.bottomMargin { 
                NumberAnimation { duration: 250; easing.type: Easing.OutCubic } 
            }
            Behavior on opacity { 
                NumberAnimation { duration: 200 } 
            }
            
            Row {
                anchors.centerIn: parent
                spacing: 8
                
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "sync"
                    iconSize: 20
                    color: root.pillContentColor
                }
                
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Re-sync"
                    color: root.pillContentColor
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    font.family: "Inter, Segoe UI, sans-serif"
                }
            }
            
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: lyricsView.resync()
            }
        }
    }
}
