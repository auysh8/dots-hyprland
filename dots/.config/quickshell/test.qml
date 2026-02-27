import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    Process {
        command: ["sh", "-c", "echo 90"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                console.log("Read: '" + data + "'");
                console.log("Parsed: " + parseInt(data));
            }
        }
        onExited: Qt.quit()
    }
}
