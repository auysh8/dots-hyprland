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

        // Build word-to-char alpha mapping
        var wordAlphaMap = []
        if (isActiveLine && wordList && wordList.length > 0) {
            var currentPos = 0
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
                        alpha = 1.0
                    } else if (posMs >= sMs) {
                        var dur = Math.max(60, eMs - sMs)
                        var fadeInDur = Math.min(220, dur * 0.45)
                        var progress = Math.min(1.0, Math.max(0.0, (posMs - sMs) / fadeInDur))
                        alpha = 0.55 + 0.45 * progress
                    } else {
                        alpha = 0.25
                    }

                    for (var c = 0; c < rawText.length; c++) {
                        wordAlphaMap[indexInMain + c] = alpha
                    }

                    currentPos = indexInMain + rawText.length
                    if (currentPos < textContent.length && textContent[currentPos] === ' ') {
                        wordAlphaMap[currentPos] = alpha
                        currentPos++
                    }
                }
            }
        }

        // 2. Break text into lines
        var lines = []
        var currentLineWords = []
        var currentLineWidth = 0
        var spaceWidth = ctx.measureText(" ").width
        
        var i = 0
        while (i < textContent.length) {
            // Read a word
            var start = i
            while (i < textContent.length && textContent[i] !== ' ') {
                i++
            }
            var word = textContent.substring(start, i)
            var wordWidth = ctx.measureText(word).width
            
            // Read spaces after word
            var spaceStart = i
            while (i < textContent.length && textContent[i] === ' ') {
                i++
            }
            var spaces = textContent.substring(spaceStart, i)
            var spacesWidth = spaces.length * spaceWidth
            
            // Check if word fits (only if not the first word in line)
            if (currentLineWords.length > 0 && currentLineWidth + wordWidth > width) {
                lines.push({ words: currentLineWords, width: currentLineWidth })
                currentLineWords = []
                currentLineWidth = 0
            }
            
            var wordChars = []
            for (var j = 0; j < word.length; j++) {
                wordChars.push({ char: word[j], index: start + j })
            }
            
            var spaceIndices = []
            for (var s = 0; s < spaces.length; s++) {
                spaceIndices.push(spaceStart + s)
            }
            
            currentLineWords.push({ 
                text: word, 
                width: wordWidth, 
                chars: wordChars, 
                spaceIndices: spaceIndices, 
                spacesWidth: spacesWidth,
                spacesText: spaces
            })
            currentLineWidth += wordWidth + spacesWidth
        }
        if (currentLineWords.length > 0) {
            lines.push({ words: currentLineWords, width: currentLineWidth })
        }

        // 3. Vertical centering
        var lineHeight = fontSize * 1.3
        var totalHeight = lines.length * lineHeight
        var startY = (height - totalHeight) / 2

        // 4. Draw
        for (var l = 0; l < lines.length; l++) {
            var line = lines[l]
            var xOffset = leftAligned ? 0 : (width - line.width) / 2
            var yOffset = startY + l * lineHeight + lineHeight / 2
            
            for (var w = 0; w < line.words.length; w++) {
                var wordObj = line.words[w]
                
                // Draw word characters
                for (var c = 0; c < wordObj.chars.length; c++) {
                    var charObj = wordObj.chars[c]
                    var charWidth = ctx.measureText(charObj.char).width
                    var a = 1.0
                    if (isActiveLine && wordList && wordList.length > 0) {
                        a = wordAlphaMap[charObj.index] !== undefined ? wordAlphaMap[charObj.index] : 0.25
                    } else {
                        a = 1.0
                    }
                    
                    ctx.globalAlpha = a
                    ctx.fillStyle = (isActiveLine && wordList && wordList.length > 0) ? activeColor : inactiveColor
                    ctx.fillText(charObj.char, xOffset, yOffset)
                    xOffset += charWidth
                }
                
                // Draw spaces
                for (var s = 0; s < wordObj.spaceIndices.length; s++) {
                    var sIdx = wordObj.spaceIndices[s]
                    var aSpace = 1.0
                    if (isActiveLine && wordList && wordList.length > 0) {
                        aSpace = wordAlphaMap[sIdx] !== undefined ? wordAlphaMap[sIdx] : 0.25
                    }
                    ctx.globalAlpha = aSpace
                    ctx.fillText(" ", xOffset, yOffset)
                    xOffset += spaceWidth
                }
            }
        }
    }
}
