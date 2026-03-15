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
    readonly property color sectionCardColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.7) : Appearance.colors.colLayer1
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : Appearance.colors.colLayer2
    readonly property color cardHoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"

    property bool show: queryText.length === 0 && rootContext.currentView === "library" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: libraryLayout.implicitHeight + (rootContext.currentTrack ? 120 : 32)
    
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
                Layout.preferredWidth: signInRow.implicitWidth + 32
                Layout.preferredHeight: 36
                buttonRadius: 18
                colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colLayer2
                
                contentItem: RowLayout {
                    id: signInRow
                    anchors.centerIn: parent
                    spacing: 8
                    
                    MaterialSymbol {
                        text: rootContext.isAuthenticated ? "sync" : "account_circle"
                        font.pixelSize: 18
                        color: rootContext.contentColor
                    }
                    StyledText {
                        text: rootContext.isAuthenticated ? "Refresh" : "Sign In"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext.contentColor
                    }
                }
                
                onClicked: {
                    rootContext.refreshAuth()
                }
            }
        }


        // Auth Setup Instruction (when not authenticated)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: authInstructionLayout.implicitHeight + 32
            radius: 16
            color: root.sectionCardColor
            visible: !rootContext.isAuthenticated
            
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
                        color: rootContext.extractedColor || rootContext.pillContentColor
                    }
                    StyledText {
                        text: "Connect YouTube Music"
                        font.pixelSize: 18
                        font.weight: 700
                        color: rootContext.contentColor
                    }
                }
                
                StyledText {
                    Layout.fillWidth: true
                    text: "Sign in to your YouTube Music account to see your liked songs, playlists, and listening history. Make sure you're logged into YouTube Music in your browser first."
                    font.pixelSize: 13
                    font.weight: 400
                    color: rootContext.secondaryContentColor
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                }
                
                RippleButton {
                    Layout.preferredWidth: connectRow.implicitWidth + 28
                    Layout.preferredHeight: 38
                    buttonRadius: 19
                    
                    contentItem: RowLayout {
                        id: connectRow
                        anchors.centerIn: parent
                        spacing: 8
                        
                        property color btnColor: rootContext.extractedColor || rootContext.pillColor
                        
                        MaterialSymbol {
                            text: "link"
                            font.pixelSize: 18
                            color: rootContext ? rootContext.extractedForeground : Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: "Connect Account"
                            font.pixelSize: 14
                            font.weight: 700
                            color: rootContext ? rootContext.extractedForeground : Appearance.colors.colOnPrimary
                        }
                    }
                    
                    onClicked: rootContext.refreshAuth()
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

                                    ListView {
                id: recentGrid
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                orientation: ListView.Horizontal
                spacing: 0
                clip: true
                cacheBuffer: 1200

                model: rootContext.libraryRecentTracks

                delegate: MusicMediaCard {
                    width: 240
                    height: 280
                    rootContext: root.rootContext
                    itemData: model
                    hoverColor: root.cardHoverColor
                    artPlaceholderColor: root.artPlaceholderColor
                    
                    onClicked: {
                        rootContext.playTrack(model.videoId, model.title, model.artist, model.cover)
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
            
            // Liked Songs Card (Special vibrant one)
            RippleButton {
                id: likedCard
                width: Math.max(260, (parent.width - 16) / 2) // takes more space
                height: 220
                buttonRadius: 20
                clip: true
                
                property color cardColor: rootContext ? (rootContext.extractedColor || rootContext.pillColor) : Appearance.colors.colPrimary
                property color fgColor: rootContext ? rootContext.extractedForeground : (ColorUtils.isDark(cardColor) ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0)
                
                colBackground: cardColor
                colRipple: ColorUtils.applyAlpha(likedCard.fgColor, 0.2)
                
                Behavior on colBackground { ColorAnimation { duration: 600; easing.type: Easing.OutCubic } }
                
                onClicked: rootContext.openPlaylist("LM")
                
                contentItem: Item {
                    anchors.fill: parent
                    
                    // Huge watermark icon
                    MaterialSymbol {
                        text: "thumb_up"
                        color: likedCard.fgColor
                        opacity: 0.15
                        iconSize: 220
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: -40
                        anchors.bottomMargin: -40
                        rotation: -15
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        
                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: ColorUtils.applyAlpha(likedCard.fgColor, 0.15)
                            MaterialSymbol { anchors.centerIn: parent; text: "favorite"; color: likedCard.fgColor }
                        }
                        
                        Item { Layout.fillHeight: true }
                        
                        StyledText {
                            text: "Liked Songs"
                            font.pixelSize: 28
                            font.weight: 800
                            color: likedCard.fgColor
                        }
                        StyledText {
                            text: rootContext.libraryLikedSongCount + " Songs"
                            font.pixelSize: 14
                            color: ColorUtils.applyAlpha(likedCard.fgColor, 0.65)
                        }
                    }
                    
                    // Play button
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.right: parent.right
                        anchors.margins: 20
                        width: 48; height: 48; radius: 24; color: likedCard.fgColor
                        MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; color: likedCard.cardColor; iconSize: 28 }
                    }
                }
            }
            
            // Regular Playlists
            Repeater {
                model: rootContext.libraryPlaylists
                
                delegate: MusicPlaylistCard {
                    rootContext: root.rootContext
                    width: Math.max(180, (parent.width - 16 * 4) / 4)
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

                        ListView {
                id: communityRow
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                cacheBuffer: 1200
                
                model: rootContext.libraryCommunityPlaylists

                delegate: MusicPlaylistCard {
                    rootContext: root.rootContext
                    playlistModel: model
                    artPlaceholderColor: root.artPlaceholderColor
                }
            }
        }
    }
}
