import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets
Item {
    id: root

    property real visibilityMeters: NaN
    property bool animationEnabled: false
    property bool animationActive: true

    WeatherAnimatedValue {
        id: visibilityAnimation
        targetValue: root.visibilityMeters
        enabled: root.animationEnabled
        active: root.animationActive
    }

    function eyeIconPath() {
        return "M12,9A3,3 0 0,1 15,12A3,3 0 0,1 12,15A3,3 0 0,1 9,12A3,3 0 0,1 12,9M12,4.5C17,4.5 21.27,7.61 23,12C21.27,16.39 17,19.5 12,19.5C7,19.5 2.73,16.39 1,12C2.73,7.61 7,4.5 12,4.5M3.18,12C4.83,15.36 8.24,17.5 12,17.5C15.76,17.5 19.17,15.36 20.82,12C19.17,8.64 15.76,6.5 12,6.5C8.24,6.5 4.83,8.64 3.18,12Z";
    }

    function valueNumberText() {
        const value = visibilityAnimation.currentValue;
        if (isNaN(value))
            return "--";
        if (root.visibilityMeters >= 1000) {
            const km = value / 1000;
            return km < 100 ? km.toFixed(1) : Math.round(km).toString();
        }
        return Math.round(value).toString();
    }

    function valueUnitText() {
        if (isNaN(root.visibilityMeters))
            return "";
        return root.visibilityMeters >= 1000 ? qsTr("km") : qsTr("m");
    }

    function descriptionText() {
        if (isNaN(root.visibilityMeters))
            return "--";
        if (root.visibilityMeters < 1000)
            return qsTr("Very poor");
        if (root.visibilityMeters < 4000)
            return qsTr("Poor");
        if (root.visibilityMeters < 10000)
            return qsTr("Moderate");
        if (root.visibilityMeters < 20000)
            return qsTr("Good");
        if (root.visibilityMeters < 40000)
            return qsTr("Clear");
        return qsTr("Excellent");
    }

    readonly property color cardFill: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
    property int shapeLobes: 8

    Canvas {
        id: shapeCanvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const cx = width / 2;
            const cy = height / 2;
            const minDim = Math.min(width, height);
            const rBase = (minDim / 2) - 12;
            const lobes = root.shapeLobes;
            const amp = 5.5;

            // Main solid foreground contour
            ctx.beginPath();
            for (let i = 0; i <= 360; i += 2) {
                const rad = (i * Math.PI) / 180;
                const r = rBase + amp * Math.cos(lobes * rad);
                const x = cx + r * Math.cos(rad);
                const y = cy + r * Math.sin(rad);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.closePath();
            ctx.fillStyle = cardFill;
            ctx.fill();

            // 3. Crisp outline
            ctx.strokeStyle = Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42);
            ctx.lineWidth = 1;
            ctx.stroke();
        }

        Connections {
            target: Appearance.colors
            function onColOutlineVariantChanged() { shapeCanvas.requestPaint(); }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.18
        spacing: 6

        Item {
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter

            Shape {
                width: 24
                height: 24
                anchors.centerIn: parent
                scale: 20 / 24
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 0
                    fillColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant

                    PathSvg {
                        path: root.eyeIconPath()
                    }
                }
            }
        }

        Text {
            text: qsTr("Visibility")
            color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
            font.family: Appearance.font.family.main
            font.pixelSize: 16
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -2
        spacing: 4

        Text {
            text: root.valueNumberText()
            color: Appearance.colors.colOnSurface
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.width * 0.24)
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.valueUnitText()
            color: Appearance.colors.colOnSurface
            font.family: Appearance.font.family.main
            font.pixelSize: Math.round(root.width * 0.12)
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 6
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: root.height * 0.13
        width: parent.width * 0.8
        text: root.descriptionText()
        color: Appearance.colors.colOnSurface
        font.family: Appearance.font.family.main
        font.pixelSize: 18
        font.bold: true
        fontSizeMode: Text.Fit
        minimumPixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
}
