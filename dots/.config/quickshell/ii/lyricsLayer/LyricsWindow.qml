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
import "./components"

Scope {
    id: root
    property bool showLyrics: LyricsService.open
    property bool closing: false
    property bool isFullscreen: false
    property bool isResizing: false

    property bool lyricsLoaded: false
    property bool isRecognizing: false
    
    // Use native MPRIS for UI updates only (art, progress)
    readonly property var availablePlayers: MprisController.players
    property MprisPlayer selectedPlayer: null
    readonly property MprisPlayer activePlayer: selectedPlayer ? selectedPlayer : MprisController.activePlayer

    property real position: 0
    
    Connections {
        target: root.activePlayer || null
        ignoreUnknownSignals: true
        function onPositionChanged() {
            var diff = Math.abs(root.position - root.activePlayer.position)
            // Fix: Tighter sync threshold (0.5s instead of 1.5s) to correct drift sooner
            if (diff > 0.5 || !root.isPlaying) {
                root.position = root.activePlayer.position
            }
        }
    }
    
    Timer {
        running: root.isPlaying
        interval: 50 // Fix: 50ms interval matches 0.05 increment for smoother, more accurate updates
        repeat: true
        onTriggered: root.position += 0.05
    }
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

    Timer {
        id: lyricsLoadTimeout
        interval: 3000 // 3 seconds timeout
        running: root.isPlaying && root.lyricsCount === 0 && !root.lyricsLoaded
        onTriggered: {
            console.log("[Lyrics] Load timed out, forcing loaded state")
            root.lyricsLoaded = true
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
    
    // FIX: Track artUrl separately as string to avoid null/undefined issues
    // FIX: Track artUrl separately as string
    property string artUrl: (activePlayer && activePlayer.trackArtUrl) ? activePlayer.trackArtUrl : ""
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${Directories.coverArt}/${artFileName}`
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
            // Art download handled by onArtUrlChanged now to prevent race conditions
        }
    }
    
    property string artDownloadLocation: Directories.coverArt // Compat
    
    // MediaPage Logic

    property bool downloaded: false
    property string displayedArtFilePath: downloaded ? Qt.resolvedUrl(artFilePath) : ""
    
    // UI Compatibility Aliases
    readonly property string albumArt: displayedArtFilePath
    readonly property bool artDownloaded: downloaded
    readonly property bool artLoading: !downloaded && artUrl.length > 0
    
    // Trigger download when path changes (MediaPage Logic)
    onArtFilePathChanged: {
        if (root.artUrl.length == 0) return
        
        console.log("[Lyrics] artFilePath changed, triggering download")
        
        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        
        root.downloaded = false
        coverArtDownloader.running = true
    }
    
    // Cleanup other state variables/functions
    property int lyricsCount: 0
    property int currentLine: -1
    property int colorUpdateTrigger: 0
    property string currentSongTitle: "" 
    
    // Color extraction from album art
    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }
    
    // Extract dominant color or use default
    readonly property color extractedColor: {
        if (!downloaded || displayedArtFilePath.length === 0) {
            return Appearance.colors.colPrimary
        }
        let c = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary
        return c
    }
    
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.extractedColor, Appearance.colors.colPrimaryContainer, 0.8)
    }
    
    // Source colors (change instantly when track changes)
    readonly property color _srcBackgroundColor: blendedColors.colLayer0
    readonly property color _srcContentColor: blendedColors.colOnLayer0
    readonly property color _srcSecondaryContentColor: blendedColors.colSubtext
    readonly property color _srcPillColor: blendedColors.colSecondaryContainer
    readonly property color _srcPillContentColor: blendedColors.colOnSecondaryContainer
    
    // Animated colors (smooth transitions over 800ms)
    property color backgroundColor: _srcBackgroundColor
    property color contentColor: _srcContentColor
    property color secondaryContentColor: _srcSecondaryContentColor
    property color pillColor: _srcPillColor
    property color pillContentColor: _srcPillContentColor
    
    // Smooth color transition behaviors
    Behavior on backgroundColor { 
        ColorAnimation { 
            duration: 800
            easing.type: Easing.OutCubic
        } 
    }
    Behavior on contentColor { 
        ColorAnimation { 
            duration: 800
            easing.type: Easing.OutCubic
        } 
    }
    Behavior on secondaryContentColor { 
        ColorAnimation { 
            duration: 800
            easing.type: Easing.OutCubic
        } 
    }
    Behavior on pillColor { 
        ColorAnimation { 
            duration: 800
            easing.type: Easing.OutCubic
        } 
    }
    Behavior on pillContentColor { 
        ColorAnimation { 
            duration: 800
            easing.type: Easing.OutCubic
        } 
    }
    
    // Debug logging for art state
    onArtLoadingChanged: console.log("[Lyrics] State: artLoading =", artLoading)
    onArtDownloadedChanged: console.log("[Lyrics] State: artDownloaded =", artDownloaded)
    
    // FIX: Clean titles on frontend too
    readonly property string cleanDisplayTitle: {
        let title = displayTitle
        if (!title) return ""
        const suffixes = [" - YouTube Music", " - YouTube", " (Official Video)", " (Official Audio)"]
        for (let i = 0; i < suffixes.length; i++) {
            if (title.endsWith(suffixes[i])) {
                title = title.substring(0, title.length - suffixes[i].length)
            }
        }
        return title
    }
    
    // Reset on title change handler removed - redundant or causing conflicts
    // State clearing is handled in onArtUrlChanged and parseUpdate logic

    Component.onCompleted: {
        // Initial Art Download Trigger
        if (artUrl && artUrl.length > 0) {
            console.log("[Lyrics] Startup art download trigger:", artUrl)
            // This will trigger onArtFilePathChanged if artFilePath is derived
            // and different from its initial empty state.
        }
        
        // Initial Position Sync
        if (root.activePlayer) {
            root.position = root.activePlayer.position
        }
    }
    
    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        
        // EXACT command from MediaPage - simple and reliable
        command: [ "bash", "-c", `[ -f '${artFilePath}' ] || curl -sSL '${targetFile}' -o '${artFilePath}'` ]
        
        onExited: (exitCode, exitStatus) => {
            console.log("[Lyrics] Download process exited. Code:", exitCode)
            root.downloaded = true
        }
    }
    
    function parseUpdate(data) {
        if (!data) return
        
        // Update parsing status
        isRecognizing = !!data.recognizing
        
        // Update lyrics if changed
        if (data.lyrics) {
            var newLyrics = data.lyrics
            
            // Handle explicitly empty lyrics (backend confirms no lyrics found)
            if (newLyrics.length === 0) {
                 lyricsLoaded = true
                 // Only clear if we had lyrics before
                 if (lyricsModel.count > 0) {
                     lyricsModel.clear()
                     lyricsCount = 0
                 }
            } else {
                // Update if count changed or first/last line different (simple checksum-ish)
                var currentCount = lyricsModel.count
                var needsUpdate = (newLyrics.length !== currentCount)
                
                if (!needsUpdate && newLyrics.length > 0 && currentCount > 0) {
                    // Check first and middle line text to ensure content is same
                    if (lyricsModel.get(0).text !== newLyrics[0].text) needsUpdate = true
                }
                
                if (needsUpdate) {
                    // console.log("[LyricsWindow] Updating lyrics model with", newLyrics.length, "lines")
                    
                    // FIX: Set state flags FIRST to prevent UI flicker
                    lyricsCount = newLyrics.length
                    lyricsLoaded = true
                    
                    lyricsModel.clear()
                    for (var i = 0; i < newLyrics.length; i++) {
                        var line = newLyrics[i]
                        var wordsJson = line.words ? JSON.stringify(line.words) : "[]"
                        lyricsModel.append({
                            "time": line.time,
                            "text": line.text,
                            "words": wordsJson
                        })
                    }
                    
                    // If we just loaded lyrics, scroll to current line immediately
                    if (typeof lyricsView !== "undefined" && lyricsView && currentLine >= 0 && currentLine < lyricsCount) {
                        // handled by component but we can't access lyricsView directly here by ID if it's inside Component
                        // Actually, I gave LyricsView id 'lyricsViewComponent' or similar in below code
                        // But I can't access children easily.
                        // However, I added binding to onLyricsLoadedChanged inside LyricsView.
                    }
                }
            }
        }
        
        // Update current line
        if (data.currentLine !== undefined && data.currentLine !== currentLine) {
            currentLine = data.currentLine
            // Auto-scroll logic handled inside LyricsView via currentLine binding
        }
        
        // Update tracked info
        cleanedTitle = data.song || ""
        artist = data.artist || ""
    }
    
    property ListModel lyricsModel: ListModel { id: lyricsModel }
    
    function toggle() {
        LyricsService.toggle()
    }

    function closeWindow() {
        if (root.showLyrics) {
            closing = true
            LyricsService.open = false
            isFullscreen = false
        }
    }
    
    function toggleFullscreen() {
        isFullscreen = !isFullscreen
    }

    IpcHandler {
        target: "lyrics"
        function toggle() { 
            console.log("[LyricsWindow] Received toggle IPC signal!")
            LyricsService.toggle() 
        }
        function open() { 
            console.log("[LyricsWindow] Received open IPC signal!")
            LyricsService.open = true 
        }
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
                        let b64 = parts.slice(2).join(":") // Handle colons in base64
                        
                        try {
                            let json = Qt.atob(b64)
                            let data = JSON.parse(json)
                            
                            // Get active player identity for matching
                            // MprisPlayer.identity is the display name like "Spotify"
                            // playerctl uses names like "spotify" or "kdeconnect.mpris_xxx"
                            let activeIdentity = (root.activePlayer?.identity || "").toLowerCase()
                            let backendIdentity = identity.toLowerCase()
                            
                            // Match by player identity (primary method when multiple players)
                            let isIdentityMatch = (
                                backendIdentity === activeIdentity ||
                                backendIdentity.includes(activeIdentity) ||
                                activeIdentity.includes(backendIdentity) ||
                                // Handle KDE Connect: "kdeconnect.mpris_xxx" vs "Metrolist - RMX3771"
                                (backendIdentity.includes("kdeconnect") && activeIdentity.includes("metrolist")) ||
                                (backendIdentity.includes("kdeconnect") && activeIdentity.includes("rmx")) ||
                                // Handle common cases
                                (backendIdentity.includes("spotify") && activeIdentity.includes("spotify"))
                            )
                            
                            // Fallback: Match by song info if identity matching fails
                            if (!isIdentityMatch) {
                                let updateSong = (data.song || "").toLowerCase().trim()
                                let updateArtist = (data.artist || "").toLowerCase().trim()
                                let frontendSong = root.cleanDisplayTitle.toLowerCase().trim()
                                let frontendArtist = root.displayArtist.toLowerCase().trim()
                                
                                isIdentityMatch = (
                                    (updateSong === frontendSong && updateSong !== "") ||
                                    (updateSong && frontendSong && (updateSong.includes(frontendSong) || frontendSong.includes(updateSong))) ||
                                    (updateArtist === frontendArtist && updateArtist !== "" && updateSong !== "" && frontendSong !== "")
                                )
                            }
                            
                            if (isIdentityMatch) {
                                root.parseUpdate(data)
                            } 
                        } catch(e) { 
                            console.log("Lyrics parse error:", e) 
                        }
                    }
                }
            }
        }
        
        stderr: SplitParser {
            onRead: (line) => console.log(line)
        }
        
        onExited: (exitCode, exitStatus) => {
            console.log("[LyricsWindow] Backend exited with code", exitCode, "- Restarting in 1s...")
            restartTimer.start()
        }
    }
    
    Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            console.log("[LyricsWindow] Restarting backend...")
            backend.running = true
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

            IdleInhibitor {
                enabled: root.isFullscreen
                window: window
            }
            
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
            
            BackgroundBlur {
                anchors.fill: lyricsPanel
                albumArt: root.albumArt
                showLyrics: root.showLyrics
                backgroundColor: root.backgroundColor
                cornerRadius: lyricsPanel.radius
                
                transform: Translate {
                    y: root.showLyrics ? 0 : -(lyricsPanel.y + lyricsPanel.height + 100)
                    Behavior on y {
                        NumberAnimation {
                            duration: root.showLyrics ? 600 : 350
                            easing.type: root.showLyrics ? Easing.OutCubic : Easing.InCubic
                        }
                    }
                }
            }
            
            Rectangle {
                id: lyricsPanel
                anchors.horizontalCenter: parent.horizontalCenter
                
                // Calculate target positions/sizes to avoid animation timing issues
                readonly property real floatingHeight: Math.min(parent.height * 0.8, 650)
                readonly property real floatingY: (parent.height - floatingHeight) / 2
                
                y: root.isFullscreen ? 0 : floatingY
                width: root.isFullscreen ? parent.width : Math.min(parent.width * 0.75, 900)
                height: root.isFullscreen ? parent.height : floatingHeight
                radius: root.isFullscreen ? 0 : 24
                color: root.backgroundColor
                clip: true
                
                Behavior on color { ColorAnimation { duration: 400 } }
                
                // Position animation for Fullscreen <-> Windowed transition
                Behavior on y {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutCubic
                    }
                }

                // Slide Open/Close Animation using Transform (Cheaper than animating Y)
                transform: Translate {
                    y: root.showLyrics ? 0 : -(lyricsPanel.y + lyricsPanel.height + 100)
                    
                    Behavior on y {
                        NumberAnimation {
                            duration: root.showLyrics ? 600 : 350
                            easing.type: root.showLyrics ? Easing.OutCubic : Easing.InCubic
                            onRunningChanged: {
                                if (!running && !root.showLyrics) root.closing = false
                            }
                        }
                    }
                }
                
                // Fullscreen transition animations
                Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic; onRunningChanged: root.isResizing = running } }
                Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                
                // Optimize: Disable shadow during resize to prevent heavy repaint
                layer.enabled: !root.isFullscreen && !root.isResizing
                layer.effect: MultiEffect {
                    shadowEnabled: !root.isFullscreen
                    shadowColor: "#50000000"
                    shadowBlur: 1.0
                    shadowVerticalOffset: 12
                }
                
                MouseArea { anchors.fill: parent; onClicked: {} }
                
                // Centered layout when in fullscreen with no lyrics
                readonly property bool centeredMode: root.isFullscreen && root.forceCenteredMode && !root.trackChanging
                
                // Top-left controls row (PlayerBadge)
                PlayerBadge {
                    id: playerBadge
                    playerName: root.playerName
                    isSpotify: root.isSpotify
                    activePlayer: root.activePlayer
                    availablePlayers: root.availablePlayers
                    contentColor: root.contentColor
                    secondaryContentColor: root.secondaryContentColor
                    pillContentColor: root.pillContentColor
                    pillColor: root.pillColor
                    
                    showPlayerPicker: root.showPlayerPicker
                    isFullscreen: root.isFullscreen
                    forceCenteredMode: root.forceCenteredMode
                    
                    onTogglePicker: root.showPlayerPicker = !root.showPlayerPicker
                    
                    onPlayerSelected: (player) => {
                        root.switching = true
                        loadingTimer.restart()
                        root.selectedPlayer = player
                        root.showPlayerPicker = false
                    }
                    
                    onModeToggled: {
                        root.layoutTransitioning = true
                        layoutTransitionTimer.restart()
                    }
                    
                    onSwitchingStarted: {
                         root.switching = true
                         loadingTimer.restart()
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

                    MediaControls {
                         isFullscreen: root.isFullscreen
                         centeredMode: lyricsPanel.centeredMode
                         
                         albumArt: root.albumArt
                         artLoading: root.artLoading
                         
                         displayTitle: root.displayTitle
                         displayArtist: root.displayArtist
                         
                         contentColor: root.contentColor
                         secondaryContentColor: root.secondaryContentColor
                         pillColor: root.pillColor
                         pillContentColor: root.pillContentColor
                         
                         activePlayer: root.activePlayer
                         isPlaying: root.isPlaying
                         duration: root.duration
                         position: root.position
                         
                         onSeek: (seconds) => {
                             if (root.activePlayer) root.activePlayer.position = seconds
                             root.position = seconds
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
                    LyricsView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 350
                        visible: !lyricsPanel.centeredMode
                        
                        isFullscreen: root.isFullscreen
                        contentColor: root.contentColor
                        secondaryContentColor: root.secondaryContentColor
                        pillColor: root.pillColor
                        pillContentColor: root.pillContentColor
                        
                        activePlayer: root.activePlayer
                        lyricsModel: root.lyricsModel
                        lyricsCount: root.lyricsCount
                        isRecognizing: root.isRecognizing
                        isPlaying: root.isPlaying
                        lyricsLoaded: root.lyricsLoaded
                        currentLine: root.currentLine
                        isResizing: root.isResizing
                        
                        onFullscreenToggled: root.toggleFullscreen()
                        onCloseRequested: root.closeWindow()
                    }
                }
            }
        }
    }
}
