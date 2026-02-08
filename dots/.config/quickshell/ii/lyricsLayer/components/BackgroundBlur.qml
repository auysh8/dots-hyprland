import QtQuick
import QtQuick.Effects
import qs.modules.common
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    // Properties
    property string albumArt: ""
    property bool showLyrics: false
    property color backgroundColor: "transparent"
    
    property real cornerRadius: 24
    
    // Blurred album art background
    Item {
        id: blurBackground
        anchors.fill: parent
        visible: root.albumArt !== ""
        
        // Apply rounded corner mask - disable if no radius (fullscreen)
        layer.enabled: root.cornerRadius > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: blurBackground.width
                height: blurBackground.height
                radius: root.cornerRadius
            }
        }
        
        // Animated container - holds the image + effect together
        Item {
            id: animatedBgContainer
            anchors.centerIn: parent
            // Performance: Use fixed large size to prevent re-rendering/re-blurring during resize
            // We use the maximum likely screen dimension to ensure coverage
            width: Math.max(Screen.width, Screen.height) * 1.2
            height: width
            
            // Animation properties
            property real offsetX: 0
            property real offsetY: 0
            property real scaleAnim: 1.0
            
            transform: [
                Translate { x: animatedBgContainer.offsetX; y: animatedBgContainer.offsetY },
                Scale { 
                    origin.x: animatedBgContainer.width / 2
                    origin.y: animatedBgContainer.height / 2
                    xScale: animatedBgContainer.scaleAnim
                    yScale: animatedBgContainer.scaleAnim
                }
            ]
            
            // Horizontal drift - more pronounced
            SequentialAnimation on offsetX {
                loops: Animation.Infinite
                running: root.showLyrics
                NumberAnimation { to: 80; duration: 8000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -80; duration: 8000; easing.type: Easing.InOutSine }
            }
            
            // Vertical drift
            SequentialAnimation on offsetY {
                loops: Animation.Infinite
                running: root.showLyrics
                NumberAnimation { to: -60; duration: 6000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 60; duration: 6000; easing.type: Easing.InOutSine }
            }
            
            // Breathing/scale effect
            SequentialAnimation on scaleAnim {
                loops: Animation.Infinite
                running: root.showLyrics
                NumberAnimation { to: 1.25; duration: 10000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 10000; easing.type: Easing.InOutSine }
            }
            
            Image {
                id: bgImage
                anchors.fill: parent
                source: root.albumArt
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
