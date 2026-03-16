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
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.4) : Appearance.colors.colLayer1

    property bool show: rootContext && rootContext.currentView === "playlist" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: Math.max(height, playlistContainer.implicitHeight + (rootContext && rootContext.currentTrack ? 120 : 32))
    flickableDirection: Flickable.VerticalFlick

    onDraggingChanged: {
        if (!dragging && contentY <= -100 && !rootContext.refreshing && !rootContext.isLoading) {
            rootContext.refreshing = true
            rootContext.openPlaylist(rootContext.activePlaylistId)
        }
    }

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
                color: rootContext ? rootContext.pillColor : Appearance.colors.colPrimary
            }

            StyledText {
                text: root.contentY < -100 ? "Release to refresh" : "Pull to refresh"
                font.weight: 600
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }
        }
    }

    ColumnLayout {
        id: playlistContainer
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // Back action
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            MusicBackButton {
                rootContext: root.rootContext
                onClicked: {
                    if (rootContext) {
                        if (rootContext.returnView && rootContext.returnView !== "playlist")
                            rootContext.currentView = rootContext.returnView
                        else
                            rootContext.currentView = "library"
                    }
                }
            }        }

        // Header Section
        RowLayout {
            Layout.fillWidth: true
            spacing: 32

            Rectangle {
                width: 240
                height: 240
                radius: 20
                color: root.artPlaceholderColor
                Layout.alignment: Qt.AlignTop
                
                RoundedImage {
                    anchors.fill: parent
                    source: rootContext ? rootContext.activePlaylistCover || "" : ""
                    sourceSize.width: 480
                    sourceSize.height: 480
                    fillMode: Image.PreserveAspectCrop
                    radius: 20
                    asynchronous: true
                    cache: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 8

                StyledText {
                    text: rootContext && rootContext.activePlaylistId.startsWith("MPREb_") ? "Album" : "Playlist"
                    font.pixelSize: 14
                    font.weight: 600
                    color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rootContext ? rootContext.activePlaylistTitle : ""
                    font.pixelSize: 48
                    font.weight: 800
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rootContext ? rootContext.activePlaylistDescription : ""
                    font.pixelSize: 14
                    color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                    visible: text.length > 0
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                RowLayout {
                    spacing: 8
                    StyledText {
                        text: rootContext ? rootContext.activePlaylistAuthor : ""
                        font.pixelSize: 14
                        font.weight: 700
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        visible: text.length > 0
                    }
                    StyledText {
                        text: "•"
                        font.pixelSize: 14
                        color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                        visible: rootContext && rootContext.activePlaylistAuthor.length > 0
                    }
                    StyledText {
                        text: rootContext ? rootContext.activePlaylistTrackCount + " songs" : ""
                        font.pixelSize: 14
                        color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                    }
                }

                Item { Layout.preferredHeight: 16 }

                RowLayout {
                    spacing: 16
                    
                    // Play Button
                    RippleButton {
                        Layout.preferredWidth: playRow.implicitWidth + 32
                        Layout.preferredHeight: 48
                        buttonRadius: 24
                        colBackground: rootContext ? rootContext.extractedColor || rootContext.pillColor : Appearance.colors.colPrimary
                        
                        property color txColor: rootContext ? rootContext.extractedForeground : Appearance.colors.colOnPrimary
                        
                        contentItem: RowLayout {
                            id: playRow
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "play_arrow"; color: parent.parent.txColor; iconSize: 24 }
                            StyledText { Layout.alignment: Qt.AlignVCenter; text: "Play"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
                        }
                        
                        onClicked: {
                            if (rootContext && rootContext.activePlaylistTracks.count > 0) {
                                let first = rootContext.activePlaylistTracks.get(0)
                                let queueTracks = []
                                for (let i = 1; i < rootContext.activePlaylistTracks.count; i++) {
                                    let t = rootContext.activePlaylistTracks.get(i)
                                    queueTracks.push({
                                        videoId: t.videoId,
                                        title: t.title,
                                        artist: t.artist,
                                        artUrl: t.artUrl || rootContext.activePlaylistCover,
                                        duration: t.duration || ""
                                    })
                                }
                                rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl || rootContext.activePlaylistCover, queueTracks)
                            }
                        }
                    }

                    // Shuffle Button
                    RippleButton {
                        Layout.preferredWidth: shuffleRow.implicitWidth + 32
                        Layout.preferredHeight: 48
                        buttonRadius: 24
                        colBackground: rootContext ? ColorUtils.transparentize(rootContext.contentColor, 0.9) : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.9)
                        
                        property color txColor: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        
                        contentItem: RowLayout {
                            id: shuffleRow
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "shuffle"; color: parent.parent.txColor; iconSize: 24 }
                            StyledText { Layout.alignment: Qt.AlignVCenter; text: "Shuffle"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
                        }
                        
                        onClicked: {
                            if (rootContext && rootContext.activePlaylistTracks.count > 0) {
                                let tracksToPlay = [];
                                for (let i = 0; i < rootContext.activePlaylistTracks.count; i++) {
                                    let t = rootContext.activePlaylistTracks.get(i);
                                    tracksToPlay.push({
                                        videoId: t.videoId,
                                        title: t.title,
                                        artist: t.artist,
                                        artUrl: t.artUrl || rootContext.activePlaylistCover,
                                        duration: t.duration || ""
                                    });
                                }
                                
                                // Fisher-Yates shuffle
                                for (let i = tracksToPlay.length - 1; i > 0; i--) {
                                    const j = Math.floor(Math.random() * (i + 1));
                                    [tracksToPlay[i], tracksToPlay[j]] = [tracksToPlay[j], tracksToPlay[i]];
                                }
                                
                                let first = tracksToPlay[0];
                                let queueTracks = tracksToPlay.slice(1);
                                rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl, queueTracks);
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 16 }

        // Tracks List
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: tracksColumn.implicitHeight + 16
            radius: 20
            color: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.85) : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)

            ColumnLayout {
                id: tracksColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: rootContext ? rootContext.activePlaylistTracks : null

                    delegate: MusicListTrackItem {
                        rootContext: root.rootContext
                        track: model
                        indexNumber: index + 1
                        
                        onClicked: {
                            if (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) {
                                rootContext.toggle()
                            } else {
                                let queueTracks = []
                                for (let i = index + 1; i < rootContext.activePlaylistTracks.count; i++) {
                                    let t = rootContext.activePlaylistTracks.get(i)
                                    queueTracks.push({
                                        videoId: t.videoId,
                                        title: t.title,
                                        artist: t.artist,
                                        artUrl: t.artUrl,
                                        duration: t.duration || ""
                                    })
                                }
                                rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl, queueTracks)
                            }
                        }
                }
            }
        }
        }
        
        // Spacer
        Item {
            Layout.fillWidth: true
            height: rootContext ? (rootContext.currentTrack ? 80 : 0) : 0
        }
    }
}
