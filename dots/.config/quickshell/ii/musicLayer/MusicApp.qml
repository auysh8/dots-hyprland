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

FocusScope {
    id: root
    
    property bool isAppMode: false
    signal closeRequested()
    
    property bool showMusic: true // Always true when instantiated as app, or controlled by parent
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

    // Playlist View Models
    property string activePlaylistId: ""
    property bool autoPlayPending: false
    property bool autoPlayShufflePending: false
    property string activePlaylistTitle: ""
    property string activePlaylistDescription: ""
    property string activePlaylistAuthor: ""
    property string activePlaylistCover: ""
    property int activePlaylistTrackCount: 0
    property ListModel activePlaylistTracks: ListModel {}
    
    // Artist View Models
    property string activeArtistId: ""
    property string activeArtistName: ""
    property string activeArtistDescription: ""
    property string activeArtistSubscribers: ""
    property string activeArtistThumbnail: ""
    property ListModel activeArtistSongs: ListModel {}
    property ListModel activeArtistAlbums: ListModel {}
    property ListModel activeArtistSingles: ListModel {}
    property ListModel activeArtistRelated: ListModel {}
    property string activeArtistSongsBrowseId: ""
    property string activeArtistAlbumsParams: ""
    property string activeArtistSinglesParams: ""
    property string activeArtistAlbumsBrowseId: ""
    property string activeArtistSinglesBrowseId: ""
    
    // Artist Full Items View Properties
    property string activeArtistItemsTitle: ""
    property var activeArtistItemsModel: null
    property bool activeArtistAlbumsFull: false
    property bool activeArtistSinglesFull: false
    property bool activeArtistSongsFull: false
    
    // Shared layer transition offset for both panel and background.
    readonly property real panelHiddenOffset: -(musicPanel.y + musicPanel.height + 100)
    property bool isLoading: true
    property bool refreshing: false
    property var currentTrack: null
    property bool currentTrackLiked: false
    property bool isTrackLoading: false
    property bool playbackPaused: false
    property ListModel queueList: ListModel {}
    property bool isQueueLoading: false
    property int trackPositionSec: 0
    property int trackDurationSec: 0
    property int repeatMode: 0  // 0: Off, 1: Repeat All, 2: Repeat One
    property bool shuffleToggled: false
    property string currentView: "home"
    property string previousView: "home"
    property string returnView: "home"
    
    onCurrentViewChanged: {
        if (currentView !== "player") {
            previousView = currentView
        }
    }
    property string lastSearchQuery: ""
    property int searchVisibleSongCount: 5
    property int searchSongPrefetchLimit: 20
    property bool searchSongsHasMore: false
    property var cachedSongResults: []
    property bool suppressSuggestionResponses: false
    
    // OAuth flow properties
    property bool oauthDialogVisible: false
    property string oauthUrl: ""
    property string oauthCode: ""
    property bool oauthSuccess: false
    property bool oauthCopied: false
    property bool isAuthenticated: false
    property string accountName: ""
    
    function startOauth() {
        oauthUrl = ""
        oauthCode = ""
        oauthSuccess = false
        oauthCopied = false
        oauthDialogVisible = true
        sendCommand({ "command": "oauth_start" })
    }
    
    function refreshAuth() {
        sendCommand({ "command": "refresh_auth" })
    }
    
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
    
    function getLibrary() {
        isLoading = true
        sendCommand({ "command": "get_library" })
    }
    
    function navigateTo(viewName) {
        root.currentView = viewName
        
        // Centralized lazy-load policy
        if (viewName === "home" && root.homeContent.count === 0 && root.quickPicks.count === 0 && !root.isLoading) {
            root.getHome()
        } else if (viewName === "explore" && root.exploreNewReleases.count === 0 && root.exploreTrending.count === 0 && !root.isLoading) {
            root.getExplore()
        } else if (viewName === "library" && root.libraryPlaylists.count === 0 && root.libraryRecentTracks.count === 0 && !root.isLoading) {
            root.getLibrary()
        }
    }

    function toggleCurrentTrackLike() {
        if (!currentTrack || isTrackLoading) return
        currentTrackLiked = !currentTrackLiked
        sendCommand({ "command": "toggle_like", "liked": currentTrackLiked, "videoId": currentTrack.videoId })
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

    function playTrack(videoId, title, artist, artUrl, queueTracks) {
        root.currentTrack = {
            videoId: videoId,
            title: title,
            artist: artist,
            artUrl: artUrl
        }
        root.isTrackLoading = true
        let msg = {
            "command": "play",
            "videoId": videoId,
            "title": title,
            "artist": artist,
            "artUrl": artUrl
        }
        if (queueTracks && Array.isArray(queueTracks)) {
            msg["queue"] = queueTracks;
        }
        sendCommand(msg)
    }
    
    function openPlaylist(browseId) {
        if (!browseId) return;
        root.returnView = root.currentView
        root.currentView = "playlist"
        root.isLoading = true
        root.activePlaylistTracks.clear()
        root.activePlaylistId = browseId
        
        sendCommand({ "command": "get_playlist", "browseId": browseId })
    }

    function openAndPlayPlaylist(browseId, shuffle = false) {
        if (!browseId) return;
        root.autoPlayPending = true;
        root.autoPlayShufflePending = shuffle;
        root.activePlaylistId = browseId;
        root.isTrackLoading = true;
        sendCommand({ "command": "get_playlist", "browseId": browseId });
    }

    function openArtist(channelId) {
        root.returnView = root.currentView
        root.currentView = "artist"
        root.isLoading = true
        root.activeArtistId = channelId || ""
        root.activeArtistSongs.clear()
        root.activeArtistAlbums.clear()
        root.activeArtistSingles.clear()
        root.activeArtistRelated.clear()
        
        if (channelId && channelId.length > 0) {
            sendCommand({ "command": "get_artist", "channelId": channelId })
        }
    }
    
    function toggle() {
        MusicService.toggle()
    }

    function closeWindow() {
        root.closeRequested()
    }

    function activeContentFlickable() {
        if (searchInput.text.length > 0 && searchView.visible)
            return searchView.flickable
        if (root.currentView === "explore" && exploreView.visible)
            return exploreView.flickable
        if (root.currentView === "library" && libraryView.visible)
            return libraryView.flickable
        if (root.currentView === "home" && homeView.visible)
            return homeView.flickable
        if (root.currentView === "playlist" && playlistView.visible)
            return playlistView.flickable
        if (root.currentView === "artist" && artistView.visible)
            return artistView.flickable
        if (root.currentView === "artist_items" && artistItemsView.visible)
            return artistItemsView.flickable
        return null
    }

    
    IpcHandler {
        target: "music"
        function toggle() { MusicService.toggle() }
    }
    
    property list<real> visualizerPoints: []

    function applyLibrarySection(data) {
        root.isLoading = false
        root.refreshing = false
        let items = data.items || []
        if (data.section === "recent_tracks") {
            root.libraryRecentTracks.clear()
            for (let i = 0; i < items.length; i++) root.libraryRecentTracks.append(items[i])
        } else if (data.section === "playlists") {
            root.libraryPlaylists.clear()
            for (let i = 0; i < items.length; i++) root.libraryPlaylists.append(items[i])
            if (data.likedCount !== undefined) root.libraryLikedSongCount = data.likedCount
            if (data.likedArt !== undefined) root.libraryLikedSongArt = data.likedArt
        } else if (data.section === "community_playlists") {
            root.libraryCommunityPlaylists.clear()
            for (let i = 0; i < items.length; i++) root.libraryCommunityPlaylists.append(items[i])
        }
    }

    function applyPlaylistDetails(data) {
        root.isLoading = false
        root.refreshing = false
        root.activePlaylistId = data.id || ""
        root.activePlaylistTitle = data.title || ""
        root.activePlaylistDescription = data.description || ""
        root.activePlaylistAuthor = data.author || ""
        root.activePlaylistCover = data.cover || ""
        root.activePlaylistTrackCount = data.trackCount || 0
        
        root.activePlaylistTracks.clear()
        let tracks = data.tracks || []
        for (let i = 0; i < tracks.length; i++) {
            root.activePlaylistTracks.append(tracks[i])
        }

        if (root.autoPlayPending && tracks.length > 0) {
            root.autoPlayPending = false;
            
            // Make a copy to shuffle
            let tracksToPlay = [...tracks];
            
            if (root.autoPlayShufflePending) {
                root.autoPlayShufflePending = false;
                // Fisher-Yates shuffle
                for (let i = tracksToPlay.length - 1; i > 0; i--) {
                    const j = Math.floor(Math.random() * (i + 1));
                    [tracksToPlay[i], tracksToPlay[j]] = [tracksToPlay[j], tracksToPlay[i]];
                }
            }
            
            let first = tracksToPlay[0];
            let queueTracks = [];
            for (let i = 1; i < tracksToPlay.length; i++) {
                let t = tracksToPlay[i];
                queueTracks.push({
                    videoId: t.videoId,
                    title: t.title,
                    artist: t.artist,
                    artUrl: t.artUrl || root.activePlaylistCover,
                    duration: t.duration || ""
                })
            }
            root.playTrack(first.videoId, first.title, first.artist, first.artUrl || root.activePlaylistCover, queueTracks)
        } else {
            root.autoPlayPending = false;
        }
    }

    function applyArtistDetails(data) {
        root.isLoading = false
        root.refreshing = false
        root.activeArtistAlbumsFull = false
        root.activeArtistSinglesFull = false
        root.activeArtistSongsFull = false
        root.activeArtistId = data.channelId || ""
        root.activeArtistName = data.name || ""
        root.activeArtistDescription = data.description || ""
        root.activeArtistSubscribers = data.subscribers || ""
        root.activeArtistThumbnail = data.thumbnailUrl || ""
        
        root.activeArtistSongs.clear()
        let artistSongs = data.topSongs || []
        for (let i = 0; i < artistSongs.length; i++)
            root.activeArtistSongs.append(artistSongs[i])
        
        root.activeArtistAlbums.clear()
        let artistAlbums = data.albums || []
        for (let i = 0; i < artistAlbums.length; i++)
            root.activeArtistAlbums.append(artistAlbums[i])
        
        root.activeArtistSingles.clear()
        let artistSingles = data.singles || []
        for (let i = 0; i < artistSingles.length; i++)
            root.activeArtistSingles.append(artistSingles[i])
        
        root.activeArtistRelated.clear()
        let artistRelated = data.relatedArtists || []
        for (let i = 0; i < artistRelated.length; i++)
            root.activeArtistRelated.append(artistRelated[i])
        
        root.activeArtistSongsBrowseId = data.songsBrowseId || ""
        root.activeArtistAlbumsParams = data.albumsParams || ""
        root.activeArtistSinglesParams = data.singlesParams || ""
        root.activeArtistAlbumsBrowseId = data.albumsBrowseId || ""
        root.activeArtistSinglesBrowseId = data.singlesBrowseId || ""
    }
    
    Process {
        id: cavaProc
        running: !!root.showMusic && !!root.currentTrack && !root.playbackPaused
        onRunningChanged: {
            if (!cavaProc.running) {
                // Return to baseline properly rather than destroying the array
                root.visualizerPoints = new Array(25).fill(0.0);
            }
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points.slice(0, 25);
            }
        }
    }
    
    // Media Color Context - extracts colors from album art (same as Lyrics Layer)
    MediaArtColorContext {
        id: mediaContext
        activePlayer: root.currentTrack ? {
            trackArtUrl: root.currentTrack.artUrl || ""
        } : null
    }

    // Map MediaArtColorContext properties to music layer aliases
    property bool downloaded: mediaContext.downloaded
    property string displayedArtFilePath: mediaContext.displayedArtFilePath

    // Hardcoded color exception for dynamic extracted art contrast
    readonly property color _fallbackLight: "white"
    readonly property color _fallbackDark: "black"

    // Check if we have a valid track playing (for color fallback)
    readonly property bool _hasTrack: root.currentTrack !== null && root.currentTrack.artUrl !== ""

    // Album art dominant blending (heavily darkened for better contrast)
    // We use the opaque colLayer0Base as the fallback and mix target to ensure App mode doesn't become transparent.
    readonly property color _srcBackgroundColor: _hasTrack ? ColorUtils.mix(ColorUtils.mix(mediaContext._srcBackgroundColor, "black", 0.7), Appearance.colors.colLayer0Base, 0.5) : Appearance.colors.colLayer0Base

    // High vibrancy: 80% album art colors, 20% system theme for readability
    // Content colors always maintain contrast by using system foreground as base
    readonly property color _srcContentColor: _hasTrack ? (ColorUtils.isDark(_srcSurfaceColor) ? ColorUtils.mix(_fallbackLight, Appearance.colors.colOnLayer0, 0.3) : ColorUtils.mix(_fallbackDark, Appearance.colors.colOnLayer0, 0.3)) : Appearance.colors.colOnLayer0
    readonly property color _srcSecondaryContentColor: _hasTrack ? (ColorUtils.isDark(_srcSurfaceColor) ? ColorUtils.mix(_fallbackLight, Appearance.colors.colSubtext, 0.3) : ColorUtils.mix(_fallbackDark, Appearance.colors.colSubtext, 0.3)) : Appearance.colors.colSubtext
    // Ensure pill content has high contrast - always use system-safe contrast colors
    // We force white (_fallbackLight) in dark mode because the extracted pillColor is too dark/murky
    readonly property color _srcPillContentColor: _hasTrack ? (Appearance.m3colors.darkmode ? _fallbackLight : _fallbackDark) : Appearance.colors.colOnSecondaryContainer
    
    // Create a dark elevated surface by mixing the blended color heavily with the dark system layer
    readonly property color _srcSurfaceColor: _hasTrack ? ColorUtils.mix(mediaContext.blendedColors.colSurface, Appearance.colors.colLayer2Base, 0.8) : Appearance.colors.colLayer2Base

    // Create a darker accent color so the nav rail, mini player, and search bar aren't overwhelmingly bright
    // Purely derives from the album art, completely ignoring system accent colors when playing
    readonly property color _srcPillColor: _hasTrack ? ColorUtils.mix(mediaContext._srcPillColor, Appearance.colors.colLayer0Base, 0.4) : Appearance.colors.colSecondaryContainer

    // Animated colors (smooth transitions)
    property color backgroundColor: _srcBackgroundColor
    property color contentColor: _srcContentColor
    property color secondaryContentColor: _srcSecondaryContentColor
    property color pillColor: _srcPillColor
    property color pillColorHover: ColorUtils.mix(_srcPillColor, _srcPillContentColor, 0.15)
    property color pillContentColor: _srcPillContentColor
    property color surfaceColor: _srcSurfaceColor
    property color loaderAccentColor: _hasTrack ? mediaContext.blendedColors.colPrimary : Appearance.colors.colPrimary

    // Extracted color alias for compatibility
    readonly property color extractedColor: mediaContext.extractedColor
    readonly property color extractedForeground: mediaContext._srcPillContentColor

    // Smooth color transition behaviors
    Behavior on backgroundColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on contentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on secondaryContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillColorHover { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on surfaceColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on loaderAccentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    
    Process {
        id: backend
        running: true
        stdinEnabled: true
        command: [Qt.resolvedUrl("venv/bin/python3").toString().replace("file://", ""), Qt.resolvedUrl("music_backend.py").toString().replace("file://", "")]
        
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    let data = JSON.parse(line)
                    
                    if (data.type === "ready") {
                        if (data.authenticated !== undefined) {
                            root.isAuthenticated = data.authenticated
                            if (data.accountName) root.accountName = data.accountName
                        }
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
                        
                        for (let i = 0; i < artists.length; i++) {
                            root.artistResults.append(artists[i])
                        }
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
                    } else if (data.type === "library_section") {
                        root.applyLibrarySection(data)
                    } else if (data.type === "playlist_details") {
                        root.applyPlaylistDetails(data)
                    } else if (data.type === "artist_details") {
                        root.applyArtistDetails(data)
                    } else if (data.type === "artist_full_songs") {
                        root.isLoading = false
                        let fullSongs = data.items || []
                        root.activeArtistSongs.clear()
                        for (let i = 0; i < fullSongs.length; i++) {
                            root.activeArtistSongs.append(fullSongs[i])
                        }
                        root.activeArtistSongsFull = true
                        
                        root.returnView = "artist"
                        root.activePlaylistTitle = "Top Songs"
                        root.activePlaylistDescription = ""
                        root.activePlaylistAuthor = root.activeArtistName
                        root.activePlaylistTrackCount = fullSongs.length
                        root.activePlaylistTracks.clear()
                        for (let i = 0; i < root.activeArtistSongs.count; i++) {
                            root.activePlaylistTracks.append(root.activeArtistSongs.get(i))
                        }
                        root.activePlaylistCover = root.activeArtistThumbnail
                        root.currentView = "playlist"
                    } else if (data.type === "artist_full_albums") {
                        root.isLoading = false
                        let fullAlbums = data.items || []
                        root.activeArtistAlbums.clear()
                        for (let i = 0; i < fullAlbums.length; i++) {
                            root.activeArtistAlbums.append(fullAlbums[i])
                        }
                        root.activeArtistAlbumsFull = true
                        root.activeArtistItemsTitle = "All Albums"
                        root.activeArtistItemsModel = root.activeArtistAlbums
                        root.currentView = "artist_items"
                    } else if (data.type === "artist_full_singles") {
                        root.isLoading = false
                        let fullSingles = data.items || []
                        root.activeArtistSingles.clear()
                        for (let i = 0; i < fullSingles.length; i++) {
                            root.activeArtistSingles.append(fullSingles[i])
                        }
                        root.activeArtistSinglesFull = true
                        root.activeArtistItemsTitle = "All Singles & EPs"
                        root.activeArtistItemsModel = root.activeArtistSingles
                        root.currentView = "artist_items"
                    } else if (data.type === "error") {
                        root.isLoading = false
                        root.refreshing = false
                        root.isTrackLoading = false
                        console.error("[MusicBackend] Error:", data.message)
                    } else if (data.type === "track_loading") {
                        root.isTrackLoading = true
                        root.trackPositionSec = 0
                        root.trackDurationSec = 0
                        root.currentTrack = {
                            videoId: data.videoId,
                            title: data.title,
                            artist: data.artist,
                            artUrl: data.artUrl
                        }
                    } else if (data.type === "playback_started") {
                        root.isTrackLoading = false
                        root.currentTrack = {
                            videoId: data.videoId,
                            title: data.title,
                            artist: data.artist,
                            artUrl: data.artUrl
                        }
                        root.currentTrackLiked = data.isLiked || false
                        root.playbackPaused = false
                        root.trackPositionSec = 0
                        root.trackDurationSec = 0
                    } else if (data.type === "playback_stopped") {
                        if (!root.isTrackLoading) {
                            root.currentTrack = null
                        }
                        root.playbackPaused = false
                    } else if (data.type === "playback_paused") {
                        root.playbackPaused = true
                    } else if (data.type === "playback_resumed") {
                        root.playbackPaused = false
                    } else if (data.type === "playback_progress") {
                        root.trackPositionSec = data.positionSec || 0
                        if (data.durationSec > 0) root.trackDurationSec = data.durationSec
                    } else if (data.type === "playback_duration") {
                        root.trackDurationSec = data.durationSec || 0
                    } else if (data.type === "like_status") {
                        if (root.currentTrack && root.currentTrack.videoId === data.videoId) {
                            root.currentTrackLiked = data.isLiked || false
                        }
                    } else if (data.type === "queue_fetching") {
                        root.isQueueLoading = true
                    } else if (data.type === "queue_updated") {
                        root.queueList.clear()
                        let q = data.queue || []
                        for (let i = 0; i < q.length; i++) {
                            root.queueList.append(q[i])
                        }
                        root.isQueueLoading = false
                    } else if (data.type === "oauth_code") {
                        root.oauthUrl = data.url
                        root.oauthCode = data.user_code
                    } else if (data.type === "oauth_success") {
                        root.oauthSuccess = true
                        root.oauthDialogVisible = false
                        root.isAuthenticated = true
                        if (data.accountName) root.accountName = data.accountName
                        root.getHome()
                        root.getLibrary()
                    } else if (data.type === "auth_refreshed") {
                        if (data.success) {
                            root.isAuthenticated = true
                            root.getHome()
                            root.getLibrary()
                        }
                    }
                } catch(e) { 
                    console.error("[MusicBackend] Parse Error on line:", line)
                }
            }
        }
        
        stderr: SplitParser {
            onRead: (line) => console.error("[MusicBackend ERR]", line)
        }
    }

    Rectangle {
        id: musicPanel
        anchors.fill: parent
        radius: root.isAppMode ? 0 : 32
        color: "transparent"
        clip: !root.isAppMode
        
        Item {
            anchors.fill: parent
            layer.enabled: !root.isAppMode
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
                opacity: root.isAppMode ? 1.0 : 0.85
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 0
                spacing: root.isAppMode ? 8 : 8
            
                // Sidebar
                Item {
                    id: navRailWrapper
                    Layout.preferredWidth: navRail.expanded ? 150 : 56
                    Layout.fillHeight: true
                    Layout.margins: root.isAppMode ? 5 : 0
                    
                    Behavior on Layout.preferredWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    
                    Item {
                        anchors.fill: parent
                        
                        NavigationRail {
                            id: navRail
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            expanded: root.isAppMode ? root.width > 900 : false
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
                                    onPressed: root.navigateTo("home")
                                    expanded: navRail.expanded
                                    buttonIcon: "home"
                                    buttonText: "Home"
                                    showToggledHighlight: false
                                    useOverrideColors: true
                                    overrideActiveColor: root.pillColor
                                    overrideActiveHoverColor: root.pillColorHover
                                    overrideIconColor: toggled ? root.pillContentColor : root.contentColor
                                    overrideTextColor: toggled ? root.pillContentColor : root.contentColor
                                }
                                NavigationRailButton {
                                    toggled: root.currentView === "explore"
                                    onPressed: root.navigateTo("explore")
                                    expanded: navRail.expanded
                                    buttonIcon: "explore"
                                    buttonText: "Explore"
                                    showToggledHighlight: false
                                    useOverrideColors: true
                                    overrideActiveColor: root.pillColor
                                    overrideActiveHoverColor: root.pillColorHover
                                    overrideIconColor: toggled ? root.pillContentColor : root.contentColor
                                    overrideTextColor: toggled ? root.pillContentColor : root.contentColor
                                }
                                NavigationRailButton {
                                    toggled: root.currentView === "library"
                                    onPressed: root.navigateTo("library")
                                    expanded: navRail.expanded
                                    buttonIcon: "library_music"
                                    buttonText: "Library"
                                    showToggledHighlight: false
                                    useOverrideColors: true
                                    overrideActiveColor: root.pillColor
                                    overrideActiveHoverColor: root.pillColorHover
                                    overrideIconColor: toggled ? root.pillContentColor : root.contentColor
                                    overrideTextColor: toggled ? root.pillContentColor : root.contentColor
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
                    radius: root.isAppMode ? (Appearance.rounding.windowRounding - 8) : 20
                    clip: true
                    
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
                                            if (!activeFocus) {
                                                hideSuggsTimer.restart()
                                            } else {
                                                hideSuggsTimer.stop()
                                            }
                                        }

                                        Timer {
                                            id: hideSuggsTimer
                                            interval: 150
                                            onTriggered: root.searchSuggestions.clear()
                                        }
                                    }
                                    
                                    RippleButton {
                                        visible: searchInput.text.length > 0
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        Layout.alignment: Qt.AlignVCenter
                                        buttonRadius: 16
                                        colBackground: "transparent"
                                        colBackgroundHover: ColorUtils.transparentize(root.pillContentColor, 0.85)
                                        
                                        contentItem: Item {
                                            anchors.fill: parent
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "close"
                                                color: root.pillContentColor
                                                iconSize: 18
                                            }
                                        }
                                        
                                        onClicked: {
                                            searchInput.text = ""
                                            root.suppressSuggestionResponses = false
                                            root.artistResults.clear()
                                            root.songResults.clear()
                                            root.albumResults.clear()
                                            root.cachedSongResults = []
                                            root.searchVisibleSongCount = 5
                                            root.searchSongsHasMore = false
                                            root.searchSuggestions.clear()
                                            searchInput.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                            
                            Rectangle {
                                id: suggestionsPopover
                                anchors.top: searchContainer.bottom
                                anchors.topMargin: 8
                                anchors.horizontalCenter: searchContainer.horizontalCenter
                                width: searchContainer.width
                                height: Math.min(suggestionsList.contentHeight + 16, 300)
                                color: searchContainer.color
                                radius: 20
                                border.width: 0
                                visible: root.searchSuggestions.count > 0 && searchInput.text.length > 0
                                z: 200

                                StyledListView {
                                    id: suggestionsList
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    clip: true
                                    model: root.searchSuggestions
                                    spacing: 4
                                    animateAppearance: false
                                    delegate: Item {
                                        width: ListView.view.width
                                        height: 40

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 12
                                            color: suggMouse.containsMouse ? root.pillColorHover : "transparent"
                                            clip: true

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12
                                                anchors.rightMargin: 12
                                                spacing: 12
                                                MaterialSymbol {
                                                    text: "search"
                                                    color: suggMouse.containsMouse ? root.backgroundColor : root.secondaryContentColor
                                                    iconSize: 18
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                StyledText {
                                                    text: model.text
                                                    color: suggMouse.containsMouse ? root.backgroundColor : root.secondaryContentColor
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            MouseArea {
                                                id: suggMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                scrollGestureEnabled: false
                                                cursorShape: Qt.PointingHandCursor
                                                onPressed: {
                                                    hideSuggsTimer.stop()
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

                            MusicPlaylistView {
                                id: playlistView
                                anchors.fill: parent
                                rootContext: root
                            }

                            MusicArtistView {
                                id: artistView
                                anchors.fill: parent
                                rootContext: root
                            }

                            MusicArtistItemsView {
                                id: artistItemsView
                                anchors.fill: parent
                                rootContext: root
                            }

                            // Central Loading Spinner
                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                implicitSize: 64
                                loading: root.isLoading

                                opacity: root.isLoading ? 1.0 : 0.0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

                                color: ColorUtils.applyAlpha(root.loaderAccentColor, 0.2)
                                shapeColor: root.loaderAccentColor
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
        
        // Fullscreen Player Overlay
        MusicPlayerView {
            id: playerView
            rootContext: root
            navRailExpanded: navRail.expanded
            z: 500
        }

        // OAuth Flow Dialog - uses shared component
        MusicOAuthDialog {
            id: oauthDialog
            rootContext: root
        }
    }
}
