import QtQuick
import QtQuick.Layouts

Row {
    id: root
    property bool playing: false
    property color barColor: "white"
    property int barCount: 5
    property int maxBarHeight: 16
    property int minBarHeight: 4
    
    spacing: 2
    height: maxBarHeight
    
    Repeater {
        model: root.barCount
        Rectangle {
            id: bar
            width: 3
            radius: 1.5
            color: root.barColor
            anchors.bottom: parent.bottom
            height: root.minBarHeight
            
            property real targetHeight: root.minBarHeight
            
            Behavior on height {
                NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
            }
            
            Timer {
                interval: 100 + (index * 20) // Staggered updates
                running: root.playing
                repeat: true
                onTriggered: {
                    // Randomize interval slightly for organic feel
                    interval = 100 + Math.random() * 150
                    bar.height = root.minBarHeight + (Math.random() * (root.maxBarHeight - root.minBarHeight))
                }
            }
            
            // Reset when stopped

            
            Connections {
                target: root
                function onPlayingChanged() {
                     if (!root.playing) bar.height = root.minBarHeight
                }
            }
        }
    }
}
