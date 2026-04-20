import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Qt5Compat.GraphicalEffects
import "../lyricsComponents" as LyricsComponents

Item {
    id: root

    property var rootContext
    property bool navRailExpanded: false
    
    // Smooth visibility transitions
    property bool show: rootContext && rootContext.currentView === "player"
    property bool queueExpanded: false
    property bool inlineLyricsExpanded: false
    property real inlineLyricsPosition: rootContext ? rootContext.trackPositionSec : 0
    property real maxLyricsPositionDrift: 0.12
    property real lastLyricsTickMs: 0

    property bool isMainViewTransitioning: mainScaleAnim.running || mainOpacityAnim.running
    property bool isLyricsViewTransitioning: lyricsScaleAnim.running || lyricsOpacityAnim.running
    property bool isQueueTransitioning: queueXAnim.running

    property bool isWindowTransitioning: rootScaleAnim.running || rootOpacityAnim.running
    property bool isLayoutTransitioning: isWindowTransitioning || isMainViewTransitioning || isLyricsViewTransitioning || isQueueTransitioning

    property real currentRadius: 32

    anchors.fill: parent

    property real animScale: 0.75
    property real animOpacity: 0.0

    transformOrigin: Item.Bottom

    scale: animScale
    opacity: animOpacity

    Behavior on animScale { NumberAnimation { id: rootScaleAnim; duration: 550; easing.type: Easing.OutBack; easing.overshoot: 0.4 } }
    Behavior on animOpacity { NumberAnimation { id: rootOpacityAnim; duration: 350; easing.type: Easing.OutCubic } }

    onShowChanged: {
        if (show) {
            root.animOpacity = 1.0
            root.animScale = 1.0
            fadeInTimer.restart()
        } else {
            fadeInTimer.stop()
            root.animOpacity = 0.0
            root.animScale = 0.75
            root.elementsVisible = false
        }
    }

    visible: root.show || animOpacity > 0.01

    // Prevent click-through to underlying views when the player is open
    MouseArea {
        anchors.fill: parent
        enabled: root.show
        onPressed: (mouse) => mouse.accepted = true
    }

    Connections {
        target: rootContext || null
        ignoreUnknownSignals: true

        function onTrackPositionSecChanged() {
            if (!rootContext) return
            const realPos = rootContext.trackPositionSec || 0.0
            const diff = Math.abs(root.inlineLyricsPosition - realPos)
            if (diff > root.maxLyricsPositionDrift || rootContext.playbackPaused) {
                root.inlineLyricsPosition = realPos
            }

            if (rootContext.showVideoInThumbnail && typeof canvasPlayer !== "undefined" && canvasPlayer.playbackState === MediaPlayer.PlayingState) {
                const playerPosSec = canvasPlayer.position / 1000.0
                const syncDiff = realPos - playerPosSec // Positive if video is behind audio

                if (Math.abs(syncDiff) > 4.0) {
                    // Hard seek only for large drift — buffers flush, so keep threshold high to avoid stutter
                    canvasPlayer.position = realPos * 1000
                } else if (syncDiff > 0.5) {
                    canvasPlayer.playbackRate = 1.08  // Gentle nudge forward
                } else if (syncDiff < -0.5) {
                    canvasPlayer.playbackRate = 0.92  // Gentle nudge back
                } else if (Math.abs(syncDiff) <= 0.1 && canvasPlayer.playbackRate !== 1.0) {
                    canvasPlayer.playbackRate = 1.0
                }
            }
        }

        function onPlaybackPausedChanged() {
            root.lastLyricsTickMs = 0
            if (rootContext) {
                root.inlineLyricsPosition = rootContext.trackPositionSec || 0
            }
            if (bgLayer && typeof bgLayer.updateCanvasPlayback === "function") {
                bgLayer.updateCanvasPlayback()
            }
        }

        function onCurrentTrackChanged() {
            root.lastLyricsTickMs = 0
            if (rootContext) {
                root.inlineLyricsPosition = rootContext.trackPositionSec || 0
            }
        }
    }

    Timer {
        id: inlineLyricsPositionTimer
        // OPTIMIZATION: Only run this high-frequency timer when lyrics are actually visible!
        running: !!rootContext && !!rootContext.currentTrack && !rootContext.playbackPaused && root.inlineLyricsExpanded
        interval: 100
        repeat: true

        onTriggered: {
            if (!rootContext || !rootContext.currentTrack)
                return

            const nowMs = Date.now()
            if (root.lastLyricsTickMs <= 0) {
                root.lastLyricsTickMs = nowMs
                root.inlineLyricsPosition = rootContext.trackPositionSec || 0
                return
            }

            const dt = (nowMs - root.lastLyricsTickMs) / 1000.0
            root.lastLyricsTickMs = nowMs

            if (dt <= 0 || dt > 0.25) {
                root.inlineLyricsPosition = rootContext.trackPositionSec || 0
                return
            }

            root.inlineLyricsPosition += dt
            if (rootContext.trackDurationSec > 0 && root.inlineLyricsPosition > rootContext.trackDurationSec) {
                root.inlineLyricsPosition = rootContext.trackDurationSec
            }
        }
    }

    property bool elementsVisible: false
    onElementsVisibleChanged: {
        if (bgLayer && typeof bgLayer.updateCanvasPlayback === "function") {
            bgLayer.updateCanvasPlayback()
        }
    }

    Timer {
        id: fadeInTimer
        interval: 250
        onTriggered: { root.elementsVisible = true }
    }

    Item {
        id: bgLayer
        anchors.fill: parent
        opacity: root.elementsVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // --- Canvas animated background ---
        property bool canvasReady: false

        // Base solid background to prevent transparency
        Rectangle {
            anchors.fill: parent
            radius: root.currentRadius
            color: rootContext ? rootContext.backgroundColor : Appearance.colors.colLayer0Base
        }

        // --- Apple Music Style Fluid Mesh Blobs ---
        Item {
            id: fluidMeshMaskWrapper
            anchors.fill: parent
            visible: root.show
            
            layer.enabled: !root.isWindowTransitioning
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: fluidMeshMaskWrapper.width
                    height: fluidMeshMaskWrapper.height
                    radius: root.currentRadius
                }
            }

            Item {
                id: fluidMeshContainer
                anchors.fill: parent
                // clip is not strictly needed since we are using OpacityMask on the parent
                
                property real bassAmplitude: {
                    if (!root.show || root.isLayoutTransitioning || !rootContext || rootContext.playbackPaused) return 0.0;
                    let src = rootContext.visualizerPoints;
                    if (!src || src.length < 3) return 0.0;
                    // Average the first 3 bins for bass, normalize to 0..1 (assuming max is around 500)
                    let bass = (src[0] + src[1] + src[2]) / 3.0;
                    return Math.min(1.0, bass / 400.0); // Smoother normalization
                }
                
                Behavior on bassAmplitude {
                    NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 120
                    blur: 1.0
                    saturation: 0.6 + (fluidMeshContainer.bassAmplitude * 0.2)
                    brightness: 0.0 + (fluidMeshContainer.bassAmplitude * 0.08)
                    contrast: 0.0 + (fluidMeshContainer.bassAmplitude * 0.05)
                }

                property bool animateBlobs: root.show && rootContext && !rootContext.playbackPaused && !root.isLayoutTransitioning

            // Blob 1 (Primary / Extracted Color)
            Rectangle {
                width: parent.width * 1.2
                height: parent.height * 1.2
                radius: Math.min(width, height) / 2
                color: rootContext ? rootContext.extractedColor : "transparent"
                opacity: 0.6
                x: parent.width * 0.1
                y: parent.height * 0.1
                
                SequentialAnimation on x {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: -parent.width * 0.2; duration: 15000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.width * 0.3; duration: 18000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.width * 0.1; duration: 16000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: parent.height * 0.4; duration: 17000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -parent.height * 0.3; duration: 14000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.1; duration: 16000; easing.type: Easing.InOutSine }
                }
            }

            // Blob 2 (Accent / Pill Color)
            Rectangle {
                width: parent.width * 1.5
                height: parent.height * 0.8
                radius: Math.min(width, height) / 2
                color: rootContext ? rootContext.pillColor : "transparent"
                opacity: 0.5
                x: parent.width * 0.2
                y: parent.height * 0.5
                
                SequentialAnimation on x {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: parent.width * 0.6; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -parent.width * 0.4; duration: 16000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.width * 0.2; duration: 18000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: -parent.height * 0.2; duration: 15000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.7; duration: 19000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.5; duration: 17000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on rotation {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 360; duration: 30000 }
                }
            }

            // Blob 3 (Secondary / Loader Accent)
            Rectangle {
                width: parent.width * 0.9
                height: parent.height * 1.3
                radius: Math.min(width, height) / 2
                color: rootContext ? rootContext.loaderAccentColor : "transparent"
                opacity: 0.55
                x: -parent.width * 0.3
                y: parent.height * 0.2
                
                SequentialAnimation on x {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: parent.width * 0.5; duration: 14000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.width * 0.1; duration: 18000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -parent.width * 0.3; duration: 16000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: parent.height * 0.8; duration: 17000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.1; duration: 15000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.2; duration: 19000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on rotation {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { from: 360; to: 0; duration: 25000 }
                }
            }
            
            // Blob 4 (Mixed / Highlight)
            Rectangle {
                width: parent.width * 1.1
                height: parent.width * 1.1
                radius: width / 2
                color: rootContext ? rootContext.extractedColor : "transparent"
                opacity: 0.4
                x: parent.width * 0.5
                y: -parent.height * 0.2
                
                SequentialAnimation on x {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: -parent.width * 0.1; duration: 18000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.width * 0.7; duration: 16000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.width * 0.5; duration: 15000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: parent.height * 0.6; duration: 14000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.2; duration: 19000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -parent.height * 0.2; duration: 17000; easing.type: Easing.InOutSine }
                }
            }
            
            // Blob 5 (Darker contrast for depth)
            Rectangle {
                width: parent.width * 1.4
                height: parent.height * 1.4
                radius: Math.min(width, height) / 2
                color: rootContext ? rootContext.backgroundColor : "transparent"
                opacity: 0.8
                x: -parent.width * 0.2
                y: parent.height * 0.6
                
                SequentialAnimation on x {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: parent.width * 0.4; duration: 19000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -parent.width * 0.5; duration: 15000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -parent.width * 0.2; duration: 18000; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on y {
                    running: true; paused: !fluidMeshContainer.animateBlobs; loops: Animation.Infinite
                    NumberAnimation { to: -parent.height * 0.1; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.8; duration: 16000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: parent.height * 0.6; duration: 19000; easing.type: Easing.InOutSine }
                }
            }
        }
        } // End fluidMeshMaskWrapper

        function updateCanvasPlayback() {
            if (!canvasPlayer.source || canvasPlayer.source.toString() === "") {
                return
            }
            
            const shouldPlay = root.elementsVisible && rootContext && !rootContext.playbackPaused
            
            if (shouldPlay) {
                if (canvasPlayer.mediaStatus === MediaPlayer.LoadedMedia || canvasPlayer.mediaStatus === MediaPlayer.BufferedMedia) {
                    canvasPlayer.play()
                }
            } else {
                canvasPlayer.pause()
            }
        }

        MediaPlayer {
            id: canvasPlayer
            // Only set source if we have a valid non-empty URL
            source: {
                if (rootContext && rootContext.showVideoInThumbnail && rootContext.currentMusicVideoUrl && rootContext.currentMusicVideoUrl.length > 0) {
                    return rootContext.currentMusicVideoUrl
                }
                const url = rootContext ? rootContext.currentCanvasUrl : ""
                return (url && url.length > 0 && url !== "about:blank") ? url : ""
            }
            loops: MediaPlayer.Infinite
            autoPlay: false  // Manual control to prevent race conditions
            videoOutput: canvasOutput
            // No audioOutput — muted, visual only

            onPlaybackStateChanged: {
                console.log("[CanvasPlayer] Playback state changed:", playbackState, "hasVideo=", hasVideo)
                if (playbackState === MediaPlayer.PlayingState) {
                    if (hasVideo) bgLayer.canvasReady = true
                } else if (playbackState === MediaPlayer.StoppedState || playbackState === MediaPlayer.StalledState) {
                    bgLayer.canvasReady = false
                }
            }
            onMediaStatusChanged: {
                console.log("[CanvasPlayer] Media status changed:", mediaStatus)
                // Only auto-play when media is fully loaded/buffered
                if (mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) {
                    bgLayer.updateCanvasPlayback()
                } else if (mediaStatus === MediaPlayer.InvalidMedia || mediaStatus === MediaPlayer.EndOfMedia) {
                    bgLayer.canvasReady = false
                    canvasPlayer.stop()
                }
            }
            onHasVideoChanged: {
                console.log("[CanvasPlayer] hasVideo changed:", hasVideo)
                if (hasVideo && playbackState === MediaPlayer.PlayingState) {
                    bgLayer.canvasReady = true
                } else if (!hasVideo) {
                    bgLayer.canvasReady = false
                }
            }

            onSourceChanged: {
                console.log("[CanvasPlayer] Source changed:", source)
                bgLayer.canvasReady = false
                // Reset player state when source changes
                if (!source || source.length === 0) {
                    canvasPlayer.stop()
                }
            }
            onErrorOccurred: (error, errorString) => {
                console.error("[CanvasPlayer] Error:", error, errorString)
                bgLayer.canvasReady = false
                // Stop playback on error to prevent cascading failures
                canvasPlayer.stop()
            }
        }


        // Gradient overlay utilizing quantized colors
        Rectangle {
            anchors.fill: parent
            radius: root.currentRadius
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.applyAlpha(rootContext ? rootContext.pillColor : Appearance.colors.colSecondaryContainer, 0.15) }
                GradientStop { position: 0.6; color: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colLayer0Base, 0.4) }
                GradientStop { position: 1.0; color: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colLayer0Base, 0.85) }
            }
        }
    }


    Item {
        anchors.fill: parent
        opacity: root.elementsVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        transform: Translate {
            y: root.elementsVisible ? 0 : 60
            Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        }

        // Collapse button (Top right)
        RippleButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 24
            implicitWidth: 48
            implicitHeight: 48
            buttonRadius: 24
            colBackground: ColorUtils.applyAlpha(rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1, 0.5)
            colBackgroundHover: ColorUtils.applyAlpha(rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1, 0.8)
            colRipple: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            horizontalPadding: 0
            verticalPadding: 0
            z: 10

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "expand_more"
                iconSize: 28
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                if (rootContext) rootContext.currentView = rootContext.previousView || "home"
            }
        }

    // Main Content
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        anchors.topMargin: 80 // Space for collapse button
        anchors.bottomMargin: 24
        spacing: 24

        // Content Area Container (Stacks Main vs Lyrics)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // --- MAIN VIEW ---
            ColumnLayout {
                id: mainPlaybackView
                anchors.fill: parent
                spacing: 24
                scale: root.inlineLyricsExpanded ? 0.92 : 1.0
                opacity: root.inlineLyricsExpanded ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { id: mainOpacityAnim; duration: 350; easing.type: Easing.InOutQuad } }
                Behavior on scale { NumberAnimation { id: mainScaleAnim; duration: 450; easing.type: Easing.OutCubic } }

        // Large Cover Art
        Item {
            id: artLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            property string _trackId: rootContext.currentTrack ? rootContext.currentTrack.videoId : ""
            readonly property bool preferLandscapeHero: !!rootContext
                && !!rootContext.currentTrack
                && !!rootContext.currentTrack.isVideoTrack
                && (
                    (!bgLayer.canvasReady && (rootContext.currentTrack.landscapeArtCandidates || []).length > 0)
                    || (rootContext.showVideoInThumbnail)
                )
            on_TrackIdChanged: {
                if (_trackId !== "") {
                    artAnim.restart()
                }
            }
            
            SequentialAnimation {
                id: artAnim
                ParallelAnimation {
                    NumberAnimation { target: artRect; property: "scale"; from: 0.85; to: 1.0; duration: 600; easing.type: Easing.OutElastic; easing.amplitude: 1.3 }
                    NumberAnimation { target: artRect; property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                id: artRect
                width: artLayout.preferLandscapeHero
                    ? Math.min(parent.width * 0.96, parent.height * 1.45)
                    : Math.min(parent.width, parent.height) * 1.0
                height: artLayout.preferLandscapeHero ? (width * 9 / 16) : width
                anchors.centerIn: parent
                radius: 32
                color: rootContext.surfaceColor

                Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                layer.enabled: !root.isLayoutTransitioning
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Appearance.colors.colShadow
                    shadowBlur: 2.0
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 12
                }

                RoundedImage {
                    id: landscapeHero
                    anchors.fill: parent
                    radius: 32
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: !bgLayer.canvasReady && status === Image.Ready && currentSource !== ""

                    property var candidateList: rootContext && rootContext.currentTrack
                        ? (rootContext.currentTrack.landscapeArtCandidates || [])
                        : []
                    property int candidateIndex: 0
                    property string currentSource: candidateIndex < candidateList.length ? candidateList[candidateIndex] : ""
                    property string _candidateKey: (rootContext && rootContext.currentTrack ? rootContext.currentTrack.videoId : "")
                        + "|" + candidateList.join("|")

                    on_CandidateKeyChanged: candidateIndex = 0
                    source: currentSource

                    onStatusChanged: {
                        if (status === Image.Error && candidateIndex < candidateList.length - 1) {
                            candidateIndex += 1
                        }
                    }
                }

                RoundedImage {
                    anchors.fill: parent
                    source: rootContext.displayedArtFilePath || ""
                    fillMode: Image.PreserveAspectCrop
                    visible: !bgLayer.canvasReady && !landscapeHero.visible && rootContext.displayedArtFilePath !== ""
                    radius: 32
                }
                
                Item {
                    id: canvasClip
                    anchors.fill: parent
                    
                    opacity: bgLayer.canvasReady ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                    layer.enabled: opacity > 0 && !root.isWindowTransitioning
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: canvasClip.width
                            height: canvasClip.height
                            radius: 32
                        }
                    }

                    VideoOutput {
                        id: canvasOutput
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                }

                RippleButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 12
                    width: 44
                    height: 44
                    buttonRadius: 22
                    visible: !!rootContext && !!rootContext.currentTrack && !!rootContext.currentTrack.isVideoTrack
                    colBackground: ColorUtils.applyAlpha(Appearance.colors.colLayer0, 0.4)
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colLayer1Hover, 0.6)
                    onClicked: {
                        if (rootContext) {
                            rootContext.showVideoInThumbnail = !rootContext.showVideoInThumbnail;
                            if (rootContext.showVideoInThumbnail && !rootContext.currentMusicVideoUrl) {
                                rootContext.sendCommand({"command": "get_video_stream", "videoId": rootContext.currentTrack.videoId});
                            }
                        }
                    }
                    contentItem: MaterialSymbol {
                        text: (rootContext && rootContext.showVideoInThumbnail) ? "image" : "movie"
                        iconSize: 24
                        color: Appearance.colors.colOnLayer0
                        anchors.centerIn: parent
                    }
                }
            }
        }

        // Track Info and Buttons Row
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 500
            spacing: 16

            property string _trackId: rootContext.currentTrack ? rootContext.currentTrack.videoId : ""
            on_TrackIdChanged: {
                if (_trackId !== "") {
                    infoAnim.restart()
                }
            }

            SequentialAnimation {
                id: infoAnim
                ParallelAnimation {
                    NumberAnimation { target: trackInfoRow; property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutCubic }
                    NumberAnimation { target: trackInfoRow; property: "scale"; from: 0.95; to: 1.0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
            }

            RowLayout {
                id: trackInfoRow
                Layout.fillWidth: true
                spacing: 16

                // Title and Artist (left side)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: rootContext.currentTrack ? rootContext.currentTrack.title : "Not Playing"
                        font.pixelSize: 26
                        font.weight: 800
                        color: rootContext.contentColor
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                    }

                    // Quality Badge
                    Rectangle {
                        visible: rootContext.currentTrack && rootContext.currentTrack.quality !== ""
                        radius: 6
                        color: ColorUtils.applyAlpha(rootContext.contentColor, 0.15)
                        Layout.preferredWidth: qualityLabel.implicitWidth + 12
                        Layout.preferredHeight: qualityLabel.implicitHeight + 4
                        
                        StyledText {
                            id: qualityLabel
                            anchors.centerIn: parent
                            text: rootContext.currentTrack ? rootContext.currentTrack.quality.toUpperCase() : ""
                            font.pixelSize: 10
                            font.weight: 900
                            font.letterSpacing: 1
                            color: rootContext.contentColor
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: rootContext.currentTrack ? rootContext.currentTrack.artist : ""
                        font.pixelSize: 16
                        font.weight: 500
                        color: rootContext.secondaryContentColor
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                    }
                }

                ButtonGroup {
                    id: playbackActionGroup
                    spacing: 4

                    // Heart/Like button
                    SelectionGroupButton {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        visible: rootContext.currentTrack !== null
                        leftmost: true
                        toggled: rootContext.currentTrackLiked
                        
                        colBackground: rootContext.pillColor
                        colBackgroundHover: rootContext.pillColorHover
                        colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.85)
                        colBackgroundToggled: rootContext.pillColor
                        colBackgroundToggledHover: rootContext.pillColorHover
                        colBackgroundToggledActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.85)

                        contentItem: RowLayout {
                            spacing: 0
                            Item {
                                implicitWidth: matIcon1.implicitWidth
                                Layout.alignment: Qt.AlignVCenter
                                MaterialSymbol {
                                    id: matIcon1
                                    anchors.centerIn: parent
                                    text: rootContext.currentTrackLiked ? "favorite" : "favorite_border"
                                    fill: rootContext.currentTrackLiked ? 1 : 0
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: rootContext.currentTrackLiked ? rootContext.loaderAccentColor : rootContext.pillContentColor
                                }
                            }
                        }

                        releaseAction: () => { rootContext.toggleCurrentTrackLike() }
                    }

                    // Queue/Radio button
                    SelectionGroupButton {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        visible: rootContext.currentTrack !== null
                        rightmost: true
                        toggled: rootContext.radioTrayVisible
                        
                        colBackground: rootContext.pillColor
                        colBackgroundHover: rootContext.pillColorHover
                        colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.85)
                        colBackgroundToggled: rootContext.pillColor
                        colBackgroundToggledHover: rootContext.pillColorHover
                        colBackgroundToggledActive: rootContext.pillColor

                        contentItem: RowLayout {
                            spacing: 0
                            Item {
                                implicitWidth: matIcon2.implicitWidth
                                Layout.alignment: Qt.AlignVCenter
                                MaterialSymbol {
                                    id: matIcon2
                                    anchors.centerIn: parent
                                    text: "more_vert"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: rootContext.pillContentColor
                                }                            
                            }
                        }

                        releaseAction: () => { rootContext.radioTrayVisible = !rootContext.radioTrayVisible }
                    }
                }
            }
        }

        // Timeline Slider (full width)
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 500
            spacing: 8

            MusicSeekSlider {
                id: trackSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 24

                wavy: !rootContext.isTrackLoading && !rootContext.playbackPaused
                highlightColor: rootContext.contentColor
                trackColor: ColorUtils.applyAlpha(rootContext.contentColor, 0.3)
                handleColor: rootContext.contentColor

                property real localSeekValue: 0
                property real lastSeekMs: 0

                Connections {
                    target: rootContext || null
                    ignoreUnknownSignals: true
                    function onTrackPositionSecChanged() {
                        if (trackSlider.pressed) return;
                        if (Date.now() - trackSlider.lastSeekMs < 1500) return;
                        trackSlider.value = rootContext.trackDurationSec > 0 ? rootContext.trackPositionSec / rootContext.trackDurationSec : 0;
                    }
                    function onTrackDurationSecChanged() {
                        if (trackSlider.pressed) return;
                        if (Date.now() - trackSlider.lastSeekMs < 1500) return;
                        trackSlider.value = rootContext.trackDurationSec > 0 ? rootContext.trackPositionSec / rootContext.trackDurationSec : 0;
                    }
                }

                enabled: rootContext.trackDurationSec > 0
                onMoved: {
                    if (rootContext.trackDurationSec > 0) {
                        trackSlider.localSeekValue = trackSlider.value;
                        trackSlider.lastSeekMs = Date.now();
                        let seekPos = value * rootContext.trackDurationSec
                        rootContext.sendCommand({"command": "seek", "position": seekPos})
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(rootContext.trackPositionSec)
                    font.pixelSize: 12
                    color: rootContext.secondaryContentColor
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(rootContext.trackDurationSec)
                    font.pixelSize: 12
                    color: rootContext.secondaryContentColor
                }
            }
        }

        // Controls
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            Layout.topMargin: -16

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                // Previous Button
                RippleButton {
                    id: prevBtnContainer
                    property bool isPressed: down

                    implicitWidth: 64 + (isPressed ? 16 : (playBtnContainer.isPressed ? -10 : 0))
                    implicitHeight: 64

                    Behavior on implicitWidth {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }

                    buttonRadius: 32
                    colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 28
                        fill: 1
                        color: rootContext.contentColor
                        text: "skip_previous"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: rootContext.sendCommand({"command": "previous"})
                }

                // Play/Pause Button
                RippleButton {
                    id: playBtnContainer
                    property bool isPressed: down

                    implicitWidth: 130 + (isPressed ? 20 : (prevBtnContainer.isPressed ? -16 : (nextBtnContainer.isPressed ? -16 : 0)))
                    implicitHeight: 64

                    Behavior on implicitWidth {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }

                    buttonRadius: isPressed ? 20 : 32
                    colBackground: rootContext.pillColor
                    colBackgroundHover: ColorUtils.mix(rootContext.pillColor, rootContext.pillContentColor, 0.9)
                    colRipple: ColorUtils.applyAlpha(rootContext.pillContentColor, 0.3)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 40
                        fill: 1
                        color: rootContext.pillContentColor
                        text: rootContext.playbackPaused ? "play_arrow" : "pause"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (rootContext.playbackPaused)
                            rootContext.sendCommand({"command": "resume"})
                        else
                            rootContext.sendCommand({"command": "pause"})
                    }
                }

                // Next Button
                RippleButton {
                    id: nextBtnContainer
                    property bool isPressed: down

                    implicitWidth: 64 + (isPressed ? 16 : (playBtnContainer.isPressed ? -10 : 0))
                    implicitHeight: 64

                    Behavior on implicitWidth {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }

                    buttonRadius: 32
                    colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 28
                        fill: 1
                        color: rootContext.contentColor
                        text: "skip_next"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: rootContext.sendCommand({"command": "next"})
                }
            
            // Closing brace for the centered RowLayout inside MainView's controls
            }
        } // Closing the Controls Item

        } // Closing the mainPlaybackView ColumnLayout
        
        // --- LYRICS VIEW ---
        ColumnLayout {
            id: lyricsPlaybackView
            anchors.fill: parent
            spacing: 16
            scale: root.inlineLyricsExpanded ? 1.0 : 1.08
            opacity: root.inlineLyricsExpanded ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { id: lyricsOpacityAnim; duration: 350; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { id: lyricsScaleAnim; duration: 450; easing.type: Easing.OutCubic } }

            LyricsComponents.LyricsView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                isResizing: root.isLayoutTransitioning

                showWindowControls: false
                experimentalMode: rootContext ? rootContext.musicSettingsExperimentalLyrics : false

                contentColor: rootContext.contentColor
                secondaryContentColor: rootContext.secondaryContentColor
                pillColor: rootContext.pillColor
                pillContentColor: rootContext.pillContentColor
                loaderColor: rootContext.loaderAccentColor

                // Use the Music app's own isolated lyrics pipeline.
                // No LyricsService dependency — zero conflict with other players.
                lyricsModel: rootContext.localLyricsModel
                lyricsCount: rootContext.localLyricsCount
                currentLine: rootContext.localLyricsCurrentLine
                lyricsLoaded: rootContext.localLyricsLoaded
                position: root.inlineLyricsPosition
                lyricsSource: rootContext.localLyricsSource
                activePlayer: null
                isPlaying: !rootContext.playbackPaused

                onSeekRequested: (time) => {
                    rootContext.sendCommand({ "command": "seek", "position": time })
                }
            }

            // Mini Bar
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                spacing: 16
                
                Item {
                    id: miniArtContainer
                    Layout.preferredHeight: 64
                    clip: true
                    
                    state: root.inlineLyricsExpanded ? "expanded" : "collapsed"
                    
                    states: [
                        State {
                            name: "expanded"
                            PropertyChanges { target: miniArtContainer; explicit: true; Layout.preferredWidth: 64 }
                            PropertyChanges { target: miniArtImage; explicit: true; opacity: 1.0 }
                        },
                        State {
                            name: "collapsed"
                            PropertyChanges { target: miniArtContainer; explicit: true; Layout.preferredWidth: 0 }
                            PropertyChanges { target: miniArtImage; explicit: true; opacity: 0.0 }
                        }
                    ]
                    
                    transitions: [
                        Transition {
                            from: "collapsed"
                            to: "expanded"
                            SequentialAnimation {
                                PauseAnimation { duration: 300 }
                                PropertyAction { target: miniArtContainer; property: "Layout.preferredWidth" }
                                NumberAnimation { target: miniArtImage; property: "opacity"; duration: 350; easing.type: Easing.InOutQuad }
                            }
                        },
                        Transition {
                            from: "expanded"
                            to: "collapsed"
                            SequentialAnimation {
                                PauseAnimation { duration: 400 }
                                ParallelAnimation {
                                    PropertyAction { target: miniArtContainer; property: "Layout.preferredWidth" }
                                    PropertyAction { target: miniArtImage; property: "opacity" }
                                }
                            }
                        }
                    ]

                    RoundedImage {
                        id: miniArtImage
                        width: 64
                        height: 64
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        source: rootContext.displayedArtFilePath || ""
                        fillMode: Image.PreserveAspectCrop
                        radius: 12
                        opacity: 0.0
                    }
                }
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: rootContext.currentTrack ? rootContext.currentTrack.title : "Not Playing"
                        font.pixelSize: 18
                        font.weight: 800
                        color: rootContext.contentColor
                        elide: Text.ElideRight
                    }
                    
                    Rectangle {
                        visible: rootContext.currentTrack && rootContext.currentTrack.quality !== ""
                        radius: 4
                        color: ColorUtils.applyAlpha(rootContext.contentColor, 0.15)
                        Layout.preferredWidth: miniQualityLabelView.implicitWidth + 8
                        Layout.preferredHeight: miniQualityLabelView.implicitHeight + 2
                        
                        StyledText {
                            id: miniQualityLabelView
                            anchors.centerIn: parent
                            text: rootContext.currentTrack ? rootContext.currentTrack.quality.toUpperCase() : ""
                            font.pixelSize: 8
                            font.weight: 900
                            font.letterSpacing: 0.5
                            color: rootContext.contentColor
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: rootContext.currentTrack ? rootContext.currentTrack.artist : ""
                        font.pixelSize: 14
                        font.weight: 500
                        color: rootContext.secondaryContentColor
                        elide: Text.ElideRight
                    }
                }
                
                WaveVisualizer {
                    id: mainWaveVisualizer
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 36
                    Layout.rightMargin: 8

                    opacity: root.inlineLyricsExpanded && rootContext.currentTrack ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 350 } }
                    visible: opacity > 0

                    style: "pills"
                    live: !rootContext.playbackPaused && !root.isLayoutTransitioning
                    
                    // Generate 5 sleek bars by picking distinct frequency bins
                    points: {
                        let src = rootContext.visualizerPoints;
                        if (!src || src.length === 0) return [];
                        let arr = [];
                        for (let i = 0; i < 5; i++) {
                            // Extract every third bin so they remain distinct
                            arr.push(src[1 + (i * 3)] || 0);
                        }
                        return arr;
                    }
                    maxVisualizerValue: 500
                    smoothing: 0 // Keep the points sharp and discrete for pills
                    color: rootContext.contentColor
                }
            }
        } // Closing Lyrics ColumnLayout

        } // Closing the Stack Item container

        // Secondary Controls
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            ButtonGroup {
                anchors.centerIn: parent
                spacing: 12
                
                // 1. Queue
                GroupButton {
                    baseWidth: 64
                    baseHeight: 48
                    buttonRadius: toggled ? 12 : 16
                    buttonRadiusPressed: 8
                    colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colBackgroundActive: ColorUtils.applyAlpha(rootContext.contentColor, 0.12)
                    colBackgroundToggled: rootContext.pillColor
                    colBackgroundToggledHover: rootContext.pillColor
                    colBackgroundToggledActive: rootContext.pillColor
                    toggled: root.queueExpanded
                    
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "queue_music"
                        iconSize: 22
                        color: root.queueExpanded ? rootContext.pillContentColor : rootContext.contentColor
                        opacity: root.queueExpanded ? 1.0 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    releaseAction: () => { root.queueExpanded = !root.queueExpanded }
                }

                // 2. Shuffle
                GroupButton {
                    baseWidth: 64
                    baseHeight: 48
                    buttonRadius: toggled ? 12 : 16
                    buttonRadiusPressed: 8
                    colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colBackgroundActive: ColorUtils.applyAlpha(rootContext.contentColor, 0.12)
                    colBackgroundToggled: rootContext.pillColor
                    colBackgroundToggledHover: rootContext.pillColor
                    colBackgroundToggledActive: rootContext.pillColor
                    toggled: rootContext.shuffleToggled
                    
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "shuffle"
                        iconSize: 22
                        color: rootContext.shuffleToggled ? rootContext.pillContentColor : rootContext.contentColor
                        opacity: rootContext.shuffleToggled ? 1.0 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    releaseAction: () => { 
                        rootContext.shuffleToggled = !rootContext.shuffleToggled
                        
                        if (rootContext.shuffleToggled && !rootContext.isQueueLoading && rootContext.queueList.count > 1) {
                            for (let i = 0; i < rootContext.queueList.count; i++) {
                                let randomIndex = Math.floor(Math.random() * rootContext.queueList.count);
                                rootContext.queueList.move(randomIndex, 0, 1);
                            }
                            
                            let newQueue = []
                            for (let i = 0; i < rootContext.queueList.count; i++) {
                                let item = rootContext.queueList.get(i)
                                newQueue.push({
                                    videoId: item.videoId,
                                    title: item.title,
                                    artist: item.artist,
                                    duration: item.duration,
                                    artUrl: item.artUrl
                                })
                            }
                            rootContext.sendCommand({"command": "sync_queue", "queue": newQueue})
                        }
                    }
                }

                // 3. Lyrics
                GroupButton {
                    baseWidth: 64
                    baseHeight: 48
                    buttonRadius: toggled ? 12 : 16
                    buttonRadiusPressed: 8
                    colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colBackgroundActive: ColorUtils.applyAlpha(rootContext.contentColor, 0.12)
                    colBackgroundToggled: rootContext.pillColor
                    colBackgroundToggledHover: rootContext.pillColor
                    colBackgroundToggledActive: rootContext.pillColor
                    toggled: root.inlineLyricsExpanded
                    
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "lyrics"
                        iconSize: 22
                        color: root.inlineLyricsExpanded ? rootContext.pillContentColor : rootContext.contentColor
                        opacity: root.inlineLyricsExpanded ? 1.0 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    releaseAction: () => { 
                        root.inlineLyricsExpanded = !root.inlineLyricsExpanded 
                        // Note: We deliberately do NOT call LyricsService.toggle() here anymore
                        // so we don't open the external, top-level LyricsWindow window layer!
                    }
                }

                // 4. Repeat
                GroupButton {
                    baseWidth: 64
                    baseHeight: 48
                    buttonRadius: toggled ? 12 : 16
                    buttonRadiusPressed: 8
                    colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                    colBackgroundActive: ColorUtils.applyAlpha(rootContext.contentColor, 0.12)
                    colBackgroundToggled: rootContext.pillColor
                    colBackgroundToggledHover: rootContext.pillColor
                    colBackgroundToggledActive: rootContext.pillColor
                    toggled: rootContext.repeatMode > 0
                    
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: rootContext.repeatMode === 2 ? "repeat_one" : "repeat"
                        iconSize: 22
                        color: rootContext.repeatMode > 0 ? rootContext.pillContentColor : rootContext.contentColor
                        opacity: rootContext.repeatMode > 0 ? 1.0 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    releaseAction: () => { 
                        rootContext.repeatMode = (rootContext.repeatMode + 1) % 3
                        rootContext.sendCommand({"command": "set_repeat", "mode": rootContext.repeatMode}) 
                    }
                }
            }
        }
    }
}

    // Catch clicks outside the panel to close it (Disabled)
    // removed MouseArea here so queue doesn't close on outside clicks

    // Floating Queue Panel (Slides from right)
    Item {
        id: queuePanel
        z: 100
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.min(420, parent.width * 0.8)
        
        transform: Translate {
            id: queuePanelTransform
            x: root.queueExpanded ? 0 : queuePanel.width + 50
            Behavior on x { NumberAnimation { id: queueXAnim; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 24
            
            // Catch clicks inside the panel so they don't fall through and close it
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                scrollGestureEnabled: false
            }
            
            Rectangle {
                anchors.fill: parent
                radius: 32
                color: rootContext.backgroundColor
                
                layer.enabled: !root.isLayoutTransitioning
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Appearance.colors.colShadow
                    shadowBlur: 2.0
                    shadowHorizontalOffset: -4
                    shadowVerticalOffset: 4
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: "Up Next"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.bold: true
                        color: rootContext.contentColor
                        Layout.fillWidth: true
                    }
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: 20
                        colBackground: ColorUtils.applyAlpha(rootContext.contentColor, 0.1)
                        colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                        colRipple: rootContext.contentColor
                        horizontalPadding: 0
                        verticalPadding: 0

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 24
                            color: rootContext.contentColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: root.queueExpanded = false
                    }
                }

                // Elevated container for songs list
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 20
                    color: rootContext.surfaceColor

                    ListView {
                        id: queueListView
                        anchors.fill: parent
                        anchors.margins: 8
                        implicitHeight: parent.height - 16
                        clip: true
                        spacing: 4
                        interactive: true
                        acceptedButtons: Qt.NoButton

                    model: rootContext.queueList

                    move: Transition { NumberAnimation { properties: "x,y"; duration: 600; easing.type: Easing.OutQuart } }
                    displaced: Transition { NumberAnimation { properties: "x,y"; duration: 600; easing.type: Easing.OutQuart } }

                    property int draggedIndex: -1

                    delegate: Item {
                        id: delegateRoot
                        width: ListView.view.width
                        height: 72
                        z: dragHandle.drag.active ? 100 : 1

                        // The content that visually gets dragged
                        Rectangle {
                            id: contentRect
                            width: delegateRoot.width
                            height: delegateRoot.height
                            anchors.horizontalCenter: parent.horizontalCenter
                            radius: 16
                            
                            // Transparent normally, frosted glass when dragging, subtle tint on hover
                            color: dragHandle.drag.active 
                                 ? rootContext.pillColor
                                 : clickArea.containsMouse 
                                    ? ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                                    : ColorUtils.applyAlpha(rootContext.contentColor, 0.0)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            
                            // Lift effect when dragging
                            scale: dragHandle.drag.active ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
                            
                            opacity: dragHandle.drag.active ? 0.95 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            // Shadow when lifted
                            layer.enabled: dragHandle.drag.active
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Appearance.colors.colShadow
                                shadowBlur: 1.5
                                shadowVerticalOffset: 6
                                shadowHorizontalOffset: 0
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 12

                                Item {
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 48

                                    RoundedImage {
                                        anchors.fill: parent
                                        radius: 12
                                        source: model.artUrl || ""
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        cache: true
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.title || ""
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.artist || ""
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                    }
                                }
                                // Duration / Drag handle (crossfade on hover)
                                Item {
                                    Layout.preferredWidth: 40
                                    Layout.preferredHeight: 48

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: model.duration || ""
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        opacity: (clickArea.containsMouse || dragHandle.drag.active) ? 0.0 : 1.0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "drag_indicator"
                                        iconSize: 22
                                        color: rootContext.secondaryContentColor
                                        opacity: (clickArea.containsMouse || dragHandle.drag.active) ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 200 } }
                                        
                                        scale: dragHandle.drag.active ? 1.2 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }

                                    MouseArea {
                                        id: dragHandle
                                        anchors.fill: parent
                                        anchors.margins: -8  // Expand hit area slightly for easier grab
                                        scrollGestureEnabled: false
                                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                                        drag.target: contentRect
                                        drag.axis: Drag.YAxis

                                        property int startIndex: -1

                                        onPressed: {
                                            startIndex = model.index
                                            queueListView.interactive = false
                                        }

                                        onPositionChanged: {
                                            if (!drag.active) return
                                            let itemH = delegateRoot.height + queueListView.spacing
                                            let centerY = delegateRoot.y + contentRect.y + contentRect.height / 2
                                            let targetIdx = Math.max(0, Math.min(
                                                rootContext.queueList.count - 1,
                                                Math.floor(centerY / itemH)
                                            ))
                                            let currentIdx = model.index
                                            if (targetIdx !== currentIdx) {
                                                rootContext.queueList.move(currentIdx, targetIdx, 1)
                                            }
                                        }

                                        onReleased: {
                                            contentRect.y = 0
                                            queueListView.interactive = true
                                            let finalIndex = model.index
                                            if (startIndex !== finalIndex && startIndex >= 0) {
                                                rootContext.sendCommand({
                                                    "command": "reorder_queue",
                                                    "from": startIndex,
                                                    "to": finalIndex
                                                })
                                            }
                                            startIndex = -1
                                        }
                                    }
                                }
                            }

                            // Click to play
                            MouseArea {
                                id: clickArea
                                anchors.fill: parent
                                hoverEnabled: true
                                scrollGestureEnabled: false
                                z: -1

                                onClicked: {
                                    let clickedIndex = model.index
                                    
                                    // Build queue from tracks AFTER the clicked one
                                    let remainingQueue = []
                                    for (let i = clickedIndex + 1; i < rootContext.queueList.count; i++) {
                                        let t = rootContext.queueList.get(i)
                                        remainingQueue.push({
                                            videoId: t.videoId,
                                            title: t.title,
                                            artist: t.artist,
                                            artUrl: t.artUrl,
                                            duration: t.duration || ""
                                        })
                                    }
                                    
                                    // Play the clicked track with the trimmed queue
                                    rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl, remainingQueue, model.artistId, model.albumId)
                                    root.queueExpanded = false
                                }
                            }
                        }
                    }
                    

                    // Fallback state if nothing is queued (like right at launch before playback starts)
                    StyledText {
                        anchors.centerIn: parent
                        visible: queueListView.count === 0 && !rootContext.isQueueLoading
                        text: "Queue is empty\nPlay a song to start Radio mode!"
                        color: rootContext.secondaryContentColor
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                }
            }
        }
    }
}
