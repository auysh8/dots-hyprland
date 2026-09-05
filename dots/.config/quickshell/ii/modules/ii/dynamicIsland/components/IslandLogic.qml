import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

Item {
    id: root
    
    // Properties to expose data
    property string popupType: "neutral"
    property string popupTitle: ""
    property string popupMessage: ""
    property bool hasPopup: false

    // Structured popup metadata
    property string popupCategory: "generic"
    property string popupAction: ""
    
    // Spam Prevention
    property var lastPopupTime: 0
    property string lastPopupContent: ""
    
    // Startup Protection
    property bool ignoreClipboard: true
    Timer {
        interval: 3000
        running: true
        onTriggered: root.ignoreClipboard = false
    }

    function isStoragePopup(title, message, category) {
        return category === "storage" || category === "disk" ||
            title.includes("storage") || title.includes("disk") ||
            message.includes("storage") || message.includes("disk")
    }

    function showPopup(type, title, message, category, action) {
        root.popupType = type
        root.popupTitle = title
        root.popupMessage = message
        root.popupCategory = category
        root.popupAction = action
        root.hasPopup = true
        root.lastPopupContent = title + message
        root.lastPopupTime = new Date().getTime()
        popupTimer.restart()
    }
    
    // -------------------------------------------------------------------------
    // Notification Service Bridge
    // -------------------------------------------------------------------------
    Connections {
        target: Notifications
        function onNotify(notif) {
            // App and KDE Connect popups are disabled
            return;
        }
    }

// -------------------------------------------------------------------------
// Media Watcher (Now Playing Popup)
// -------------------------------------------------------------------------
property string lastTrackTitle: ""
Connections {
    target: MprisController
    function onTrackChanged() {
        var newTitle = MprisController.activeTrack.title;
        var newArtist = MprisController.activeTrack.artist;
        if (newTitle !== "" && newTitle !== root.lastTrackTitle) {
            root.lastTrackTitle = newTitle;
            
            // Build message
            let msg = newTitle + (newArtist ? " • " + newArtist : "");
            
            // IMPORTANT: Set category BEFORE setting other properties
            root.popupCategory = "media";
            root.popupAction = "playing";
            
            // Then set the rest
            root.popupType = "neutral";
            root.popupTitle = "Now Playing";
            root.popupMessage = msg;
            root.hasPopup = true;
            
            // Update spam prevention to match
            root.lastPopupContent = "Now Playing" + msg;
            root.lastPopupTime = new Date().getTime();
            
            popupTimer.restart();
        }
    }
}

    signal batteryEvent(bool plugged)
    
    // Bluetooth
    // [{name: "Device", battery: 80}]
    property var bluetoothDevices: []
    property bool hasBluetoothDevices: bluetoothDevices.length > 0
    
    // -------------------------------------------------------------------------
    // Popup Watcher
    // -------------------------------------------------------------------------
    signal requestCustomBattery(real percent, string name)

    Timer {
        id: btBatteryTriggerTimer
        interval: 4500 // Wait longer (4.5s) for bluetoothctl to update
        property string targetDeviceName: ""
        onTriggered: {
            // Use the timer's own property (not root), normalize case, and trim
            var target = (btBatteryTriggerTimer.targetDeviceName || "").toLowerCase().trim();
            print("DynamicIsland: Checking battery for '" + btBatteryTriggerTimer.targetDeviceName + "' (normalized: '" + target + "')");

            // Find battery level for device
            var found = false;
            var bat = 0;

            for (var i = 0; i < root.bluetoothDevices.length; i++) {
                var dName = (root.bluetoothDevices[i].name || "").toLowerCase().trim();
                if (target && (target.includes(dName) || dName.includes(target))) {
                    bat = root.bluetoothDevices[i].battery;
                    found = true;
                    print("DynamicIsland: Found battery -> " + bat + "% for " + root.bluetoothDevices[i].name);
                    break;
                }
            }

            if (found && bat >= 0) {
                root.requestCustomBattery(bat / 100.0, btBatteryTriggerTimer.targetDeviceName);
            } else {
                print("DynamicIsland: Battery info not found for '" + btBatteryTriggerTimer.targetDeviceName + "'");
            }
        }
    }

    Process {
        id: popupWatcher
        command: ["sh", "-c", "touch /tmp/qs_popup.log && stdbuf -oL tail -n 0 -f /tmp/qs_popup.log"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var parts = data.trim().split("|");
                if (parts.length >= 3) {
                    var incomingType = parts[0].toLowerCase();
                    var allowedTypes = ["neutral", "good", "bad", "toggle"];
                    if (!allowedTypes.includes(incomingType)) return;
                    
                    // Pre-normalize media messages to avoid flicker & spam check misses
                    if (parts[1].toLowerCase().includes("now playing")) {
                        parts[2] = parts[2].replace(" - ", " • ");
                    }

                    var t = parts[1].trim().toLowerCase();
                    var m = parts.length > 2 ? parts[2].trim().toLowerCase() : "";
                    
                    print("DynamicIsland Log: " + data.trim());

                    // Suppress Caps Lock Popups
                    if (t.includes("caps")) {
                         return;
                    }
                    
                    if (t.includes("battery") || t.includes("plugged") || t.includes("unplugged") ||
                        m.includes("battery") || m.includes("plugged") || m.includes("unplugged")) {
                         
                         var isPlugged = false;
                         if (t.includes("plugged in") || m.includes("plugged in") || (t.includes("plugged") && !t.includes("unplugged"))) {
                            isPlugged = true;
                         }
                         
                         root.batteryEvent(isPlugged);
                         return;
                    }

                    // Startup protection for Clipboard (wl-paste triggers on init)
                    if (t.includes("clipboard") && root.ignoreClipboard) return;
                    
                    // Spam Check
                    var contentHash = parts[1] + parts[2];
                    var now = new Date().getTime();
                    if (contentHash === root.lastPopupContent && (now - root.lastPopupTime) < 4000) {
                        return; // Ignore duplicate
                    }

                    // Special handling for "Now Playing" - ignore from log if media watcher recently fired
                    if (t === "now playing" && (now - root.lastPopupTime) < 2000) {
                        console.log("DynamicIsland: Ignoring Now Playing from log - media watcher handled it");
                        return;
                    }

                    root.lastPopupContent = contentHash;
                    root.lastPopupTime = now;

                    // Parse structured metadata if present
                    var cat = parts.length >= 4 ? parts[3].trim().toLowerCase() : "generic";
                    var act = parts.length >= 5 ? parts[4].trim().toLowerCase() : "";

                    if (root.isStoragePopup(t, m, cat) && ResourceUsage.diskUsedPercentage < 0.95)
                        return;

                    if ((cat === "download" || t.includes("download") || m.includes("download")) && (m.includes("downloaded") || m.includes("completed") || m.includes("done") || m.includes("finished")) && DownloadService.status !== "completed")
                        return;

                    // Migration Fallbacks for Legacy Scripts (Mapping titles to categories)
                    if (cat === "generic") {
                        if (t === "now playing" || t.startsWith("now playing")) {
                            cat = "media";
                            act = "playing";
                        }
                        else if (t.includes("download") || m.includes("download")) cat = "download";
                        else if (t.includes("wifi")) cat = "wifi";
                        else if (t.includes("bluetooth")) cat = "bluetooth";
                        else if (t.includes("battery") || t.includes("power")) cat = "battery";
                        else if (t.includes("microphone")) cat = "microphone";
                        else if (t.includes("screenshot")) cat = "screenshot";
                        else if (t.includes("storage") || t.includes("disk")) cat = "storage";
                        else if (t.includes("clipboard")) cat = "clipboard";
                        else if (t.includes("pomodoro")) cat = "pomodoro";
                        else if (t.includes("update")) cat = "update";
                        else if (t.includes("caps") || t.includes("num")) cat = "keyboard";
                        else if (t.includes("dock") || t.includes("notification")) cat = "notification";

                        // Action inference for legacy scripts
                        if (act === "" && m !== "") {
                             if (m.includes("completed") || m.includes("saved") || m.includes("done") || m.includes("finished")) act = "complete";
                             else if (m.includes("connected")) act = "connected";
                             else if (m.includes("disconnected") || m.includes("lost")) act = "disconnected";
                             else if (m.includes("muted") || m.includes("mute") || m.includes("off")) act = "muted";
                             else if (m.includes("charging") || m.includes("plugged")) act = "charging";
                             else if (m.includes("low")) act = "low";
                        }
                    }

                    // Apply structured metadata first to prevent icon flicker
                    root.popupCategory = cat;
                    root.popupAction = act;

                    // Then apply display content
                    root.popupType = incomingType;
                    root.popupTitle = parts[1];
                    root.popupMessage = parts[2];
                    root.hasPopup = true;
                    
                    // Bluetooth Connection Sequence (Preserve specialized logic)
                    if (cat === "bluetooth" && act === "connected" && !t.includes("battery")) {
                        // Extract device name: "Connected: AirPods" -> "AirPods"
                        var devName = parts[2].replace("Connected:", "").trim();
                        print("DynamicIsland: Bluetooth Connected to " + devName + ", scheduling battery check...");
                        
                        btBatteryTriggerTimer.targetDeviceName = devName;
                        
                        // Force a fresh scan immediately
                        btWatcher.running = false;
                        btWatcher.running = true;
                        
                        btBatteryTriggerTimer.restart();
                    }
                    
                    popupTimer.restart();
                }
            }
        }
    }
    
    Timer {
        id: popupTimer
        interval: root.popupType === "bad" ? 5000 : 3000
        onTriggered: {
            root.hasPopup = false
            root.popupCategory = "generic"
            root.popupAction = ""
        }
    }


    // -------------------------------------------------------------------------
    // Universal Mic Mute Watcher (Pipewire native + Audio service)
    // -------------------------------------------------------------------------
    property bool micMuted: Audio.source?.audio?.muted ?? false
    property bool micInitialized: false

    Timer {
        interval: 1500
        running: true
        onTriggered: {
            root.micInitialized = true
        }
    }

    onMicMutedChanged: {
        if (!root.micInitialized) return;
        var newMute = root.micMuted;
        root.showPopup(
            newMute ? "bad" : "good",
            "Microphone",
            newMute ? "Muted" : "Unmuted",
            "microphone",
            newMute ? "muted" : "unmuted"
        );
    }

    // -------------------------------------------------------------------------
    // Bluetooth Watcher
    // -------------------------------------------------------------------------
    Process {
        id: btWatcher
        // Loop through connected devices and get info
        command: ["sh", "-c", "bluetoothctl devices Connected | cut -f2 -d' ' | while read mac; do echo '---'; bluetoothctl info $mac | grep -E 'Name:|Battery Percentage:'; done"]
        running: true
        
        stdout: SplitParser {
            onRead: (data) => {
                let line = data.trim();
                if (!line) return;
                
                if (line === "---") {
                    // Commit the *previous* device if valid
                    if (root._btTempName && root._btTempBatt >= 0) {
                        let list = [...root.bluetoothDevices]; // Clone
                        let found = false;
                        for (let i=0; i<list.length; i++) {
                            if (list[i].name === root._btTempName) {
                                list[i].battery = root._btTempBatt;
                                found = true;
                                break;
                            }
                        }
                        if (!found) list.push({name: root._btTempName, battery: root._btTempBatt});
                        root.bluetoothDevices = list;
                    }
                    // Reset for next device
                    root._btTempName = "";
                    root._btTempBatt = -1;
                    return;
                }
                
                if (line.startsWith("Name:")) root._btTempName = line.substring(5).trim();
                if (line.startsWith("Battery Percentage:")) {
                    var val = -1;
                    
                    // 1. Try to find a decimal number (0-100) that is NOT part of a hex string (0x...)
                    // Remove potential hex codes first to avoid confusion
                    var cleanLine = line.replace(/0x[0-9A-Fa-f]+/g, "");
                    var matches = cleanLine.match(/(\d{1,3})/);
                    
                    if (matches && matches[1]) {
                        val = parseInt(matches[1]);
                    } else {
                        // 2. Fallback: Parse hex if no decimal found
                        var hexMatch = line.match(/0x([0-9A-Fa-f]+)/);
                        if (hexMatch) {
                            val = parseInt(hexMatch[1], 16);
                        }
                    }

                    if (val >= 0) {
                        root._btTempBatt = Math.min(100, Math.max(0, val));
                    }
                }
            }
        }
    }
    
    // Internal parser state
    property string _btTempName: ""
    property int _btTempBatt: -1
    property var _lowBattWarned: ({}) // Map to track warned devices
    
    Timer {
        id: btListCleanup
        interval: 10000 
        running: true
        repeat: true
        onTriggered: {
             // Check for Low Battery on existing devices
             for(let i=0; i<root.bluetoothDevices.length; i++) {
                 let dev = root.bluetoothDevices[i];
                 if (dev.battery >= 0 && dev.battery <= 20) {
                     // Check if already warned recently (e.g., in last hour)
                     let lastWarn = root._lowBattWarned[dev.name] || 0;
                     let now = new Date().getTime();
                     if (now - lastWarn > 3600000) { // 1 hour
                         // Trigger Low Battery Popup via log injection (easiest way to loop back)
                         // Or use internal method? Internal is cleaner.
                         root.popupType = "bad";
                         root.popupTitle = "Battery";
                         root.popupMessage = "Low Battery: " + dev.name + " (" + dev.battery + "%)";
                         root.popupCategory = "battery"
                         root.popupAction = "low"
                         root.hasPopup = true;
                         popupTimer.restart();
                         
                         root._lowBattWarned[dev.name] = now;
                     }
                 }
             }
        
             // Clear list and restart scan to handle disconnections
             root.bluetoothDevices = []; 
             btWatcher.running = false;
             btWatcher.running = true;
        }
    }
}
