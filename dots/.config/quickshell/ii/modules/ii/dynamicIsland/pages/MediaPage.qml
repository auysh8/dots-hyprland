import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

import "media_color_cache.js" as MediaColorCache


Item {
    id: root
    clip: false
    implicitHeight: mainLayout.implicitHeight + 20 // Add margins to height

    // Player switching
    readonly property var availablePlayers: MprisController.players
    property MprisPlayer selectedPlayer: null
    readonly property MprisPlayer spotifyPlayer: {
        for (let i = 0; i < availablePlayers.length; ++i) {
            const p = availablePlayers[i]
            const id = (p?.identity || "").toLowerCase()
            if (id.includes("spotify")) return p
        }
        return null
    }
    readonly property MprisPlayer activePlayer: {
        if (selectedPlayer && availablePlayers.indexOf(selectedPlayer) >= 0) return selectedPlayer
        if (spotifyPlayer && spotifyPlayer.isPlaying) return spotifyPlayer
        return MprisController.activePlayer ? MprisController.activePlayer : spotifyPlayer
    }
    property bool showPlayerPicker: false

    function splitTrackMeta(rawTitle, rawArtist) {
        const title = rawTitle || ""
        const artist = rawArtist || ""
        if (artist.length > 0) return { title: title, artist: artist }

        const dotSep = title.indexOf(" • ")
        if (dotSep > 0 && dotSep < title.length - 3)
            return { title: title.slice(0, dotSep), artist: title.slice(dotSep + 3) }

        const dashSep = title.indexOf(" - ")
        if (dashSep > 0 && dashSep < title.length - 3)
            return { title: title.slice(0, dashSep), artist: title.slice(dashSep + 3) }

        return { title: title, artist: "" }
    }
    
    // Art Handling
    // Art Handling
    property var artUrl: activePlayer ? activePlayer.trackArtUrl : ""
    property bool isLocalArt: artUrl ? (String(artUrl).startsWith("file://") || String(artUrl).startsWith("/")) : false
    
    property string artDownloadLocation: Directories.coverArt
    property string artFileName: isLocalArt ? String(artUrl).split('/').pop() : Qt.md5(String(artUrl))
    property string artFilePath: isLocalArt ? String(artUrl).replace("file://", "") : `${artDownloadLocation}/${artFileName}`

    property bool downloaded: isLocalArt
    property string displayedArtFilePath: downloaded ? (isLocalArt ? artUrl : Qt.resolvedUrl(artFilePath)) : ""
    
    onArtFilePathChanged: {
        if (root.artUrl.length == 0 || root.isLocalArt) return

        // Binding does not work in Process
        coverArtDownloader.targetFile = root.artUrl 
        coverArtDownloader.artFilePath = root.artFilePath
        // Download
        root.downloaded = false
        coverArtDownloader.running = true
    }

    Process {
        id: coverArtDownloader
        property string targetFile: root.artUrl
        property string artFilePath: root.artFilePath
        // Check if file exists, if not download it
        command: [ "bash", "-c", `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'` ]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true
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

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: ColorUtils.mix(root.extractedColor, Appearance.colors.colPrimaryContainer, 0.8)
    }

    property color contentColor: blendedColors.colOnLayer0
    property color secondaryContentColor: blendedColors.colSubtext
    property color pillColor: blendedColors.colSecondaryContainer
    property color pillContentColor: blendedColors.colOnSecondaryContainer
    property color backgroundColor: blendedColors.colLayer0 

    Behavior on contentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on secondaryContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on pillContentColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }
    Behavior on backgroundColor { ColorAnimation { duration: 800; easing.type: Easing.OutCubic } }

    // Interpolated Position Logic
    property real currentPosition: 0
    
    Connections {
        target: activePlayer || null
        ignoreUnknownSignals: true
        function onPositionChanged() {
            var diff = Math.abs(root.currentPosition - activePlayer.position)
            if (diff > 1.5 || !(activePlayer && activePlayer.isPlaying)) {
                root.currentPosition = activePlayer.position
            }
        }
    }
    
    Timer {
        running: activePlayer && activePlayer.isPlaying
        interval: 20
        repeat: true
        onTriggered: root.currentPosition += 0.02
    }

    Component.onCompleted: {
        if (activePlayer) {
            root.currentPosition = activePlayer.position
        }
    }

    // Background Art
    Item {
        anchors.fill: parent
        
        Image {
            id: bgArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            visible: false
            asynchronous: true
        }

        // Apply rounding natively via layer.effect instead of manual masks
        Rectangle {
            id: roundedBg
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: "transparent"
            clip: true

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: bgArt.width
                    height: bgArt.height
                    radius: Appearance.rounding.normal
                }
            }

            Image {
                anchors.fill: parent
                source: bgArt.source
                fillMode: Image.PreserveAspectCrop
                visible: true
            }
        }
        
        // Dark Overlay for readability
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.68
            radius: Appearance.rounding.normal
        }
        
        // Placeholder if no art
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            visible: bgArt.status !== Image.Ready || bgArt.source == ""
            z: -1
        }

        // Slight border
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Appearance.rounding.normal
            border.width: 2
            border.color: Appearance.colors.colLayer0Border
            opacity: 0.8
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 2

        // Top Row (Title + Player Badge)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Title + Artist (left)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const meta = root.splitTrackMeta(activePlayer?.trackTitle || "", activePlayer?.trackArtist || "")
                        return meta.title || "No Media"
                    }
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: root.contentColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const meta = root.splitTrackMeta(activePlayer?.trackTitle || "", activePlayer?.trackArtist || "")
                        return meta.artist || "Unknown Artist"
                    }
                    font.pixelSize: 13
                    color: root.secondaryContentColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }
            }

            // Player Badge (right)
            RippleButton {
                id: playerBadge

                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                implicitHeight: 28
                implicitWidth: playerRow.implicitWidth + 24
                buttonRadius: 14
                pointingHandCursor: root.availablePlayers.length > 1

                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.15)
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.3)
                colRipple: root.contentColor

                visible: root.availablePlayers.length > 0

                onClicked: {
                    if (root.availablePlayers.length > 1) {
                        if (playerPickerPopup.opened) playerPickerPopup.close()
                        else playerPickerPopup.open()
                    }
                }

                contentItem: Row {
                    id: playerRow
                    spacing: 6

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            let name = (activePlayer?.identity || "").toLowerCase();
                            if (name.includes("spotify"))
                                return "music_note";

                            if (name.includes("firefox") || name.includes("chrome"))
                                return "language";

                            if (name.includes("vlc") || name.includes("mpv"))
                                return "movie";

                            return "headphones";
                        }
                        iconSize: 14
                        color: root.secondaryContentColor
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: activePlayer?.identity || "No Player"
                        color: root.secondaryContentColor
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: playerPickerPopup.opened ? "expand_less" : "expand_more"
                        iconSize: 12
                        color: root.secondaryContentColor
                        visible: root.availablePlayers.length > 1
                    }

                }

                Popup {
                    id: playerPickerPopup
                    y: playerBadge.height + 4
                    x: playerBadge.width - width
                    width: 200
                    padding: 6

                    enter: Transition {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                    }
                    exit: Transition {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                        NumberAnimation { property: "scale"; from: 1.0; to: 0.92; duration: 150; easing.type: Easing.InCubic }
                    }
                    
                    transformOrigin: Item.TopRight

                    background: Item {
                        Rectangle {
                            id: popupBg
                            anchors.fill: parent
                            radius: 12
                            color: ColorUtils.mix(root.backgroundColor, "#000000", 0.4)
                            opacity: 0.95
                            layer.enabled: true
                            layer.effect: StyledDropShadow { target: popupBg }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.25)
                            border.width: 1
                        }
                    }

                    contentItem: Column {
                        spacing: 0
                        Repeater {
                            model: root.availablePlayers

                            RippleButton {
                                id: playerItem
                                width: parent.width
                                implicitHeight: 36
                                buttonRadius: 8
                                toggled: root.activePlayer === modelData

                                colBackground: "transparent"
                                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                                colBackgroundToggled: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.08)
                                colRipple: root.contentColor

                                onClicked: {
                                    root.selectedPlayer = modelData
                                    playerPickerPopup.close()
                                }

                                contentItem: Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12

                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.right: playerIcon.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.identity || "Unknown Player"
                                        color: root.contentColor
                                        font.pixelSize: 12
                                        font.weight: root.activePlayer === modelData ? Font.DemiBold : Font.Normal
                                        elide: Text.ElideRight
                                    }

                                    MaterialSymbol {
                                        id: playerIcon
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            let id = (modelData.identity || "").toLowerCase();
                                            if (id.includes("spotify")) return "music_note";
                                            if (id.includes("firefox") || id.includes("chrome")) return "language";
                                            if (id.includes("vlc") || id.includes("mpv")) return "movie";
                                            return "headphones";
                                        }
                                        iconSize: 16
                                        color: root.activePlayer === modelData ? root.contentColor : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.7)
                                    }
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 2
                                    height: 16
                                    radius: 1
                                    color: root.pillContentColor
                                    visible: root.activePlayer === modelData
                                }
                            }
                        }
                    }
                }
            }
        }



        // Spacer to push slider and controls down
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 10
        }

        // Squiggly Slider
        StyledSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            
            configuration: (activePlayer && activePlayer.isPlaying) ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
            highlightColor: root.contentColor
            trackColor: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.5)
            handleColor: root.contentColor
            value: {
                return (activePlayer && activePlayer.length > 0) ? root.currentPosition / activePlayer.length : 0;
            }
            
            onMoved: {
                if (activePlayer) {
                    activePlayer.position = value * activePlayer.length;
                    root.currentPosition = activePlayer.position;
                }
            }
        }

        // Controls
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            // Lyrics Toggle (Keep small and simple)
            RippleButton {
                id: lyricsToggle

                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: height / 2
                toggled: LyricsService.open

                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
                colBackgroundHover: colBackground
                colBackgroundToggled: root.pillColor
                colBackgroundToggledHover: colBackgroundToggled
                colRipple: root.contentColor
                colRippleToggled: root.pillContentColor

                onClicked: LyricsService.toggle()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "lyrics"
                    iconSize: 18
                    color: lyricsToggle.toggled ? root.pillContentColor : root.contentColor
                }
            }
            Item { Layout.fillWidth: true }

            // Previous Button (Oval/Pill with bounce)
            RippleButton {
                id: prevBtn

                implicitWidth: 40 + (down ? 8 : (playBtn.down ? -6 : 0))
                implicitHeight: 40
                buttonRadius: height / 2

                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                colRipple: root.contentColor

                onClicked: activePlayer?.previous()

                Behavior on implicitWidth {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    iconSize: 24
                    color: root.contentColor
                }
            }

            // Play/Pause Button (Squircle with bounce)
            RippleButton {
                id: playBtn

                implicitWidth: 60 + (down ? 12 : (prevBtn.down || nextBtn.down ? -8 : 0))
                implicitHeight: 40
                buttonRadius: height / 2

                colBackground: root.pillColor
                colRipple: root.pillContentColor

                onClicked: activePlayer?.togglePlaying()

                Behavior on implicitWidth {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: (activePlayer && activePlayer.isPlaying) ? "pause" : "play_arrow"
                    iconSize: 28
                    color: root.pillContentColor
                }
            }

            // Next Button (Oval/Pill with bounce)
            RippleButton {
                id: nextBtn

                implicitWidth: 40 + (down ? 8 : (playBtn.down ? -6 : 0))
                implicitHeight: 40
                buttonRadius: height / 2

                colBackground: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                colRipple: root.contentColor

                onClicked: activePlayer?.next()

                Behavior on implicitWidth {
                    animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_next"
                    iconSize: 24
                    color: root.contentColor
                }
            }

            Item { Layout.fillWidth: true }
            
             // Empty space
             Item { width: 28 }
        }
    }
}
