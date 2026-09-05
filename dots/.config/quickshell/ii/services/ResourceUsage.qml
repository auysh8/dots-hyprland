pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real temperature: 0
    property real networkDownloadSpeed: 0
    property real networkUploadSpeed: 0
    property real lastRx: 0
    property real lastTx: 0
    property real diskUsedPercentage: 0
    property string diskUsedString: "--"
    property string diskTotalString: "--"
    property string diskAvailableString: "--"
    property real cpuUsage: 0
    property var previousCpuStats

    // GPU Properties
    property string gpuName: ""
    property string gpuVendor: ""
    property bool gpuAvailable: false
    property real gpuUsage: 0
    property real gpuVramUsedGB: 0
    property real gpuVramTotalGB: 0
    property real gpuVramPercentage: 0
    property real gpuTemperature: 0
    property list<real> gpuUsageHistory: []

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"
    property string maxAvailableGpuString: gpuName.length > 0 ? gpuName : "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function formatSpeed(bytes) {
        if (bytes < 1024) return bytes.toFixed(0) + " B/s";
        else if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB/s";
        else return (bytes / (1024 * 1024)).toFixed(1) + " MB/s";
    }

    function kbToSizeString(kb) {
        if (kb < 1024 * 1024) return (kb / 1024).toFixed(1) + " MB";
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateDiskUsage() {
        diskUsageProc.running = false;
        diskUsageProc.running = true;
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateGpuUsageHistory() {
        gpuUsageHistory = [...gpuUsageHistory, gpuUsage]
        if (gpuUsageHistory.length > historyLength) {
            gpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
        updateGpuUsageHistory()
    }

	Timer {
		interval: 1000
        running: true 
        repeat: true
        triggeredOnStart: true
		onTriggered: {
            gpuInfoProc.running = false
            gpuInfoProc.running = true
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            
            // Network Speed
            fileNetDev.reload()
            var lines = fileNetDev.text().split('\n')
            var rx = 0; var tx = 0;
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (line.indexOf(':') === -1) continue
                var parts = line.split(/\s+/)
                if (parts.length > 9 && parts[0] !== 'lo:') {
                     if (parts[0].indexOf(':') !== -1) {
                         rx += Number(parts[1]); tx += Number(parts[9]);
                     }
                }
            }
            
            if (lastRx > 0) {
                 const timeSec = interval / 1000
                 networkDownloadSpeed = (rx - lastRx) / timeSec
                 networkUploadSpeed = (tx - lastTx) / timeSec
                 
                 if (networkDownloadSpeed < 0) networkDownloadSpeed = 0;
                 if (networkUploadSpeed < 0) networkUploadSpeed = 0;
            }
            lastRx = rx; lastTx = tx;

            // Temperature
            fileTemp.reload()
            const tempText = fileTemp.text().trim()
            if (tempText) {
                temperature = Number(tempText) / 1000
            }

            root.updateDiskUsage()
            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	    FileView { id: fileMeminfo; path: "/proc/meminfo" }
	    FileView { id: fileStat; path: "/proc/stat" }
	    FileView { id: fileNetDev; path: "/proc/net/dev" }
	    FileView { 
	        id: fileTemp
	        path: "/sys/class/thermal/thermal_zone1/temp" 
	    }

	    Process {
	        id: diskUsageProc
	        command: ["df", "-P", "/"]
	        stdout: StdioCollector {
	            id: diskUsageCollector
	            onStreamFinished: {
	                const lines = diskUsageCollector.text.trim().split("\n")
	                if (lines.length < 2) return

	                const parts = lines[1].trim().split(/\s+/)
	                if (parts.length < 5) return

	                const total = Number(parts[1])
	                const used = Number(parts[2])
	                const available = Number(parts[3])
	                const usedPercent = Number(String(parts[4]).replace("%", ""))

	                if (total <= 0 || isNaN(usedPercent)) return

	                root.diskUsedPercentage = usedPercent / 100
	                root.diskUsedString = root.kbToSizeString(used)
	                root.diskTotalString = root.kbToSizeString(total)
	                root.diskAvailableString = root.kbToSizeString(available)
	            }
	        }
	    }
	
	    Process {
	        id: findThermalZoneProc
	        environment: ({ LANG: "C" })
	        command: ["bash", "-c", "p=$(grep -l 'SEN1\\|SEN3\\|acpitz\\|ambient\\|pch_' /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -n1 | sed 's/type/temp/'); if [[ -z \"$p\" ]]; then p=$(grep -l 'x86_pkg_temp\\|TCPU' /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -n1 | sed 's/type/temp/'); fi; echo \"$p\""]
	        running: true
	        stdout: StdioCollector {
	            onStreamFinished: {
	                const newPath = text.trim()
	                if (newPath) {
	                    fileTemp.path = newPath
	                }
	            }
	        }
	    }
	
	    Process {        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    Process {
        id: gpuInfoProc
        command: [`${Directories.scripts}/gpu/get_igpuinfo.sh`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.gpuAvailable = Object.keys(data).length > 0;
                    if (root.gpuAvailable) {
                        root.gpuVendor = data.vendor || "";
                        root.gpuName = data.name || "GPU";
                        root.gpuUsage = (data.usagePercent ?? 0) / 100;
                        root.gpuVramUsedGB = data.vramUsedGB ?? 0;
                        root.gpuVramTotalGB = data.vramTotalGB ?? 0;
                        root.gpuVramPercentage = (data.vramPercent ?? 0) / 100;
                        root.gpuTemperature = data.tempEdgeC ?? 0;
                    }
                } catch (e) {
                    root.gpuAvailable = false;
                }
            }
        }
    }
}
