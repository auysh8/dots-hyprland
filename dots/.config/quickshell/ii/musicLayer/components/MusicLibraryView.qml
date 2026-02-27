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
    
    // Add dummy content till I add backend data if you want to preview UI
    property var dummyRecent: [
        {"title": "Dawn FM", "artist": "The Weeknd", "cover": "https://lh3.googleusercontent.com/9nF_aBqL1Q12Ie1eGjG7VzB9JIfqE2EbxF6Fz0Q8o7F15pM-m-w7gKQK1X0D6oO5_S012tZ2gZ=w544-h544-l90-rj"},
        {"title": "Optimist", "artist": "FINNEAS", "cover": "https://lh3.googleusercontent.com/4SjA6T1T6mJ3CjGmV5D_O7zQ3aC8C2qL3F0Z7A6F15pM-m-w7gKQK1X0D6oO5=w544-h544-l90-rj"},
        {"title": "Planet Her", "artist": "Doja Cat", "cover": "https://lh3.googleusercontent.com/F2w8Z8Z9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9A9=w544-h544-l90-rj"},
        {"title": "Justice", "artist": "Justin Bieber", "cover": "https://lh3.googleusercontent.com/A6F15pM-m-w7gKQK1X0D6oO5_S012tZ2gZ=w544-h544-l90-rj"},
        {"title": "Nectar", "artist": "Joji", "cover": "https://lh3.googleusercontent.com/9nF_aBqL1Q12Ie1eGjG7VzB9JIfqE2EbxF6Fz0Q8o7F15pM-m-w7gKQK1X0D6oO5_S012tZ2gZ=w544-h544-l90-rj"}
    ]

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
        }

        // Filters Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            
            // Reusing basic pill concept
            Repeater {
                model: ["Playlists", "Albums", "Artists"]
                delegate: Rectangle {
                    height: 36
                    width: filterText.implicitWidth + 32
                    radius: 18
                    color: filterHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"
                    border.width: 1
                    border.color: ColorUtils.transparentize(rootContext.contentColor, 0.7)
                    
                    Behavior on color { ColorAnimation { duration: 150 } }
                    
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: index === 0 ? "queue_music" : index === 1 ? "album" : "mic"
                            color: rootContext.contentColor
                            iconSize: 18
                        }
                        StyledText {
                            id: filterText
                            text: modelData
                            font.pixelSize: 14
                            font.weight: 600
                            color: rootContext.contentColor
                        }
                    }
                    MouseArea {
                        id: filterHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }

        // Recently Played
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            StyledText {
                text: "Recently Played"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext.contentColor
            }

            ListView {
                id: recentRow
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                
                // using dummy for now
                model: root.dummyRecent

                delegate: Item {
                    width: 120
                    height: 180

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            radius: 14
                            color: root.artPlaceholderColor
                            
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: parent.width; height: parent.height; radius: 14 }
                            }

                            Image {
                                anchors.fill: parent
                                source: modelData.cover
                                fillMode: Image.PreserveAspectCrop
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                            }
                        }

                        StyledText {
                            text: modelData.title
                            Layout.fillWidth: true
                            font.pixelSize: 14
                            font.weight: 600
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                        }
                        
                        StyledText {
                            text: modelData.artist
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
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#6A11CB" }
                    GradientStop { position: 1.0; color: "#2575FC" }
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
                        text: "356 Songs"  // Will use libraryLikedSongCount later
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
            
            // Regular Playlists (Dummy for now)
            Repeater {
                model: [
                    {"name": "Workout Mix", "count": 60, "color": "#1A1A1D"},
                    {"name": "Chill Vibes", "count": 120, "color": "#232b2b"},
                    {"name": "Late Night Jazz", "count": 45, "color": "#1f1d24"}
                ]
                
                delegate: Rectangle {
                    width: Math.max(180, (parent.width - 16 * 4) / 4)
                    height: 180
                    radius: 20
                    color: root.sectionCardColor
                    border.width: 1
                    border.color: ColorUtils.transparentize("white", 0.9)
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        
                        Rectangle {
                            width: 60; height: 60; radius: 10
                            color: modelData.color
                            // placeholder image goes here later
                        }
                        Item { Layout.fillHeight: true }
                        
                        StyledText {
                            text: modelData.name
                            font.pixelSize: 18
                            font.weight: 700
                            color: rootContext.contentColor
                        }
                        StyledText {
                            text: modelData.count + " songs"
                            font.pixelSize: 13
                            color: rootContext.secondaryContentColor
                        }
                    }
                }
            }
        }
    }
}
