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
import qs.modules.ii.background.widgets.media
import qs.modules.ii.background.widgets.images
import qs.modules.ii.background.widgets.resources
import qs.modules.ii.background.widgets.visualizer
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.worldclock
import qs.modules.ii.background.widgets.usercard
import qs.modules.ii.background.widgets.notes
import qs.modules.ii.background.widgets.todo
import qs.modules.ii.background.widgets.timers

Variants {
    id: root
    model: Quickshell.screens

    function getShapeFromName(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie7Sided
        }
    }

    function getColorFromName(name) {
        switch (name) {
            case "primary":            return Appearance.colors.colPrimary
            case "secondary":          return Appearance.colors.colSecondary
            case "tertiary":           return Appearance.colors.colTertiary
            case "primaryContainer":   return Appearance.colors.colPrimaryContainer
            case "secondaryContainer": return Appearance.colors.colSecondaryContainer
            case "tertiaryContainer":  return Appearance.colors.colTertiaryContainer
            case "layer0":             return Appearance.colors.colLayer0
            case "layer1":             return Appearance.colors.colLayer1
            default:                  return Appearance.colors.colPrimaryContainer
        }
    }

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Centered wallpaper
        property bool centeredWallpaperEnabled: (Config.options.background.centeredWallpaper ?? false) && (!(Config.options.background.centeredWallpaperOnlyWhenLocked ?? false) || GlobalStates.screenLocked)
        property int centeredWallpaperShape: root.getShapeFromName(Config.options.background.centeredWallpaperShape ?? "Cookie7Sided")
        property int centeredWallpaperSize: Config.options.background.centeredWallpaperSize ?? 400
        property color centeredWallpaperColor: root.getColorFromName(Config.options.background.centeredWallpaperColor ?? "primaryContainer")
        readonly property bool centeredWallpaperFaceTracking: Config.options.background.centeredWallpaperFaceTracking ?? true
        property real focalX: 0.5
        property real focalY: 0.5
        property bool hasSubject: false
        property string focalType: "center"

        readonly property real splitFraction: {
            switch (Config.options.background.splitRatio ?? "100") {
                case "25": return 0.28
                case "50": return 0.54
                default:   return 1.0
            }
        }
        readonly property bool overviewBlurActive: (Config.options.overview?.style === "niri" && GlobalStates.overviewOpen && Config.options.overview?.enable) ?? false
        readonly property bool userBlurActive: (Config.options.background.showBlur ?? false) && !bgRoot.wallpaperIsVideo
        readonly property bool blurFullScreen: bgRoot.overviewBlurActive || bgRoot.splitFraction >= 1.0

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10
        property int totalWorkspaces: Math.ceil(lastWorkspaceId / workspaceChunkSize) * workspaceChunkSize
        // Wallpaper
        property string effectiveWallpaperPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall;
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath;
        }
        property bool wallpaperIsVideo: bgRoot.effectiveWallpaperPath.endsWith(".mp4") || bgRoot.effectiveWallpaperPath.endsWith(".webm") || bgRoot.effectiveWallpaperPath.endsWith(".mkv") || bgRoot.effectiveWallpaperPath.endsWith(".avi") || bgRoot.effectiveWallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : bgRoot.effectiveWallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real parallaxRation: Config.options.background.parallax.workspaceZoom
        readonly property bool workspaceParallaxEnabled: Config.options.background.parallax.enableWorkspace
        readonly property bool sidebarParallaxEnabled: Config.options.background.parallax.enableSidebar
        readonly property bool backgroundParallaxEnabled: workspaceParallaxEnabled || sidebarParallaxEnabled
        readonly property real minimumParallaxRatio: 1.07
        readonly property real effectiveParallaxRatio: backgroundParallaxEnabled ? Math.max(parallaxRation, minimumParallaxRatio) : parallaxRation
        // Wallpaper item is always sized as screen × parallax ratio, regardless of image pixel dimensions.
        // fillMode: PreserveAspectCrop handles covering any aspect ratio — no magick identify needed.
        property real scaledWallpaperWidth: screen.width * effectiveParallaxRatio
        property real scaledWallpaperHeight: screen.height * effectiveParallaxRatio
        property real parallaxTotalPixelsX: Math.max(0, scaledWallpaperWidth - screen.width)
        property real parallaxTotalPixelsY: Math.max(0, scaledWallpaperHeight - screen.height)
        // verticalParallax derived from the loaded image's intrinsic size (set in wallpaper.onStatusChanged)
        property bool wallpaperIsPortrait: false
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperIsPortrait) || Config.options.background.parallax.vertical
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
        WlrLayershell.namespace: "quickshell:background"
        WlrLayershell.keyboardFocus: GlobalStates.desktopWidgetKeyboardFocus
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
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

        property string currentWallpaperSource: Config.options.background.wallpaperPath
        property string previousWallpaperSource: Config.options.background.wallpaperPath
        property real transitionProgress: 1.0
        property var shaderList: ["circlePit", "circleSelect", "magic", "Doom", "Peel", "transition", "pixelate", "stripes", "crt", "dissolve", "glitch", "ripple", "shatter"]
        property string currentShader: "magic"
        property string wallpaperAnimation: Config.options.background.wallpaperAnimation ?? "random"

        Component.onCompleted: {
            // Publish screen dimensions to Wallpapers service for crop cache generation
            Wallpapers.screenWidth = bgRoot.screen.width
            Wallpapers.screenHeight = bgRoot.screen.height
            previousWallpaper.source = ""
            // wallpaper.source is driven by _originalPath binding (bgRoot.wallpaperPath)
            bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
            bgRoot.previousWallpaperSource = ""
            bgRoot.transitionProgress = 1.0
            if (bgRoot.wallpaperAnimation !== "") {
                bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                    ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    : bgRoot.wallpaperAnimation
            }
            bgRoot.updateFocalPoint()
        }

        function updateFocalPoint() {
            if (!bgRoot.centeredWallpaperFaceTracking || bgRoot.wallpaperPath.length === 0 || bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo) {
                bgRoot.focalX = 0.5
                bgRoot.focalY = 0.5
                bgRoot.hasSubject = false
                bgRoot.focalType = "center"
                return
            }
            detectFocalPointProc.imagePath = bgRoot.wallpaperPath
            detectFocalPointProc.running = false
            detectFocalPointProc.running = true
        }

        onWallpaperPathChanged: {
            bgRoot.updateFocalPoint()
            if (wallpaperSafetyTriggered) {
                previousWallpaper.source = ""
                // wallpaper.source is driven by _originalPath binding — safety path handled by _originalPath returning ""
                bgRoot.transitionProgress = 1.0
                return
            }
            if (bgRoot.wallpaperAnimation === "") {
                // wallpaper.source auto-updates via _originalPath → bgRoot.wallpaperPath binding
                bgRoot.currentWallpaperSource = wallpaperPath
                return
            }

            previousWallpaper.source = bgRoot.currentWallpaperSource
            // wallpaper.source auto-updates via _originalPath → bgRoot.wallpaperPath binding
            bgRoot.currentWallpaperSource = wallpaperPath
            if (bgRoot.wallpaperAnimation === "random") {
                bgRoot.currentShader = bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
            } else {
                bgRoot.currentShader = bgRoot.wallpaperAnimation
            }
            bgRoot.transitionProgress = 0.0
        }

        Process {
            id: detectFocalPointProc
            property string imagePath: ""
            command: [Quickshell.shellPath("scripts/images/detect-focal-point-venv.sh"), imagePath]
            stdout: StdioCollector {
                id: focalPointCollector
                onStreamFinished: {
                    const output = focalPointCollector.text ? focalPointCollector.text.trim() : ""
                    if (!output || output.length === 0) return
                    try {
                        const res = JSON.parse(output)
                        if (res.has_subject) {
                            bgRoot.focalX = res.focal_x ?? 0.5
                            bgRoot.focalY = res.focal_y ?? 0.5
                            bgRoot.hasSubject = true
                            bgRoot.focalType = res.focal_type ?? "subject"
                        } else {
                            bgRoot.focalX = 0.5
                            bgRoot.focalY = 0.5
                            bgRoot.hasSubject = false
                            bgRoot.focalType = "center"
                        }
                    } catch (e) {
                        bgRoot.focalX = 0.5
                        bgRoot.focalY = 0.5
                        bgRoot.hasSubject = false
                        bgRoot.focalType = "center"
                    }
                }
            }
        }

        NumberAnimation {
            id: transitionAnim
            target: bgRoot
            property: "transitionProgress"
            from: 0.0
            to: 1.0
            duration: 1200
            easing.type: Easing.InOutCubic
            onFinished: {
                previousWallpaper.source = ""
                bgRoot.previousWallpaperSource = ""
                bgRoot.transitionProgress = 1.0
            }
        }

        Timer {
            id: wallpaperChangeTimer
            interval: (Config.options && Config.options.wallpaperSelector && Config.options.wallpaperSelector.changeInterval) ? Config.options.wallpaperSelector.changeInterval : 0
            running: interval > 0
            repeat: true
            onTriggered: {
                if (Wallpapers.folderModel.count > 0) {
                    Wallpapers.randomFromCurrentFolder()
                }
            }
        }

        Item {
            anchors.fill: parent

            Image {
                id: previousWallpaper
                anchors.fill: wallpaper
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: false
                layer.enabled: true
                visible: !blurLoader.active && !bgRoot.centeredWallpaperEnabled && previousWallpaper.source != "" && (bgRoot.wallpaperAnimation !== "" && bgRoot.transitionProgress < 1.0)
                opacity: (status === Image.Ready) ? 1 : 0
            }

            // Wallpaper
            StyledImage {
                id: wallpaper
                visible: opacity > 0 && !blurLoader.active && !bgRoot.centeredWallpaperEnabled
                    && (bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0)
                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                cache: true
                smooth: true
                asynchronous: true
                onStatusChanged: {
                    if (status === Image.Ready) {
                        // Update portrait detection for vertical parallax using QML's intrinsic image size
                        bgRoot.wallpaperIsPortrait = (implicitHeight > implicitWidth)
                        if (bgRoot.transitionProgress === 0.0) {
                            transitionAnim.restart()
                        }
                    } else if (status === Image.Error && source === _cropPath && _originalPath.length > 0) {
                        // Crop not generated yet — fall back to original
                        source = _originalPath
                    }
                }

                property int workspaceIndex: (bgRoot.monitor.activeWorkspace?.id ?? 1) - 1
                property real middleFraction: 0.5
                property real fraction: {
                    // 0 - start of the picture
                    // 1 - end of the picture
                    if (bgRoot.totalWorkspaces <= 1) {
                        return middleFraction;
                    }
                    return Math.max(0, Math.min(1, workspaceIndex / (bgRoot.totalWorkspaces - 1)));
                }

                property real usedFractionX: {
                    let usedFraction = middleFraction;
                    if (bgRoot.workspaceParallaxEnabled && !bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    if (bgRoot.sidebarParallaxEnabled) {
                        let sidebarFraction = bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2;
                        usedFraction += (sidebarFraction * GlobalStates.sidebarRightOpen - sidebarFraction * GlobalStates.sidebarLeftOpen);
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }
                property real usedFractionY: {
                    let usedFraction = middleFraction;
                    if (bgRoot.workspaceParallaxEnabled && bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }

                x: {
                    if (bgRoot.screen.width > width) {
                        // Center the picture
                        return (bgRoot.screen.width - width) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsX * usedFractionX;
                }
                y: {
                    if (bgRoot.screen.height > height) {
                        // Center the picture
                        return (bgRoot.screen.height - height) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsY * usedFractionY;
                }

                // Use pre-cropped cache if available, fall back to original
                property string _originalPath: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                property string _cropPath: _originalPath.length > 0
                    ? Wallpapers.getCachedCropPath(_originalPath, bgRoot.screen.width, bgRoot.screen.height)
                    : ""
                source: _cropPath.length > 0 ? _cropPath : _originalPath
                fillMode: Image.PreserveAspectCrop
                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                width: bgRoot.scaledWallpaperWidth
                height: bgRoot.scaledWallpaperHeight
            }


            ShaderEffect {
                id: transitionEffect
                anchors.fill: wallpaper
                layer.enabled: blurLoader.active
                visible: !blurLoader.active && !bgRoot.wallpaperIsVideo && !bgRoot.centeredWallpaperEnabled
                    && bgRoot.wallpaperAnimation !== "" && bgRoot.transitionProgress < 1.0
                    && wallpaper.status === Image.Ready

                property var fromImage: previousWallpaper
                property var toImage: wallpaper
                property var source1: previousWallpaper
                property var source2: wallpaper
                property real time: 0.0
                property real progress: bgRoot.transitionProgress
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)

                fragmentShader: bgRoot.wallpaperAnimation !== ""
                    ? Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
                    : ""

                Timer {
                    interval: 16
                    repeat: true
                    running: transitionEffect.visible
                    onTriggered: transitionEffect.time += interval / 1000.0
                }
                onVisibleChanged: if (!visible) transitionEffect.time = 0.0
            }

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
                    source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: radius * 2 + 1

                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            Loader {
                id: fastBlurLoader
                active: (bgRoot.userBlurActive || bgRoot.overviewBlurActive)
                    && (!bgRoot.centeredWallpaperEnabled || bgRoot.blurFullScreen)
                anchors.fill: parent
                sourceComponent: Item {
                    id: blurRoot
                    anchors.fill: parent

                    readonly property real fadeWidth: 140
                    readonly property real blurRadius: 48
                    readonly property bool alignRight: (Config.options.background.splitSide ?? "left") === "right"
                    property real coreWidth: bgRoot.blurFullScreen ? blurRoot.width : blurRoot.width * bgRoot.splitFraction

                    Behavior on coreWidth {
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    FastBlur {
                        id: blurLayer
                        anchors.fill: parent
                        source: bgRoot.wallpaperAnimation === "" || bgRoot.transitionProgress >= 1.0 ? wallpaper : transitionEffect
                        radius: blurRoot.blurRadius

                        layer.enabled: !bgRoot.blurFullScreen
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: blurLayer.width
                                height: blurLayer.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: blurRoot.alignRight ? 1 - (blurRoot.coreWidth / blurRoot.width) : Math.max(0, (blurRoot.coreWidth - blurRoot.fadeWidth) / blurRoot.width); color: blurRoot.alignRight ? "transparent" : "white" }
                                    GradientStop { position: blurRoot.alignRight ? Math.min(1, 1 - (blurRoot.coreWidth - blurRoot.fadeWidth) / blurRoot.width) : Math.min(1, blurRoot.coreWidth / blurRoot.width); color: blurRoot.alignRight ? "white" : "transparent" }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: centeredWallpaperBg
                anchors.fill: parent
                color: bgRoot.centeredWallpaperColor
                opacity: bgRoot.centeredWallpaperEnabled ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            MaterialShape {
                id: centeredWallpaperShapeItem
                property real targetCenterX: (bgRoot.centeredWallpaperFaceTracking && bgRoot.hasSubject)
                    ? Math.max(width / 2 + 40, Math.min(parent.width - width / 2 - 40, wallpaper.x + (wallpaper.width * bgRoot.focalX)))
                    : parent.width / 2
                property real targetCenterY: (bgRoot.centeredWallpaperFaceTracking && bgRoot.hasSubject)
                    ? Math.max(height / 2 + 40, Math.min(parent.height - height / 2 - 40, wallpaper.y + (wallpaper.height * bgRoot.focalY)))
                    : parent.height / 2

                x: targetCenterX - width / 2
                y: targetCenterY - height / 2

                Behavior on x {
                    NumberAnimation {
                        duration: 800
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 800
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }

                width: bgRoot.centeredWallpaperSize
                height: bgRoot.centeredWallpaperSize
                color: bgRoot.centeredWallpaperColor
                shape: bgRoot.centeredWallpaperShape
                transformOrigin: Item.Center
                visible: opacity > 0

                state: bgRoot.centeredWallpaperEnabled ? "shown" : "hidden"

                states: [
                    State {
                        name: "shown"
                        PropertyChanges { target: centeredWallpaperShapeItem; scale: 1; opacity: 1 }
                    },
                    State {
                        name: "hidden"
                        PropertyChanges { target: centeredWallpaperShapeItem; scale: 1.4; opacity: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        to: "shown"
                        ParallelAnimation {
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "scale"; from: 0; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "opacity"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                        }
                    },
                    Transition {
                        to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "scale"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "opacity"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                        }
                    }
                ]

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: centeredWallpaperShapeItem.width
                        height: centeredWallpaperShapeItem.height
                        shape: bgRoot.centeredWallpaperShape
                    }
                }

                Item {
                    id: framedImageContainer
                    anchors.fill: parent
                    clip: true

                    // 1:1 Wallpaper peephole:
                    // Positioned and sized identically to the background wallpaper so the shape
                    // acts as a seamless cutout/aperture revealing the true wallpaper underneath.
                    StyledImage {
                        id: framedImage
                        x: wallpaper.x - centeredWallpaperShapeItem.x
                        y: wallpaper.y - centeredWallpaperShapeItem.y
                        width: wallpaper.width
                        height: wallpaper.height

                        source: wallpaper.source
                        fillMode: Image.PreserveAspectCrop
                        cache: true
                        antialiasing: true
                    }
                }
            }

            FadeLoader {
                id: visualizerLoader
                shown: Config.options.background.widgets.visualizer ? Config.options.background.widgets.visualizer.enable : false
                sourceComponent: VisualizerWidget {
                    screenWidth: bgRoot.screen.width
                    screenHeight: bgRoot.screen.height
                    scaledScreenWidth: bgRoot.screen.width
                    scaledScreenHeight: bgRoot.screen.height
                    wallpaperScale: 1
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height
                readonly property real parallaxFactor: {
                    var f = Config.options.background.parallax.widgetsFactor;
                    return f / bgRoot.effectiveParallaxRatio;
                }
                readonly property bool locked: GlobalStates.screenLocked
                x: (bgRoot.backgroundParallaxEnabled && !bgRoot.verticalParallax) ? (wallpaper.x * parallaxFactor * !locked) : 0
                y: (bgRoot.backgroundParallaxEnabled && bgRoot.verticalParallax) ? (wallpaper.y * parallaxFactor * !locked) : 0

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
                    shown: Config.options.background.widgets.customImage ? Config.options.background.widgets.customImage.enable : false
                    sourceComponent: CustomImage {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.calendar ? Config.options.background.widgets.calendar.enable : false
                    sourceComponent: CalendarWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.weather ? Config.options.background.widgets.weather.enable : false
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.clock ? Config.options.background.widgets.clock.enable : false
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.notes ? Config.options.background.widgets.notes.enable : false
                    sourceComponent: NotesWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    id: mediaLoader
                    property bool enableLoading: true
                    shown: (Config.options.background.widgets.media ? Config.options.background.widgets.media.enable : false) && enableLoading
                    sourceComponent: MediaWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.images ? Config.options.background.widgets.images.enable : false
                    sourceComponent: ImageConverterWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.resources ? Config.options.background.widgets.resources.enable : false
                    sourceComponent: ResourcesWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.worldClock ? Config.options.background.widgets.worldClock.enable : false
                    sourceComponent: WorldClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.userCard ? Config.options.background.widgets.userCard.enable : false
                    sourceComponent: UserCardWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.todo ? Config.options.background.widgets.todo.enable : false
                    sourceComponent: TodoWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.timers ? Config.options.background.widgets.timers.enable : false
                    sourceComponent: TimerWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
            }

            DropArea {
                id: wallpaperDropArea
                anchors.fill: parent
                z: -3
                keys: ["application/x-widget-key", "text/uri-list"]

                onDropped: (drop) => {
                    if (drop.hasFormat("application/x-widget-key")) {
                        const key = drop.getDataAsString("application/x-widget-key")
                        if (key && Config.options && Config.options.background && Config.options.background.widgets && Config.options.background.widgets[key]) {
                            Config.options.background.widgets[key].enable = true
                            Config.options.background.widgets[key].placementStrategy = "free"
                            Config.options.background.widgets[key].x = Math.max(20, Math.min(drop.x - 100, bgRoot.screen.width - 250))
                            Config.options.background.widgets[key].y = Math.max(20, Math.min(drop.y - 50, bgRoot.screen.height - 200))
                            GlobalStates.widgetPickerOpen = false
                        }
                        drop.acceptProposedAction()
                        return
                    }

                    if (drop.hasUrls) {
                        const url = drop.urls[0]
                        if (url) {
                            const path = FileUtils.trimFileProtocol(url.toString())
                            if (/\.(jpg|jpeg|png|webp|mp4|webm|mkv|avi|mov)$/i.test(path)) {
                                Wallpapers.select(path, Appearance.m3colors.darkmode)
                            }
                        }
                        drop.acceptProposedAction()
                    }
                }
            }

            MouseArea {
                id: desktopRightClickArea
                anchors.fill: parent
                z: -2
                acceptedButtons: Qt.RightButton
                onClicked: (mouse) => {
                    GlobalStates.desktopMenuScreen = bgRoot.screen
                    GlobalStates.desktopMenuX = mouse.x
                    GlobalStates.desktopMenuY = mouse.y
                    GlobalStates.desktopMenuOpen = true
                }
            }
        }
    }
}
