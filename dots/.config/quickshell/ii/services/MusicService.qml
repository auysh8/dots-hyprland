import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

Singleton {
    property bool open: false
    function toggle() { open = !open }
}
