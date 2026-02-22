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
    property real cpuUsage: 0
    property var previousCpuStats

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

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
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1000
        running: true 
        repeat: true
		onTriggered: {
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

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	    FileView { id: fileMeminfo; path: "/proc/meminfo" }
	    FileView { id: fileStat; path: "/proc/stat" }
	    FileView { id: fileNetDev; path: "/proc/net/dev" }
	    FileView { 
	        id: fileTemp
	        path: "/sys/class/thermal/thermal_zone0/temp" 
	    }
	
	    Process {
	        id: findThermalZoneProc
	        environment: ({ LANG: "C" })
	        command: ["bash", "-c", "grep -l 'x86_pkg_temp\\|TCPU' /sys/class/thermal/thermal_zone*/type | head -n1 | sed 's/type/temp/'"]
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
}
