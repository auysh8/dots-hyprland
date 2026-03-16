import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Qt5Compat.GraphicalEffects
import "../../lyricsLayer/components" as LyricsComponents

Item {
    id: root

    property var rootContext
    property bool navRailExpanded: false
    
    // Smooth visibility transitions
    property bool show: rootContext.currentView === "player"
    property bool queueExpanded: false
    property bool inlineLyricsExpanded: false
    
    property real currentRadius: show ? 32 : 20

    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottomMargin: show ? 0 : 24
    anchors.leftMargin: show ? 0 : ((navRailExpanded ? 150 : 80) + 32)
    anchors.rightMargin: show ? 0 : 24

    height: show ? parent.height : 80

    Behavior on height { NumberAnimation { id: hAnim; duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
    Behavior on anchors.bottomMargin { NumberAnimation { id: bAnim; duration: 400; easing.type: Easing.OutCubic } }
    Behavior on anchors.leftMargin { NumberAnimation { id: lAnim; duration: 450; easing.type: Easing.OutCubic } }
    Behavior on anchors.rightMargin { NumberAnimation { id: rAnim; duration: 450; easing.type: Easing.OutCubic } }
    Behavior on currentRadius { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

    visible: show || hAnim.running || bAnim.running || lAnim.running || rAnim.running

    // Elements appear instantly on open, disappear immediately on close (halfway through collapse)
    property bool elementsVisible: false
    onShowChanged: {
        if (show) {
            root.elementsVisible = true
        } else {
            root.elementsVisible = false
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.elementsVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

        Image {
            id: bgArt
            anchors.fill: parent
            source: rootContext.displayedArtFilePath || ""
            fillMode: Image.PreserveAspectCrop
            visible: false
        }

        Rectangle {
            id: bgMask
            anchors.fill: parent
            radius: root.currentRadius
            visible: false
            color: rootContext.surfaceColor
        }

        OpacityMask {
            anchors.fill: parent
            source: bgArt
            maskSource: bgMask
        }

        // Overlay to guarantee contrast
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
            opacity: 0.7
            radius: root.currentRadius
        }
        
        // Gradient overlay utilizing quantized colors
        Rectangle {
            anchors.fill: parent
            radius: root.currentRadius
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.transparentize(rootContext.pillColor, 0.2) }
                GradientStop { position: 0.6; color: ColorUtils.transparentize(rootContext.backgroundColor, 0.4) }
                GradientStop { position: 1.0; color: rootContext.backgroundColor }
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.elementsVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        transform: Translate {
            y: root.elementsVisible ? 0 : 30
            Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        }

        // Collapse button (Top left/right)
        RippleButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        implicitWidth: 48
        implicitHeight: 48
        buttonRadius: 24
        
        colBackground: ColorUtils.transparentize(rootContext.contentColor, 0.9)
        colBackgroundHover: ColorUtils.transparentize(rootContext.contentColor, 0.8)
        colRipple: rootContext.contentColor
        
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "expand_more"
            iconSize: 28
            color: rootContext.contentColor
        }
        
        onClicked: {
            rootContext.currentView = rootContext.previousView || "home"
        }
        z: 10
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
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
                Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

        // Large Cover Art
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            property string _trackId: rootContext.currentTrack ? rootContext.currentTrack.videoId : ""
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
                width: Math.min(parent.width, parent.height) * 1.0
                height: width
                anchors.centerIn: parent
                radius: 32
                color: ColorUtils.transparentize(rootContext.pillColor, 0.5)

                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Appearance.colors.colShadow
                    shadowBlur: 2.0
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 12
                }

                RoundedImage {
                    anchors.fill: parent
                    source: rootContext.displayedArtFilePath || ""
                    fillMode: Image.PreserveAspectCrop
                    visible: rootContext.displayedArtFilePath !== ""
                    radius: 32
                }
            }
        }

        // Track Info
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 400
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
                    NumberAnimation { target: trackInfoCol; property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutCubic }
                    NumberAnimation { target: trackInfoCol; property: "scale"; from: 0.95; to: 1.0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
                }
            }
            
            ColumnLayout {
                id: trackInfoCol
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
            
            Item {
                Layout.alignment: Qt.AlignVCenter
                width: 32
                height: 32
                visible: rootContext.currentTrack !== null
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: rootContext.currentTrackLiked ? "favorite" : "favorite_border"
                    iconSize: 28
                    color: rootContext.currentTrackLiked ? Appearance.colors.colError : rootContext.contentColor
                    opacity: heartArea.containsMouse ? 1.0 : (rootContext.currentTrackLiked ? 1.0 : 0.6)
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                
                MouseArea {
                    id: heartArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: rootContext.toggleCurrentTrackLike()
                }
            }
        }

        // Timeline Slider
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 400
            spacing: 8

            StyledSlider {
                id: trackSlider
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                
                configuration: (!rootContext.isTrackLoading && !rootContext.playbackPaused) ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
                highlightColor: rootContext.contentColor
                trackColor: ColorUtils.transparentize(rootContext.contentColor, 0.7)
                handleColor: rootContext.contentColor
                
                value: rootContext.trackDurationSec > 0 ? rootContext.trackPositionSec / rootContext.trackDurationSec : 0
                Behavior on value { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }

                enabled: rootContext.trackDurationSec > 0
                onMoved: {
                    if (rootContext.trackDurationSec > 0) {
                        let seekPos = value * rootContext.trackDurationSec
                        rootContext.sendCommand({"command": "seek", "position": seekPos})
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                
                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(rootContext.trackPositionSec)
                    font.pixelSize: 14
                    color: rootContext.secondaryContentColor
                }
                
                Item { Layout.fillWidth: true }
                
                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(rootContext.trackDurationSec)
                    font.pixelSize: 14
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
                Item {
                    id: prevBtnContainer
                    property bool isPressed: prevArea.pressed
                    
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
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: prevArea.containsMouse 
                            ? ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                            : ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 28
                            fill: 1
                            color: rootContext.contentColor
                            text: "skip_previous"
                        }
                    }
                    
                    MouseArea {
                        id: prevArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootContext.sendCommand({"command": "previous"})
                    }
                }

                // Play/Pause Button
                Item {
                    id: playBtnContainer
                    property bool isPressed: playArea.pressed
                    
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
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: playBtnContainer.isPressed ? 20 : 32
                        color: rootContext.pillColor
                        
                        Behavior on radius { NumberAnimation { duration: 200 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 40
                            fill: 1
                            color: rootContext.pillContentColor
                            text: rootContext.playbackPaused ? "play_arrow" : "pause"
                        }
                    }
                    
                    MouseArea {
                        id: playArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (rootContext.playbackPaused)
                                rootContext.sendCommand({"command": "resume"})
                            else
                                rootContext.sendCommand({"command": "pause"})
                        }
                    }
                }

                // Next Button
                Item {
                    id: nextBtnContainer
                    property bool isPressed: nextArea.pressed
                    
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
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: nextArea.containsMouse 
                            ? ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                            : ColorUtils.applyAlpha(rootContext.contentColor, 0.04)
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                        
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: 28
                            fill: 1
                            color: rootContext.contentColor
                            text: "skip_next"
                        }
                    }
                    
                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rootContext.sendCommand({"command": "next"})
                    }
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
            Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

            LyricsComponents.LyricsView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                
                showWindowControls: false
                
                contentColor: rootContext.contentColor
                secondaryContentColor: rootContext.secondaryContentColor
                pillColor: rootContext.pillColor
                pillContentColor: rootContext.pillContentColor
                
                lyricsModel: LyricsService.model
                lyricsCount: LyricsService.count
                currentLine: LyricsService.currentLine
                lyricsLoaded: LyricsService.loaded
                position: LyricsService.position
                lyricsSource: LyricsService.sourceName
                activePlayer: LyricsService.activePlayer
                isPlaying: !rootContext.playbackPaused
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
                                ParallelAnimation {
                                    NumberAnimation { target: miniArtContainer; property: "Layout.preferredWidth"; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                                    NumberAnimation { target: miniArtImage; property: "opacity"; duration: 350; easing.type: Easing.InOutQuad }
                                }
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
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 36
                    Layout.rightMargin: 8
                    
                    opacity: root.inlineLyricsExpanded && rootContext.currentTrack ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 350 } }
                    visible: opacity > 0
                    
                    style: "pills"
                    live: !rootContext.playbackPaused
                    
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
                    maxVisualizerValue: 1000
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
            x: root.queueExpanded ? 0 : queuePanel.width + 50
            Behavior on x { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        }

        Item {
            anchors.fill: parent
            anchors.margins: 24
            
            // Catch clicks inside the panel so they don't fall through and close it
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true    
            }
            
            Rectangle {
                anchors.fill: parent
                radius: 32
                color: ColorUtils.mix(Appearance.m3colors.m3surfaceContainerLowest, rootContext.pillColor, 0.15)
                
                layer.enabled: true
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
                        colBackground: rootContext.pillColor
                        colBackgroundHover: rootContext.pillColor
                        colRipple: rootContext.contentColor
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "close"
                            iconSize: 24
                            color: rootContext.pillContentColor
                        }
                        onClicked: root.queueExpanded = false
                    }
                }

                // Elevated container for songs list
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 20
                    color: ColorUtils.transparentize(rootContext.pillColor, 0.9)

                    ListView {
                        id: queueListView
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        spacing: 4
                    
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
                                    rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl, remainingQueue)
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
