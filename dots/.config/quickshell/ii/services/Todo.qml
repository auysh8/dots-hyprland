pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Simple to-do list manager.
 * Each item is an object with "content" and "done" properties.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []
    
    function generateId() {
        return Date.now().toString(36) + "_" + Math.random().toString(36).substring(2, 9);
    }

    function addItem(item) {
        if (!item.id) {
            item.id = generateId();
        }
        list.unshift(item);
        // Reassign to trigger onListChanged
        root.list = list.slice(0);
        todoFileView.setText(JSON.stringify(root.list));
    }

    function addTask(desc) {
        const item = {
            "id": generateId(),
            "content": desc,
            "done": false,
            "createdAt": Date.now()
        };
        addItem(item);
    }

    function markDone(index) {
        if (index >= 0 && index < list.length) {
            list[index].done = true;
            // Reassign to trigger onListChanged
            root.list = list.slice(0);
            todoFileView.setText(JSON.stringify(root.list));
        }
    }

    function markDoneById(id) {
        const idx = list.findIndex(item => item.id === id);
        if (idx !== -1) {
            markDone(idx);
        }
    }

    function markUnfinished(index) {
        if (index >= 0 && index < list.length) {
            list[index].done = false;
            // Reassign to trigger onListChanged
            root.list = list.slice(0);
            todoFileView.setText(JSON.stringify(root.list));
        }
    }

    function markUnfinishedById(id) {
        const idx = list.findIndex(item => item.id === id);
        if (idx !== -1) {
            markUnfinished(idx);
        }
    }

    function deleteItem(index) {
        if (index >= 0 && index < list.length) {
            list.splice(index, 1);
            // Reassign to trigger onListChanged
            root.list = list.slice(0);
            todoFileView.setText(JSON.stringify(root.list));
        }
    }

    function deleteItemById(id) {
        const idx = list.findIndex(item => item.id === id);
        if (idx !== -1) {
            deleteItem(idx);
        }
    }

    function refresh() {
        todoFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text();
            try {
                let parsed = JSON.parse(fileContents);
                if (Array.isArray(parsed)) {
                    let needsSave = false;
                    parsed.forEach((item, idx) => {
                        if (!item.id) {
                            item.id = (item.createdAt || (Date.now() - idx * 1000)).toString(36) + "_" + Math.random().toString(36).substring(2, 9);
                            needsSave = true;
                        }
                    });
                    root.list = parsed;
                    if (needsSave) {
                        todoFileView.setText(JSON.stringify(root.list));
                    }
                } else {
                    root.list = [];
                }
            } catch (e) {
                console.log("[To Do] JSON parse error: " + e);
                root.list = [];
            }
            console.log("[To Do] File loaded");
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}

