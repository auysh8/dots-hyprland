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
    
    function getYoutubeThumbnail(url) {
        if (!url) return "";
        let match = String(url).match(/(?:v=|\/embed\/|\/v\/|youtu\.be\/|\/shorts\/)([a-zA-Z0-9_-]{11})/);
        return (match && match[1]) ? ("https://i.ytimg.com/vi/" + match[1] + "/hqdefault.jpg") : "";
    }

    // Core inputs
    property string artUrl: (activePlayer && activePlayer.trackArtUrl) ? activePlayer.trackArtUrl : ""
    property string fallbackArtUrl: ""
    property string effectiveArtUrl: {
        if (artUrl && artUrl.length > 0) return artUrl;
        if (fallbackArtUrl && fallbackArtUrl.length > 0) return fallbackArtUrl;
        let directUrl = (activePlayer && activePlayer.url) || (activePlayer && activePlayer.trackUrl) || (activePlayer && activePlayer.metadata ? (activePlayer.metadata["xesam:url"] || activePlayer.metadata["url"]) : "");
        let ytThumb = getYoutubeThumbnail(directUrl);
        if (ytThumb.length > 0) return ytThumb;
        return "";
    }
    property bool isLocalArt: effectiveArtUrl ? (String(effectiveArtUrl).startsWith("file://") || String(effectiveArtUrl).startsWith("/")) : false
    
    // File paths
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: isLocalArt ? String(effectiveArtUrl).split('/').pop() : (Qt.md5(String(effectiveArtUrl)) + ".jpg")
    property string artFilePath: isLocalArt ? String(effectiveArtUrl).replace("file://", "") : `${artDownloadLocation}/${artFileName}`

    // State
    property bool downloaded: false
    property string displayedArtFilePath: {
        if (!downloaded) return "";
        let path = isLocalArt ? effectiveArtUrl : artFilePath;
        if (!path || path.length === 0) return "";
        return (path.startsWith("file://") || path.startsWith("http://") || path.startsWith("https://")) 
            ? path 
            : Qt.resolvedUrl(path);
    }
    
    function updateArtState() {
        console.log("[MediaArtColorContext] updateArtState() activePlayer:", activePlayer ? activePlayer.identity : "null", "effectiveArtUrl:", root.effectiveArtUrl, "isLocalArt:", root.isLocalArt, "artFilePath:", root.artFilePath)
        localArtChecker.running = false
        coverArtDownloader.running = false
        fallbackCoverArtDownloader.running = false

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

    Connections {
        target: activePlayer || null
        ignoreUnknownSignals: true
        function onTrackArtUrlChanged() {
            root.fallbackArtUrl = ""
            root.updateArtState()
        }
        function onTrackTitleChanged() {
            root.fallbackArtUrl = ""
            root.updateArtState()
        }
    }

    Process {
        id: youtubeArtFetcher
        command: {
            let pName = (activePlayer && activePlayer.dbusName) ? String(activePlayer.dbusName).replace("org.mpris.MediaPlayer2.", "") : "";
            return pName ? [ "playerctl", "--player=" + pName, "metadata", "xesam:url" ] : [ "playerctl", "metadata", "xesam:url" ];
        }
        stdout: SplitParser {
            onRead: data => {
                var text = String(data).trim()
                var match = text.match(/(?:v=|\/embed\/|\/v\/|youtu\.be\/|\/shorts\/)([a-zA-Z0-9_-]{11})/)
                if (match && match[1]) {
                    var url = "https://i.ytimg.com/vi/" + match[1] + "/hqdefault.jpg"
                    console.log("[MediaArtColorContext] youtubeArtFetcher extracted thumbnail URL:", url)
                    root.fallbackArtUrl = url
                }
            }
        }
    }

    Process {
        id: localArtChecker
        property string checkPath: ""
        command: [
            Directories.materialColorHelperPath,
            "file-ready", checkPath, "1500"
        ]
        onExited: (exitCode, exitStatus) => {
            console.log("[MediaArtColorContext] localArtChecker exited with code:", exitCode, "for path:", checkPath)
            root.downloaded = true
            if (exitCode === 0) {
                console.log("[MediaArtColorContext] Local art verified non-empty! displayedArtFilePath:", root.displayedArtFilePath)
            } else {
                console.log("[MediaArtColorContext] Local art wait timed out. Setting downloaded = true.")
            }
        }
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.effectiveArtUrl
        property string artFilePath: root.artFilePath
        command: [
            Directories.materialColorHelperPath,
            "download-cover", targetFile, artFilePath
        ]
        onExited: (exitCode, exitStatus) => {
            console.log("[MediaArtColorContext] coverArtDownloader exited with code:", exitCode, "target:", targetFile)
            if (exitCode === 0) {
                root.downloaded = true
                console.log("[MediaArtColorContext] Remote art downloaded successfully! displayedArtFilePath:", root.displayedArtFilePath)
            } else {
                console.log("[MediaArtColorContext] Remote art helper download failed, attempting shell curl fallback...")
                fallbackCoverArtDownloader.targetFile = targetFile
                fallbackCoverArtDownloader.artFilePath = artFilePath
                fallbackCoverArtDownloader.running = false
                fallbackCoverArtDownloader.running = true
            }
        }
    }

    Process {
        id: fallbackCoverArtDownloader
        property string targetFile: root.effectiveArtUrl
        property string artFilePath: root.artFilePath
        command: [
            "bash", "-c",
            'mkdir -p "$(dirname "$1")" && { [ -f "$1" ] && [ -s "$1" ] || curl -sSL -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0" "$2" -o "$1"; } && [ -s "$1" ]',
            "_", artFilePath, targetFile
        ]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.downloaded = true
                console.log("[MediaArtColorContext] Fallback curl download succeeded! displayedArtFilePath:", root.displayedArtFilePath)
            } else {
                console.log("[MediaArtColorContext] Fallback curl download failed!")
            }
        }
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
