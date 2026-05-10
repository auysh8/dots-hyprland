import QtQuick
import Quickshell
Item {
    Component.onCompleted: {
        console.log("QML DEBUG: " + Qt.resolvedUrl("../../scripts/venv/bin/python3").toString());
        console.log("QML DEBUG: " + Quickshell.shellPath("scripts/venv/bin/python3"));
        Qt.quit();
    }
}
