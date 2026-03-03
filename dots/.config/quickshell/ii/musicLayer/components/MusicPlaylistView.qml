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
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : "#2f3239"

    property bool show: rootContext && rootContext.currentView === "playlist" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: Math.max(height, playlistContainer.implicitHeight + (rootContext && rootContext.currentTrack ? 120 : 32))
    flickableDirection: Flickable.VerticalFlick

    onDraggingChanged: {
        if (!dragging && contentY < -120 && !rootContext.refreshing && !rootContext.isLoading) {
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
                color: rootContext ? rootContext.pillColor : "white"
            }

            StyledText {
                text: root.contentY < -100 ? "Release to refresh" : "Pull to refresh"
                font.weight: 600
                color: rootContext ? rootContext.contentColor : "white"
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
            
            Rectangle {
                width: 40; height: 40; radius: 20
                color: backHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "transparent"
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    color: rootContext.contentColor
                    iconSize: 24
                }
                
                MouseArea {
                    id: backHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (rootContext.previousView && rootContext.previousView !== "playlist")
                            rootContext.currentView = rootContext.previousView
                        else
                            rootContext.currentView = "library"
                    }
                }
            }
        }

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
                    color: rootContext ? rootContext.secondaryContentColor : "gray"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rootContext ? rootContext.activePlaylistTitle : ""
                    font.pixelSize: 48
                    font.weight: 800
                    color: rootContext ? rootContext.contentColor : "white"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rootContext ? rootContext.activePlaylistDescription : ""
                    font.pixelSize: 14
                    color: rootContext ? rootContext.secondaryContentColor : "gray"
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
                        color: rootContext ? rootContext.contentColor : "white"
                        visible: text.length > 0
                    }
                    StyledText {
                        text: "•"
                        font.pixelSize: 14
                        color: rootContext ? rootContext.secondaryContentColor : "gray"
                        visible: rootContext && rootContext.activePlaylistAuthor.length > 0
                    }
                    StyledText {
                        text: rootContext ? rootContext.activePlaylistTrackCount + " songs" : ""
                        font.pixelSize: 14
                        color: rootContext ? rootContext.secondaryContentColor : "gray"
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
                        colBackground: rootContext ? rootContext.extractedColor || rootContext.pillColor : "white"
                        
                        property color txColor: ColorUtils.overlayForeground(colBackground, "primary")
                        
                        contentItem: RowLayout {
                            id: playRow
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol { text: "play_arrow"; color: parent.parent.txColor; iconSize: 24 }
                            StyledText { text: "Play"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
                        }
                        
                        onClicked: {
                            if (rootContext && rootContext.activePlaylistTracks.count > 0) {
                                let first = rootContext.activePlaylistTracks.get(0)
                                rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl || rootContext.activePlaylistCover)
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
            color: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.7) : "#20ffffff"

            ColumnLayout {
                id: tracksColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: rootContext ? rootContext.activePlaylistTracks : null

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 64
                        radius: 12
                        color: trackHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 16

                            StyledText {
                                text: (index + 1).toString()
                                font.pixelSize: 14
                                Layout.preferredWidth: 32
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignVCenter
                                color: rootContext.secondaryContentColor
                            }

                            Rectangle {
                                width: 48
                                height: 48
                                radius: 8
                                color: ColorUtils.transparentize(rootContext.pillColor, 0.5)

                                RoundedImage {
                                    anchors.fill: parent
                                    source: model.artUrl || rootContext.activePlaylistCover || ""
                                    sourceSize.width: 96
                                    sourceSize.height: 96
                                    fillMode: Image.PreserveAspectCrop
                                    radius: 8
                                    asynchronous: true
                                    cache: true
                                }
                                
                                Rectangle {
                                    anchors.fill: parent
                                    color: "#40000000"
                                    radius: 8
                                    visible: trackHover.containsMouse || (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) ? (rootContext.playbackPaused ? "play_arrow" : "pause") : "play_arrow"
                                        color: "white"
                                        iconSize: 24
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: model.title
                                    font.weight: 600
                                    color: (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) ? (rootContext.extractedColor || rootContext.pillColor) : rootContext.contentColor
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignLeft
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: model.artist
                                    font.pixelSize: 12
                                    color: rootContext.secondaryContentColor
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignLeft
                                }
                            }

                            StyledText {
                                text: (model.duration && model.duration.length > 0) ? model.duration : "--:--"
                                color: rootContext.secondaryContentColor
                                font.pixelSize: 12
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: trackHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) {
                                    rootContext.toggle() // Pause/play
                                } else {
                                    rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl || rootContext.activePlaylistCover)
                                }
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
