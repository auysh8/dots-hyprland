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
let activeDownloadIds = new Set();
let terminalStatusHoldUntil = 0;

function postStatus(message) {
    try {
        port.postMessage(message);
    } catch (e) {
        // Port disconnected, will retry on reconnect
    }
}

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
            terminalStatusHoldUntil = 0;
            let totalBytes = 0;
            let currentBytesReceived = 0;
            let filename = "";
            activeDownloadIds = new Set(items.map(item => item.id));

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

            postStatus({
                active: true,
                status: "active",
                filename: filename,
                progress: percentage,
                count: items.length,
                speed: speed
            });
        } else {
            if (Date.now() < terminalStatusHoldUntil) return;

            // No downloads
            lastCheckTime = 0;
            lastBytesReceived = 0;
            postStatus({
                active: false,
                status: "idle"
            });
        }
    });
}

function sendTerminalStatus(downloadId, status) {
    browser.downloads.search({ id: downloadId }).then((items) => {
        const item = items[0] || {};
        const filename = item.filename ? item.filename.split('/').pop() : "";
        const totalBytes = item.totalBytes || 0;
        const receivedBytes = item.bytesReceived || 0;

        activeDownloadIds.delete(downloadId);
        terminalStatusHoldUntil = Date.now() + 4000;
        postStatus({
            active: activeDownloadIds.size > 0,
            status: status,
            filename: filename,
            progress: totalBytes > 0 ? receivedBytes / totalBytes : (status === "completed" ? 1 : 0),
            count: activeDownloadIds.size,
            speed: ""
        });

        if (activeDownloadIds.size > 0) sendStatus();
    });
}

// Poll every second is good enough for UI
setInterval(sendStatus, 1000);

// Also listen for events to update immediately
browser.downloads.onCreated.addListener(sendStatus);
browser.downloads.onChanged.addListener((delta) => {
    if (delta.state && delta.state.current === "complete") {
        sendTerminalStatus(delta.id, "completed");
        return;
    }

    if (delta.state && delta.state.current === "interrupted") {
        sendTerminalStatus(delta.id, "interrupted");
        return;
    }

    sendStatus();
});
