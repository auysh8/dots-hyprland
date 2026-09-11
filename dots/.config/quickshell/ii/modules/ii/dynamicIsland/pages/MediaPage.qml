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
    implicitHeight: mainLayout.implicitHeight + 10

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

        let primary = MprisController.activePlayer;
        if (primary && (!primary.trackArtUrl || primary.trackArtUrl.length === 0)) {
            for (let i = 0; i < availablePlayers.length; ++i) {
                let p = availablePlayers[i];
                if (p && p.trackArtUrl && p.trackArtUrl.length > 0) {
                    let t1 = (primary.trackTitle || "").toLowerCase();
                    let t2 = (p.trackTitle || "").toLowerCase();
                    if (t1.length > 0 && (t1.includes(t2) || t2.includes(t1) || p.isPlaying)) {
                        return p;
                    }
                }
            }
        }
        return primary ? primary : spotifyPlayer
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

    function formatTime(seconds) {
        if (!seconds || isNaN(seconds) || seconds < 0) return "0:00";
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    function cycleLoopStatus() {
        if (!activePlayer || activePlayer.loopStatus === undefined) return;
        if (activePlayer.loopStatus === MprisLoopStatus.None) {
            activePlayer.loopStatus = MprisLoopStatus.Playlist;
        } else if (activePlayer.loopStatus === MprisLoopStatus.Playlist) {
            activePlayer.loopStatus = MprisLoopStatus.Track;
        } else {
            activePlayer.loopStatus = MprisLoopStatus.None;
        }
    }
    
    // Shared Media Color Context
    MediaArtColorContext {
        id: mediaContext
        activePlayer: root.activePlayer
    }

    // Art Handling mapped to mediaContext
    property string displayedArtFilePath: mediaContext.displayedArtFilePath

    // Color extraction from mediaContext
    property color contentColor: mediaContext.contentColor
    property color secondaryContentColor: mediaContext.secondaryContentColor
    property color pillColor: mediaContext.pillColor
    property color pillContentColor: mediaContext.pillContentColor
    property color backgroundColor: mediaContext.backgroundColor

    // Linked Timeline Player (for players like ytkew that delegate audio to mpv)
    readonly property MprisPlayer timelinePlayer: {
        const isYtkew = (activePlayer?.identity || "").toLowerCase().includes("ytkew");
        if (isYtkew) {
            for (let i = 0; i < availablePlayers.length; ++i) {
                const p = availablePlayers[i];
                const id = (p?.identity || "").toLowerCase();
                if (id.includes("mpv") && (p.isPlaying || p.trackTitle === activePlayer?.trackTitle)) {
                    return p;
                }
            }
        }
        return activePlayer;
    }

    // Interpolated Position Logic
    property real currentPosition: 0
    readonly property string activeTrackTitle: activePlayer?.trackTitle ?? ""
    
    onActiveTrackTitleChanged: {
        root.currentPosition = timelinePlayer ? timelinePlayer.position : 0
    }

    onTimelinePlayerChanged: {
        if (timelinePlayer) {
            root.currentPosition = timelinePlayer.position
        }
    }

    Connections {
        target: timelinePlayer || null
        ignoreUnknownSignals: true
        function onPositionChanged() {
            var diff = Math.abs(root.currentPosition - timelinePlayer.position)
            if (diff > 1.5 || !(timelinePlayer && timelinePlayer.isPlaying)) {
                root.currentPosition = timelinePlayer.position
            }
        }
        function onPlaybackStateChanged() {
            if (timelinePlayer) {
                root.currentPosition = timelinePlayer.position
            }
        }
        function onTrackTitleChanged() {
            if (timelinePlayer) {
                root.currentPosition = timelinePlayer.position
            }
        }
        function onMetadataChanged() {
            if (timelinePlayer) {
                root.currentPosition = timelinePlayer.position
            }
        }
    }
    
    Timer {
        running: timelinePlayer && timelinePlayer.isPlaying
        interval: 20
        repeat: true
        property int tickCount: 0
        onTriggered: {
            root.currentPosition += 0.02
            tickCount++
            if (tickCount >= 50) {
                tickCount = 0
                if (timelinePlayer) {
                    timelinePlayer.positionChanged()
                    if (Math.abs(root.currentPosition - timelinePlayer.position) > 1.0) {
                        root.currentPosition = timelinePlayer.position
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (timelinePlayer) {
            root.currentPosition = timelinePlayer.position
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 2

        // Top Row: Album Art Card + Metadata & Player Chip
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Dedicated Album Art Card (Squircle with Shadow)
            Item {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 54
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: albumArtContainer
                    anchors.fill: parent
                    radius: 16
                    color: Appearance.colors.colLayer2
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: albumArtContainer.width
                            height: albumArtContainer.height
                            radius: albumArtContainer.radius
                        }
                    }

                    Image {
                        id: coverArtImage
                        anchors.fill: parent
                        source: root.displayedArtFilePath
                        fillMode: Image.PreserveAspectCrop
                        opacity: (root.displayedArtFilePath !== "" && status === Image.Ready) ? 1.0 : 0.0
                        visible: opacity > 0.0
                        asynchronous: true

                        Behavior on opacity {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    // Fallback Icon
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "music_note"
                        iconSize: 26
                        fill: 1
                        color: root.secondaryContentColor
                        opacity: coverArtImage.opacity < 0.5 ? 1.0 : 0.0
                        visible: opacity > 0.0

                        Behavior on opacity {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                }

                    Rectangle {
                        anchors.fill: albumArtContainer
                        radius: 16
                        color: "transparent"
                        border.width: 1
                        border.color: ColorUtils.applyAlpha(root.contentColor, 0.15)
                    }
                }

            // Title + Artist + Source Badge
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                // Title Row: Track Title + Player Pill Chip aligned horizontally
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

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
                    }

                    // Compact Player Badge
                    RippleButton {
                        id: playerBadge
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                        implicitHeight: 22
                        implicitWidth: playerRow.implicitWidth + 14
                        buttonRadius: 11
                        pointingHandCursor: root.availablePlayers.length > 1

                        colBackground: ColorUtils.applyAlpha(root.contentColor, 0.10)
                        colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.20)
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
                            spacing: 4

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    let name = (activePlayer?.identity || "").toLowerCase();
                                    if (name.includes("spotify")) return "music_note";
                                    if (name.includes("firefox") || name.includes("chrome")) return "language";
                                    if (name.includes("vlc") || name.includes("mpv")) return "movie";
                                    return "headphones";
                                }
                                iconSize: 12
                                fill: 1
                                color: root.secondaryContentColor
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: activePlayer?.identity || "No Player"
                                color: root.secondaryContentColor
                                font.pixelSize: 10
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: playerPickerPopup.opened ? "expand_less" : "expand_more"
                                iconSize: 11
                                fill: 1
                                color: root.secondaryContentColor
                                visible: root.availablePlayers.length > 1
                            }
                        }

                        Popup {
                            id: playerPickerPopup
                            y: playerBadge.height + 4
                            x: playerBadge.width - width
                            width: 180
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

                            background: Rectangle {
                                radius: 12
                                color: ColorUtils.mix(root.backgroundColor, "#1A1A1A", 0.8)
                                border.color: ColorUtils.applyAlpha(root.contentColor, 0.25)
                                border.width: 1
                            }

                            contentItem: Column {
                                spacing: 2
                                Repeater {
                                    model: root.availablePlayers

                                    RippleButton {
                                        width: parent.width
                                        implicitHeight: 32
                                        buttonRadius: 8
                                        toggled: root.activePlayer === modelData

                                        colBackground: "transparent"
                                        colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.12)
                                        colBackgroundToggled: ColorUtils.applyAlpha(root.contentColor, 0.08)
                                        colRipple: root.contentColor

                                        onClicked: {
                                            root.selectedPlayer = modelData
                                            playerPickerPopup.close()
                                        }

                                        contentItem: Item {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8

                                            StyledText {
                                                anchors.left: parent.left
                                                anchors.right: pIcon.left
                                                anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.identity || "Unknown Player"
                                                color: root.contentColor
                                                font.pixelSize: 11
                                                font.weight: root.activePlayer === modelData ? Font.DemiBold : Font.Normal
                                                elide: Text.ElideRight
                                            }

                                            MaterialSymbol {
                                                id: pIcon
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: {
                                                    let id = (modelData.identity || "").toLowerCase();
                                                    if (id.includes("spotify")) return "music_note";
                                                    if (id.includes("firefox") || id.includes("chrome")) return "language";
                                                    if (id.includes("vlc") || id.includes("mpv")) return "movie";
                                                    return "headphones";
                                                }
                                                iconSize: 14
                                                fill: 1
                                                color: root.activePlayer === modelData ? root.contentColor : ColorUtils.applyAlpha(root.contentColor, 0.7)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Artist Text
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const meta = root.splitTrackMeta(activePlayer?.trackTitle || "", activePlayer?.trackArtist || "")
                        return meta.artist || "Unknown Artist"
                    }
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: root.secondaryContentColor
                    elide: Text.ElideRight
                }
            }
        }

        // Row with Progress Section (Slider + Timestamps) and Tactile ButtonGroup (Play/Pause, Next)
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 12

            // Left Side: Waveform Slider & Timestamps
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledSlider {
                    id: mediaSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14

                    configuration: (timelinePlayer && timelinePlayer.isPlaying) ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
                    highlightColor: root.pillColor
                    trackColor: ColorUtils.applyAlpha(root.contentColor, 0.25)
                    handleColor: root.pillColor
                    value: {
                        const dur = timelinePlayer?.length || activePlayer?.length || 0;
                        if (dur <= 0) return 0;
                        return Math.min(1.0, Math.max(0.0, root.currentPosition / dur));
                    }

                    onMoved: {
                        const target = (timelinePlayer && timelinePlayer.length > 0) ? timelinePlayer : activePlayer;
                        if (target && target.length > 0) {
                            target.position = value * target.length;
                            root.currentPosition = target.position;
                        }
                    }
                }

                // Timestamps (Elapsed & Total)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4

                    StyledText {
                        text: root.formatTime(root.currentPosition)
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: root.secondaryContentColor
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: root.formatTime(timelinePlayer?.length || activePlayer?.length || 0)
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: root.secondaryContentColor
                    }
                }
            }

            // Right Side: Tactile ButtonGroup for Play/Pause and Next
            ButtonGroup {
                id: mediaInlineControls
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 120
                width: 120
                spacing: 6

                // Play / Pause Button
                GroupButton {
                    id: playBtn
                    Layout.fillWidth: true
                    baseWidth: 70
                    baseHeight: 38
                    clickedWidth: baseWidth + 10
                    buttonRadius: 19
                    buttonRadiusPressed: 13
                    bounce: true

                    colBackground: root.pillColor
                    colBackgroundHover: ColorUtils.mix(root.pillColor, root.pillContentColor, 0.88)
                    colBackgroundActive: ColorUtils.mix(root.pillColor, root.pillContentColor, 0.76)

                    onClicked: activePlayer?.togglePlaying()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: (activePlayer && activePlayer.isPlaying) ? "pause" : "play_arrow"
                        iconSize: 22
                        fill: 1
                        color: root.pillContentColor
                    }
                }

                // Next Track Button
                GroupButton {
                    id: nextBtn
                    Layout.fillWidth: true
                    baseWidth: 44
                    baseHeight: 38
                    clickedWidth: baseWidth + 8
                    buttonRadius: 19
                    buttonRadiusPressed: 13
                    bounce: true

                    colBackground: ColorUtils.applyAlpha(root.contentColor, 0.12)
                    colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.22)
                    colBackgroundActive: ColorUtils.applyAlpha(root.contentColor, 0.32)

                    onClicked: activePlayer?.next()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "skip_next"
                        iconSize: 20
                        fill: 1
                        color: root.contentColor
                    }
                }
            }
        }
    }
}
