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
                
                // Trigger Now Playing Popup
                root.popupType = "neutral";
                root.popupTitle = "Now Playing";
                // Show "Song Name • Artist Name"
                root.popupMessage = newTitle + (newArtist ? " • " + newArtist : "");
                root.hasPopup = true;
                
                popupTimer.restart();
            }
        }
    }

    signal batteryEvent(bool plugged)
    
    // Privacy
    property bool micActive: false
    
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
                    var allowedTypes = ["neutral", "good", "bad"];
                    if (!allowedTypes.includes(incomingType)) return;
                    
                    var t = parts[1].trim().toLowerCase();
                    var m = parts.length > 2 ? parts[2].trim().toLowerCase() : "";
                    
                    print("DynamicIsland Log: " + data.trim());
                    
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
                    root.lastPopupContent = contentHash;
                    root.lastPopupTime = now;

                    root.popupType = incomingType;
                    root.popupTitle = parts[1];
                    root.popupMessage = parts[2];
                    root.hasPopup = true;
                    
                    // Bluetooth Connection Sequence
                    if (t.includes("bluetooth") && m.includes("connected")) {
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
        onTriggered: root.hasPopup = false
    }

    // -------------------------------------------------------------------------
    // Clipboard Watcher
    // -------------------------------------------------------------------------
    Process {
        id: clipboardWatcher
        command: ["wl-paste", "--watch", "bash", "-c", "echo 'neutral|Clipboard|Copied' >> /tmp/qs_popup.log"]
        running: true
    }

    // -------------------------------------------------------------------------
    // Privacy (Mic) Watcher
    // -------------------------------------------------------------------------
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: privacyProc.running = true
    }
    
    Process {
        id: privacyProc
        command: ["sh", "-c", "pactl list source-outputs short | wc -l"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                let count = parseInt(data.trim());
                root.micActive = !isNaN(count) && count > 0;
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // Privacy (Camera) Watcher
    // -------------------------------------------------------------------------
    property bool cameraActive: false
    
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: cameraProc.running = true
    }
    
    Process {
        id: cameraProc
        // Check for processes using any /dev/video* device
        command: ["sh", "-c", "ls /dev/video* 2>/dev/null | xargs -r fuser 2>/dev/null | wc -w"]
        stdout: SplitParser {
            onRead: (data) => {
                let count = parseInt(data.trim());
                root.cameraActive = !isNaN(count) && count > 0;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Universal Mic Mute Watcher
    // -------------------------------------------------------------------------
    property bool micMuted: false
    property bool micFirstRun: true

    Process {
        id: micCheck
        command: ["sh", "-c", "LC_ALL=C pactl get-source-mute @DEFAULT_SOURCE@"]
        running: true // Run once on startup
        stdout: SplitParser {
            onRead: (data) => {
                var newMute = data.includes("yes");
                if (root.micFirstRun) {
                    root.micMuted = newMute;
                    root.micFirstRun = false;
                } else if (root.micMuted !== newMute) {
                    root.micMuted = newMute;
                    // Trigger Popup
                    // Use 'bad' for suspended/muted states to trigger shake animation
                    root.popupType = newMute ? "bad" : "good";
                    root.popupTitle = "Microphone";
                    root.popupMessage = newMute ? "Muted" : "Unmuted";
                    root.hasPopup = true;
                    popupTimer.restart();
                }
            }
        }
    }

    Process {
        id: micWatcher
        command: ["sh", "-c", "LC_ALL=C pactl subscribe | grep --line-buffered 'source'"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                // Debounce/Re-check status on any source event
                micCheck.running = false
                micCheck.running = true
            }
        }
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
