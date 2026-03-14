import QtQuick
import QtQuick.Effects
import qs.modules.common
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    // Properties
    property string albumArt: ""
    property bool active: false // Controls the animation (used to be showLyrics)
    property bool animated: false // Opt-in to drifting animation
    property color backgroundColor: "transparent"
    
    property real cornerRadius: 24
    
    property string lastValidArt: root.albumArt
    onAlbumArtChanged: {
        if (root.albumArt !== "") {
            lastValidArt = root.albumArt
        }
    }
    
    // Blurred album art background
    Item {
        id: blurBackground
        anchors.fill: parent
        opacity: root.albumArt !== "" ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: root.albumArt !== "" ? 800 : 350 } }
        visible: opacity > 0
        
        // Apply rounded corner mask - disable if no radius (fullscreen)
        layer.enabled: root.cornerRadius > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: blurBackground.width
                height: blurBackground.height
                radius: root.cornerRadius
            }
        }
        
        // Container - holds the image + effect together
        Item {
            id: animatedBgContainer
            
            // Dynamic sizing based on animation state
            // If animated, we need a larger container to pan around without showing edges
            width: root.animated ? Math.max(Screen.width, Screen.height) * 1.2 : parent.width
            height: root.animated ? width : parent.height
            anchors.centerIn: parent
            
            // Animation properties
            property real offsetX: 0
            property real offsetY: 0
            property real scaleAnim: 1.0
            
            transform: [
                Translate { x: root.animated ? animatedBgContainer.offsetX : 0; y: root.animated ? animatedBgContainer.offsetY : 0 },
                Scale { 
                    origin.x: animatedBgContainer.width / 2
                    origin.y: animatedBgContainer.height / 2
                    xScale: root.animated ? animatedBgContainer.scaleAnim : 1.0
                    yScale: root.animated ? animatedBgContainer.scaleAnim : 1.0
                }
            ]
            
            // Horizontal drift - more pronounced
            SequentialAnimation on offsetX {
                loops: Animation.Infinite
                running: root.animated && root.active
                NumberAnimation { to: 80; duration: 8000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -80; duration: 8000; easing.type: Easing.InOutSine }
            }
            
            // Vertical drift
            SequentialAnimation on offsetY {
                loops: Animation.Infinite
                running: root.animated && root.active
                NumberAnimation { to: -60; duration: 6000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 60; duration: 6000; easing.type: Easing.InOutSine }
            }
            
            // Breathing/scale effect
            SequentialAnimation on scaleAnim {
                loops: Animation.Infinite
                running: root.animated && root.active
                NumberAnimation { to: 1.25; duration: 10000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 10000; easing.type: Easing.InOutSine }
            }
            
            Image {
                id: bgImage
                anchors.fill: parent
                source: root.lastValidArt
                fillMode: Image.PreserveAspectCrop
                visible: false
                // Optimize: Limit source size for blur performance
                sourceSize.width: 1280
                sourceSize.height: 1280
            }
            
            MultiEffect {
                anchors.fill: bgImage
                source: bgImage
                blurEnabled: true
                blurMax: 32
                blur: 1.0
                saturation: 0.4
                brightness: -0.2
            }
        }
        
        // Dark overlay for readability
        Rectangle {
            anchors.fill: parent
            color: root.backgroundColor
            opacity: 0.4
        }
    }
}
