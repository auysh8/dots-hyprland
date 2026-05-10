import QtQuick
import Quickshell
Item {
    Component.onCompleted: {
        console.log("QML DEBUG: " + Quickshell.shellPath("scripts/venv/bin/python3").replace("file://", ""));
        Qt.quit();
    }
}
