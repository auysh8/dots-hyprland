import QtQuick 2.15
import QtQuick.Controls 2.15

Window {
    visible: true
    width: 400
    height: 300
    Column {
        anchors.fill: parent
        Button {
            text: "Make List"
            onClicked: {
                te.insert(te.cursorPosition, "- ")
            }
        }
        Button {
            text: "Make Bold"
            onClicked: {
                te.cursorSelection.font.bold = !te.cursorSelection.font.bold
            }
        }
        TextEdit {
            id: te
            width: 300
            height: 200
            text: "Line 1\nLine 2\nLine 3"
            textFormat: TextEdit.MarkdownText
            wrapMode: TextEdit.Wrap
        }
    }
}
