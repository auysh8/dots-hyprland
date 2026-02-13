pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets

Slider {
    id: root

    property list<real> stopIndicatorValues: [1]
    enum Configuration {
        Wavy = 4,
        Sleek = 6,
        XS = 12,
        S = 18,
        M = 30,
        L = 42,
        XL = 72
    }

    property var configuration: StyledSlider.Configuration.S

    property real handleDefaultWidth: 3
    property real handlePressedWidth: 1.5
    property color highlightColor: Appearance.colors.colPrimary
    property color trackColor: Appearance.colors.colSecondaryContainer
    property color handleColor: Appearance.colors.colPrimary
    property color dotColor: Appearance.m3colors.m3onSecondaryContainer
    property color dotColorHighlighted: Appearance.m3colors.m3onPrimary
    property real unsharpenRadius: Appearance.rounding.unsharpen

    // Track thickness — bound directly to configuration, NO animation.
    // Wavy=4, Sleek=6, etc. Snaps instantly on config change.
    property real trackWidth: configuration

    property real trackRadius: trackWidth >= StyledSlider.Configuration.XL ? 21
        : trackWidth >= StyledSlider.Configuration.L ? 12
        : trackWidth >= StyledSlider.Configuration.M ? 9
        : trackWidth >= StyledSlider.Configuration.S ? 6
        : height / 2

    property real handleHeight: (configuration === StyledSlider.Configuration.Wavy || configuration === StyledSlider.Configuration.Sleek) ? 24 : Math.max(33, trackWidth + 9)

    property real handleWidth: root.pressed ? handlePressedWidth : handleDefaultWidth
    property real handleMargins: 4
    property real trackDotSize: 3
    property bool usePercentTooltip: true
    property string tooltipContent: usePercentTooltip ? `${Math.round(((value - from) / (to - from)) * 100)}%` : `${Math.round(value)}`

    property bool wavy: configuration === StyledSlider.Configuration.Wavy
    property bool animateWave: true

    // Wave amplitude — set imperatively to avoid initialization races.
    // Instant on init, animated on subsequent wavy↔straight changes.
    property real amplitudeMultiplier: 0

    // Set correct initial value after all bindings are applied
    Component.onCompleted: amplitudeMultiplier = wavy ? 0.5 : 0.0

    // Explicit animation for wavy ↔ straight transitions
    NumberAnimation {
        id: ampAnim
        target: root
        property: "amplitudeMultiplier"
        duration: 400
        easing.type: Easing.OutCubic
    }

    onWavyChanged: {
        ampAnim.stop()
        ampAnim.from = amplitudeMultiplier
        ampAnim.to = wavy ? 0.5 : 0.0
        ampAnim.restart()
    }

    property real waveFrequency: 6
    property real waveFps: 60

    leftPadding: handleMargins
    rightPadding: handleMargins
    property real effectiveDraggingWidth: width - leftPadding - rightPadding

    // Pre-computed fill widths (clamped to 0)
    readonly property real _leftW: Math.max(0, handleMargins + (visualPosition * effectiveDraggingWidth) - (handleWidth / 2 + handleMargins))
    readonly property real _rightW: Math.max(0, handleMargins + ((1 - visualPosition) * effectiveDraggingWidth) - (handleWidth / 2 + handleMargins))

    Layout.fillWidth: true
    from: 0
    to: 1

    Behavior on value {
        SmoothedAnimation {
            velocity: Appearance.animation.elementMoveFast.velocity
        }
    }

    Behavior on handleMargins {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    component TrackDot: Rectangle {
        required property real value
        property real normalizedValue: (value - root.from) / (root.to - root.from)
        anchors.verticalCenter: parent.verticalCenter
        x: root.handleMargins + (normalizedValue * root.effectiveDraggingWidth) - (root.trackDotSize / 2)
        width: root.trackDotSize
        height: root.trackDotSize
        radius: Appearance.rounding.full
        color: normalizedValue > root.visualPosition ? root.dotColor : root.dotColorHighlighted

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => mouse.accepted = false
        cursorShape: root.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor 
    }

    background: Item {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        implicitHeight: root.trackWidth

        // ─── LEFT FILL: Solid Rectangle (non-wavy modes) ───
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: root._leftW
            height: root.trackWidth
            // Only show when NOT wavy AND amplitude has fully settled to 0
            visible: !root.wavy && root.amplitudeMultiplier <= 0.01
            color: root.highlightColor
            topLeftRadius: root.trackRadius
            bottomLeftRadius: root.trackRadius
            topRightRadius: root.unsharpenRadius
            bottomRightRadius: root.unsharpenRadius
        }

        // ─── LEFT FILL: Wavy Canvas (wavy mode) ───
        // Always mounted — never destroyed/recreated by a Loader.
        // Hidden via `visible` when not in wavy mode.
        WavyLine {
            id: wavyFill
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: root._leftW
            // Use a safe fallback if root hasn't been laid out yet
            height: root.height > 0 ? root.height : 24
            // Stay visible during fadeout animation (amplitude > 0)
            visible: root.wavy || root.amplitudeMultiplier > 0.01

            frequency: root.waveFrequency
            fullLength: Math.max(root.width, 1)
            color: root.highlightColor
            amplitudeMultiplier: root.amplitudeMultiplier
            lineWidth: root.trackWidth

            // Animate the wave continuously (only when visible)
            FrameAnimation {
                running: wavyFill.visible && root.animateWave
                onTriggered: wavyFill.requestPaint()
            }
        }

        // ─── RIGHT FILL: Unfilled track ───
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            width: root._rightW
            height: root.trackWidth
            color: root.trackColor
            topRightRadius: root.trackRadius
            bottomRightRadius: root.trackRadius
            topLeftRadius: root.unsharpenRadius
            bottomLeftRadius: root.unsharpenRadius
        }

        // Stop indicators
        Repeater {
            model: root.stopIndicatorValues
            TrackDot {
                required property real modelData
                value: modelData
                anchors.verticalCenter: parent?.verticalCenter
            }
        }
    }

    handle: Rectangle {
        id: handle

        implicitWidth: root.handleWidth
        implicitHeight: root.handleHeight
        x: root.handleMargins + (root.visualPosition * root.effectiveDraggingWidth) - (root.handleWidth / 2)
        anchors.verticalCenter: parent.verticalCenter
        radius: Appearance.rounding.full
        color: root.handleColor

        Behavior on implicitWidth {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledToolTip {
            extraVisibleCondition: root.pressed
            text: root.tooltipContent
            font {
                family: Appearance.font.family.numbers
                variableAxes: Appearance.font.variableAxes.numbers
            }
        }
    }
}