import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property real value: 0
    property string level: "--"
    property int activeIndex: -1
    property string icon: "wb_sunny"
    property string title: qsTr("UV index")
    property bool animationEnabled: false
    property bool animationActive: true

    readonly property int currentBucket: {
        const uv = Number(root.value);
        if (isNaN(uv) || uv < 3) return 0; // Low (0-2)
        if (uv < 6) return 1;              // Moderate (3-5)
        if (uv < 8) return 2;              // High (6-7)
        if (uv < 11) return 3;             // Very High (8-10)
        return 4;                          // Extreme (11+)
    }

    readonly property var uvPalette: ["#00e59b", "#ffc302", "#ff712b", "#f62a55", "#9930ff"]
    readonly property color activeDotColor: uvPalette[Math.min(uvPalette.length - 1, Math.max(0, currentBucket))]
    readonly property color mutedDotColor: Appearance.m3colors.darkmode ? 
        Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.12)

    WeatherAnimatedValue {
        id: valueAnimation
        targetValue: root.value
        enabled: root.animationEnabled
        active: root.animationActive
    }

    function uvIconPath() {
        return "M20,11H23V13H20V11M1,11H4V13H1V11M13,1V4H11V1H13M4.92,3.5L7.05,5.64L5.63,7.05L3.5,4.93L4.92,3.5M16.95,5.63L19.07,3.5L20.5,4.93L18.37,7.05L16.95,5.63M12,6A6,6 0 0,1 18,12C18,14.22 16.79,16.16 15,17.2V19A1,1 0 0,1 14,20H10A1,1 0 0,1 9,19V17.2C7.21,16.16 6,14.22 6,12A6,6 0 0,1 12,6M14,21V22A1,1 0 0,1 13,23H11A1,1 0 0,1 10,22V21H14M11,18H13V15.87C14.73,15.43 16,13.86 16,12A4,4 0 0,0 12,8A4,4 0 0,0 8,12C8,13.86 9.27,15.43 11,15.87V18Z";
    }

    Item {
        id: vectorLayer
        width: 176
        height: 176
        anchors.centerIn: parent
        scale: Math.min(root.width, root.height) / 176 * 0.98

        // Scalloped 12-petal flower / sunburst contour
        Canvas {
            id: flowerCanvas
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = width / 2;
                const cy = height / 2;
                const lobes = 12;
                const R_base = (Math.min(width, height) / 2) - 8;
                const petalAmp = 6.5;

                ctx.beginPath();
                for (let i = 0; i <= 360; i += 2) {
                    const rad = (i * Math.PI) / 180;
                    const r = R_base + petalAmp * Math.cos(lobes * rad);
                    const x = cx + r * Math.cos(rad);
                    const y = cy + r * Math.sin(rad);
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }
                ctx.closePath();
                ctx.fillStyle = Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e";
                ctx.fill();
                ctx.strokeStyle = Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42);
                ctx.lineWidth = 1;
                ctx.stroke();
            }

            Connections {
                target: Appearance.colors
                function onColOutlineVariantChanged() { flowerCanvas.requestPaint(); }
            }
        }

        // UV Severity Dot Indicator Arc
        Repeater {
            model: [
                { x: 38, y: 126, index: 0 },
                { x: 58, y: 140, index: 1 },
                { x: 88, y: 146, index: 2 },
                { x: 118, y: 140, index: 3 },
                { x: 138, y: 126, index: 4 }
            ]

            delegate: Item {
                width: 12
                height: 12
                x: modelData.x - 6
                y: modelData.y - 6

                Rectangle {
                    anchors.centerIn: parent
                    width: modelData.index === root.currentBucket ? 11 : 6
                    height: width
                    radius: width / 2
                    color: modelData.index === root.currentBucket ? 
                        root.activeDotColor : root.mutedDotColor

                    Behavior on width {
                        NumberAnimation { duration: 250; easing.type: Easing.OutBack }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 250 }
                    }
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.20
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
                        path: root.uvIconPath()
                    }
                }
            }
        }

        Text {
            text: root.title
            color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
            font.family: Appearance.font.family.main
            font.bold: true
            font.pixelSize: 16
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -4
        text: isNaN(valueAnimation.currentValue) ? "--" : Math.round(valueAnimation.currentValue)
        color: Appearance.colors.colOnSurface
        font.family: Appearance.font.family.main
        font.bold: true
        font.pixelSize: 58
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: 16
        width: parent.width * 0.82
        text: root.level
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
