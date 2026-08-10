import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.models

import "media_color_cache.js" as MediaColorCache

/**
 * Shared context for processing media album art, downloading it, extracting its dominant color,
 * and generating a dynamic material color scheme.
 */
Item {
    id: root
    
    property var activePlayer: null
    
    // Core inputs
    property string artUrl: (activePlayer && activePlayer.trackArtUrl) ? activePlayer.trackArtUrl : ""
    property string fallbackArtUrl: ""
    property string effectiveArtUrl: (artUrl && artUrl.length > 0) ? artUrl : fallbackArtUrl
    property bool isLocalArt: effectiveArtUrl ? (String(effectiveArtUrl).startsWith("file://") || String(effectiveArtUrl).startsWith("/")) : false
    
    // File paths
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: isLocalArt ? String(effectiveArtUrl).split('/').pop() : Qt.md5(String(effectiveArtUrl))
    property string artFilePath: isLocalArt ? String(effectiveArtUrl).replace("file://", "") : `${artDownloadLocation}/${artFileName}`

    // State
    property bool downloaded: false
    property string displayedArtFilePath: downloaded ? (isLocalArt ? effectiveArtUrl : Qt.resolvedUrl(artFilePath)) : ""
    
    function updateArtState() {
        console.log("[MediaArtColorContext] updateArtState() activePlayer:", activePlayer ? activePlayer.identity : "null", "effectiveArtUrl:", root.effectiveArtUrl, "isLocalArt:", root.isLocalArt, "artFilePath:", root.artFilePath)
        localArtRetryTimer.stop()
        localArtRetryTimer.retryCount = 0
        localArtChecker.running = false
        coverArtDownloader.running = false

        if (!root.effectiveArtUrl || root.effectiveArtUrl.length === 0) {
            console.log("[MediaArtColorContext] effectiveArtUrl is empty, running youtubeArtFetcher...")
            root.downloaded = false
            youtubeArtFetcher.running = false
            youtubeArtFetcher.running = true
            return
        }

        if (root.isLocalArt) {
            var localPath = String(root.effectiveArtUrl).replace(/^file:\/\//, "")
            console.log("[MediaArtColorContext] Checking local art file existence & size:", localPath)
            root.downloaded = false
            localArtChecker.checkPath = localPath
            localArtChecker.running = true
        } else {
            console.log("[MediaArtColorContext] Downloading remote art:", root.effectiveArtUrl, "->", root.artFilePath)
            coverArtDownloader.targetFile = root.effectiveArtUrl 
            coverArtDownloader.artFilePath = root.artFilePath
            root.downloaded = false
            coverArtDownloader.running = true
        }
    }

    onArtUrlChanged: {
        fallbackArtUrl = ""
        updateArtState()
    }
    onEffectiveArtUrlChanged: updateArtState()
    onArtFilePathChanged: updateArtState()
    onActivePlayerChanged: {
        console.log("[MediaArtColorContext] activePlayer changed to:", activePlayer ? (activePlayer.identity + " | " + activePlayer.dbusName) : "null")
        fallbackArtUrl = ""
        updateArtState()
    }
    Component.onCompleted: updateArtState()

    Process {
        id: youtubeArtFetcher
        command: [ "bash", "-c", 'URL=$(playerctl metadata xesam:url 2>/dev/null); VID=$(echo "$URL" | grep -oP "(?:v=|\\/embed\\/|\\/v\\/|youtu\\.be\\/|\\/shorts\\/)\\K[a-zA-Z0-9_-]{11}"); [ -n "$VID" ] && echo "https://i.ytimg.com/vi/$VID/hqdefault.jpg"' ]
        stdout: SplitParser {
            onRead: data => {
                var url = String(data).trim()
                if (url.length > 0) {
                    console.log("[MediaArtColorContext] youtubeArtFetcher extracted thumbnail URL:", url)
                    root.fallbackArtUrl = url
                }
            }
        }
    }

    Process {
        id: localArtChecker
        property string checkPath: ""
        command: [ "bash", "-c", '[ -s "$1" ]', "_", checkPath ]
        onExited: (exitCode, exitStatus) => {
            console.log("[MediaArtColorContext] localArtChecker exited with code:", exitCode, "for path:", checkPath)
            if (exitCode === 0) {
                root.downloaded = true
                console.log("[MediaArtColorContext] Local art verified non-empty! displayedArtFilePath:", root.displayedArtFilePath)
            } else if (localArtRetryTimer.retryCount < 15) {
                console.log("[MediaArtColorContext] Local art not ready yet, retrying...", localArtRetryTimer.retryCount + 1)
                localArtRetryTimer.start()
            } else {
                console.log("[MediaArtColorContext] Max retries reached for local art. Setting downloaded = true anyway.")
                root.downloaded = true
            }
        }
    }

    Timer {
        id: localArtRetryTimer
        property int retryCount: 0
        interval: 100
        repeat: false
        onTriggered: {
            retryCount++
            localArtChecker.running = false
            localArtChecker.running = true
        }
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        command: [
            "bash", "-c",
            '[ -f "$1" ] && [ -s "$1" ] || { curl -sSL -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" "$2" -o "$1" && [ -s "$1" ]; }',
            "_", artFilePath, targetFile
        ]
        onExited: (exitCode, exitStatus) => {
            console.log("[MediaArtColorContext] coverArtDownloader exited with code:", exitCode, "target:", targetFile)
            if (exitCode === 0) {
                root.downloaded = true
                console.log("[MediaArtColorContext] Remote art downloaded successfully! displayedArtFilePath:", root.displayedArtFilePath)
            } else {
                console.log("[MediaArtColorContext] Remote art download failed!")
                coverArtCleaner.running = false
                coverArtCleaner.cleanPath = artFilePath
                coverArtCleaner.running = true
            }
        }
    }

    Process {
        id: coverArtCleaner
        property string cleanPath: ""
        command: [ "bash", "-c", '[ -f "$1" ] && [ ! -s "$1" ] && rm -f "$1"', "_", cleanPath ]
    }

    // Color Extraction
    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    // Extract dominant color or use default
    readonly property color cachedExtractedColor: MediaColorCache.getColor(root.artFileName, Appearance.colors.colPrimary)
    readonly property color extractedColor: {
        if (!downloaded || displayedArtFilePath.length === 0) {
            return cachedExtractedColor
        }

        let c = (colorQuantizer && colorQuantizer.colors && colorQuantizer.colors.length > 0)
            ? colorQuantizer.colors[0]
            : null
        return (c !== undefined && c !== null) ? c : cachedExtractedColor
    }

    Connections {
        target: colorQuantizer
        function onColorsChanged() {
            if (colorQuantizer.colors && colorQuantizer.colors.length > 0) {
                MediaColorCache.setColor(root.artFileName, colorQuantizer.colors[0])
            }
        }
    }

    // Generated Theme
    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.extractedColor
    }

    // Stable Theme Tokens (Unanimated)
    readonly property color _srcBackgroundColor: blendedColors.colLayer0
    readonly property color _srcContentColor: blendedColors.colOnLayer0
    readonly property color _srcSecondaryContentColor: blendedColors.colSubtext
    readonly property color _srcPillColor: blendedColors.colPrimary // or colSecondaryContainer
    readonly property color _srcPillContentColor: blendedColors.colOnPrimary

    // Animated Theme Tokens
    property color backgroundColor: _srcBackgroundColor
    property color contentColor: _srcContentColor
    property color secondaryContentColor: _srcSecondaryContentColor
    property color pillColor: _srcPillColor
    property color pillContentColor: _srcPillContentColor

    Behavior on backgroundColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on contentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on secondaryContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
}
