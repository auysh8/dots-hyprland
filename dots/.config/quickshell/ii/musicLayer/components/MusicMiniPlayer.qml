import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var rootContext
    property bool navRailExpanded: false
    readonly property color elevatedPanelColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

    visible: rootContext && rootContext.currentTrack !== null
    z: 100

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // Played Section
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: "Played"
                font.pixelSize: Appearance.font.pixelSize.xlarge
                font.weight: 600
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                Layout.fillWidth: true
            }
        }

        // History/Queue Items with ListView for Animations
        StyledListView {
            id: historyList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: count > 0 ? (Math.min(10, count) * (64 + 14) - 14) : 0
            Layout.maximumHeight: count > 0 ? (Math.min(10, count) * (64 + 14) - 14) : 0
            spacing: 14
            interactive: true // Allow scrolling if it exceeds
            clip: true
            
            model: rootContext ? rootContext.libraryRecentTracks : null
            
            // Slide and bounce down existing items
            displaced: Transition {
                NumberAnimation { properties: "x,y"; duration: 500; easing.type: Easing.OutBack }
            }
            // Add new items with slide and bounce + fade
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400 }
                NumberAnimation { properties: "x,y"; from: -30; duration: 500; easing.type: Easing.OutBack }
            }

            delegate: MusicListTrackItem {
                width: historyList.width
                rootContext: root.rootContext
                track: model
                fallbackArtUrl: model.cover || ""
                
                onClicked: {
                    if (rootContext && rootContext.playTrack) {
                        rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl || model.cover, undefined, model.artistId, model.albumId)
                    }
                }
            }
        }

        Item { Layout.fillHeight: true } // spacer to push player card to bottom

        // Giant Now Playing Card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: width * 1.1 // Tall card ratio
            radius: 24
            color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer2
            clip: true
            
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.3)
                shadowBlur: 1.0
                shadowVerticalOffset: 8
            }

            RoundedImage {
                anchors.fill: parent
                source: rootContext ? rootContext.displayedArtFilePath : ""
                fillMode: Image.PreserveAspectCrop
                radius: 24
            }
            
            // Gradient overlay for text readability
            Rectangle {
                anchors.fill: parent
                radius: 24
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "transparent" }
                    GradientStop { position: 1.0; color: "#CC000000" }
                }
            }

            // Text Info + Add Button
            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 20
                spacing: 12
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    
                    StyledText {
                        text: rootContext && rootContext.currentTrack ? rootContext.currentTrack.title : ""
                        font.pixelSize: 20
                        font.weight: 700
                        color: "white"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: rootContext && rootContext.currentTrack ? rootContext.currentTrack.artist : ""
                        font.pixelSize: 14
                        color: "#DDDDDD"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                

            }

            // Click to open full player
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (rootContext && rootContext.currentTrack) {
                        rootContext.currentView = "player"
                    }
                }
            }
        }
    }
}
