import QtQuick

Canvas {
    id: root

    property string textContent: ""
    property var wordList: []
    property real positionSec: 0
    property bool isActiveLine: false
    property bool leftAligned: false

    property color activeColor: "white"
    property color inactiveColor: "gray"
    property int fontSize: 26

    property real _smoothPosMs: positionSec * 1000

    on_SmoothPosMsChanged: {
        if (isActiveLine && wordList && wordList.length > 0 && visible) {
            requestPaint()
        }
    }

    onIsActiveLineChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onActiveColorChanged: requestPaint()
    onInactiveColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        if (!textContent) return

        ctx.font = "bold " + fontSize + "px 'Inter', 'Segoe UI', sans-serif"
        ctx.textAlign = "left"
        ctx.textBaseline = "middle"

        var totalWidth = ctx.measureText(textContent).width
        var startX = leftAligned ? 0 : (width - totalWidth) / 2
        var centerY = height / 2

        if (!isActiveLine || !wordList || wordList.length === 0) {
            ctx.fillStyle = inactiveColor
            ctx.globalAlpha = 1.0
            ctx.fillText(textContent, startX, centerY)
            return
        }

        // Build word-to-char mapping
        var currentPos = 0
        var charIdxMap = []
        var wordAlphaMap = []

        for (var i = 0; i < wordList.length; i++) {
            var w = wordList[i]
            var rawText = w.text
            var indexInMain = textContent.indexOf(rawText, currentPos)
            if (indexInMain !== -1) {
                var sMs = (w.time || 0) * 1000
                var eMs = (w.end || (w.time + 0.3)) * 1000
                var posMs = _smoothPosMs

                var alpha
                if (posMs + 30 >= eMs) {
                    // Word fully sung
                    alpha = 1.0
                } else if (posMs >= sMs) {
                    // Word being sung — fade from 0.55 to 1.0 (matches standard mode)
                    var dur = Math.max(60, eMs - sMs)
                    var fadeInDur = Math.min(220, dur * 0.45)
                    var progress = Math.min(1.0, Math.max(0.0, (posMs - sMs) / fadeInDur))
                    alpha = 0.55 + 0.45 * progress
                } else {
                    // Not yet reached
                    alpha = 0.25
                }

                for (var c = 0; c < rawText.length; c++) {
                    wordAlphaMap[indexInMain + c] = alpha
                }

                // Map trailing space to the word's alpha
                currentPos = indexInMain + rawText.length
                if (currentPos < textContent.length && textContent[currentPos] === ' ') {
                    wordAlphaMap[currentPos] = alpha
                    currentPos++
                }
            }
        }

        // Draw each character with its word's alpha
        var xOffset = startX
        for (var i = 0; i < textContent.length; i++) {
            var charStr = textContent[i]
            var charWidth = ctx.measureText(charStr).width
            var a = wordAlphaMap[i] !== undefined ? wordAlphaMap[i] : 0.25

            ctx.globalAlpha = a
            ctx.fillStyle = activeColor
            ctx.fillText(charStr, xOffset, centerY)

            xOffset += charWidth
        }
    }
}
