pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        // Wallpaper
        property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
        property real preferredWallpaperScale: Config.options.background.parallax.workspaceZoom
        property real effectiveWallpaperScale: 1 // Some reasonable init value, to be updated
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
        property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.zoomScaleReady = false;
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Zoom scale calculation state
        property bool zoomScaleReady: true

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    if (width <= screenWidth || height <= screenHeight) {
                        // Undersized/perfectly sized wallpapers
                        bgRoot.effectiveWallpaperScale = Math.max(screenWidth / width, screenHeight / height);
                    } else {
                        // Oversized = can be zoomed for parallax, yay
                        bgRoot.effectiveWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                    }
                    bgRoot.zoomScaleReady = true;
                }
            }
        }

        Item {
            id: wallpaperContainer
            anchors.fill: parent
            clip: true

            // Animation state
            property string oldSource: ""
            property string newSource: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
            property bool isAnimating: false
            property bool pendingAnimation: false
            property real revealProgress: 1.0

            // Wallpaper positioning properties
            property int chunkSize: Config?.options.bar.workspaces.shown ?? 10
            property int lower: Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
            property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
            property int range: upper - lower
            property real valueX: {
                let result = 0.5;
                if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                    result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                }
                if (Config.options.background.parallax.enableSidebar) {
                    result += (0.15 * GlobalStates.sidebarRightOpen - 0.15 * GlobalStates.sidebarLeftOpen);
                }
                return result;
            }
            property real valueY: {
                let result = 0.5;
                if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                    result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                }
                return result;
            }
            property real effectiveValueX: Math.max(0, Math.min(1, valueX))
            property real effectiveValueY: Math.max(0, Math.min(1, valueY))
            property real wpX: -(bgRoot.movableXSpace) - (effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
            property real wpY: -(bgRoot.movableYSpace) - (effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
            property real wpW: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
            property real wpH: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale

            // Frozen position/dimensions for old wallpaper (captured at transition start)
            property real frozenX: 0
            property real frozenY: 0
            property real frozenW: 0
            property real frozenH: 0
            property real frozenNewX: 0
            property real frozenNewY: 0

            property bool oldImageReady: true
            property bool imageReady: false

            onNewSourceChanged: {
                if (oldSource !== "" && oldSource !== newSource && newSource !== "") {
                    // Freeze current position/dimensions for old wallpaper
                    frozenX = wpX;
                    frozenY = wpY;
                    frozenW = wpW;
                    frozenH = wpH;

                    frozenNewX = wpX;
                    frozenNewY = wpY; 
                    
                    // Immediately mark as pending and set old source.
                    // This ensures the old wallpaper (which is on the top layer)
                    // stays visible while the new image loads underneath.
                    pendingAnimation = true;
                    fadeProgress = 0;
                    oldWallpaper.source = oldSource;
                    
                    if (oldWallpaper.status === Image.Ready) {
                        oldImageReady = true;
                        startTransition();
                    } else {
                        oldImageReady = false;
                    }
                } else {
                    // First load or same source
                    pendingAnimation = false;
                    isAnimating = false;
                    imageReady = (wallpaper.status === Image.Ready);
                }
                oldSource = newSource;
            }

            // Function to start the actual fade transition
            function startTransition() {
                // Already set pendingAnimation in onNewSourceChanged
                imageReady = (wallpaper.status === Image.Ready);
                revealProgress = 0;
                fadeProgress = 0;
                fadeAnimation.restart();
            }

            // Fade animation progress (0 = old wallpaper visible, 1 = black)
            property real fadeProgress: 0

            // Function to try starting reveal animation (checks both conditions)
            function tryStartReveal() {
                const bothImagesReady = imageReady && (oldImageReady || oldWallpaper.status === Image.Ready);
                if (pendingAnimation && bothImagesReady && bgRoot.zoomScaleReady && fadeProgress >= 1) {
                    // Capture the CURRENT position right before reveal starts
                    // This ensures no shift when animation ends
                    frozenNewX = wpX;
                    frozenNewY = wpY;
                    isAnimating = true;
                    revealAnimation.restart();
                }
            }

            // Function called when new image is ready
            function onImageLoaded() {
                imageReady = true;
                tryStartReveal();
            }

            // Function called when old image is ready
            function onOldImageLoaded() {
                oldImageReady = true;
                if (pendingAnimation && fadeAnimation.progress === 0 && !fadeAnimation.running) {
                    startTransition();
                }
                tryStartReveal();
            }

            // Watch for zoom scale ready changes
            Connections {
                target: bgRoot
                function onZoomScaleReadyChanged() {
                    if (bgRoot.zoomScaleReady) {
                        wallpaperContainer.tryStartReveal();
                    }
                }
            }

            // Fade to black animation
            NumberAnimation {
                id: fadeAnimation
                target: wallpaperContainer
                property: "fadeProgress"
                from: 0
                to: 1
                duration: 800
                easing.type: Easing.OutCubic
                onFinished: {
                    wallpaperContainer.tryStartReveal();
                }
            }

            // Circle reveal animation
            NumberAnimation {
                id: revealAnimation
                target: wallpaperContainer
                property: "revealProgress"
                from: 0
                to: 1
                duration: 1600
                easing.type: Easing.OutQuint
                onFinished: {
                    // Check if the main wallpaper is ready before completing
                    if (wallpaper.status === Image.Ready) {
                        wallpaperContainer.isAnimating = false;
                        wallpaperContainer.pendingAnimation = false;
                    }
                    // If not ready, the onStatusChanged handler will complete the transition
                }
            }

            // Helper function to complete transition when image is ready
            function completeTransitionIfReady() {
                if (revealAnimation.running === false && revealProgress >= 1 && wallpaper.status === Image.Ready) {
                    isAnimating = false;
                    pendingAnimation = false;
                }
            }

            // --- LAYER ORDER: BOTTOM TO TOP ---

            // 1. The main wallpaper (at the bottom)
            Image {
                id: wallpaper
                x: wallpaperContainer.isAnimating ? wallpaperContainer.frozenNewX : wallpaperContainer.wpX
                y: wallpaperContainer.isAnimating ? wallpaperContainer.frozenNewY : wallpaperContainer.wpY
                width: wallpaperContainer.wpW
                height: wallpaperContainer.wpH
                source: wallpaperContainer.newSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                cache: true
                // Visible only when NOT animating (static state)
                // Visible only when NOT animating (static state)
                visible: !blurLoader.active
                sourceSize {
                    width: bgRoot.screen.width * bgRoot.monitor.scale
                    height: bgRoot.screen.height * bgRoot.monitor.scale
                }
                
                onStatusChanged: {
                    if (status === Image.Ready) {
                        wallpaperContainer.onImageLoaded();
                        // Also try to complete transition if reveal animation finished waiting for this
                        wallpaperContainer.completeTransitionIfReady();
                    }
                }
                
                Behavior on x {
                    enabled: !wallpaperContainer.isAnimating && !wallpaperContainer.pendingAnimation
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: !wallpaperContainer.isAnimating && !wallpaperContainer.pendingAnimation
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // 2. Black background (transition base)
            Rectangle {
                id: fadeToBlack
                anchors.fill: parent
                color: "black"
                visible: wallpaperContainer.pendingAnimation || wallpaperContainer.isAnimating
            }

            // 3. New wallpaper fade in (above black)
            Item {
                id: newWallpaperClip
                anchors.fill: parent
                visible: wallpaperContainer.isAnimating && !blurLoader.active
                opacity: wallpaperContainer.revealProgress

                Image {
                    id: maskedWallpaper
                    x: wallpaperContainer.frozenNewX
                    y: wallpaperContainer.frozenNewY
                    width: wallpaperContainer.wpW
                    height: wallpaperContainer.wpH
                    source: wallpaperContainer.newSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    retainWhileLoading: true
                    cache: true
                    sourceSize {
                        width: bgRoot.screen.width * bgRoot.monitor.scale
                        height: bgRoot.screen.height * bgRoot.monitor.scale
                    }
                }
            }

            // 4. Old wallpaper fade out (AT THE VERY TOP)
            Image {
                id: oldWallpaper
                visible: wallpaperContainer.pendingAnimation && !wallpaperContainer.isAnimating && !blurLoader.active
                opacity: 1 - wallpaperContainer.fadeProgress
                scale: 1 - (wallpaperContainer.fadeProgress * 0.08)
                transformOrigin: Item.Center
                x: wallpaperContainer.frozenX
                y: wallpaperContainer.frozenY
                width: wallpaperContainer.frozenW
                height: wallpaperContainer.frozenH
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                retainWhileLoading: true
                cache: true
                sourceSize {
                    width: bgRoot.screen.width * bgRoot.monitor.scale
                    height: bgRoot.screen.height * bgRoot.monitor.scale
                }

                onStatusChanged: {
                    if (status === Image.Ready) {
                        wallpaperContainer.onOldImageLoaded();
                    }
                }
            }

            // Add maxRadius property to wallpaperContainer
            property real maxRadius: Math.sqrt(Math.pow(bgRoot.screen.width, 2) + Math.pow(bgRoot.screen.height, 2)) / 2 * 1.2

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: wallpaper
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: wallpaper
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: radius * 2 + 1

                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                opacity: (wallpaperContainer.pendingAnimation || wallpaperContainer.isAnimating) ? 0 : 1
                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                        easing.type: Easing.OutCubic
                    }
                }
                anchors {
                    left: wallpaper.left
                    right: wallpaper.right
                    top: wallpaper.top
                    bottom: wallpaper.bottom
                    horizontalCenter: undefined
                    verticalCenter: undefined
                    leftMargin: {
                        const xOnWallpaper = bgRoot.movableXSpace;
                        const extraMove = (wallpaperContainer.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1);
                        return xOnWallpaper - extraMove;
                    }
                    topMargin: {
                        const yOnWallpaper = bgRoot.movableYSpace;
                        const extraMove = (wallpaperContainer.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1);
                        return yOnWallpaper - extraMove;
                    }
                    Behavior on leftMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on topMargin {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
                width: wallpaper.width
                height: wallpaper.height
                states: State {
                    name: "centered"
                    when: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered
                    PropertyChanges {
                        target: widgetCanvas
                        width: parent.width
                        height: parent.height
                    }
                    AnchorChanges {
                        target: widgetCanvas
                        anchors {
                            left: undefined
                            right: undefined
                            top: undefined
                            bottom: undefined
                            horizontalCenter: parent.horizontalCenter
                            verticalCenter: parent.verticalCenter
                        }
                    }
                }
                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                        wallpaperScale: bgRoot.effectiveWallpaperScale
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }

            }
        }
    }
}
