import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 400
    height: 400
    
    TextArea {
        anchors.fill: parent
        textFormat: TextEdit.MarkdownText
        text: "**Hello** *World*"
    }
}
