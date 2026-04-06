import QtQuick
import QtQuick.Controls
import qs.modules.common.functions

Item {
    id: root

    property bool isFullscreen: false
    property color contentColor: "white"
    property color loaderColor: "white"
    property var lyricsModel: null
    property int lyricsCount: 0
    readonly property int resolvedLyricsCount: (
        lyricsModel && lyricsModel.count !== undefined
            ? lyricsModel.count
            : lyricsCount
    )
    property int currentLine: -1
    property real position: 0
    property bool isResizing: false
    property int textInset: isFullscreen ? 32 : 20

    property bool manualScrollMode: false
    property real userManualOffset: 0
    property real _lastDragTranslation: 0

    signal seekRequested(real time)

    readonly property real anchorY: height * 0.35
    readonly property real lineGap: 16
    readonly property real fallbackLineHeight: isFullscreen ? 86 : 66
    property var itemHeights: ({})

    function itemHeightFor(idx) {
        if (idx < 0 || idx >= resolvedLyricsCount)
            return fallbackLineHeight
        const v = itemHeights[idx]
        return v !== undefined ? v : fallbackLineHeight
    }

    function baseOffsetFor(idx) {
        if (idx <= 0)
            return 0
        let y = 0
        for (let i = 0; i < idx; ++i) {
            y += itemHeightFor(i) + lineGap
        }
        return y
    }

    function stackHeight() {
        if (resolvedLyricsCount <= 0)
            return 0
        return baseOffsetFor(resolvedLyricsCount - 1) + itemHeightFor(resolvedLyricsCount - 1)
    }

    function clampManualOffset(value) {
        if (resolvedLyricsCount <= 0 || currentLine < 0)
            return 0

        const totalAbove = baseOffsetFor(currentLine)
        const totalBelow = stackHeight() - baseOffsetFor(currentLine) - itemHeightFor(currentLine)
        const visibleAbove = anchorY - 48
        const visibleBelow = height - anchorY - itemHeightFor(currentLine) + 32
        const minOffset = Math.min(0, -totalBelow + visibleBelow)
        const maxOffset = Math.max(0, totalAbove - visibleAbove)
        return Math.max(minOffset, Math.min(maxOffset, value))
    }

    function nudgeManualOffset(delta) {
        manualScrollMode = true
        userManualOffset = clampManualOffset(userManualOffset + delta)
        resetManualScrollTimer.restart()
    }

    function resync() {
        manualScrollMode = false
        userManualOffset = 0
        resetManualScrollTimer.stop()
    }

    function targetYFor(idx) {
        if (resolvedLyricsCount <= 0)
            return 0
        if (currentLine < 0 || currentLine >= resolvedLyricsCount) {
            return 24 + baseOffsetFor(idx) + userManualOffset
        }

        const currentBase = baseOffsetFor(currentLine)
        const currentHeight = itemHeightFor(currentLine)
        return anchorY - (currentHeight / 2) + (baseOffsetFor(idx) - currentBase) + userManualOffset
    }

    onCurrentLineChanged: {
        if (!manualScrollMode)
            resync()
    }

    Timer {
        id: resetManualScrollTimer
        interval: 3000
        onTriggered: root.resync()
    }

    DragHandler {
        id: dragHandler
        target: null
        xAxis.enabled: false

        onActiveChanged: {
            if (active) {
                root.manualScrollMode = true
                root._lastDragTranslation = 0
                resetManualScrollTimer.stop()
            } else {
                root._lastDragTranslation = 0
                resetManualScrollTimer.restart()
            }
        }

        onTranslationChanged: {
            const delta = translation.y - root._lastDragTranslation
            root._lastDragTranslation = translation.y
            root.userManualOffset = root.clampManualOffset(root.userManualOffset + delta)
        }
    }

    WheelHandler {
        target: null

        onWheel: function(event) {
            const steps = event.angleDelta.y / 120
            if (steps === 0)
                return
            root.nudgeManualOffset(steps * 36)
            event.accepted = true
        }
    }

    Repeater {
        model: root.resolvedLyricsCount

        delegate: Item {
            id: lyricItem

            readonly property var lineData: root.lyricsModel ? root.lyricsModel.get(index) : null
            readonly property real lineTime: lineData ? Number(lineData.time || 0) : 0
            readonly property string lineText: lineData ? (lineData.text || "") : ""
            readonly property string lineWordsRaw: lineData ? (lineData.words || "[]") : "[]"
            readonly property bool isCurrent: index === root.currentLine
            readonly property int distance: Math.abs(index - root.currentLine)
            readonly property real targetY: root.targetYFor(index)
            readonly property real baseScale: (
                isCurrent ? 1.0
                : distance === 1 ? 0.965
                : distance === 2 ? 0.935 : 0.91
            )
            readonly property real baseOpacity: (
                isCurrent ? 1.0
                : distance === 1 ? 0.62
                : distance === 2 ? 0.34 : 0.18
            )

            property real lineBounceScale: 1.0
            property real lineBounceYOffset: 0
            property bool isHovered: lyricMouseArea.containsMouse

            x: 0
            y: targetY + lineBounceYOffset
            width: root.width
            height: lineTextItem.implicitHeight + (isCurrent ? 28 : 18)
            z: isCurrent ? 5 : Math.max(0, 1000 - distance)

            onHeightChanged: {
                const nextHeights = Object.assign({}, root.itemHeights)
                nextHeights[index] = height
                root.itemHeights = nextHeights
            }

            Behavior on y {
                enabled: !root.isResizing
                SequentialAnimation {
                    PauseAnimation { duration: Math.min(lyricItem.distance * 20, 200) }
                    NumberAnimation {
                        duration: 750
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                id: lyricMouseArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                scrollGestureEnabled: false

                onClicked: {
                    if (lyricItem.lineData && lyricItem.lineTime >= 0)
                        root.seekRequested(lyricItem.lineTime)
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: lineTextItem.x - 8
                width: lineTextItem.implicitWidth + 24
                height: lineTextItem.implicitHeight + 8
                radius: 8
                color: root.contentColor
                opacity: lyricItem.isHovered && !lyricItem.isCurrent ? 0.1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Item {
                id: motionLayer
                anchors.fill: parent
                scale: lyricItem.baseScale * lyricItem.lineBounceScale

                Behavior on scale {
                    enabled: !root.isResizing
                    NumberAnimation {
                        duration: 430
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: lineTextItem
                    x: root.textInset
                    width: parent.width - (root.textInset * 2)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.QtRendering
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    font.weight: lyricItem.isCurrent ? Font.Bold : Font.Normal
                    font.family: "Inter, Segoe UI, sans-serif"
                    font.pixelSize: lyricItem.isCurrent
                        ? (root.isFullscreen ? 60 : 42)
                        : (root.isFullscreen ? 46 : 32)
                    opacity: lyricItem.baseOpacity
                    color: root.contentColor
                    visible: !(lyricItem.isCurrent && hasWords)

                    property var wordList: {
                        try { return JSON.parse(lyricItem.lineWordsRaw) } catch(e) { return [] }
                    }
                    property bool hasWords: wordList && wordList.length > 0
                    property bool hasWordsAlias: hasWords

                    Behavior on opacity {
                        enabled: !root.isResizing
                        NumberAnimation {
                            duration: 430
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on font.pixelSize {
                        enabled: !root.isResizing
                        NumberAnimation {
                            duration: 430
                            easing.type: Easing.OutCubic
                        }
                    }

                    text: lyricItem.lineText
                }

                CanvasLyricsLine {
                    id: canvasLine
                    x: root.textInset
                    width: parent.width - (root.textInset * 2)
                    anchors.verticalCenter: parent.verticalCenter
                    height: lineTextItem.implicitHeight * 2
                    textContent: lyricItem.lineText
                    wordList: lineTextItem.wordList
                    positionSec: root.position
                    isActiveLine: lyricItem.isCurrent
                    leftAligned: true
                    activeColor: root.contentColor
                    inactiveColor: ColorUtils.applyAlpha(root.contentColor, 0.2)
                    fontSize: root.isFullscreen ? 60 : 42
                    visible: lyricItem.isCurrent && lineTextItem.hasWordsAlias
                    z: 3
                }
            }

            onIsCurrentChanged: {
                if (root.isResizing)
                    return

                if (isCurrent) {
                    currentLineBounce.restart()
                } else {
                    exitLineBounce.restart()
                }
            }

            SequentialAnimation {
                id: currentLineBounce
                running: false

                ScriptAction {
                    script: {
                        lyricItem.lineBounceScale = 0.9
                        lyricItem.lineBounceYOffset = 42
                    }
                }

                PauseAnimation { duration: 28 }

                ParallelAnimation {
                    NumberAnimation {
                        target: lyricItem
                        property: "lineBounceScale"
                        to: 1.065
                        duration: 160
                        easing.type: Easing.OutExpo
                    }
                    NumberAnimation {
                        target: lyricItem
                        property: "lineBounceYOffset"
                        to: -12
                        duration: 160
                        easing.type: Easing.OutExpo
                    }
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: lyricItem
                        property: "lineBounceScale"
                        to: 1.0
                        duration: 280
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.34
                    }
                    NumberAnimation {
                        target: lyricItem
                        property: "lineBounceYOffset"
                        to: 0
                        duration: 280
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.28
                    }
                }
            }

            ParallelAnimation {
                id: exitLineBounce
                running: false

                NumberAnimation {
                    target: lyricItem
                    property: "lineBounceScale"
                    to: 1.0
                    duration: 180
                    easing.type: Easing.OutQuad
                }

                NumberAnimation {
                    target: lyricItem
                    property: "lineBounceYOffset"
                    to: 0
                    duration: 180
                    easing.type: Easing.OutQuad
                }
            }
        }
    }
}
