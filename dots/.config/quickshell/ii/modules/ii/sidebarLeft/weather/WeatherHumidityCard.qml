import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

WeatherInsightCard {
    id: root

    property real humidityValue: NaN
    property string humidityText: "--"
    property string dewPointText: "--"
    property color accent: "#6f649b"
    property bool animationEnabled: false
    property bool animationActive: true

    readonly property real dewPointValue: numericTextValue(dewPointText)

    icon: ""
    title: ""
    radius: 42
    circular: false
    cardColor: Appearance.m3colors.m3surfaceContainerLowest ?? "#ffffff"

    readonly property color textInk: Appearance.m3colors.darkmode ? "#f0ebff" : "#241a39"

    function humidityIconPath() {
        return "M580,720Q605,720 622.5,702.5Q640,685 640,660Q640,635 622.5,617.5Q605,600 580,600Q555,600 537.5,617.5Q520,635 520,660Q520,685 537.5,702.5Q555,720 580,720ZM378,718L638,458L582,402L322,662L378,718ZM380,520Q405,520 422.5,502.5Q440,485 440,460Q440,435 422.5,417.5Q405,400 380,400Q355,400 337.5,417.5Q320,435 320,460Q320,485 337.5,502.5Q355,520 380,520ZM480,880Q343,880 251.5,786Q160,692 160,552Q160,452 239.5,334.5Q319,217 480,80Q641,217 720.5,334.5Q800,452 800,552Q800,692 708.5,786Q617,880 480,880ZM480,800Q584,800 652,729.5Q720,659 720,552Q720,479 659.5,387Q599,295 480,186Q361,295 300.5,387Q240,479 240,552Q240,659 308,729.5Q376,800 480,800ZM480,480Q480,480 480,480Q480,480 480,480Q480,480 480,480Q480,480 480,480Q480,480 480,480Q480,480 480,480Q480,480 480,480Z";
    }

    function humidityPercentValue() {
        if (isNaN(root.humidityValue))
            return NaN;
        return root.humidityValue <= 1.0 ? root.humidityValue * 100.0 : root.humidityValue;
    }

    function numericTextValue(text) {
        const match = (text || "").match(/[-+]?\d+(?:\.\d+)?/);
        return match ? Number(match[0]) : NaN;
    }

    function animatedHumidityText() {
        return isNaN(humidityAnimation.currentValue) ? "--" : Math.round(humidityAnimation.currentValue) + "%";
    }

    function animatedDewPointText() {
        const val = isNaN(dewPointAnimation.currentValue) ? root.dewPointValue : dewPointAnimation.currentValue;
        if (isNaN(val)) return root.dewPointText !== "--" ? root.dewPointText : "24°";
        return Math.round(val) + "°";
    }

    Timer {
        id: resizeDebounceTimer
        interval: 60
        repeat: false
        onTriggered: waveCanvas.requestPaint()
    }

    onHumidityValueChanged: waveCanvas.requestPaint()
    onWidthChanged: resizeDebounceTimer.restart()
    onHeightChanged: resizeDebounceTimer.restart()

    WeatherAnimatedValue {
        id: humidityAnimation
        targetValue: root.humidityPercentValue()
        enabled: root.animationEnabled
        active: root.animationActive
        onCurrentValueChanged: waveCanvas.requestPaint()
    }

    WeatherAnimatedValue {
        id: dewPointAnimation
        targetValue: root.dewPointValue
        enabled: root.animationEnabled
        active: root.animationActive
    }

    // Wavy Liquid Fill Background (strictly clipped to squircle radius 42)
    Canvas {
        id: waveCanvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width;
            const h = height;
            if (w <= 0 || h <= 0) return;

            const r = root.radius || 42;

            // 1. Strictly clip canvas drawing to squircle boundary (zero corner bleed)
            ctx.save();
            ctx.beginPath();
            if (typeof ctx.roundRect === "function") {
                ctx.roundRect(0, 0, w, h, r);
            } else {
                ctx.moveTo(r, 0);
                ctx.arcTo(w, 0, w, h, r);
                ctx.arcTo(w, h, 0, h, r);
                ctx.arcTo(0, h, 0, 0, r);
                ctx.arcTo(0, 0, w, 0, r);
                ctx.closePath();
            }
            ctx.clip();

            // 2. Compute dynamic water level based on relative humidity percentage
            const rawVal = isNaN(humidityAnimation.currentValue) ?
                (isNaN(root.humidityPercentValue()) ? 60 : root.humidityPercentValue()) :
                humidityAnimation.currentValue;
            // Clamped between 15% and 88% so wave curve and liquid are always visible and balanced
            const clampedPct = Math.max(0.15, Math.min(0.88, rawVal / 100.0));
            const topY = h * (1.0 - clampedPct);
            const waveAmp = 5;

            // 3. Draw sinusoidal wavy surface across width
            ctx.beginPath();
            ctx.moveTo(0, topY);
            const steps = 60;
            for (let i = 0; i <= steps; i++) {
                const x = (i / steps) * w;
                const y = topY + waveAmp * Math.sin((x / w) * Math.PI * 5 + 0.8);
                ctx.lineTo(x, y);
            }
            ctx.lineTo(w, h);
            ctx.lineTo(0, h);
            ctx.closePath();

            const liquidColor = Appearance.m3colors.darkmode ? 
                "#463d63" : (Appearance.colors.colSecondaryContainer ?? "#71649e");
            ctx.fillStyle = liquidColor;
            ctx.fill();

            ctx.restore();
        }

        Connections {
            target: Appearance.colors
            function onColSecondaryContainerChanged() { waveCanvas.requestPaint(); }
        }

        Connections {
            target: Appearance.m3colors
            function onDarkmodeChanged() { waveCanvas.requestPaint(); }
        }
    }

    // Border overlay to keep the crisp 1px outline stroke on top of the liquid
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42)
        z: 1
    }

    Row {
        id: cardHeader
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 22
        anchors.topMargin: 22
        height: 24
        spacing: 6
        z: 2

        Item {
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            Shape {
                width: 960
                height: 960
                anchors.centerIn: parent
                scale: 20 / 960
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 0
                    fillColor: root.textInk

                    PathSvg {
                        path: root.humidityIconPath()
                    }
                }
            }
        }

        Text {
            id: headerLabel
            height: cardHeader.height
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Relative humidity")
            color: root.textInk
            font.family: Appearance.font.family.main
            font.pixelSize: 16
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Text {
        anchors.left: parent.left
        anchors.top: cardHeader.bottom
        anchors.leftMargin: 22
        anchors.topMargin: 14
        text: root.animatedHumidityText()
        color: root.textInk
        font.family: Appearance.font.family.main
        font.pixelSize: 56
        font.bold: true
        lineHeight: 0.9
        z: 2
    }

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 22
        anchors.bottomMargin: 20
        spacing: 10
        z: 2

        Rectangle {
            width: 44
            height: 44
            radius: 22
            color: "#fedf85"
            anchors.verticalCenter: parent.verticalCenter

            Text {
                anchors.centerIn: parent
                text: root.animatedDewPointText()
                color: "#281e00"
                font.family: Appearance.font.family.main
                font.pixelSize: 15
                font.bold: true
            }
        }

        Text {
            text: qsTr("Dew point")
            color: root.textInk
            font.family: Appearance.font.family.main
            font.pixelSize: 16
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
