import QtQuick
import Quickshell
import Quickshell.Io

Item {
    Process {
        running: true
        command: [
            Quickshell.shellPath("../scripts/venv/bin/python3").replace("file://", ""),
            "-u",
            Quickshell.shellPath("../scripts/gemini_server.py").replace("file://", "")
        ]
        stdout: SplitParser {
            onRead: data => console.log("[Gemini Server] " + data.trim())
        }
        stderr: SplitParser {
            onRead: data => console.log("[Gemini Server ERROR] " + data.trim())
        }
        onExited: (exitCode, exitStatus) => {
            console.log("Process Exited: " + exitCode + " " + exitStatus);
            Qt.quit();
        }
    }
}
