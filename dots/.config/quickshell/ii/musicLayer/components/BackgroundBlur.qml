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
        
        // Static container - holds the image + effect together
        Item {
            id: animatedBgContainer
            anchors.fill: parent
            
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
