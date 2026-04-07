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
    readonly property bool isAuthenticated: !!(rootContext && rootContext.isAuthenticated)
    readonly property color sectionCardColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    readonly property color artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    readonly property color cardHoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"

    property bool show: queryText.length === 0 && rootContext && rootContext.currentView === "library" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: libraryLayout.implicitHeight + ((rootContext && rootContext.currentTrack) ? 120 : 32)
    contentWidth: width
    pressDelay: 150

    Behavior on width {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // The dummy array was removed.

    ColumnLayout {
        id: libraryLayout
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 0

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 16
            StyledText {
                text: "Your Library"
                font.pixelSize: 32
                font.weight: 800
                color: rootContext.contentColor
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                Layout.preferredHeight: 36
                buttonRadius: 18
                colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colLayer2Base
                colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer2, 0.2)

                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: root.isAuthenticated ? "sync" : "account_circle"
                        font.pixelSize: 18
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        text: root.isAuthenticated ? "Refresh" : "Sign In"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer2
                    }
                }

                onClicked: {
                    if (rootContext) rootContext.refreshAuth()
                }
            }
        }


        // Auth Setup Instruction (when not authenticated)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: authInstructionLayout.implicitHeight + 32
            radius: 16
            color: root.sectionCardColor
            visible: rootContext && !root.isAuthenticated
            
            ColumnLayout {
                id: authInstructionLayout
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                
                RowLayout {
                    spacing: 10
                    MaterialSymbol {
                        text: "music_note"
                        font.pixelSize: 28
                        color: rootContext ? (rootContext.extractedColor || rootContext.pillContentColor) : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: "Connect YouTube Music"
                        font.pixelSize: 18
                        font.weight: 700
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer1
                    }
                }
                
                StyledText {
                    Layout.fillWidth: true
                    text: "Sign in to your YouTube Music account to see your liked songs, playlists, and listening history. Make sure you're logged into YouTube Music in your browser first."
                    font.pixelSize: 13
                    font.weight: 400
                    color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                }
                
                RippleButton {
                    Layout.preferredHeight: 38
                    buttonRadius: 19
                    colBackground: rootContext ? (rootContext.extractedColor || rootContext.pillColor) : Appearance.colors.colSecondaryContainer
                    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.extractedForeground : Appearance.colors.colOnSecondaryContainer, 0.2)

                    contentItem: RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: "link"
                            font.pixelSize: 18
                            color: rootContext ? rootContext.extractedForeground : Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: "Connect Account"
                            font.pixelSize: 14
                            font.weight: 700
                            color: rootContext ? rootContext.extractedForeground : Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    onClicked: if (rootContext) rootContext.refreshAuth()
                }
            }
        }

        // Recently Played
        ColumnLayout {
            id: recentSection
            Layout.fillWidth: true
            spacing: 16

            property bool hasData: rootContext.libraryRecentTracks.count > 0
            visible: hasData
            Layout.topMargin: 16

            StyledText {
                text: "Recently Played"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext.contentColor
            }

            MusicHorizontalFlickable {
                id: recentGrid
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                implicitHeight: 280
                contentWidth: recentRow.implicitWidth
                contentHeight: recentRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: recentRow
                    spacing: 0

                    Repeater {
                        model: rootContext.libraryRecentTracks

                        delegate: MusicMediaCard {
                            width: 240
                            height: 280
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: root.cardHoverColor
                            artPlaceholderColor: root.artPlaceholderColor

                            onClicked: {
                                rootContext.playTrack(model.videoId, model.title, model.artist, model.cover, undefined, model.artistId, model.albumId)
                            }
                        }
                    }
                }
            }
        }
        
        // Dynamic Playlists Grid
        Flow {
            id: playlistsSection
            Layout.fillWidth: true
            spacing: 16

            property bool hasData: rootContext.libraryPlaylists.count > 0 || rootContext.libraryLikedSongCount > 0
            visible: hasData
            Layout.topMargin: 32
            property int targetCellWidth: 180
            property int columns: Math.max(1, Math.floor((width + spacing) / (targetCellWidth + spacing)))
            property int cellWidth: Math.floor((width - Math.max(0, columns - 1) * spacing) / columns)
            
            // Liked Songs Card
            MusicPlaylistCard {
                id: likedCard
                rootContext: root.rootContext
                width: playlistsSection.cellWidth
                
                // Construct a dummy model that mimics what MusicPlaylistCard expects
                playlistModel: ({
                    id: "LM",
                    title: "Liked Songs",
                    author: rootContext.libraryLikedSongCount + " Songs",
                    cover: "", // Will use fallback art if empty
                    isLikedSongs: true // Flag to trigger custom heart icon logic if needed
                })
                
                artPlaceholderColor: rootContext ? rootContext.pillColor : Appearance.colors.colPrimaryContainer
            }
            
            // Regular Playlists
            Repeater {
                model: rootContext.libraryPlaylists
                
                delegate: MusicPlaylistCard {
                    rootContext: root.rootContext
                    width: playlistsSection.cellWidth
                    playlistModel: model
                    artPlaceholderColor: root.artPlaceholderColor
                }
            }
        }

        // Community Playlists (From the community)
        ColumnLayout {
            id: communitySection
            Layout.fillWidth: true
            spacing: 16

            property bool hasData: rootContext.libraryCommunityPlaylists.count > 0
            visible: hasData
            Layout.topMargin: 32

            StyledText {
                text: "From the community"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext.contentColor
            }

            MusicHorizontalFlickable {
                id: communityRow
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                implicitHeight: 220
                contentWidth: communityContentRow.implicitWidth
                contentHeight: communityContentRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: communityContentRow
                    spacing: 16

                    Repeater {
                        model: rootContext.libraryCommunityPlaylists

                        delegate: MusicPlaylistCard {
                            rootContext: root.rootContext
                            width: 180
                            playlistModel: model
                            artPlaceholderColor: root.artPlaceholderColor
                        }
                    }
                }
            }
        }
    }
}
