import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    property var rootContext
    property string queryText: ""
    readonly property var flickable: root


    anchors.fill: parent
    contentHeight: resultsColumn.implicitHeight + ((rootContext && rootContext.currentTrack) ? 120 : 32)
    contentWidth: width
    pressDelay: 150

    property bool show: queryText.length > 0 && rootContext && rootContext.currentView !== "playlist" && rootContext.currentView !== "artist" && rootContext.currentView !== "artist_items" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    clip: true

    ColumnLayout {
        id: resultsColumn
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // Artists
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext && rootContext.artistResults.count > 0

            StyledText {
                text: "Artists"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }

            MusicHorizontalFlickable {
                id: artistList
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                implicitHeight: 220
                contentWidth: artistRow.implicitWidth
                contentHeight: artistRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: artistRow
                    spacing: 0

                    Repeater {
                        model: rootContext ? rootContext.artistResults : null

                        delegate: MusicMediaCard {
                            width: 180
                            height: 220
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "transparent"
                            artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

                            onClicked: {
                                if (rootContext) rootContext.openArtist(model.videoId || "")
                            }
                        }
                    }
                }
            }
        }

        // Songs
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext && rootContext.songResults.count > 0

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: "Songs"
                    font.pixelSize: 20
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    visible: rootContext && rootContext.searchSongsHasMore
                    Layout.preferredHeight: 34
                    buttonRadius: 17
                    colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colLayer2Base
                    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer2, 0.2)

                    contentItem: StyledText {
                        text: "Load more"
                        font.pixelSize: 13
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer2
                    }

                    onClicked: if (rootContext) rootContext.loadMoreSongs()
                }
            }

            Rectangle {
                id: songsContainer
                Layout.fillWidth: true
                implicitHeight: songResultsColumn.height + 32
                Layout.preferredHeight: implicitHeight
                radius: 24
                color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
                clip: true

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                ColumnLayout {
                    id: songResultsColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: rootContext ? rootContext.songResults : null

                        delegate: MusicListTrackItem {
                            rootContext: root.rootContext
                            track: model

                            onClicked: {
                                if (rootContext) rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl, undefined, model.artistId, model.albumId)
                            }
                        }
                    }
                }
            }
        }

        // Albums
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext && rootContext.albumResults.count > 0

            StyledText {
                text: "Albums"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }

            Flow {
                id: albumGrid
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                width: parent.width
                spacing: 0
                property int targetCellWidth: 200
                property int columns: Math.max(1, Math.floor(width / targetCellWidth))
                property int cellWidth: Math.floor(width / columns)
                property int cellHeight: Math.max(280, cellWidth + 72)

                Repeater {
                    model: rootContext ? rootContext.albumResults : null

                    delegate: MusicMediaCard {
                        width: albumGrid.cellWidth
                        height: albumGrid.cellHeight
                        rootContext: root.rootContext
                        itemData: model
                        hoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.3) : "transparent"
                        artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

                        customSubtitle: model.artist

                        onClicked: {
                            if (rootContext) rootContext.openPlaylist(model.videoId)
                        }
                    }
                }
            }
        }

        // Spacer
        Item {
            Layout.fillWidth: true
            height: rootContext && rootContext.currentTrack ? 80 : 0
        }
    }
}
