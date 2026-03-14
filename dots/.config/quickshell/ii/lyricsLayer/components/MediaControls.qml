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
            sourceSize.width: 400
            sourceSize.height: 400
            antialiasing: true
            smooth: true
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
            color: ColorUtils.applyAlpha(root.contentColor, 0.1)
            visible: root.artLoading

            StyledText {
                anchors.centerIn: parent
                text: "Loading..."
                color: root.contentColor
                font.pixelSize: 14
            }
        }

        // Placeholder
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: ColorUtils.applyAlpha(root.contentColor, 0.1)
            visible: root.albumArt === "" && !root.artLoading

            MaterialSymbol {
                anchors.centerIn: parent
                text: "music_note"
                iconSize: 64
                color: root.secondaryContentColor
            }
        }
    }

    // Title
    StyledText {
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
    StyledText {
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
                    trackColor: ColorUtils.applyAlpha(root.contentColor, 0.2)
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
                    trackColor: ColorUtils.applyAlpha(root.contentColor, 0.2)
                    value: root.duration > 0 ? root.position / root.duration : 0
                }
            }
        }

        // Time Labels
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: StringUtils.friendlyTimeForSeconds(root.position)
                color: root.secondaryContentColor
                font.pixelSize: 13
                font.family: "Inter, Segoe UI, sans-serif"
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: StringUtils.friendlyTimeForSeconds(root.duration)
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
                RippleButton {
                    id: prevBtnContainer

                    Layout.preferredWidth: (isFullscreen ? 80 : 64) + (down ? 16 : (playBtnContainer.down ? -10 : 0))
                    Layout.preferredHeight: isFullscreen ? 75 : 60
                    buttonRadius: down ? 24 : Layout.preferredHeight / 2

                    colBackground: ColorUtils.applyAlpha(root.contentColor, 0.12)
                    colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.2)
                    colRipple: root.contentColor

                    onClicked: root.activePlayer?.previous()

                    Behavior on Layout.preferredWidth { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Behavior on Layout.preferredHeight { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 } 
                    }
                    Behavior on buttonRadius { 
                        NumberAnimation { duration: 200 }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 28
                        fill: 1
                        color: root.contentColor
                        text: "skip_previous"
                    }
                }

                // Play/Pause Button
                RippleButton {
                    id: playBtnContainer

                    Layout.preferredWidth: (isFullscreen ? 170 : 130) + (down ? 20 : (prevBtnContainer.down ? -16 : (nextBtnContainer.down ? -16 : 0)))
                    Layout.preferredHeight: isFullscreen ? 75 : 60
                    buttonRadius: down ? 20 : 24
                    
                    Behavior on buttonRadius { NumberAnimation { duration: 200 } }

                    colBackground: root.pillColor
                    colBackgroundHover: Qt.darker(root.pillColor, 1.05)
                    colRipple: root.pillContentColor

                    onClicked: root.activePlayer?.togglePlaying()

                    Behavior on Layout.preferredWidth { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Behavior on Layout.preferredHeight { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 } 
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 40
                        fill: 1
                        color: root.pillContentColor
                        text: root.isPlaying ? "pause" : "play_arrow"
                    }
                }

                // Next Button
                RippleButton {
                    id: nextBtnContainer
                    
                    Layout.preferredWidth: (isFullscreen ? 80 : 64) + (down ? 16 : (playBtnContainer.down ? -10 : 0))
                    Layout.preferredHeight: isFullscreen ? 75 : 60
                    buttonRadius: down ? 24 : Layout.preferredHeight / 2

                    colBackground: ColorUtils.applyAlpha(root.contentColor, 0.12)
                    colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.2)
                    colRipple: root.contentColor

                    onClicked: root.activePlayer?.next()

                    Behavior on Layout.preferredWidth { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Behavior on Layout.preferredHeight { 
                        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2 } 
                    }
                    Behavior on buttonRadius { 
                        NumberAnimation { duration: 200 }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 28
                        fill: 1
                        color: root.contentColor
                        text: "skip_next"
                    }
                }
            }
        }
    }
}
