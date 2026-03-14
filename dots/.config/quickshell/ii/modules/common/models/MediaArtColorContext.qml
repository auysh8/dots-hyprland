import QtQuick
import Quickshell
import Quickshell.Io
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
    property bool isLocalArt: artUrl ? (String(artUrl).startsWith("file://") || String(artUrl).startsWith("/")) : false
    
    // File paths
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: isLocalArt ? String(artUrl).split('/').pop() : Qt.md5(String(artUrl))
    property string artFilePath: isLocalArt ? String(artUrl).replace("file://", "") : `${artDownloadLocation}/${artFileName}`

    // State
    property bool downloaded: isLocalArt
    property string displayedArtFilePath: downloaded ? (isLocalArt ? artUrl : Qt.resolvedUrl(artFilePath)) : ""
    
    // Auto-download remote art
    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0 || root.isLocalArt) return

        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        // Check if file exists, if not download it
        command: [ "bash", "-c", '[ -f "$1" ] || { curl -sSL "$2" -o "$1" && [ -s "$1" ]; }', "_", artFilePath, targetFile ]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.downloaded = true
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
