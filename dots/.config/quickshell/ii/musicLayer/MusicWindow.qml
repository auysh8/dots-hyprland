import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.modules.common.widgets
import qs.modules.common
import qs.services
import Qt5Compat.GraphicalEffects
import qs.modules.common.models
import qs.modules.common.functions
import "./components"

Scope {
    id: root
    
    property bool showMusic: MusicService.open
    property bool closing: false

    Timer {
        id: closeFallbackTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (!root.showMusic) {
                root.closing = false
            }
        }
    }

    onShowMusicChanged: {
        if (showMusic) {
            closing = false
            closeFallbackTimer.stop()
            if (homeContent.count === 0) getHome()
        } else if (closing) {
            closeFallbackTimer.restart()
        }
    }
    
    property ListModel searchResults: ListModel {} // Legacy/General
    property ListModel artistResults: ListModel {}
    property ListModel songResults: ListModel {}
    property ListModel albumResults: ListModel {}
    property ListModel searchSuggestions: ListModel {}
    
    property ListModel homeContent: ListModel {}
    property ListModel quickPicks: ListModel {}
    property ListModel shortsContent: ListModel {}
    
    property ListModel exploreNewReleases: ListModel {}
    property ListModel exploreTrending: ListModel {}
    
    // Library View Models
    property ListModel libraryPlaylists: ListModel {}
    property ListModel libraryRecentTracks: ListModel {}
    property ListModel libraryCommunityPlaylists: ListModel {}
    property int libraryLikedSongCount: 0
    property string libraryLikedSongArt: ""
    
    // Shared layer transition offset for both panel and background.
    readonly property real panelHiddenOffset: -(musicPanel.y + musicPanel.height + 100)
    property bool isLoading: true
    property bool refreshing: false
    property var currentTrack: null
    property bool isTrackLoading: false
    property bool playbackPaused: false
    property string currentView: "home"
    property string lastSearchQuery: ""
    property int searchVisibleSongCount: 5
    property int searchSongPrefetchLimit: 20
    property bool searchSongsHasMore: false
    property var cachedSongResults: []
    property bool suppressSuggestionResponses: false
    
    function sendCommand(cmdObject) {
        backend.write(JSON.stringify(cmdObject) + "\n")
    }
    
    function getHome() {
        isLoading = true
        sendCommand({ "command": "get_home" })
    }

    function getExplore() {
        isLoading = true
        sendCommand({ "command": "get_explore" })
    }
    
    function applyVisibleSongResults() {
        root.songResults.clear()
        const visibleCount = Math.min(root.searchVisibleSongCount, root.cachedSongResults.length)
        for (let i = 0; i < visibleCount; i++) {
            root.songResults.append(root.cachedSongResults[i])
        }
        root.searchSongsHasMore = root.cachedSongResults.length > visibleCount
    }

    function search(query) {
        const trimmed = query.trim()
        if (trimmed === "") return
        root.lastSearchQuery = trimmed
        root.searchVisibleSongCount = 5
        root.suppressSuggestionResponses = true

        isLoading = true
        artistResults.clear()
        songResults.clear()
        albumResults.clear()
        cachedSongResults = []
        searchSongsHasMore = false
        searchSuggestions.clear() // Clear suggestions on search
        sendCommand({
            "command": "search",
            "query": trimmed,
            "songLimit": root.searchSongPrefetchLimit
        })
    }

    function loadMoreSongs() {
        if (root.cachedSongResults.length === 0) return
        root.searchVisibleSongCount = Math.min(root.cachedSongResults.length, root.searchVisibleSongCount + 10)
        root.applyVisibleSongResults()
    }

    function playTrack(videoId, title, artist, artUrl) {
        root.currentTrack = {
            videoId: videoId,
            title: title,
            artist: artist,
            artUrl: artUrl
        }
        root.isTrackLoading = true
        sendCommand({
            "command": "play",
            "videoId": videoId,
            "title": title,
            "artist": artist,
            "artUrl": artUrl
        })
    }
    
    function toggle() {
        MusicService.toggle()
    }

    function closeWindow() {
        if (!root.showMusic && !root.closing) return
        closing = true
        MusicService.open = false
        closeFallbackTimer.restart()
    }

    function activeContentFlickable() {
        if (searchInput.text.length > 0 && searchView.visible)
            return searchView.flickable
        if (root.currentView === "explore" && exploreView.visible)
            return exploreView.flickable
        if (root.currentView === "home" && homeView.visible)
            return homeView.flickable
        return null
    }

    function forwardWheelEvent(event) {
        const flick = activeContentFlickable()
        if (!flick) {
            event.accepted = false
            return
        }

        const angleY = event.angleDelta ? event.angleDelta.y : 0
        const pixelY = event.pixelDelta ? event.pixelDelta.y : 0
        if (angleY === 0 && pixelY === 0) {
            event.accepted = false
            return
        }

        const threshold = flick.mouseScrollDeltaThreshold ?? 120
        const mouseFactor = flick.mouseScrollFactor ?? 50
        const touchpadFactor = flick.touchpadScrollFactor ?? 100
        const unitDelta = angleY !== 0 ? (angleY / threshold) : (pixelY / 15)
        const scrollFactor = Math.abs(angleY) >= threshold ? mouseFactor : touchpadFactor

        const maxY = Math.max(0, flick.contentHeight - flick.height)
        const baseY = (flick.scrollTargetY !== undefined) ? flick.scrollTargetY : flick.contentY
        const targetY = Math.max(0, Math.min(baseY - (unitDelta * scrollFactor), maxY))

        flick.scrollTargetY = targetY
        flick.contentY = targetY
        event.accepted = true
    }
    
    IpcHandler {
        target: "music"
        function toggle() { MusicService.toggle() }
    }
    
    property string artUrl: currentTrack ? currentTrack.artUrl : ""
    property string artLocalPath: (currentTrack && currentTrack.artLocalPath) ? currentTrack.artLocalPath : ""
    
    // Use the backend-provided local path if available, fallback to remote URL otherwise.
    property string displayedArtFilePath: artLocalPath !== "" ? "file://" + artLocalPath : artUrl
    
    // Ensure ColorQuantizer triggers properly when art changes
    onDisplayedArtFilePathChanged: {
        console.log("[MusicWindow] Displayed art file path changed:", displayedArtFilePath)
    }
    
    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }
    
    readonly property color extractedColor: {
        if (!root.currentTrack || !root.currentTrack.artUrl) {
            return Appearance.colors.colPrimary
        }
        let c = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary
        return c
    }
    
    property QtObject blendedColors: QtObject {
        property bool isPlaying: root.currentTrack && root.currentTrack.artUrl
        property color accent: isPlaying ? root.extractedColor : Appearance.m3colors.m3primary
        
        // Dynamically shift hue and saturation to match the album art perfectly, 
        // while preserving the exact lightness levels of the system's Material 3 theme!
        property color colLayer0: isPlaying 
            ? ColorUtils.mix(ColorUtils.adaptToAccent(Appearance.m3colors.m3background, accent), Appearance.m3colors.m3background, 0.5) 
            : Appearance.m3colors.m3background
            
        property color colSurface: isPlaying 
            ? ColorUtils.mix(ColorUtils.adaptToAccent(Appearance.m3colors.m3surfaceContainerLow, accent), Appearance.m3colors.m3surfaceContainerLow, 0.5) 
            : Appearance.m3colors.m3surfaceContainerLow
            
        property color colSecondaryContainer: isPlaying 
            ? ColorUtils.mix(ColorUtils.adaptToAccent(Appearance.m3colors.m3surfaceContainerHigh, accent), Appearance.m3colors.m3surfaceContainerHigh, 0.6) 
            : Appearance.m3colors.m3surfaceContainerHigh
            
        // Text gets a very subtle (15%) tonal shift to blend gracefully without losing pure contrast
        property color colOnLayer0: isPlaying 
            ? ColorUtils.mix(ColorUtils.adaptToAccent(Appearance.m3colors.m3onSurface, accent), Appearance.m3colors.m3onSurface, 0.15) 
            : Appearance.m3colors.m3onSurface
            
        property color colSubtext: isPlaying 
            ? ColorUtils.mix(ColorUtils.adaptToAccent(Appearance.colors.colSubtext, accent), Appearance.colors.colSubtext, 0.15) 
            : Appearance.colors.colSubtext
            
        property color colOnSecondaryContainer: isPlaying 
            ? ColorUtils.mix(ColorUtils.adaptToAccent(Appearance.m3colors.m3onSurface, accent), Appearance.m3colors.m3onSurface, 0.15) 
            : Appearance.m3colors.m3onSurface
    }
    
    readonly property color _srcBackgroundColor: blendedColors.colLayer0
    readonly property color _srcContentColor: blendedColors.colOnLayer0
    readonly property color _srcSecondaryContentColor: blendedColors.colSubtext
    readonly property color _srcPillColor: blendedColors.colSecondaryContainer
    readonly property color _srcPillContentColor: blendedColors.colOnSecondaryContainer
    readonly property color _srcSurfaceColor: blendedColors.colSurface
    
    property color backgroundColor: _srcBackgroundColor
    property color contentColor: _srcContentColor
    property color secondaryContentColor: _srcSecondaryContentColor
    property color pillColor: _srcPillColor
    property color pillContentColor: _srcPillContentColor
    property color surfaceColor: _srcSurfaceColor
    
    Behavior on backgroundColor { ColorAnimation { duration: blendedColors.isPlaying ? 800 : 350; easing.type: Easing.OutCubic } }
    Behavior on contentColor { ColorAnimation { duration: blendedColors.isPlaying ? 800 : 350; easing.type: Easing.OutCubic } }
    Behavior on secondaryContentColor { ColorAnimation { duration: blendedColors.isPlaying ? 800 : 350; easing.type: Easing.OutCubic } }
    Behavior on pillColor { ColorAnimation { duration: blendedColors.isPlaying ? 800 : 350; easing.type: Easing.OutCubic } }
    Behavior on pillContentColor { ColorAnimation { duration: blendedColors.isPlaying ? 800 : 350; easing.type: Easing.OutCubic } }
    Behavior on surfaceColor { ColorAnimation { duration: blendedColors.isPlaying ? 800 : 350; easing.type: Easing.OutCubic } }
    
    Process {
        id: backend
        running: true
        stdinEnabled: true
        command: [Qt.resolvedUrl("venv/bin/python3").toString().replace("file://", ""), Qt.resolvedUrl("music_backend.py").toString().replace("file://", "")]
        
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    let data = JSON.parse(line)
                    // console.log("[MusicBackend]", line)
                    
                    if (data.type === "ready") {
                        root.getHome()
                    } else if (data.type === "suggestions") {
                        if (root.suppressSuggestionResponses) {
                            return
                        }
                        root.searchSuggestions.clear()
                        let results = data.results || []
                        for (let i = 0; i < results.length; i++) {
                            root.searchSuggestions.append({ "text": results[i] })
                        }
                    } else if (data.type === "search_results") {
                        root.isLoading = false
                        root.refreshing = false
                        root.artistResults.clear()
                        root.songResults.clear()
                        root.albumResults.clear()
                        root.lastSearchQuery = data.query || root.lastSearchQuery
                        
                        let artists = data.artists || []
                        let songs = data.songs || []
                        let albums = data.albums || []
                        root.cachedSongResults = songs
                        
                        for (let i = 0; i < artists.length; i++) root.artistResults.append(artists[i])
                        for (let i = 0; i < albums.length; i++) root.albumResults.append(albums[i])
                        root.applyVisibleSongResults()
                        
                    } else if (data.type === "home_section") {
                        root.isLoading = false
                        root.refreshing = false
                        let items = data.items || []
                        if (data.section === "recommendations") {
                            root.homeContent.clear()
                            for (let i = 0; i < items.length; i++) root.homeContent.append(items[i])
                        } else if (data.section === "quick_picks") {
                            root.quickPicks.clear()
                            for (let i = 0; i < items.length; i++) root.quickPicks.append(items[i])
                        } else if (data.section === "shorts") {
                            root.shortsContent.clear()
                            for (let i = 0; i < items.length; i++) root.shortsContent.append(items[i])
                        }
                    } else if (data.type === "home_content") {
                        root.isLoading = false
                        root.refreshing = false
                        root.homeContent.clear()
                        root.quickPicks.clear()
                        root.shortsContent.clear()
                        
                        let recs = data.recommendations || data.results || []
                        let picks = data.quick_picks || []
                        let shorts = data.shorts_content || []
                        
                        console.log("[MusicWindow] Home Content - Recs:", recs.length, "Picks:", picks.length, "Shorts:", shorts.length)
                        
                        for (let i = 0; i < recs.length; i++) {
                            root.homeContent.append(recs[i])
                        }
                        for (let i = 0; i < picks.length; i++) {
                            root.quickPicks.append(picks[i])
                        }
                        for (let i = 0; i < shorts.length; i++) {
                            root.shortsContent.append(shorts[i])
                        }
                    } else if (data.type === "explore_section") {
                        root.isLoading = false
                        root.refreshing = false
                        let items = data.items || []
                        if (data.section === "trending") {
                            root.exploreTrending.clear()
                            for (let i = 0; i < items.length; i++) root.exploreTrending.append(items[i])
                        } else if (data.section === "new_releases") {
                            root.exploreNewReleases.clear()
                            for (let i = 0; i < items.length; i++) root.exploreNewReleases.append(items[i])
                        }
                    } else if (data.type === "error") {
                        root.isLoading = false
                        root.refreshing = false
                        root.isTrackLoading = false
                        console.error("[MusicBackend] Error:", data.message)
                    } else if (data.type === "playback_started") {
                        root.isTrackLoading = false
                        root.currentTrack = {
                            videoId: data.videoId,
                            title: data.title,
                            artist: data.artist,
                            artUrl: data.artUrl,
                            artLocalPath: data.artLocalPath || ""
                        }
                        root.playbackPaused = false
                    } else if (data.type === "playback_stopped") {
                        if (!root.isTrackLoading) {
                            root.currentTrack = null
                        }
                        root.playbackPaused = false
                    } else if (data.type === "playback_paused") {
                        root.playbackPaused = true
                    } else if (data.type === "playback_resumed") {
                        root.playbackPaused = false
                    }
                } catch(e) { 
                    console.log("[MusicBackend] Parse Error on line:", line) 
                }
            }
        }
        
        stderr: SplitParser {
            onRead: (line) => console.log("[MusicBackend ERR]", line)
        }
    }
    
    Variants {
        model: Quickshell.screens
        
        LayerManagedPanelWindow {
            required property var modelData
            screen: modelData
            shown: root.showMusic
            closing: root.closing
            layerNamespace: "music-layer"
            onCloseRequested: root.closeWindow()

            MouseArea {
                anchors.fill: parent
                enabled: root.showMusic
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: root.closeWindow()
            }
            
            BackgroundBlur {
                anchors.fill: musicPanel
                albumArt: root.displayedArtFilePath
                showLyrics: root.showMusic
                backgroundColor: root.backgroundColor
                cornerRadius: musicPanel.radius
                
                transform: Translate {
                    y: root.showMusic ? 0 : root.panelHiddenOffset
                    Behavior on y {
                        NumberAnimation {
                            duration: root.showMusic ? 600 : 350
                            easing.type: root.showMusic ? Easing.OutCubic : Easing.InCubic
                        }
                    }
                }
            }
            
            Rectangle {
                id: musicPanel
                anchors.horizontalCenter: parent.horizontalCenter
                
                readonly property real floatingHeight: Math.min(parent.height * 0.85, 800)
                readonly property real floatingY: (parent.height - floatingHeight) / 2
                
                y: floatingY
                width: Math.min(parent.width * 0.7, 1100)
                height: floatingHeight
                radius: 32
                color: "transparent"
                clip: true
                
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#50000000"
                    shadowBlur: 1.0
                    shadowVerticalOffset: 12
                }
                
                transform: Translate {
                    y: root.showMusic ? 0 : root.panelHiddenOffset
                    Behavior on y {
                        NumberAnimation {
                            duration: root.showMusic ? 600 : 350
                            easing.type: root.showMusic ? Easing.OutCubic : Easing.InCubic
                            onRunningChanged: {
                                if (!running && !root.showMusic) {
                                    root.closing = false
                                    closeFallbackTimer.stop()
                                }
                            }
                        }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    scrollGestureEnabled: false
                    onClicked: {}
                }
                
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: musicPanel.width
                            height: musicPanel.height
                            radius: musicPanel.radius
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: root.backgroundColor
                        opacity: 0.85
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                    
                    // Sidebar
                    Item {
                        Layout.preferredWidth: navRail.expanded ? 150 : 80
                        Layout.fillHeight: true
                        
                        Behavior on Layout.preferredWidth {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        
                        Item {
                            anchors.fill: parent
                            
                            NavigationRail {
                                id: navRail
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    horizontalCenter: parent.horizontalCenter
                                    topMargin: 20
                                }
                                expanded: false
                                spacing: 10
                                
                                NavigationRailExpandButton {
                                    focus: root.visible
                                }
                                
                                NavigationRailTabArray {
                                    currentIndex: root.currentView === "home" ? 0 : root.currentView === "explore" ? 1 : 2
                                    expanded: navRail.expanded
                                    Layout.topMargin: 0
                                    useOverrideColors: true
                                    overridePillColor: root.pillColor
                                    
                                    NavigationRailButton {
                                        toggled: root.currentView === "home"
                                        onPressed: root.currentView = "home"
                                        expanded: navRail.expanded
                                        buttonIcon: "home"
                                        buttonText: "Home"
                                        showToggledHighlight: true
                                        useOverrideColors: true
                                        overrideActiveColor: root.pillColor
                                        overrideActiveHoverColor: Qt.lighter(root.pillColor, 1.15)
                                        overrideIconColor: root.pillContentColor
                                        overrideTextColor: root.contentColor
                                    }
                                    NavigationRailButton {
                                        toggled: root.currentView === "explore"
                                        onPressed: {
                                            root.currentView = "explore"
                                            if (root.exploreNewReleases.count === 0 && root.exploreTrending.count === 0) {
                                                root.getExplore()
                                            }
                                        }
                                        expanded: navRail.expanded
                                        buttonIcon: "explore"
                                        buttonText: "Explore"
                                        showToggledHighlight: true
                                        useOverrideColors: true
                                        overrideActiveColor: root.pillColor
                                        overrideActiveHoverColor: Qt.lighter(root.pillColor, 1.15)
                                        overrideIconColor: root.pillContentColor
                                        overrideTextColor: root.contentColor
                                    }
                                    NavigationRailButton {
                                        toggled: root.currentView === "library"
                                        onPressed: root.currentView = "library"
                                        expanded: navRail.expanded
                                        buttonIcon: "library_music"
                                        buttonText: "Library"
                                        showToggledHighlight: true
                                        useOverrideColors: true
                                        overrideActiveColor: root.pillColor
                                        overrideActiveHoverColor: Qt.lighter(root.pillColor, 1.15)
                                        overrideIconColor: root.pillContentColor
                                        overrideTextColor: root.contentColor
                                    }
                                }
                                
                                Item { Layout.fillHeight: true } // Push array to top
                            }
                        }
                    }
                    
                    // Main Content
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.surfaceColor
                        radius: 20 // Settings uses rounding.windowRounding - root.contentPadding, hardcode matching value
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 0
                        
                        // Search Header
                        Item {
                            z: 999
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            
                            Rectangle {
                                id: searchContainer
                                anchors.centerIn: parent
                                width: Math.min(parent.width * 0.6, 500)
                                height: 48
                                radius: 24
                                color: root.pillColor
                                border.width: 0
                                
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    spacing: 12
                                    
                                    MaterialSymbol {
                                        text: "search"
                                        color: root.pillContentColor
                                        iconSize: 20
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                    
                                    TextInput {
                                        id: searchInput
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: root.pillContentColor
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: 500
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        
                                        Text {
                                            text: "Search YouTube Music..."
                                            color: ColorUtils.transparentize(root.pillContentColor, 0.5)
                                            visible: searchInput.text.length === 0
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            font: searchInput.font
                                        }
                                        
                                        onTextEdited: {
                                            root.suppressSuggestionResponses = false
                                            root.artistResults.clear()
                                            root.songResults.clear()
                                            root.albumResults.clear()
                                            root.cachedSongResults = []
                                            root.searchVisibleSongCount = 5
                                            root.searchSongsHasMore = false
                                            root.sendCommand({ "command": "get_suggestions", "query": text })
                                        }
                                        
                                        onAccepted: root.search(text)
                                        
                                        onActiveFocusChanged: {
                                            console.log("[MusicWindow] searchInput focus changed to: " + activeFocus);
                                            if (!activeFocus) {
                                                hideSuggsTimer.restart()
                                            } else {
                                                hideSuggsTimer.stop()
                                            }
                                        }

                                        Timer {
                                            id: hideSuggsTimer
                                            interval: 150 // Small delay allows onClicked in the menu to register before disappearing
                                            onTriggered: root.searchSuggestions.clear()
                                        }
                                    }
                                }
                            }
                            
                            Rectangle {
                                id: suggestionsPopover
                                anchors.top: searchContainer.bottom
                                anchors.topMargin: 8 // Give a subtle floating shadow gap
                                anchors.horizontalCenter: searchContainer.horizontalCenter
                                width: searchContainer.width
                                height: Math.min(suggestionsList.contentHeight + 16, 300)
                                color: searchContainer.color
                                radius: 20
                                border.width: 0
                                visible: root.searchSuggestions.count > 0 && searchInput.text.length > 0
                                z: 200
                                
                                ListView {
                                    id: suggestionsList
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    clip: true
                                    model: root.searchSuggestions
                                    delegate: Item {
                                        width: ListView.view.width
                                        height: 40
                                        
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 12
                                            color: suggMouse.containsMouse ? ColorUtils.transparentize(root.contentColor, 0.9) : "transparent"
                                            
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                spacing: 12
                                                MaterialSymbol { text: "search"; color: suggMouse.containsMouse ? root.contentColor : root.secondaryContentColor; iconSize: 18 }
                                                StyledText { text: model.text; color: suggMouse.containsMouse ? root.contentColor : root.contentColor; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }
                                            
                                            MouseArea {
                                                id: suggMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                scrollGestureEnabled: false
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: {
                                                    console.log("[MusicWindow] Suggestion clicked: " + model.text);
                                                    hideSuggsTimer.stop() // Prevent the timer from clearing our intended search
                                                    searchInput.text = model.text
                                                    root.search(model.text)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Content Views
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (event) => root.forwardWheelEvent(event)
                            }

                            MusicSearchView {
                                id: searchView
                                anchors.fill: parent
                                rootContext: root
                                queryText: searchInput.text
                            }

                            MusicExploreView {
                                id: exploreView
                                anchors.fill: parent
                                rootContext: root
                                queryText: searchInput.text
                            }

                            MusicHomeView {
                                id: homeView
                                anchors.fill: parent
                                rootContext: root
                                queryText: searchInput.text
                            }

                            MusicLibraryView {
                                id: libraryView
                                anchors.fill: parent
                                rootContext: root
                                queryText: searchInput.text
                            }

                            // Central Loading Spinner
                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                implicitSize: 64
                                loading: root.isLoading

                                opacity: root.isLoading ? 1.0 : 0.0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

                                color: root.pillColor
                            }
                        }
                        }
                    }
                    }
                }
                
                // Floating Miniplayer
                MusicMiniPlayer {
                    id: playerPanel
                    rootContext: root
                    navRailExpanded: navRail.expanded
                }
            }
        }
    }
}
