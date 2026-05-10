import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    property var rootContext
    readonly property var flickable: root
    readonly property color artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

    property bool show: rootContext && rootContext.currentView === "artist" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    contentWidth: width
    contentHeight: Math.max(height, contentContainer.y + contentContainer.height + (rootContext && rootContext.currentTrack ? 120 : 32) + 16)
    flickableDirection: Flickable.VerticalFlick
    pressDelay: 150

    Behavior on width {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    onDraggingChanged: {
        if (!dragging && contentY <= -100 && !rootContext.refreshing && !rootContext.isLoading) {
            rootContext.refreshing = true
            rootContext.openArtist(rootContext.activeArtistId)
        }
    }

    // Pull to refresh indicator
    Item {
        width: parent.width
        height: 60
        y: -60
        visible: root.contentY < -20

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            opacity: Math.min(Math.abs(root.contentY) / 100, 1.0)

            MaterialLoadingIndicator {
                implicitSize: 24
                loading: true
                color: rootContext ? ColorUtils.applyAlpha(rootContext.loaderAccentColor, 0.2) : Appearance.colors.colPrimaryContainer
                shapeColor: rootContext ? rootContext.loaderAccentColor : Appearance.colors.colPrimary
            }

            StyledText {
                text: root.contentY < -100 ? "Release to refresh" : "Pull to refresh"
                font.weight: 600
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }
        }
    }

    // ─── Floating Back Button ────────────────────────────────────────
    RowLayout {
        width: parent.width - 64
        y: 16 + Math.max(0, root.contentY) // Stays relative to scroll for a bit or just fixed? Actually flickable children move. 
        // We'll just let it scroll normally but sit on top of the banner.
        x: 32
        z: 10
        
        MusicBackButton {
            rootContext: root.rootContext
            onClicked: {
                if (rootContext) {
                    if (rootContext.returnView && rootContext.returnView !== "artist")
                        rootContext.currentView = rootContext.returnView
                    else
                        rootContext.currentView = "home"
                }
            }
        }
    }

    // ─── Asymmetric Background Hero ──────────────────────────────────
    Item {
        id: heroBanner
        width: root.width
        
        // Parallax effect: The image scrolls up at half the speed of the content
        y: root.contentY > 0 ? root.contentY * 0.5 : Math.min(0, root.contentY)
        
        // Dynamic height for overscroll
        height: 850 - Math.min(0, root.contentY)
        
        // Fade out the image as the user scrolls down into the track list
        opacity: Math.max(0, 1 - (root.contentY / 600))
        z: 0

        // Blurred background layer (same image, heavily blurred) for the immersive cloud glow effect
        RoundedImage {
            anchors.fill: parent
            source: rootContext ? rootContext.activeArtistThumbnail : ""
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            asynchronous: true
            cache: true
            opacity: 0.4
            layer.enabled: true
            layer.effect: FastBlur {
                radius: 80
            }
        }

        RoundedImage {
            id: heroImage
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: parent.width
            height: parent.height
            source: rootContext ? rootContext.activeArtistThumbnail : ""
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignTop
            asynchronous: true
            cache: true
        }

        // Top gradient fade
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: rootContext ? rootContext.backgroundColor : Appearance.colors.colBase }
                GradientStop { position: 0.12; color: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colBase, 0.0) }
            }
        }

        // Bottom gradient fade
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.35; color: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colBase, 0.0) }
                GradientStop { position: 1.0; color: rootContext ? rootContext.backgroundColor : Appearance.colors.colBase }
            }
        }

        // Left gradient fade
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: rootContext ? rootContext.backgroundColor : Appearance.colors.colBase }
                GradientStop { position: 0.12; color: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colBase, 0.0) }
            }
        }

        // Right gradient fade
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.88; color: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colBase, 0.0) }
                GradientStop { position: 1.0; color: rootContext ? rootContext.backgroundColor : Appearance.colors.colBase }
            }
        }
    }

    ColumnLayout {
        id: artistContainer
        width: parent.width - 64
        anchors.bottom: parent.top
        anchors.bottomMargin: -850 + 48 // Sit 48px above the bottom of the banner
        anchors.left: parent.left
        anchors.leftMargin: 32
        spacing: 48

        // ─── Header Section ──────────────────────────────────────────
        ColumnLayout {
            spacing: 16

            StyledText {
                text: rootContext ? rootContext.activeArtistName : ""
                font.pixelSize: 84
                font.weight: 900
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }
            
            StyledText {
                text: rootContext ? rootContext.activeArtistSubscribers : ""
                font.pixelSize: 16
                font.weight: 600
                color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                visible: text.length > 0
            }

            StyledText {
                Layout.maximumWidth: parent.width * 0.6
                text: rootContext ? rootContext.activeArtistDescription : ""
                font.pixelSize: 14
                color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
                visible: text.length > 0
            }

            Item { Layout.preferredHeight: 8 }

            MusicActionButtons {
                rootContext: root.rootContext
                tracksModel: root.rootContext ? root.rootContext.activeArtistSongs : null
                coverUrl: root.rootContext ? root.rootContext.activeArtistThumbnail : ""
                authorName: root.rootContext ? root.rootContext.activeArtistName : ""
            }
        }
    }

    ColumnLayout {
        id: contentContainer
        width: parent.width - 64
        anchors.top: parent.top
        anchors.topMargin: Math.max(850, artistContainer.y + artistContainer.height + 48)
        anchors.left: parent.left
        anchors.leftMargin: 32
        spacing: 48

        // ─── Top Songs ───────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: rootContext && rootContext.activeArtistSongs.count > 0

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Top Songs"
                    font.pixelSize: 22
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    Layout.fillWidth: true
                }
                RippleButton {
                    Layout.preferredWidth: seeAllSongsText.implicitWidth + 24
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: rootContext ? rootContext.pillColor : "transparent"
                    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : Appearance.colors.colLayer1Hover
                    visible: rootContext && (rootContext.activeArtistSongsBrowseId.length > 0 || rootContext.activeArtistSongsFull) && rootContext.activeArtistSongs.count > 0

                    contentItem: StyledText {
                        id: seeAllSongsText
                        text: "See all"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }                    
                    onClicked: {
                        if (rootContext && rootContext.activeArtistId) {
                            if (!rootContext.activeArtistSongsFull && rootContext.activeArtistSongsBrowseId) {
                                rootContext.isLoading = true
                                rootContext.sendCommand({
                                    "command": "get_artist_full_songs",
                                    "channelId": rootContext.activeArtistId,
                                    "songsBrowseId": rootContext.activeArtistSongsBrowseId
                                })
                            } else if (rootContext.activeArtistSongsFull) {
                                rootContext.returnView = "artist"
                                rootContext.activePlaylistTitle = "Top Songs"
                                rootContext.activePlaylistDescription = ""
                                rootContext.activePlaylistAuthor = rootContext.activeArtistName
                                rootContext.activePlaylistTrackCount = rootContext.activePlaylistTracks.count
                                rootContext.activePlaylistCover = rootContext.activeArtistThumbnail
                                rootContext.currentView = "playlist"
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: songsColumn.implicitHeight + 16
                Layout.preferredHeight: implicitHeight
                radius: 20
                color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

                ColumnLayout {
                    id: songsColumn
                    width: parent.width - 16
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    spacing: 4

                    Repeater {
                        model: rootContext ? rootContext.activeArtistSongs : null

                        delegate: MusicListTrackItem {
                            Layout.fillWidth: true
                            rootContext: root.rootContext
                            track: model
                            fallbackArtUrl: rootContext ? rootContext.activeArtistThumbnail : ""
                            indexNumber: index + 1

                            onClicked: {
                                if (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) {
                                    rootContext.toggle()
                                } else {
                                    let queueTracks = []
                                    for (let i = index + 1; i < rootContext.activeArtistSongs.count; i++) {
                                        let t = rootContext.activeArtistSongs.get(i)
                                        queueTracks.push({
                                            videoId: t.videoId,
                                            title: t.title,
                                            artist: t.artist,
                                            artUrl: t.artUrl || (rootContext ? rootContext.activeArtistThumbnail : ""),
                                            duration: t.duration || ""
                                        })
                                    }
                                    rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl || (rootContext ? rootContext.activeArtistThumbnail : ""), queueTracks, model.artistId, model.albumId)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Albums ──────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: rootContext && rootContext.activeArtistAlbums.count > 0

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Albums"
                    font.pixelSize: 22
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    Layout.fillWidth: true
                }
                RippleButton {
                    Layout.preferredWidth: seeAllAlbumsText.implicitWidth + 24
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: rootContext ? rootContext.pillColor : "transparent"
                    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : Appearance.colors.colLayer1Hover
                    visible: rootContext && (rootContext.activeArtistAlbumsParams.length > 0 || rootContext.activeArtistAlbumsFull) && rootContext.activeArtistAlbums.count > 0

                    contentItem: StyledText {
                        id: seeAllAlbumsText
                        text: "See all"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }                    
                    onClicked: {
                        if (rootContext && rootContext.activeArtistId) {
                            if (!rootContext.activeArtistAlbumsFull && rootContext.activeArtistAlbumsParams) {
                                rootContext.isLoading = true
                                rootContext.sendCommand({
                                    "command": "get_artist_full_items",
                                    "channelId": rootContext.activeArtistAlbumsBrowseId || rootContext.activeArtistId,
                                    "params": rootContext.activeArtistAlbumsParams,
                                    "itemType": "albums"
                                })
                            } else if (rootContext.activeArtistAlbumsFull) {
                                rootContext.activeArtistItemsTitle = "All Albums"
                                rootContext.activeArtistItemsModel = rootContext.activeArtistAlbums
                                rootContext.currentView = "artist_items"
                            }
                        }
                    }
                }
            }

            MusicHorizontalFlickable {
                id: albumsList
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                implicitHeight: 280
                contentWidth: albumsRow.implicitWidth
                contentHeight: albumsRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: albumsRow
                    spacing: 0

                    Repeater {
                        model: rootContext ? rootContext.activeArtistAlbums : null

                        delegate: MusicMediaCard {
                            width: 240
                            height: 280
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"
                            artPlaceholderColor: root.artPlaceholderColor

                            customSubtitle: {
                                let parts = []
                                if (model.year) parts.push(model.year)
                                if (model.type) parts.push(model.type)
                                return parts.join(" • ")
                            }

                            onClicked: {
                                if (model.browseId && rootContext) {
                                    rootContext.openPlaylist(model.browseId)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Singles ─────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: rootContext && rootContext.activeArtistSingles.count > 0

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Singles"
                    font.pixelSize: 22
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    Layout.fillWidth: true
                }
                RippleButton {
                    Layout.preferredWidth: seeAllSinglesText.implicitWidth + 24
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: rootContext ? rootContext.pillColor : "transparent"
                    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : Appearance.colors.colLayer1Hover
                    visible: rootContext && (rootContext.activeArtistSinglesParams.length > 0 || rootContext.activeArtistSinglesFull) && rootContext.activeArtistSingles.count > 0

                    contentItem: StyledText {
                        id: seeAllSinglesText
                        text: "See all"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }                    
                    onClicked: {
                        if (rootContext && rootContext.activeArtistId) {
                            if (!rootContext.activeArtistSinglesFull && rootContext.activeArtistSinglesParams) {
                                rootContext.isLoading = true
                                rootContext.sendCommand({
                                    "command": "get_artist_full_items",
                                    "channelId": rootContext.activeArtistSinglesBrowseId || rootContext.activeArtistId,
                                    "params": rootContext.activeArtistSinglesParams,
                                    "itemType": "singles"
                                })
                            } else if (rootContext.activeArtistSinglesFull) {
                                rootContext.activeArtistItemsTitle = "All Singles & EPs"
                                rootContext.activeArtistItemsModel = rootContext.activeArtistSingles
                                rootContext.currentView = "artist_items"
                            }
                        }
                    }
                }
            }

            MusicHorizontalFlickable {
                id: singlesList
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                implicitHeight: 280
                contentWidth: singlesRow.implicitWidth
                contentHeight: singlesRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: singlesRow
                    spacing: 0

                    Repeater {
                        model: rootContext ? rootContext.activeArtistSingles : null

                        delegate: MusicMediaCard {
                            width: 240
                            height: 280
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"
                            artPlaceholderColor: root.artPlaceholderColor

                            customSubtitle: {
                                let parts = []
                                if (model.year) parts.push(model.year)
                                if (model.type) parts.push(model.type)
                                return parts.join(" • ")
                            }

                            onClicked: {
                                if (model.browseId && rootContext) {
                                    rootContext.openPlaylist(model.browseId)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Related Artists ─────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: rootContext && rootContext.activeArtistRelated.count > 0

            StyledText {
                text: "Fans might also like"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }

            MusicHorizontalFlickable {
                id: relatedArtistsList
                Layout.fillWidth: true
                Layout.preferredHeight: 260
                implicitHeight: 260
                contentWidth: relatedArtistsRow.implicitWidth
                contentHeight: relatedArtistsRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: relatedArtistsRow
                    spacing: 0

                    Repeater {
                        model: rootContext ? rootContext.activeArtistRelated : null

                        delegate: MusicMediaCard {
                            width: 180
                            height: 260
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"
                            artPlaceholderColor: root.artPlaceholderColor

                            customSubtitle: model.subscribers || ""

                            onClicked: {
                                if (model.browseId && rootContext) {
                                    rootContext.openArtist(model.browseId)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bottom spacer for miniplayer
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: rootContext ? (rootContext.currentTrack ? 80 : 0) : 0
        }
    }
}
