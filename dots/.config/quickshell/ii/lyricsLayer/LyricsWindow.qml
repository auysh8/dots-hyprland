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
    property bool isFullscreen: false
    property bool isResizing: false
    property bool lyricsLoaded: false
    
    // Use native MPRIS for UI updates only (art, progress)
    readonly property var availablePlayers: MprisController.players
property MprisPlayer selectedPlayer: null
readonly property MprisPlayer activePlayer: selectedPlayer ? selectedPlayer : MprisController.activePlayer

readonly property real position: activePlayer ? activePlayer.position : 0
readonly property real duration: activePlayer ? activePlayer.length : 0
readonly property bool isPlaying: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing

    
    // Player switching
    property bool showPlayerPicker: false
    property bool switching: false // Controls fade animation
    property bool trackChanging: false // Prevents layout flash during track changes
    property bool forceCenteredMode: false // Manual toggle for lyrics visibility in fullscreen
    property bool layoutTransitioning: false // Controls layout transition fade
    
    Timer {
        id: loadingTimer
        interval: 400
        onTriggered: root.switching = false
    }
    
    Timer {
        id: trackChangeTimer
        interval: 2000
        onTriggered: root.trackChanging = false
    }
    
    Timer {
        id: layoutTransitionTimer
        interval: 200 // Half of fade duration
        onTriggered: {
            root.forceCenteredMode = !root.forceCenteredMode
            layoutTransitioning = false
        }
    }
    
    // FIX: Auto-open when Spotify is playing
    readonly property string playerName: activePlayer?.identity || ""
    readonly property bool isSpotify: playerName.toLowerCase().includes("spotify")
    
    // MPRIS track info for display (source of truth)
    readonly property string displayTitle: activePlayer?.trackTitle || ""
    readonly property string displayArtist: activePlayer?.trackArtist || ""
    
    // Backend data for lyrics sync check only
    property string cleanedTitle: ""
    property string artist: ""
    
    // FIX: Track artUrl separately to detect changes
    property var artUrl: activePlayer?.trackArtUrl
    property string lastProcessedArtUrl: "" // Track what we last processed
    property string lastProcessedTitle: "" // Track last title for song change detection
    
    // FIX: Watch displayTitle changes to detect song changes (works for player switching too)
    onDisplayTitleChanged: {
        if (displayTitle.length > 0 && displayTitle !== lastProcessedTitle) {
            console.log("[Lyrics] Track changed to:", displayTitle)
            lastProcessedTitle = displayTitle
            lyricsLoaded = false
            
            // Set track changing state to prevent layout flash
            trackChanging = true
            trackChangeTimer.restart()
            
            // Clear lyrics for new song
            lyricsModel.clear()
            lyricsCount = 0
            currentLine = -1
            currentSongTitle = ""
            
            // Trigger art download if artUrl is valid
            if (artUrl && artUrl.length > 0) {
                lastProcessedArtUrl = artUrl
                artDownloaded = false
                artLoading = false
                Qt.callLater(downloadArt)
            }
        }
    }
    
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl || "")
    property string artFilePath: artFileName ? `${artDownloadLocation}/${artFileName}` : ""
    
    // FIX: Separate loading state from downloaded state
    property bool artLoading: false
    property bool artDownloaded: false
    property string displayedArtFilePath: artDownloaded ? Qt.resolvedUrl(artFilePath) : ""
    
    // FIX: Use displayedArtFilePath for image too (consistency)
    readonly property string albumArt: displayedArtFilePath
    
    // Lyrics state
    property int currentLine: -1
    property int lyricsCount: 0
    
    // FIX: Force color update counter to re-trigger ColorQuantizer
    property int colorUpdateTrigger: 0
    
    // Color extraction from album art
    ColorQuantizer {
        id: colorQuantizer
        // FIX: Add trigger dependency to force re-evaluation
        source: root.colorUpdateTrigger >= 0 ? root.displayedArtFilePath : ""
        depth: 0
        rescaleSize: 1
    }
    
    // Extract dominant color or use default
    readonly property color extractedColor: {
        if (!artDownloaded || displayedArtFilePath.length === 0) {
            return Appearance.colors.colPrimary
        }
        let c = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary
        console.log("[Lyrics] Extracted color:", c, "from:", displayedArtFilePath)
        return c
    }
    
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.extractedColor, Appearance.colors.colPrimaryContainer, 0.8)
    }
    
    readonly property color backgroundColor: blendedColors.colLayer0
    readonly property color contentColor: blendedColors.colOnLayer0
    readonly property color secondaryContentColor: blendedColors.colSubtext
    readonly property color pillColor: blendedColors.colSecondaryContainer
    readonly property color pillContentColor: blendedColors.colOnSecondaryContainer
    

    // FIX: Watch artUrl changes directly and reset state immediately
    onArtUrlChanged: {
        console.log("[Lyrics] artUrl changed to:", artUrl)
        
        // FIX: Only process if artUrl is valid AND different from last
        // Don't clear anything when artUrl becomes empty (pause state)
        if (artUrl && artUrl.length > 0 && artUrl !== lastProcessedArtUrl) {
            lastProcessedArtUrl = artUrl
            artDownloaded = false
            artLoading = false
            
            // Clear lyrics when song actually changes (new valid artUrl)
            console.log("[Lyrics] New song detected, clearing lyrics")
            lyricsModel.clear()
            lyricsCount = 0
            currentLine = -1
            currentSongTitle = ""
            
            // Start download process
            Qt.callLater(downloadArt)
        }
    }
    
    // FIX: Separate download function for better control
    function downloadArt() {
        if (!artUrl || artUrl.length === 0) {
            artDownloaded = false
            artLoading = false
            return
        }
        
        console.log("[Lyrics] Starting download for:", artFilePath)
        
        // Update binding-dependent properties before starting process
        coverArtDownloader.targetFile = artUrl
        coverArtDownloader.artFilePath = artFilePath
        
        artLoading = true
        artDownloaded = false
        coverArtDownloader.running = true
    }
    
    Process {
        id: coverArtDownloader
        property string targetFile: ""
        property string artFilePath: ""
        
        // FIX: Always download, don't check if file exists
        // (or add timestamp check for cache validity)
        command: ["bash", "-c", `curl -sSL '${targetFile}' -o '${artFilePath}'`]
        
        onExited: (exitCode, exitStatus) => {
            console.log("[Lyrics] Download finished, exitCode:", exitCode)
            root.artLoading = false
            
            if (exitCode === 0) {
                root.artDownloaded = true
                // FIX: Force color re-extraction by changing trigger
                root.colorUpdateTrigger++
                console.log("[Lyrics] Art downloaded successfully, trigger:", root.colorUpdateTrigger)
            } else {
                console.log("[Lyrics] Download failed")
                root.artDownloaded = false
            }
        }
    }
    
    ListModel { id: lyricsModel }
    
    function toggle() {
        if (showLyrics) closeWindow()
        else showLyrics = true
    }
    
    function toggleFullscreen() {
        if (showLyrics) {
            isFullscreen = !isFullscreen
            console.log("[Lyrics] Fullscreen:", isFullscreen)
        }
    }
    
    function closeWindow() {
        if (root.showLyrics) {
            closing = true
            showLyrics = false
            isFullscreen = false // Reset fullscreen on close
        }
    }
    
    function formatTime(seconds) {
        if (!seconds || seconds < 0) return "0:00"
        let mins = Math.floor(seconds / 60)
        let secs = Math.floor(seconds % 60)
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }
    
    property string currentSongTitle: ""
    
    function parseUpdate(data) {
        // 1. We received a response (even if empty), so stop the loading animation.
        root.lyricsLoaded = true 
        
        let newLyrics = data.lyrics || []
        let songTitle = data.song || ""
        let newCurrentLine = data.currentLine !== undefined ? data.currentLine : -1
        
        // OPTIMIZATION: If song hasn't changed, just update the position
        // This prevents flickering and high CPU usage from rebuilding the model every line
        if (songTitle !== "" && songTitle === currentSongTitle && lyricsModel.count > 0 && lyricsModel.count === newLyrics.length) {
            if (root.currentLine !== newCurrentLine) {
                root.currentLine = newCurrentLine
            }
            return
        }
        
        console.log("[Lyrics] New song or lyrics loaded. Lines:", newLyrics.length)
        
        // Full update
        currentSongTitle = songTitle
        root.currentLine = newCurrentLine
        lyricsModel.clear()
        
        for (let i = 0; i < newLyrics.length; i++) {
            lyricsModel.append({ 
                text: newLyrics[i].text, 
                time: newLyrics[i].time,
                words: JSON.stringify(newLyrics[i].words || []) 
            })
        }
        
        lyricsCount = newLyrics.length
        
        // Reset scroll only on full load
        if (lyricsCount > 0) {
            lyricsView.positionViewAtBeginning()
        }
    }
    
    Timer {
        running: root.isPlaying && root.showLyrics
        interval: 500
        repeat: true
        onTriggered: {
            // Update MPRIS position for progress bar
            activePlayer?.positionChanged()
        }
    }
    
    IpcHandler {
        target: "lyrics"
        function toggle() { root.toggle() }
        function open() { root.showLyrics = true }
        function close() { root.closeWindow() }
        function fullscreen() { root.toggleFullscreen() }
    }
    
    // Trigger update when we switch players
    onPlayerNameChanged: {
        if (playerName !== "") {
            // Need to implement command sending to backend if possible
            // For now, relies on next poll cycle which is frequent enough (0.5s)
        }
    }
    
    // Note: Backend auto-detects via MPRIS, no need to send track info
    // onCleanedTitleChanged: {
    //     // StdinSink not available in this Quickshell version
    // }
    
    Process {
        // Backend Process (restarted on change)
        id: backend
        running: true
        command: [Qt.resolvedUrl("venv/bin/python3").toString().replace("file://", ""), Qt.resolvedUrl("lyrics_backend.py").toString().replace("file://", "")]
        
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("READY:") || line.startsWith("RESP:")) {
                    let prefix = line.indexOf(":")
                    let b64 = line.substring(prefix + 1)
                    try {
                        let json = Qt.atob(b64)
                        let data = JSON.parse(json)
                        root.parseUpdate(data)
                    } catch(e) { console.log("Lyrics parse error:", e) }
                } else if (line.startsWith("UPDATE:")) {
                    // format: UPDATE:identity:base64
                    let parts = line.split(":")
                    if (parts.length >= 3) {
                        let identity = parts[1]
                        let b64 = parts[2]
                        
                        // Debug identity mismatch
                        // console.log("Update check:", identity, "vs", root.playerName)
                        
                        // FIX: Loose matching for identities (ignore instance IDs if needed)
                        if (identity === root.playerName || 
                            (identity.indexOf(root.playerName.toLowerCase()) >= 0) ||
                            (root.playerName.toLowerCase().indexOf(identity) >= 0)) {
                            try {
                                let json = Qt.atob(b64)
                                let data = JSON.parse(json)
                                root.parseUpdate(data)
                            } catch(e) { console.log("Lyrics parse error:", e) }
                        }
                    }
                }
            }
        }
        
        stderr: SplitParser {
            onRead: (line) => console.log(line)
        }
    }
    
    Variants {
        model: Quickshell.screens
        
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.showLyrics || root.closing
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "lyrics-layer"
            // Enable keyboard focus in fullscreen mode
            WlrLayershell.keyboardFocus: root.isFullscreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            
            // Keyboard shortcuts (only work in fullscreen when focused)
            Keys.onPressed: (event) => {
                if (!root.isFullscreen) return
                
                switch (event.key) {
                    case Qt.Key_Space:
                        // Toggle play/pause
                        root.activePlayer?.togglePlaying()
                        event.accepted = true
                        break
                    case Qt.Key_Left:
                        // Seek backward 5 seconds
                        if (root.activePlayer) {
                            root.activePlayer.position = Math.max(0, root.position - 5)
                        }
                        event.accepted = true
                        break
                    case Qt.Key_Right:
                        // Seek forward 5 seconds
                        if (root.activePlayer) {
                            root.activePlayer.position = Math.min(root.duration, root.position + 5)
                        }
                        event.accepted = true
                        break
                    case Qt.Key_Up:
                    case Qt.Key_P:
                        // Previous track
                        root.activePlayer?.previous()
                        event.accepted = true
                        break
                    case Qt.Key_Down:
                    case Qt.Key_N:
                        // Next track
                        root.activePlayer?.next()
                        event.accepted = true
                        break
                    case Qt.Key_Escape:
                    case Qt.Key_Super_L:
                    case Qt.Key_Super_R:
                        // Close the layer
                        root.closeWindow()
                        event.accepted = true
                        break
                    case Qt.Key_F:
                        // Toggle fullscreen
                        root.toggleFullscreen()
                        event.accepted = true
                        break
                }
            }
            
            // Focus item for keyboard input
            Item {
                id: keyboardFocus
                anchors.fill: parent
                focus: root.isFullscreen
                
                // Using Shortcut items for better layer shell compatibility
                Shortcut {
                    enabled: root.isFullscreen
                    sequence: "Space"
                    onActivated: root.activePlayer?.togglePlaying()
                }
                Shortcut {
                    enabled: root.isFullscreen
                    sequence: "Left"
                    onActivated: {
                        if (root.activePlayer) root.activePlayer.position = Math.max(0, root.position - 5)
                    }
                }
                Shortcut {
                    enabled: root.isFullscreen
                    sequence: "Right"
                    onActivated: {
                        if (root.activePlayer) root.activePlayer.position = Math.min(root.duration, root.position + 5)
                    }
                }
                Shortcut {
                    enabled: root.isFullscreen
                    sequences: ["Up", "P"]
                    onActivated: root.activePlayer?.previous()
                }
                Shortcut {
                    enabled: root.isFullscreen
                    sequences: ["Down", "N"]
                    onActivated: root.activePlayer?.next()
                }
                Shortcut {
                    enabled: root.isFullscreen
                    sequence: "Escape"
                    onActivated: root.closeWindow()
                }
                Shortcut {
                    enabled: root.isFullscreen
                    sequence: "F"
                    onActivated: root.toggleFullscreen()
                }
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: root.closeWindow()
            }
            
            // Blurred album art background
            Item {
                id: blurBackground
                anchors.fill: lyricsPanel
                visible: root.albumArt !== ""
                
                // Apply rounded corner mask
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: blurBackground.width
                        height: blurBackground.height
                        radius: lyricsPanel.radius
                    }
                }
                
                // Animated container - holds the image + effect together
                Item {
                    id: animatedBgContainer
                    anchors.centerIn: parent
                    width: parent.width * 1.6
                    height: parent.height * 1.6
                    
                    // Animation properties
                    property real offsetX: 0
                    property real offsetY: 0
                    property real scaleAnim: 1.0
                    
                    transform: [
                        Translate { x: animatedBgContainer.offsetX; y: animatedBgContainer.offsetY },
                        Scale { 
                            origin.x: animatedBgContainer.width / 2
                            origin.y: animatedBgContainer.height / 2
                            xScale: animatedBgContainer.scaleAnim
                            yScale: animatedBgContainer.scaleAnim
                        }
                    ]
                    
                    // Horizontal drift - more pronounced
                    SequentialAnimation on offsetX {
                        loops: Animation.Infinite
                        running: root.showLyrics
                        NumberAnimation { to: 80; duration: 8000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: -80; duration: 8000; easing.type: Easing.InOutSine }
                    }
                    
                    // Vertical drift
                    SequentialAnimation on offsetY {
                        loops: Animation.Infinite
                        running: root.showLyrics
                        NumberAnimation { to: -60; duration: 6000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 60; duration: 6000; easing.type: Easing.InOutSine }
                    }
                    
                    // Breathing/scale effect
                    SequentialAnimation on scaleAnim {
                        loops: Animation.Infinite
                        running: root.showLyrics
                        NumberAnimation { to: 1.25; duration: 10000; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 10000; easing.type: Easing.InOutSine }
                    }
                    
                    Image {
                        id: bgImage
                        anchors.fill: parent
                        source: root.albumArt
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                    }
                    
                    MultiEffect {
                        anchors.fill: bgImage
                        source: bgImage
                        blurEnabled: true
                        blurMax: 32
                        blur: 1.0
                        saturation: 0.4
                        brightness: -0.2
                    }
                }
                
                // Dark overlay for readability
                Rectangle {
                    anchors.fill: parent
                    color: root.backgroundColor
                    opacity: 0.4
                }
            }
            
            Rectangle {
                id: lyricsPanel
                anchors.horizontalCenter: parent.horizontalCenter
                
                // Calculate target positions/sizes to avoid animation timing issues
                readonly property real floatingHeight: Math.min(parent.height * 0.8, 650)
                readonly property real floatingY: (parent.height - floatingHeight) / 2
                
                y: root.showLyrics ? (root.isFullscreen ? 0 : floatingY) : -height - 50
                width: root.isFullscreen ? parent.width : Math.min(parent.width * 0.75, 900)
                height: root.isFullscreen ? parent.height : floatingHeight
                radius: root.isFullscreen ? 0 : 24
                color: root.backgroundColor
                clip: true
                
                Behavior on color { ColorAnimation { duration: 400 } }
                
                Behavior on y {
                    NumberAnimation {
                        duration: root.showLyrics ? 400 : 250
                        easing.type: root.showLyrics ? Easing.OutCubic : Easing.InCubic
                        onRunningChanged: {
                            if (!running && !root.showLyrics) root.closing = false
                        }
                    }
                }
                
                // Fullscreen transition animations
                Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic; onRunningChanged: root.isResizing = running } }
                Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                
                layer.enabled: !root.isFullscreen
                layer.effect: MultiEffect {
                    shadowEnabled: !root.isFullscreen
                    shadowColor: "#50000000"
                    shadowBlur: 1.0
                    shadowVerticalOffset: 12
                }
                
                MouseArea { anchors.fill: parent; onClicked: {} }
                
                // Centered layout when in fullscreen with no lyrics
                readonly property bool centeredMode: root.isFullscreen && root.forceCenteredMode && !root.trackChanging
                
                // Top-left controls row
                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: root.isFullscreen ? 60 : 30
                    spacing: 8
                    z: 100
                    
                    // Player indicator badge (top-left) - clickable for switching
                    Rectangle {
                        id: playerBadge
                        height: 36
                        width: playerRow.width + 24
                        radius: 18
                        color: playerBadgeArea.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
                        visible: root.playerName !== ""
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    
                    Row {
                        id: playerRow
                        anchors.centerIn: parent
                        
                        // ... (unchanged content)
                        
                        spacing: 8
                        
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isSpotify ? "music_note" : "headphones"
                            iconSize: 18
                            color: root.secondaryContentColor
                        }
                        
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.playerName
                            color: root.secondaryContentColor
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.family: "Inter, Segoe UI, sans-serif"
                        }
                        
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.showPlayerPicker ? "expand_less" : "expand_more"
                            iconSize: 14
                            color: root.secondaryContentColor
                            visible: root.availablePlayers.length > 1
                        }
                    }
                    
                    MouseArea {
                        id: playerBadgeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.availablePlayers.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root.availablePlayers.length > 1) {
                                root.showPlayerPicker = !root.showPlayerPicker
                            }
                        }
                    }
                    
                    // Player picker dropdown
                    Item { // Container
                        id: popupContainer
                        anchors.top: parent.bottom
                        anchors.topMargin: 4
                        anchors.left: parent.left
                        width: 180
                        height: playerPickerColumn.height + 12
                        visible: root.showPlayerPicker
                        opacity: root.showPlayerPicker ? 1 : 0
                        
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        
                        // Backdrop Blur
                        ShaderEffectSource {
                            id: blurSource
                            sourceItem: contentLayout
                            // Map this popup's geometry to the source item's coordinate space
                            sourceRect: Qt.rect(
                                mapToItem(contentLayout, 0, 0).x,
                                mapToItem(contentLayout, 0, 0).y,
                                width,
                                height
                            )
                            width: parent.width
                            height: parent.height
                            visible: false
                        }
                        
                        FastBlur {
                            anchors.fill: parent
                            source: blurSource
                            radius: 32
                            transparentBorder: true
                        }
                        
                        // Tint & Border
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.rgba(0.1, 0.1, 0.1, 0.45)
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                            border.width: 1
                        }
                        
                        Column {
                            id: playerPickerColumn
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 6
                            spacing: 2
                            
                            Repeater {
                                model: root.availablePlayers
                                
                                Rectangle {
                                    width: parent.width
                                    height: 32
                                    radius: 8
                                    color: playerItemArea.containsMouse ? Qt.rgba(1,1,1,0.15) : (root.activePlayer === modelData ? Qt.rgba(1,1,1,0.1) : "transparent")
                                    
                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.identity.toLowerCase().includes("spotify") ? "music_note" : "headphones"
                                            iconSize: 16
                                            color: "white"
                                        }
                                        
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.identity || "Unknown Player"
                                            color: "white"
                                            font.pixelSize: 12
                                            font.weight: root.activePlayer === modelData ? Font.Bold : Font.Normal
                                            font.family: "Inter, Segoe UI, sans-serif"
                                        }
                                    }
                                    
                                    // Active indicator
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 6
                                        height: 6
                                        radius: 3
                                        color: root.pillColor
                                        visible: root.activePlayer === modelData
                                    }
                                    
                                    MouseArea {
                                        id: playerItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.switching = true
                                            loadingTimer.restart()
                                            root.selectedPlayer = modelData
                                            root.showPlayerPicker = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }
                    
                    // Lyrics visibility toggle button (fullscreen only)
                    Rectangle {
                        height: 36
                        width: 36
                        radius: 18
                        color: lyricsToggleArea.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
                        visible: root.isFullscreen
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.forceCenteredMode ? "lyrics" : "notes"
                            iconSize: 14
                            color: root.secondaryContentColor
                        }
                        
                        MouseArea {
                            id: lyricsToggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.layoutTransitioning = true
                                layoutTransitionTimer.restart()
                            }
                        }
                    }
                }
                
                RowLayout {
                    id: contentLayout
                    anchors.fill: parent
                    anchors.margins: root.isFullscreen ? 60 : 30
                    opacity: (root.switching || root.layoutTransitioning) ? 0 : 1
                    clip: true // Prevent overflow during layout animations
                    
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                    
                    spacing: root.isFullscreen ? 80 : 40
                    // Center content when no lyrics in fullscreen
                    layoutDirection: lyricsPanel.centeredMode ? Qt.LeftToRight : Qt.LeftToRight


                    // Left spacer for centering in centered mode
                    Item {
                        Layout.fillWidth: lyricsPanel.centeredMode
                        visible: opacity > 0
                    }

                    ColumnLayout {
                        Layout.preferredWidth: lyricsPanel.centeredMode ? 500 : (root.isFullscreen ? 420 : 260)
                        Layout.maximumWidth: lyricsPanel.centeredMode ? 500 : (root.isFullscreen ? 420 : 260)
                        Layout.fillHeight: true
                        spacing: root.isFullscreen ? 24 : 16

                        // Spacer to center content vertically in fullscreen
                        Item { Layout.fillHeight: root.isFullscreen; visible: root.isFullscreen }

                        // Album art item - Much larger in fullscreen (Apple Music style)
                        Item {
                            Layout.preferredWidth: root.isFullscreen ? 380 : 200
                            Layout.preferredHeight: root.isFullscreen ? 380 : 200
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 60 // Push down to avoid overlap with player badge

                            Image {
                                id: albumImage
                                anchors.fill: parent
                                source: root.albumArt
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                                cache: false
                                asynchronous: true
                            }

                            Rectangle {
                                id: maskRect
                                anchors.fill: parent
                                radius: 16
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: albumImage
                                maskSource: maskRect
                                visible: root.albumArt !== "" && !root.artLoading
                            }

                            // Loading indicator
                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: Appearance.m3colors.m3surfaceContainerHighest
                                visible: root.artLoading

                                Text {
                                    anchors.centerIn: parent
                                    text: "Loading..."
                                    color: "white"
                                    font.pixelSize: 14
                                }
                            }

                            // Placeholder
                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: Appearance.m3colors.m3surfaceContainerHighest
                                visible: root.albumArt === "" && !root.artLoading

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "music_note"
                                    iconSize: 64
                                    color: "#888"
                                }
                            }
                        }

                        // Title
                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            // Use MPRIS data directly for display
                            text: root.artLoading ? "Loading..." : (root.displayTitle || "No song playing")
                            color: root.contentColor
                            font.pixelSize: root.isFullscreen ? 28 : 22
                            font.weight: Font.Bold
                            font.family: "Inter, Segoe UI, sans-serif"
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            opacity: root.artLoading ? 0.5 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Artist
                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            // Use MPRIS data directly for display
                            text: root.artLoading ? "..." : (root.displayArtist || "Unknown Artist")
                            color: root.secondaryContentColor
                            font.pixelSize: root.isFullscreen ? 20 : 16
                            font.family: "Inter, Segoe UI, sans-serif"
                            elide: Text.ElideRight
                            opacity: root.artLoading ? 0.5 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }

                        // Flexible spacer - pushes controls to bottom, but shrinks if needed
                        Item { Layout.fillHeight: true }

                        // --- CONTROLS SECTION ---
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Progress Bar
                            Item {
                                id: progressBarContainer
                                Layout.fillWidth: true
                                implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                                Loader {
                                    id: sliderLoader
                                    anchors.fill: parent
                                    active: root.activePlayer?.canSeek ?? false
                                    sourceComponent: StyledSlider {
                                        configuration: root.isPlaying ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
                                        highlightColor: root.contentColor 
                                        trackColor: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                                        handleColor: root.contentColor
                                        value: root.duration > 0 ? root.position / root.duration : 0
                                        onMoved: {
                                            if (root.activePlayer) root.activePlayer.position = value * root.duration;
                                        }
                                    }
                                }

                                Loader {
                                    id: progressBarLoader
                                    anchors {
                                        verticalCenter: parent.verticalCenter
                                        left: parent.left
                                        right: parent.right
                                    }
                                    active: !(root.activePlayer?.canSeek ?? false)
                                    sourceComponent: StyledProgressBar {
                                        wavy: root.isPlaying
                                        highlightColor: root.contentColor
                                        trackColor: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                                        value: root.duration > 0 ? root.position / root.duration : 0
                                    }
                                }
                            }

                            // Time Labels
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: root.formatTime(root.position)
                                    color: root.secondaryContentColor
                                    font.pixelSize: 13
                                    font.family: "Inter, Segoe UI, sans-serif"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.formatTime(root.duration)
                                    color: root.secondaryContentColor
                                    font.pixelSize: 13
                                    font.family: "Inter, Segoe UI, sans-serif"
                                }
                            }

                            // Buttons
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 32

                                    component MediaBtn: RippleButton {
                                        implicitWidth: 48
                                        implicitHeight: 48
                                        buttonRadius: 24
                                        property string iconName
                                        colBackground: "transparent" 
                                        colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
                                        colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                                        contentItem: MaterialSymbol {
                                            iconSize: 28
                                            fill: 1
                                            anchors.centerIn: parent
                                            color: root.contentColor
                                            text: iconName
                                        }
                                    }

                                    MediaBtn {
                                        iconName: "skip_previous"
                                        downAction: () => root.activePlayer?.previous()
                                    }

                                    RippleButton {
                                        implicitWidth: 64
                                        implicitHeight: 64
                                        buttonRadius: root.isPlaying ? 16 : 32
                                        Behavior on buttonRadius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                        downAction: () => root.activePlayer?.togglePlaying()
                                        colBackground: root.isPlaying ? root.contentColor : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
                                        colBackgroundHover: root.isPlaying ? Qt.darker(root.contentColor, 1.1) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                                        colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.3)
                                        contentItem: MaterialSymbol {
                                            iconSize: 36
                                            fill: 1
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: root.isPlaying ? root.backgroundColor : root.contentColor
                                            text: root.isPlaying ? "pause" : "play_arrow"
                                        }
                                    }

                                    MediaBtn {
                                        iconName: "skip_next"
                                        downAction: () => root.activePlayer?.next()
                                    }
                                }
                            }
                        }
                    }
                    

                    
                    // Right spacer for centering in centered mode
                    Item {
                        Layout.fillWidth: lyricsPanel.centeredMode
                        visible: lyricsPanel.centeredMode
                    }
                    
                    // Divider - hidden in fullscreen or centered mode
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 24
                        Layout.bottomMargin: 24
                        color: root.contentColor
                        opacity: 0.15
                        visible: !root.isFullscreen && !lyricsPanel.centeredMode
                    }
                    
                    // Lyrics section - hidden in centered mode
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 350
                        visible: !lyricsPanel.centeredMode
                        
                        
                        // Close button (top-right)
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            width: 32
                            height: 32
                            radius: 16
                            color: closeBtn.containsMouse ? Qt.rgba(1,1,1,0.2) : "transparent"
                            z: 10
                            
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: root.secondaryContentColor
                                font.pixelSize: 16
                                font.weight: Font.Medium
                            }
                            
                            MouseArea {
                                id: closeBtn
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeWindow()
                            }
                        }
                        Item {
                            anchors.fill: parent
                            anchors.topMargin: 48
                            anchors.bottomMargin: 16
                            clip: true

                            // 1. The Morphing Loader
                            // VISIBLE: Only while actively waiting for data
                            Item {
                                id: loaderContainer
                                anchors.centerIn: parent
                                width: 64
                                height: 64
                                visible: root.isPlaying && root.lyricsCount === 0 && !root.lyricsLoaded
                                
                                MaterialCookie {
                                    id: loadingCookie
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    color: root.secondaryContentColor
                                    sides: 12 
                                    Behavior on sides { NumberAnimation { duration: 0 } }
                                }

                                RotationAnimator {
                                    target: loadingCookie
                                    from: 0; to: 360
                                    duration: 2000
                                    loops: Animation.Infinite
                                    running: loaderContainer.visible // Only spin if visible
                                }

                                Timer {
                                    interval: 800
                                    running: loaderContainer.visible // Only morph if visible
                                    repeat: true
                                    triggeredOnStart: true
                                    onTriggered: {
                                        const shapes = [0, 4, 5, 6, 12]
                                        let next = shapes[Math.floor(Math.random() * shapes.length)]
                                        while (next === loadingCookie.sides) {
                                            next = shapes[Math.floor(Math.random() * shapes.length)]
                                        }
                                        loadingCookie.sides = next
                                    }
                                }
                            }

                            // 2. The Status Text
                            // VISIBLE: If we are paused OR if we finished loading and found nothing
                            Text {
                                anchors.centerIn: parent
                                
                                // Dynamic text based on state
                                text: root.isPlaying ? "No lyrics found" : "♪ Play some music ♪"
                                
                                color: root.secondaryContentColor
                                opacity: 0.6
                                font.pixelSize: 18
                                font.family: "Inter, Segoe UI, sans-serif"
                                
                                // Show if lyrics are empty AND (we are not playing OR we are done loading)
                                visible: root.lyricsCount === 0 && (!root.isPlaying || root.lyricsLoaded)
                            }

                            // 3. The Lyrics List
                            ListView {
                                id: lyricsView
                                visible: root.lyricsCount > 0
                                anchors.fill: parent
                                anchors.margins: 16
                                model: lyricsModel
                                spacing: 16
                                clip: true
                                
                                // ... (rest of your existing ListView code) ...


                                
                                // ... (rest of your existing ListView code) ...
                        

                                
                                // ... (rest of your existing ListView code) ...
                                
                                
                                
                                // Manual scroll tracking
                                property bool manualScrollMode: false
                                
                                onFlickStarted: {
                                    manualScrollMode = true
                                    manualScrollTimer.restart()
                                }
                                
                                onDraggingChanged: {
                                    if (dragging) {
                                        manualScrollMode = true
                                        manualScrollTimer.stop()
                                    } else {
                                        manualScrollTimer.restart()
                                    }
                                }
                                
                                // Timer to reset manual mode after inactivity
                                Timer {
                                    id: manualScrollTimer
                                    interval: 3000
                                    onTriggered: lyricsView.manualScrollMode = false
                                }
                                
                                // Function to re-sync to current line
                                function resync() {
                                    manualScrollMode = false
                                    manualScrollTimer.stop()
                                    positionViewAtIndex(root.currentLine, ListView.Center)
                                }
                                
                                // Highlight configuration
                                highlightRangeMode: manualScrollMode ? ListView.NoHighlightRange : ListView.ApplyRange
                                preferredHighlightBegin: height * 0.25
                                preferredHighlightEnd: height * 0.25
                                highlightMoveDuration: root.isResizing ? 0 : 600 
                                highlightResizeDuration: root.isResizing ? 0 : 600// Controls the slide speed (vertical)
                                highlightMoveVelocity: -1
                                
                                // --- NEW: The Sliding Pill ---
                                highlight: Item {
                                    // This Item automatically moves to cover the current lyric line
                                     // Ensure it sits behind text if needed, or adjust delegate z
                                    
                                    Rectangle {
                                        anchors.centerIn: parent
                                        // Match height of delegate minus spacing/padding
                                        height: parent.height - 12
                                        
                                        // Bind width to the specific text width of the current line
                                        width: lyricsView.currentItem ? lyricsView.currentItem.pillWidth : 0
                                        
                                        radius: height / 2
                                        color: root.pillColor
                                        opacity: 1.0
                                        border.color: Qt.rgba(1,1,1,0.1)
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

                                currentIndex: lyricsView.manualScrollMode ? currentIndex : root.currentLine
                                
                                delegate: Item {
                                    id: lyricItem
                                    width: ListView.view.width
                                    height: lyricText.implicitHeight + (isCurrent ? 32 : 16)
                                    
                                    readonly property bool isCurrent: ListView.isCurrentItem
                                    readonly property int distance: Math.abs(index - ListView.view.currentIndex)
                                    
                                    // --- NEW: Expose width for the highlight to read ---
                                    property real pillWidth: Math.min(lyricText.implicitWidth + 48, parent.width - 16)
                                    
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
                                    
                                    Text {
                                        id: lyricText
                                        anchors.centerIn: parent
                                        width: parent.width - 48
                                        horizontalAlignment: Text.AlignHCenter
                                        
                                        // KARAOKE LOGIC
                                        property var wordList: {
                                            if (!model.words) return []
                                            try { return JSON.parse(model.words) } catch(e) { return [] }
                                        }

                                        textFormat: (lyricItem.isCurrent && wordList && wordList.length > 0) ? Text.RichText : Text.PlainText
                                        
                                        text: {
                                            if (lyricItem.isCurrent && wordList && wordList.length > 0) {
                                                // Trigger update on position change
                                                const pos = root.activePlayer ? root.activePlayer.position : 0
                                                const activeColor = root.pillContentColor.toString()
                                                const inactiveColor = Qt.rgba(root.pillContentColor.r, root.pillContentColor.g, root.pillContentColor.b, 0.5).toString()
                                                
                                                let html = ""
                                                for (let i = 0; i < wordList.length; i++) {
                                                    let w = wordList[i]
                                                    let c = (pos >= w.time) ? activeColor : inactiveColor
                                                    html += `<font color="${c}">${w.text}</font> `
                                                }
                                                return html
                                            }
                                            return model.text
                                        }

                                        z:2
                                        
                                        // Color logic for plain text mode (fallback)
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
                                anchors.bottomMargin: lyricsView.manualScrollMode ? 20 : -60
                                width: 140
                                height: 44
                                radius: 22
                                color: root.pillColor
                                opacity: lyricsView.manualScrollMode ? 1.0 : 0
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
                                    
                                    Text {
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
                }
            }
        }
    }
}
 
