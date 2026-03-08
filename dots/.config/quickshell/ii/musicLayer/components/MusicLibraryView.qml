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
            id: recentSection
            Layout.fillWidth: true
            spacing: 16

            property bool hasData: rootContext.libraryRecentTracks.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 16 : -height

            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            StyledText {
                text: "Recently Played"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext.contentColor
            }

            Flickable {
                id: recentRow
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                contentWidth: recentRowContent.width
                contentHeight: 280
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: recentRowContent
                    spacing: 0

                    Repeater {
                        model: rootContext.libraryRecentTracks

                        delegate: Item {
                            width: Math.max(1, (recentRow.width - 20) / 4)
                            height: 280

                            Rectangle {
                                id: recentCard
                                anchors.fill: parent
                                anchors.margins: 8
                                radius: 20
                                color: recentHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"
                                
                                Behavior on color { ColorAnimation { duration: 200 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 12
                                    anchors.bottomMargin: 16
                                    spacing: 12

                                    Rectangle {
                                        id: recentArtContainer
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: width
                                        radius: 20
                                        color: root.artPlaceholderColor
                                        
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle { width: recentArtContainer.width; height: recentArtContainer.height; radius: 20 }
                                        }

                                        Image {
                                            anchors.fill: parent
                                            source: model.cover || ""
                                            sourceSize.width: 272
                                            sourceSize.height: 272
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            visible: status === Image.Ready
                                            
                                            scale: recentHover.containsMouse ? 1.1 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                        }
                                        
                                        Rectangle {
                                            anchors.fill: parent
                                            color: "#60000000"
                                            opacity: recentHover.containsMouse ? 1.0 : 0.0
                                            
                                            Behavior on opacity { NumberAnimation { duration: 200 } }

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: "play_arrow"
                                                color: "white"
                                                iconSize: 42
                                                scale: recentHover.containsMouse ? 1.0 : 0.5
                                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        StyledText {
                                            text: model.title
                                            Layout.fillWidth: true
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

                                MouseArea {
                                    id: recentHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rootContext.playTrack(model.videoId, model.title, model.artist, model.cover)
                                }
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
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 32 : -height

            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
            
            // Liked Songs Card (Special vibrant one)
            Rectangle {
                width: Math.max(260, (parent.width - 16) / 2) // takes more space
                height: 220
                radius: 20
                clip: true
                
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#7a31e8" }
                    GradientStop { position: 1.0; color: "#3a73f8" }
                }
                
                // Huge watermark icon
                MaterialSymbol {
                    text: "thumb_up"
                    color: "white"
                    opacity: 0.15
                    iconSize: 220
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -40
                    anchors.bottomMargin: -40
                    rotation: -15
                }
                
                MouseArea {
                    id: likedHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: rootContext.openPlaylist("LM")
                }

                // Subtly darken on hover
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    radius: 20
                    opacity: likedHover.containsMouse ? 0.15 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
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
                    height: 220
                    radius: 20
                    color: playlistHover.containsMouse ? "#121212" : "#050505"
                    border.width: 1
                    border.color: "#1c1c1c"
                    
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

                    // Play buttons
                    ColumnLayout {
                        z: 1
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.margins: 14
                        spacing: 8
                        
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 40; height: 40; radius: 20; color: "white"
                            MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; color: "black"; iconSize: 26 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.openAndPlayPlaylist(model.id, false)
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 36; height: 36; radius: 18; color: "transparent"
                            MaterialSymbol { anchors.centerIn: parent; text: "shuffle"; color: "white"; iconSize: 22 }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.openAndPlayPlaylist(model.id, true) // true for shuffle
                            }
                            
                            // subtle hover
                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: "white"
                                opacity: parent.children[1].containsMouse ? 0.1 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
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

        // Community Playlists (From the community)
        ColumnLayout {
            id: communitySection
            Layout.fillWidth: true
            spacing: 16

            property bool hasData: rootContext.libraryCommunityPlaylists.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 32 : -height

            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            StyledText {
                text: "From the community"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext.contentColor
            }

            Flickable {
                id: communityRow
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                contentWidth: communityRowContent.width
                contentHeight: 220
                flickableDirection: Flickable.HorizontalFlick
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: communityRowContent
                    spacing: 16

                    Repeater {
                        model: rootContext.libraryCommunityPlaylists

                        delegate: Rectangle {
                            width: Math.max(180, (communityRow.width - 16 * 4) / 4)
                            height: 220
                            radius: 20
                            color: commHover.containsMouse ? "#121212" : "#050505"
                            border.width: 1
                            border.color: "#1c1c1c"
                            
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                
                                Rectangle {
                                    id: commArtContainer
                                    width: 60; height: 60; radius: 10
                                    color: root.artPlaceholderColor
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle { width: commArtContainer.width; height: commArtContainer.height; radius: 10 }
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
                                    text: model.artist
                                    font.pixelSize: 13
                                    color: rootContext.secondaryContentColor
                                }
                            }

                            // Play buttons
                            ColumnLayout {
                                z: 1
                                anchors.top: parent.top; anchors.right: parent.right
                                anchors.margins: 14
                                spacing: 8
                                
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 40; height: 40; radius: 20; color: "white"
                                    MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; color: "black"; iconSize: 26 }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: rootContext.openAndPlayPlaylist(model.id, false)
                                    }
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 36; height: 36; radius: 18; color: "transparent"
                                    MaterialSymbol { anchors.centerIn: parent; text: "shuffle"; color: "white"; iconSize: 22 }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: rootContext.openAndPlayPlaylist(model.id, true)
                                    }
                                    
                                    // subtle hover
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: "white"
                                        opacity: parent.children[1].containsMouse ? 0.1 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }
                                }
                            }

                            MouseArea {
                                id: commHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.openPlaylist(model.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
