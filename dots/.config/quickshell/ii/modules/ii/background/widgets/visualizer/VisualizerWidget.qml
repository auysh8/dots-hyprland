import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "visualizer"

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: (activePlayer && activePlayer.isPlaying) ? true : false
    readonly property var points: GlobalStates.visualizerPoints

    property real barWidth: 4
    property real barSpacing: 8
    property real maxBarHeight: 220
    property real maxVisualizerValue: 1000
    property real smoothingDuration: 150

    readonly property int barCount: Math.max(1, Math.floor(screenWidth / (barWidth + barSpacing)))

    readonly property var smoothedPoints: {
        let raw = points
        if (!raw || raw.length === 0) return Array(barCount).fill(0)
        let count = barCount
        let mapped = new Array(count)
        let rawLenM1 = raw.length - 1

        for (let i = 0; i < count; i++) {
            let progress = i / (count - 1 || 1)
            let relPos = progress * rawLenM1
            let low = Math.floor(relPos)
            let high = Math.ceil(relPos)
            let mix = relPos - low
            mapped[i] = (raw[low] * (1 - mix)) + (raw[high] * (high < raw.length ? mix : 0))
        }

        let smoothed = new Array(count)
        let sW = 0.2
        for (let j = 0; j < count; j++) {
            let p = mapped[Math.max(0, j - 1)]
            let n = mapped[Math.min(count - 1, j + 1)]
            smoothed[j] = (p * sW) + (mapped[j] * (1.0 - 2 * sW)) + (n * sW)
        }
        return smoothed
    }

    property real activityOpacity: 0
    Behavior on activityOpacity {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    Timer {
        id: silenceTimer
        interval: 1000
        onTriggered: root.activityOpacity = 0
    }

    onPointsChanged: {
        if (points.some(p => p > 0)) {
            root.activityOpacity = 1.0
            silenceTimer.restart()
        }
    }

    implicitWidth: screenWidth
    implicitHeight: maxBarHeight + 20

    x: 0
    y: screenHeight - implicitHeight
    draggable: false

    // Precomputed 20-step gradient table: evaluated once when colors change, 0 JS overhead per frame
    readonly property var colorPalette: {
        let p = []
        const c1 = Appearance.colors.colPrimary
        const c0 = Appearance.colors.colPrimaryContainer
        for (let i = 0; i <= 20; i++) {
            let t = i / 20.0
            p.push(Qt.rgba(
                c1.r * t + c0.r * (1.0 - t),
                c1.g * t + c0.g * (1.0 - t),
                c1.b * t + c0.b * (1.0 - t),
                1
            ))
        }
        return p
    }

    Row {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        spacing: root.barSpacing
        opacity: root.activityOpacity

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                width: root.barWidth
                property real pointValue: {
                    const v = root.smoothedPoints[index] ?? 0
                    return Math.max(root.barWidth, (v / root.maxVisualizerValue) * root.maxBarHeight)
                }
                height: pointValue
                topLeftRadius: root.barWidth / 2
                topRightRadius: root.barWidth / 2
                anchors.bottom: parent.bottom

                // Instant table lookup for the gradient
                color: root.colorPalette[Math.min(20, Math.floor((pointValue / root.maxBarHeight) * 20))]
            }
        }
    }
}
