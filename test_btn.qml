import QtQuick
import QtQuick.Controls

ApplicationWindow {
    width: 200
    height: 200
    visible: true
    
    property var releaseAction: () => { console.log("Arrow function executed"); Qt.quit() }
    
    MouseArea {
        anchors.fill: parent
        onClicked: {
            console.log("Clicked")
            if (releaseAction) releaseAction()
        }
    }
}
