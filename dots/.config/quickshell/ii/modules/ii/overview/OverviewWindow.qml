pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item { // Window
    id: root
    property var toplevel
    property var windowData
    property var monitorData
    property var scale
    property bool restrictToWorkspace: true
    property real widthRatio: {
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: {
        return Math.max((windowData?.at[0] - (monitorData?.x ?? 0) - monitorData?.reserved[0]) * widthRatio * root.scale, 0) + xOffset;
    }

    property real initY: {
        return Math.max((windowData?.at[1] - (monitorData?.y ?? 0) - monitorData?.reserved[1]) * heightRatio * root.scale, 0) + yOffset;
    }
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor.id

    property var targetWindowWidth: windowData?.size[0] * scale * widthRatio
    property var targetWindowHeight: windowData?.size[1] * scale * heightRatio
    property bool hovered: false
    property bool pressed: false

    property string windowClass: (windowData?.class ?? "").toLowerCase()
    property bool isCode: windowClass.includes("code") || windowClass.includes("cursor") || windowClass.includes("nvim") || windowClass.includes("zed") || windowClass.includes("dev")
    property bool isBrowser: windowClass.includes("zen") || windowClass.includes("firefox") || windowClass.includes("chrome") || windowClass.includes("brave") || windowClass.includes("chromium")
    property bool isTerminal: windowClass.includes("kitty") || windowClass.includes("foot") || windowClass.includes("terminal") || windowClass.includes("alacritty") || windowClass.includes("ghostty") || windowClass.includes("wezterm")

    property color badgeColor: isCode ? Appearance.colors.colSecondaryContainer : 
        isBrowser ? Appearance.colors.colTertiaryContainer : 
        isTerminal ? Appearance.colors.colPrimaryContainer : 
        Appearance.colors.colLayer3

    property color badgeGlyphColor: isCode ? Appearance.colors.colOnSecondaryContainer : 
        isBrowser ? Appearance.colors.colOnTertiaryContainer : 
        isTerminal ? Appearance.colors.colOnPrimaryContainer : 
        Appearance.colors.colOnLayer3

    property string badgeSymbol: isCode ? "code" : 
        isBrowser ? "public" : 
        isTerminal ? "terminal" : ""

    property string iconPath: Quickshell.iconPath(AppSearch.guessIcon(windowData?.class), "image-missing")

    property real windowPadding: 3

    x: initX + windowPadding
    y: initY + windowPadding
    width: Math.max(1, targetWindowWidth - windowPadding * 2)
    height: Math.max(1, targetWindowHeight - windowPadding * 2)
    opacity: windowData.monitor == widgetMonitorId ? 1 : 0.4

    property real topLeftRadius: 12
    property real topRightRadius: 12
    property real bottomLeftRadius: 12
    property real bottomRightRadius: 12

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomRightRadius: root.bottomRightRadius
            bottomLeftRadius: root.bottomLeftRadius
        }
    }

    Behavior on x {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: windowCard
        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomRightRadius: root.bottomRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        color: Appearance.colors.colLayer2
        clip: true

        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.85)
        border.width: 1

        // Live Window Preview Capture
        ScreencopyView {
            id: windowPreview
            anchors.fill: parent
            captureSource: GlobalStates.overviewOpen ? root.toplevel : null
            live: true

            // Interaction and dimming tint overlay
            Rectangle {
                anchors.fill: parent
                color: root.pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.4) : 
                    root.hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.6) : 
                    ColorUtils.transparentize(Appearance.colors.colLayer2, 0.75)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        // Centered App Squircle Badge with Original App Icon
        Rectangle {
            id: appBadge
            anchors.centerIn: parent
            property real badgeSize: Math.max(38, Math.min(68, Math.min(root.width * 0.44, root.height * 0.44)))
            width: badgeSize
            height: badgeSize
            radius: badgeSize * 0.28
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.m3colors.m3outlineVariant, 0.7)

            StyledImage {
                anchors.centerIn: parent
                width: appBadge.badgeSize * 0.72
                height: appBadge.badgeSize * 0.72
                source: root.iconPath
                mipmap: true
            }
        }
    }
}
