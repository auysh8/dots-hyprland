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
        if (isActiveLine && wordList && wordList.length > 0) {
            requestPaint()
        }
    }
    
    onIsActiveLineChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onActiveColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        if (!textContent) return

        ctx.font = "bold " + fontSize + "px 'Inter', 'Segoe UI', sans-serif"
        ctx.textAlign = "left"
        ctx.textBaseline = "middle"

        // Measure total width to place it consistently with the active layout mode
        var totalWidth = ctx.measureText(textContent).width
        var startX = leftAligned ? 0 : (width - totalWidth) / 2
        var centerY = height / 2

        if (!isActiveLine || !wordList || wordList.length === 0) {
            ctx.fillStyle = inactiveColor
            ctx.fillText(textContent, startX, centerY)
            return
        }

        // Metrolist-style character/word iteration
        var currentPos = 0
        var charIdxMap = []
        var wordData = []

        for (var i = 0; i < wordList.length; i++) {
            var w = wordList[i]
            var rawText = w.text
            var indexInMain = textContent.indexOf(rawText, currentPos)
            if (indexInMain !== -1) {
                var sMs = (w.time || 0) * 1000
                var eMs = (w.end || (w.time + 0.3)) * 1000
                
                var isSung = _smoothPosMs > eMs
                var isActive = _smoothPosMs >= sMs && _smoothPosMs <= eMs
                var sungFactor = 0
                if (isSung) sungFactor = 1.0
                else if (isActive) sungFactor = Math.max(0, Math.min(1.0, (_smoothPosMs - sMs) / Math.max(1, eMs - sMs)))
                
                var timeSinceStart = _smoothPosMs - sMs
                var wobble = 0
                if (timeSinceStart >= 0 && timeSinceStart <= 750) {
                    if (timeSinceStart < 125) wobble = timeSinceStart / 125
                    else wobble = Math.max(0, 1.0 - (timeSinceStart - 125) / 625)
                }

                wordData.push({
                    text: rawText,
                    sMs: sMs,
                    eMs: eMs,
                    sungFactor: sungFactor,
                    isSung: isSung,
                    wobble: wobble
                })

                for (var c = 0; c < rawText.length; c++) {
                    charIdxMap[indexInMain + c] = i
                }
                
                currentPos = indexInMain + rawText.length
                if (currentPos < textContent.length && textContent[currentPos] === ' ') {
                    charIdxMap[currentPos] = i
                    currentPos++
                }
            } else {
                wordData.push(null)
            }
        }

        var xOffset = startX
        
        for (var i = 0; i < textContent.length; i++) {
            var charStr = textContent[i]
            var charWidth = ctx.measureText(charStr).width
            
            var wIdx = charIdxMap[i]
            var wData = wIdx !== undefined ? wordData[wIdx] : null
            
            var cScaleX = 1.0
            var cScaleY = 1.0
            var cTranslateY = 0
            
            var baseAlpha = 0.25
            var drawActive = false
            var activeAlpha = 1.0
            
            if (wData) {
                var wobbleX = wData.wobble * 0.025
                var wobbleY = wData.wobble * 0.015
                cScaleX += wobbleX
                cScaleY += wobbleY
                
                baseAlpha = wData.isSung ? 1.0 : (0.25 + 0.75 * wData.sungFactor)
                
                if (wData.sungFactor > 0 && !wData.isSung) {
                    drawActive = true
                    activeAlpha = wData.sungFactor
                } else if (wData.isSung) {
                    drawActive = true
                    activeAlpha = 1.0
                }
            }

            ctx.save()
            
            // Translate to center of character for scaling
            ctx.translate(xOffset + charWidth / 2, centerY + cTranslateY)
            ctx.scale(cScaleX, cScaleY)
            
            // Draw inactive/base color
            ctx.globalAlpha = baseAlpha
            ctx.fillStyle = inactiveColor
            ctx.fillText(charStr, -charWidth / 2, 0)
            
            // Draw active/glow color clipped
            if (drawActive) {
                ctx.globalAlpha = 1.0
                ctx.beginPath()
                // Clip rect exactly matching sung percentage
                var clipWidth = charWidth * activeAlpha
                ctx.rect(-charWidth / 2, -fontSize, clipWidth, fontSize * 2)
                ctx.clip()
                
                ctx.fillStyle = activeColor
                ctx.fillText(charStr, -charWidth / 2, 0)
            }

            ctx.restore()
            
            xOffset += charWidth
        }
    }
}
