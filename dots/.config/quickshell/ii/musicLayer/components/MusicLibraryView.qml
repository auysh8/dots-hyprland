import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root

    property var rootContext
    property string queryText: ""
    readonly property var flickable: root
    readonly property color sectionCardColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.7) : "#24ffffff"
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : "#2f3239"

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
        spacing: 32

        // Header
        RowLayout {
            Layout.fillWidth: true
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
                colBackground: Appearance.colors.colLayer2
                
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
                    color: rootContext.subtextColor
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
                            color: ColorUtils.overlayForeground(connectRow.btnColor, "primary")
                        }
                        StyledText {
                            text: "Connect Account"
                            font.pixelSize: 14
                            font.weight: 700
                            color: ColorUtils.overlayForeground(connectRow.btnColor, "primary")
                        }
                    }
                    
                    onClicked: rootContext.refreshAuth()
                }
            }
        }

        // Recently Played
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.libraryRecentTracks.count > 0

            StyledText {
                text: "Recently Played"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext.contentColor
            }

            ListView {
                id: recentRow
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 800
                model: rootContext.libraryRecentTracks

                delegate: Item {
                    width: 160
                    height: 220

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        Rectangle {
                            id: recentArtContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            radius: 14
                            color: root.artPlaceholderColor
                            
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: recentArtContainer.width; height: recentArtContainer.height; radius: 14 }
                            }

                            Image {
                                anchors.fill: parent
                                source: model.cover || ""
                                sourceSize.width: 272
                                sourceSize.height: 272
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    rootContext.playTrack(model.videoId, model.title, model.artist, model.cover)
                                }
                            }
                        }

                        StyledText {
                            text: model.title
                            Layout.fillWidth: true
                            font.pixelSize: 14
                            font.weight: 600
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                        }
                        
                        StyledText {
                            text: model.artist
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: rootContext.secondaryContentColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
        
        // Dynamic Playlists Grid
        Flow {
            Layout.fillWidth: true
            spacing: 16
            
            // Liked Songs Card (Special vibrant one)
            Rectangle {
                width: Math.max(260, (parent.width - 16) / 2) // takes more space
                height: 180
                radius: 20
                clip: true
                color: "#2575FC" // solid fallback
                
                // Background image (with heavy blur/darkening to act as gradient)
                Image {
                    id: likedSongsBg
                    anchors.fill: parent
                    source: rootContext.libraryLikedSongArt || ""
                    sourceSize.width: 272
                    sourceSize.height: 272
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    opacity: 0.8
                    visible: source !== ""
                    
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle { width: likedSongsBg.width; height: likedSongsBg.height; radius: 20 }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rootContext.openPlaylist("LM")
                }
                
                // Overlay gradient to blend text
                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#aa6A11CB" }
                        GradientStop { position: 1.0; color: "#dd2575FC" }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    
                    Rectangle {
                        width: 40; height: 40; radius: 20
                        color: "white"
                        opacity: 0.2
                        MaterialSymbol { anchors.centerIn: parent; text: "favorite"; color: "white" }
                    }
                    
                    Item { Layout.fillHeight: true }
                    
                    StyledText {
                        text: "Liked Songs"
                        font.pixelSize: 28
                        font.weight: 800
                        color: "white"
                    }
                    StyledText {
                        text: rootContext.libraryLikedSongCount + " Songs"
                        font.pixelSize: 14
                        color: ColorUtils.transparentize("white", 0.8)
                    }
                }
                
                // Play button
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.right: parent.right
                    anchors.margins: 20
                    width: 48; height: 48; radius: 24; color: "white"
                    MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; color: "black"; iconSize: 28 }
                }
            }
            
            // Regular Playlists
            Repeater {
                model: rootContext.libraryPlaylists
                
                delegate: Rectangle {
                    width: Math.max(180, (parent.width - 16 * 4) / 4)
                    height: 180
                    radius: 20
                    color: playlistHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : root.sectionCardColor
                    border.width: 1
                    border.color: ColorUtils.transparentize("white", 0.9)
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        
                        Rectangle {
                            id: playlistArtContainer
                            width: 60; height: 60; radius: 10
                            color: root.artPlaceholderColor
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: playlistArtContainer.width; height: playlistArtContainer.height; radius: 10 }
                            }

                            Image {
                                anchors.fill: parent
                                source: model.cover || ""
                                sourceSize.width: 120
                                sourceSize.height: 120
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                        }
                        Item { Layout.fillHeight: true }
                        
                        StyledText {
                            text: model.title
                            font.pixelSize: 18
                            font.weight: 700
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                        }
                        StyledText {
                            text: model.count + " songs"
                            font.pixelSize: 13
                            color: rootContext.secondaryContentColor
                            visible: model.count !== "0" && model.count !== undefined
                        }
                    }

                    MouseArea {
                        id: playlistHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootContext.openPlaylist(model.id)
                    }
                }
            }
        }

        // Community Playlists (Based on History)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.libraryCommunityPlaylists.count > 0

            StyledText {
                text: "Discover from History"
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
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 800
                model: rootContext.libraryCommunityPlaylists

                delegate: Item {
                    width: 160
                    height: 220

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        Rectangle {
                            id: commArtContainer
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            radius: 14
                            color: root.artPlaceholderColor
                            
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: commArtContainer.width; height: commArtContainer.height; radius: 14 }
                            }

                            Image {
                                anchors.fill: parent
                                source: model.cover || ""
                                sourceSize.width: 272
                                sourceSize.height: 272
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.openPlaylist(model.id)
                            }
                        }

                        StyledText {
                            text: model.title
                            Layout.fillWidth: true
                            font.pixelSize: 14
                            font.weight: 600
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                        }
                        
                        StyledText {
                            text: model.artist
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: rootContext.secondaryContentColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
