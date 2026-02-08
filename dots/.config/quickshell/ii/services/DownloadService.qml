pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false
    property string filename: ""
    property real progress: 0.0
    property int count: 0
    property string speed: ""

    // Path to the file written by the python native host
    readonly property string statusFile: "/tmp/quickshell_downloads.json"

    // Called from shell.qml to ensure singleton is instantiated
    function load() {
        refresh();
    }

    function refresh() {
        fileView.reload();
    }

    // Timer to periodically check for updates
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    FileView {
        id: fileView
        path: root.statusFile
        
        onLoaded: {
            const fileContents = fileView.text();
            if (!fileContents || fileContents.length === 0) {
                root.active = false;
                return;
            }
            try {
                const data = JSON.parse(fileContents);
                root.active = data.active || false;
                root.filename = data.filename || "";
                root.progress = data.progress || 0.0;
                root.count = data.count || 0;
                root.speed = data.speed || "";
            } catch (e) {
                root.active = false;
            }
        }
        
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                // File doesn't exist yet, that's OK
                root.active = false;
            } else {
                root.active = false;
            }
        }
    }
}
