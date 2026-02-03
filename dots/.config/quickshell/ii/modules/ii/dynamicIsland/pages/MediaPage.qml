import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

import "pages"

Item {
    id: root
    implicitHeight: mainLayout.implicitHeight + 32 // Add margins to height
    
    // Art Handling
    property string artUrl: (MprisController.activePlayer && MprisController.activePlayer.trackArtUrl) ? MprisController.activePlayer.trackArtUrl : ""
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: Qt.md5(artUrl)
    property string artFilePath: `${artDownloadLocation}/${artFileName}`

    property bool downloaded: false
    property string displayedArtFilePath: downloaded ? Qt.resolvedUrl(artFilePath) : ""
    
    onArtFilePathChanged: {
        if (root.artUrl.length == 0) return

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        // Download
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        // Check if file exists, if not download it
        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'` ]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true
        }
    }

    // Color Extraction
    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    // Extract dominant color or use default
    readonly property color extractedColor: {
        if (!downloaded || displayedArtFilePath.length === 0) {
            return Appearance.colors.colPrimary
        }
        let c = colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary
        return c
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.extractedColor, Appearance.colors.colPrimaryContainer, 0.8)
    }

    property color contentColor: blendedColors.colOnLayer0
    property color secondaryContentColor: blendedColors.colSubtext
    property color pillColor: blendedColors.colSecondaryContainer
    property color pillContentColor: blendedColors.colOnSecondaryContainer
    property color backgroundColor: blendedColors.colLayer0 

    Behavior on contentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on secondaryContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on backgroundColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }

    // Interpolated Position Logic
    property real currentPosition: 0
    
    Connections {
        target: MprisController.activePlayer || null
        ignoreUnknownSignals: true
        function onPositionChanged() {
            var diff = Math.abs(root.currentPosition - MprisController.activePlayer.position)
            if (diff > 1.5 || !MprisController.isPlaying) {
                root.currentPosition = MprisController.activePlayer.position
            }
        }
    }
    
    Timer {
        running: MprisController.isPlaying
        interval: 20
        repeat: true
        onTriggered: root.currentPosition += 0.02
    }

    Component.onCompleted: {
        if (MprisController.activePlayer) {
            root.currentPosition = MprisController.activePlayer.position
        }
    }

    // Background Art
    Item {
        anchors.fill: parent
        
        Image {
            id: bgArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        
        Rectangle {
            id: bgMask
            anchors.fill: parent
            radius: Appearance.rounding.normal
            visible: false
        }
        
        OpacityMask {
            anchors.fill: parent
            source: bgArt
            maskSource: bgMask
        }
        
        // Dark Overlay for readability
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.6
            radius: Appearance.rounding.normal
        }
        
        // Placeholder if no art
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            visible: bgArt.status !== Image.Ready || bgArt.source == ""
            z: -1
        }

        // Slight border
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Appearance.rounding.normal
            border.width: 2
            border.color: Appearance.colors.colLayer0Border
            opacity: 0.8
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 6

        // Top Info
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            
            Text {
                Layout.fillWidth: true
                text: MprisController.activeTrack.title || "No Media"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: root.contentColor
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }
            
            Text {
                Layout.fillWidth: true
                text: MprisController.activeTrack.artist || "Unknown Artist"
                font.pixelSize: 13
                color: root.secondaryContentColor
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }
        }

        // Squiggly Slider
        StyledSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 24 // Give it some room for the wave
            
            configuration: MprisController.isPlaying ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
            highlightColor: root.contentColor
            trackColor: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.5)
            handleColor: root.contentColor
            value: {
                const player = MprisController.activePlayer;
                return (player && player.length > 0) ? root.currentPosition / player.length : 0;
            }
            
            onMoved: {
                const player = MprisController.activePlayer;
                if (player) {
                    player.position = value * player.length;
                    root.currentPosition = player.position;
                }
            }
        }

        // Controls
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            // Lyrics Toggle (Keep small and simple)
             Item {
                implicitWidth: 32
                implicitHeight: 32
                
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: LyricsService.open ? root.pillColor : (hover.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1))
                    Behavior on color { ColorAnimation { duration: 150 } }
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "lyrics"
                        iconSize: 18
                        color: LyricsService.open ? root.pillContentColor : root.contentColor
                    }
                }
                
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: LyricsService.toggle()
                }
             }

            Item { Layout.fillWidth: true }

            // Previous Button (Oval/Pill with bounce)
            Item {
                id: prevBtn
                property bool isPressed: prevArea.pressed
                
                implicitWidth: 40 + (isPressed ? 8 : (playBtn.isPressed ? -6 : 0))
                implicitHeight: 40
                
                Behavior on implicitWidth { 
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }
                
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: prevArea.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_previous"
                        iconSize: 24
                        color: root.contentColor
                    }
                }
                
                MouseArea {
                    id: prevArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.previous()
                }
            }

            // Play/Pause Button (Squircle with bounce)
            Item {
                id: playBtn
                property bool isPressed: playArea.pressed
                
                implicitWidth: 60 + (isPressed ? 12 : (prevBtn.isPressed || nextBtn.isPressed ? -8 : 0))
                implicitHeight: 40
                
                Behavior on implicitWidth { 
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }
                
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: playArea.containsMouse ? Qt.darker(root.pillColor, 1.05) : root.pillColor
                    
                    Behavior on radius { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: MprisController.isPlaying ? "pause" : "play_arrow"
                        iconSize: 28
                        color: root.pillContentColor
                    }
                }
                
                MouseArea {
                    id: playArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.togglePlaying()
                }
            }

            // Next Button (Oval/Pill with bounce)
            Item {
                id: nextBtn
                property bool isPressed: nextArea.pressed
                
                implicitWidth: 40 + (isPressed ? 8 : (playBtn.isPressed ? -6 : 0))
                implicitHeight: 40
                
                Behavior on implicitWidth { 
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }
                
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: nextArea.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_next"
                        iconSize: 24
                        color: root.contentColor
                    }
                }
                
                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.next()
                }
            }

            Item { Layout.fillWidth: true }
            
             // Empty space
             Item { width: 28 }
        }
    }
}
