import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    
    // Properties
    property bool isFullscreen: false
    property bool centeredMode: false
    
    property string albumArt: ""
    property bool artLoading: false
    
    property string displayTitle: ""
    property string displayArtist: ""
    
    property color contentColor: "white"
    property color secondaryContentColor: "gray"
    property color pillColor: "white"
    property color pillContentColor: "black"
    
    property var activePlayer: null
    property bool isPlaying: false
    property real duration: 0
    property real position: 0
    
    signal seek(real seconds)

    function formatTime(seconds) {
        if (isNaN(seconds) || seconds < 0) return "0:00";
        let h = Math.floor(seconds / 3600);
        let m = Math.floor((seconds % 3600) / 60);
        let s = Math.floor(seconds % 60);
        if (h > 0) {
            return h + ":" + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
        }
        return m + ":" + (s < 10 ? "0" + s : s);
    }
    
    Layout.preferredWidth: centeredMode ? 500 : (isFullscreen ? 420 : 260)
    Layout.maximumWidth: centeredMode ? 500 : (isFullscreen ? 420 : 260)
    Layout.fillHeight: true
    spacing: isFullscreen ? 24 : 16

    // Spacer to center content vertically in fullscreen
    Item { Layout.fillHeight: isFullscreen; visible: isFullscreen }

    // Album art item
    Item {
        Layout.preferredWidth: isFullscreen ? 380 : 200
        Layout.preferredHeight: isFullscreen ? 380 : 200
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 60 // Push down to avoid overlap with player badge

        Image {
            id: albumImage
            anchors.fill: parent
            source: root.albumArt
            fillMode: Image.PreserveAspectCrop
            visible: false
            asynchronous: true
        }

        Rectangle {
            id: maskRect
            anchors.fill: parent
            radius: 16
            visible: false
        }

        OpacityMask {
            anchors.fill: parent
            source: albumImage
            maskSource: maskRect
            visible: root.albumArt !== "" && !root.artLoading
        }

        // Loading indicator
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Appearance.m3colors.m3surfaceContainerHighest
            visible: root.artLoading

            Text {
                anchors.centerIn: parent
                text: "Loading..."
                color: "white"
                font.pixelSize: 14
            }
        }

        // Placeholder
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Appearance.m3colors.m3surfaceContainerHighest
            visible: root.albumArt === "" && !root.artLoading

            MaterialSymbol {
                anchors.centerIn: parent
                text: "music_note"
                iconSize: 64
                color: "#888"
            }
        }
    }

    // Title
    Text {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.artLoading ? "Loading..." : (root.displayTitle || "No song playing")
        color: root.contentColor
        font.pixelSize: isFullscreen ? 28 : 22
        font.weight: Font.Bold
        font.family: "Inter, Segoe UI, sans-serif"
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
        opacity: root.artLoading ? 0.5 : 1.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Artist
    Text {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.artLoading ? "..." : (root.displayArtist || "Unknown Artist")
        color: root.secondaryContentColor
        font.pixelSize: isFullscreen ? 20 : 16
        font.family: "Inter, Segoe UI, sans-serif"
        elide: Text.ElideRight
        opacity: root.artLoading ? 0.5 : 1.0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Flexible spacer
    Item { Layout.fillHeight: true }

    // --- CONTROLS SECTION ---
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        // Progress Bar
        Item {
            id: progressBarContainer
            Layout.fillWidth: true
            implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

            Loader {
                id: sliderLoader
                anchors.fill: parent
                active: root.activePlayer?.canSeek ?? false
                sourceComponent: StyledSlider {
                    configuration: root.isPlaying ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
                    highlightColor: root.contentColor 
                    trackColor: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                    handleColor: root.contentColor
                    value: root.duration > 0 ? root.position / root.duration : 0
                    onMoved: {
                        root.seek(value * root.duration);
                    }
                }
            }

            Loader {
                id: progressBarLoader
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    right: parent.right
                }
                active: !(root.activePlayer?.canSeek ?? false)
                sourceComponent: StyledProgressBar {
                    wavy: root.isPlaying
                    highlightColor: root.contentColor
                    trackColor: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                    value: root.duration > 0 ? root.position / root.duration : 0
                }
            }
        }

        // Time Labels
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.formatTime(root.position)
                color: root.secondaryContentColor
                font.pixelSize: 13
                font.family: "Inter, Segoe UI, sans-serif"
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.formatTime(root.duration)
                color: root.secondaryContentColor
                font.pixelSize: 13
                font.family: "Inter, Segoe UI, sans-serif"
            }
        }

        // Buttons
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: isFullscreen ? 90 : 64
            
            RowLayout {
                anchors.centerIn: parent
                spacing: isFullscreen ? 6 : 4

                // Previous Button
                Item {
                    id: prevBtnContainer
                    property bool isPressed: prevArea.pressed
                    
                    implicitWidth: (isFullscreen ? 80 : 64) + (isPressed ? 16 : (playBtnContainer.isPressed ? -10 : 0))
                    implicitHeight: isFullscreen ? 75 : 60
                    
                    Behavior on implicitWidth { 
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight { 
                        NumberAnimation { 
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        } 
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: prevArea.containsMouse 
                            ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                            : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 28
                            fill: 1
                            color: root.contentColor
                            text: "skip_previous"
                        }
                    }
                    
                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activePlayer?.previous()
                    }
                }

                // Play/Pause Button
                Item {
                    id: playBtnContainer
                    property bool isPressed: playArea.pressed
                    
                    implicitWidth: (isFullscreen ? 170 : 130) + (isPressed ? 20 : (prevBtnContainer.isPressed ? -16 : (nextBtnContainer.isPressed ? -16 : 0)))
                    implicitHeight: isFullscreen ? 75 : 60
                    
                    Behavior on implicitWidth { 
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight { 
                        NumberAnimation { 
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        } 
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: playBtnContainer.isPressed ? 20 : 24
                        color: playArea.containsMouse 
                            ? Qt.darker(root.pillColor, 1.05)
                            : root.pillColor
                        
                        Behavior on radius { NumberAnimation { duration: 200 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 40
                            fill: 1
                            color: root.pillContentColor
                            text: root.isPlaying ? "pause" : "play_arrow"
                        }
                    }
                    
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activePlayer?.togglePlaying()
                    }
                }

                // Next Button
                Item {
                    id: nextBtnContainer
                    property bool isPressed: nextArea.pressed
                    
                    implicitWidth: (isFullscreen ? 80 : 64) + (isPressed ? 16 : (playBtnContainer.isPressed ? -10 : 0))
                    implicitHeight: isFullscreen ? 75 : 60
                    
                    Behavior on implicitWidth { 
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight { 
                        NumberAnimation { 
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        } 
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: nextArea.containsMouse 
                            ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2)
                            : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 28
                            fill: 1
                            color: root.contentColor
                            text: "skip_next"
                        }
                    }
                    
                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activePlayer?.next()
                    }
                }
            }
        }
    }
}
