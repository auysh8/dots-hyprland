let port = null;

function connectToNative() {
    port = browser.runtime.connectNative("com.quickshell.downloadmonitor");
    port.onDisconnect.addListener(() => {
        console.log("Disconnected from native host. Reconnecting...");
        setTimeout(connectToNative, 5000);
    });
}

connectToNative();

let lastCheckTime = 0;
let lastBytesReceived = 0;

function formatSpeed(bytesPerSec) {
    if (bytesPerSec === 0) return "0 KB/s";
    const k = 1024;
    const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    const i = Math.floor(Math.log(bytesPerSec) / Math.log(k));
    return parseFloat((bytesPerSec / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function sendStatus() {
    browser.downloads.search({ state: "in_progress" }).then((items) => {
        if (items.length > 0) {
            // Found active downloads
            let totalBytes = 0;
            let currentBytesReceived = 0;
            let filename = "";

            // Focus on the primary download (first one) for details, sum progress for total
            for (let item of items) {
                totalBytes += item.totalBytes;
                currentBytesReceived += item.bytesReceived;
                if (!filename) filename = item.filename.split('/').pop();
            }

            let percentage = totalBytes > 0 ? (currentBytesReceived / totalBytes) : 0;

            // Calculate speed
            const now = Date.now();
            let speed = "Unknown";

            if (lastCheckTime > 0) {
                const timeDiff = (now - lastCheckTime) / 1000; // seconds
                const bytesDiff = currentBytesReceived - lastBytesReceived;

                if (timeDiff > 0 && bytesDiff >= 0) {
                    const bytesPerSec = bytesDiff / timeDiff;
                    speed = formatSpeed(bytesPerSec);
                }
            } else {
                speed = "Calculating...";
            }

            // Update history for next check
            lastCheckTime = now;
            lastBytesReceived = currentBytesReceived;

            try {
                port.postMessage({
                    active: true,
                    filename: filename,
                    progress: percentage,
                    count: items.length,
                    speed: speed
                });
            } catch (e) {
                // Port disconnected, will retry on reconnect
            }
        } else {
            // No downloads
            lastCheckTime = 0;
            lastBytesReceived = 0;
            try {
                port.postMessage({
                    active: false
                });
            } catch (e) { }
        }
    });
}

// Poll every second is good enough for UI
setInterval(sendStatus, 1000);

// Also listen for events to update immediately
browser.downloads.onCreated.addListener(sendStatus);
browser.downloads.onChanged.addListener(sendStatus);
