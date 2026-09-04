import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock"

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    readonly property string clockStyle: GlobalStates.screenLocked ? Config.options.background.widgets.clock.styleLocked : Config.options.background.widgets.clock.style
    readonly property bool forceCenter: (GlobalStates.screenLocked && Config.options.lock.centerClock)
    readonly property bool shouldShow: (!Config.options.background.widgets.clock.showOnlyWhenLocked || GlobalStates.screenLocked)
    function getFrameColorFromName(name) {
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

    property bool frameActive: Config.options.background.centeredWallpaper
    property real frameHeight: Config.options.background.centeredWallpaperSize
    property color frameColor: getFrameColorFromName(Config.options?.background?.centeredWallpaperColor ?? "primaryContainer")
    readonly property bool frameIsDark: frameColor.hslLightness < 0.5

    readonly property color frameAdaptiveTextColor: {
        const colorName = Config.options?.background?.centeredWallpaperColor ?? "primaryContainer";
        let onColor = Appearance.colors.colOnPrimaryContainer;
        switch (colorName) {
            case "primary":            onColor = Appearance.colors.colOnPrimary; break;
            case "secondary":          onColor = Appearance.colors.colOnSecondary; break;
            case "tertiary":           onColor = Appearance.colors.colOnTertiary; break;
            case "primaryContainer":   onColor = Appearance.colors.colOnPrimaryContainer; break;
            case "secondaryContainer": onColor = Appearance.colors.colOnSecondaryContainer; break;
            case "tertiaryContainer":  onColor = Appearance.colors.colOnTertiaryContainer; break;
            case "layer0":             onColor = Appearance.colors.colOnLayer0; break;
            case "layer1":             onColor = Appearance.colors.colOnLayer1; break;
            default:                   onColor = frameIsDark ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0; break;
        }
        if (frameIsDark) {
            return onColor.hslLightness >= 0.70 ? onColor : ColorUtils.colorWithLightness(onColor, 0.90);
        } else {
            return onColor.hslLightness <= 0.30 ? onColor : ColorUtils.colorWithLightness(onColor, 0.15);
        }
    }

    readonly property string customClockColorKey: Config.options.background.widgets.clock.color ?? ""

    readonly property color resolvedClockColor: {
        if (root.frameActive) {
            if (customClockColorKey === "") {
                return frameAdaptiveTextColor;
            }
            const propName = "col" + customClockColorKey.charAt(0).toUpperCase() + customClockColorKey.slice(1);
            const explicitCol = Appearance.colors[propName] ?? frameAdaptiveTextColor;
            const contrastDiff = Math.abs(explicitCol.hslLightness - frameColor.hslLightness);
            if (contrastDiff < 0.35) {
                return ColorUtils.colorWithLightness(explicitCol, frameIsDark ? 0.88 : 0.15);
            }
            return explicitCol;
        }
        if (customClockColorKey === "") return root.colText;
        const propName = "col" + customClockColorKey.charAt(0).toUpperCase() + customClockColorKey.slice(1);
        return Appearance.colors[propName] ?? root.colText;
    }

    readonly property color resolvedPixelTintBold: {
        if (!root.frameActive) {
            return Appearance.colors.colPrimary;
        }
        const colorName = Config.options?.background?.centeredWallpaperColor ?? "primaryContainer";
        const accent = (customClockColorKey !== "")
            ? (Appearance.colors["col" + customClockColorKey.charAt(0).toUpperCase() + customClockColorKey.slice(1)] ?? Appearance.colors.colPrimary)
            : ((colorName === "secondary" || colorName === "secondaryContainer")
                ? Appearance.colors.colSecondary
                : ((colorName === "tertiary" || colorName === "tertiaryContainer")
                    ? Appearance.colors.colTertiary
                    : Appearance.colors.colPrimary));
        return ColorUtils.colorWithLightness(accent, frameIsDark ? 0.90 : 0.14);
    }

    readonly property color resolvedPixelTintSoft: {
        if (!root.frameActive) {
            return Appearance.colors.colPrimaryContainer;
        }
        const colorName = Config.options?.background?.centeredWallpaperColor ?? "primaryContainer";
        const accent = (customClockColorKey !== "")
            ? (Appearance.colors["col" + customClockColorKey.charAt(0).toUpperCase() + customClockColorKey.slice(1)] ?? Appearance.colors.colPrimary)
            : ((colorName === "secondary" || colorName === "secondaryContainer")
                ? Appearance.colors.colSecondary
                : ((colorName === "tertiary" || colorName === "tertiaryContainer")
                    ? Appearance.colors.colTertiary
                    : Appearance.colors.colPrimary));
        return ColorUtils.colorWithLightness(accent, frameIsDark ? 0.68 : 0.35);
    }
    property bool wallpaperSafetyTriggered: false
    needsColText: clockStyle === "digital"

    readonly property real lockTargetY: {
        if (!forceCenter) return targetY;
        if (frameActive) {
            const h = (root.height > 0 ? root.height : contentColumn.implicitHeight);
            const frameTop = (root.screenHeight - frameHeight) / 2;
            return Math.max(30, (frameTop - h) / 2);
        }
        return (root.screenHeight - root.height) / 2;
    }

    x: forceCenter ? ((root.screenWidth - root.width) / 2) : targetX
    y: forceCenter ? lockTargetY : targetY
    visibleWhenLocked: true

    function restoreXYBinding() {
        root.x = Qt.binding(() => root.forceCenter ? ((root.screenWidth - root.width) / 2) : root.targetX);
        root.y = Qt.binding(() => root.forceCenter ? root.lockTargetY : root.targetY);
    }

    property var textHorizontalAlignment: {
        if (!Config.options.background.widgets.clock.digital.adaptiveAlignment || root.forceCenter || Config.options.background.widgets.clock.digital.vertical) 
            return Text.AlignHCenter;
        if (root.x < root.scaledScreenWidth / 3)
            return Text.AlignLeft;
        if (root.x > root.scaledScreenWidth * 2 / 3)
            return Text.AlignRight;
        return Text.AlignHCenter;
    }

    Column {
        id: contentColumn
        anchors.centerIn: parent
        spacing: 10

        FadeLoader {
            id: cookieClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "cookie" && (root.shouldShow)
            fade: false
            sourceComponent: CookieClock {
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        FadeLoader {
            id: digitalClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "digital" && (root.shouldShow)
            fade: false
            sourceComponent: DigitalClock {
                colText: root.resolvedClockColor
                textHorizontalAlignment: root.textHorizontalAlignment
            }
        }

        FadeLoader {
            id: pixelClockLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: root.clockStyle === "pixel" && (root.shouldShow)
            fade: false
            sourceComponent: PixelClock {
                tintSoft: root.resolvedPixelTintSoft
                tintBold: root.resolvedPixelTintBold
            }
        }

        FadeLoader {
            id: quoteLoader
            anchors.horizontalCenter: parent.horizontalCenter
            shown: Config.options.background.widgets.clock.quote.enable && (root.clockStyle === "pixel" || root.clockStyle === "cookie") && Config.options.background.widgets.clock.quote.text !== "" && root.shouldShow
            sourceComponent: CookieQuote {}
        }

        StatusRow {
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    component StatusRow: Item {
        id: statusText
        implicitHeight: statusTextBg.implicitHeight
        implicitWidth: statusTextBg.implicitWidth
        StyledRectangularShadow {
            target: statusTextBg
            visible: statusTextBg.visible && root.clockStyle === "cookie"
            opacity: statusTextBg.opacity
        }
        Rectangle {
            id: statusTextBg
            anchors.centerIn: parent
            clip: true
            opacity: (safetyStatusText.shown || lockStatusText.shown) ? 1 : 0
            visible: opacity > 0
            implicitHeight: statusTextRow.implicitHeight + 5 * 2
            implicitWidth: statusTextRow.implicitWidth + 5 * 2
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, root.clockStyle === "cookie" ? 0 : 1)

            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: statusTextRow
                anchors.centerIn: parent
                spacing: 14
                Item {
                    Layout.fillWidth: root.textHorizontalAlignment !== Text.AlignLeft
                    implicitWidth: 1
                }
                ClockStatusText {
                    id: safetyStatusText
                    shown: root.wallpaperSafetyTriggered
                    statusIcon: "hide_image"
                    statusText: Translation.tr("Wallpaper safety enforced")
                }
                ClockStatusText {
                    id: lockStatusText
                    shown: GlobalStates.screenLocked && Config.options.lock.showLockedText
                    statusIcon: "lock"
                    statusText: Translation.tr("Locked")
                }
                Item {
                    Layout.fillWidth: root.textHorizontalAlignment !== Text.AlignRight
                    implicitWidth: 1
                }
            }
        }
    }

    component ClockStatusText: Row {
        id: statusTextRow
        property alias statusIcon: statusIconWidget.text
        property alias statusText: statusTextWidget.text
        property bool shown: true
        property color textColor: root.clockStyle === "cookie" ? Appearance.colors.colOnSecondaryContainer : root.resolvedClockColor
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        spacing: 4
        MaterialSymbol {
            id: statusIconWidget
            anchors.verticalCenter: statusTextRow.verticalCenter
            iconSize: Appearance.font.pixelSize.huge
            color: statusTextRow.textColor
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
        ClockText {
            id: statusTextWidget
            color: statusTextRow.textColor
            horizontalAlignment: root.textHorizontalAlignment
            anchors.verticalCenter: statusTextRow.verticalCenter
            font {
                pixelSize: Appearance.font.pixelSize.large
                weight: Font.Normal
            }
            style: Text.Raised
            styleColor: Appearance.colors.colShadow
        }
    }
}
