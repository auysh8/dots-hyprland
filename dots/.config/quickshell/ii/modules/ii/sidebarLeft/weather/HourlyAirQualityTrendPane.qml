import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var sourceModel
    property int maxHours: 25
    property var items: []
    property var keyLines: []
    property real chartMax: 150
    property bool hasData: false
    readonly property real sidePadding: 16
    readonly property real leftGutter: 28
    readonly property real rightGutter: 68
    readonly property real topPadding: 14
    readonly property real chartTop: 70
    readonly property real chartBottom: height - 52
    readonly property real chartWidth: Math.max(0, width - sidePadding * 2)
    readonly property real plotWidth: Math.max(0, chartWidth - leftGutter - rightGutter)
    property real itemWidth: plotWidth > 0 ? plotWidth / 6 : 60
    readonly property real contentWidth: Math.max(plotWidth, items.length * itemWidth)

    function aqiThresholds() {
        return [0, 20, 50, 100, 150, 250];
    }

    function aqiLevelIndex(aqi) {
        if (aqi === undefined || aqi === null || isNaN(aqi))
            return -1;

        const thresholds = root.aqiThresholds();
        for (let i = thresholds.length - 1; i >= 0; --i) {
            if (aqi >= thresholds[i])
                return i;
        }
        return -1;
    }

    function aqiLevelName(level) {
        const names = [qsTr("Excellent"), qsTr("Good"), qsTr("Poor"), qsTr("Unhealthy"), qsTr("Very unhealthy"), qsTr("Hazardous")];
        return level >= 0 && level < names.length ? names[level] : "--";
    }

    function aqiPalette(level) {
        const colors = ["#00e59b", "#ffc302", "#ff712b", "#f62a55", "#c72eaa", "#9930ff"];
        return colors[Math.max(0, Math.min(colors.length - 1, level >= 0 ? level : 0))];
    }

    function pollutantIndex(value, thresholds) {
        if (value === undefined || value === null || isNaN(value))
            return NaN;

        const aqi = root.aqiThresholds();
        for (let level = thresholds.length - 1; level >= 0; --level) {
            if (value >= thresholds[level]) {
                if (level < thresholds.length - 1) {
                    const bpLo = thresholds[level];
                    const bpHi = thresholds[level + 1];
                    const inLo = aqi[level];
                    const inHi = aqi[level + 1];
                    return Math.round((inHi - inLo) / (bpHi - bpLo) * (value - bpLo) + inLo);
                }
                return Math.round(value * aqi[aqi.length - 1] / thresholds[thresholds.length - 1]);
            }
        }
        return NaN;
    }

    function hourlyAqiValue(air, hour) {
        if (hour && typeof hour.aqi === "number" && !isNaN(hour.aqi) && hour.aqi > 0)
            return hour.aqi;
        if (air && typeof air.aqi === "number" && !isNaN(air.aqi) && air.aqi > 0)
            return air.aqi;
        if (!air)
            return NaN;

        const pm25 = (air.pm25 !== undefined && !isNaN(air.pm25)) ? air.pm25 : air.pm2_5;
        const values = [root.pollutantIndex(air.ozone, [0, 50, 100, 160, 240, 480]), 
                        root.pollutantIndex(air.nitrogenDioxide, [0, 10, 25, 200, 400, 1000]), 
                        root.pollutantIndex(air.pm10, [0, 15, 45, 80, 160, 400]),
                        root.pollutantIndex(pm25, [0, 5, 15, 30, 60, 150])].filter(function (v) {
                            return !isNaN(v);
                        });
        if (values.length === 0)
            return NaN;

        return Math.max.apply(Math, values);
    }

    Connections {
        target: Weather
        function onAirQualityChanged() { root.rebuild(); }
        function onHourlyForecastChanged() { root.rebuild(); }
    }

    function hourLabel(epoch) {
        if (!epoch) return "--";
        const d = new Date(epoch * 1000);
        const h = d.getHours();
        if (DateTime.use12HourFormat) {
            const h12 = (h % 12 === 0) ? 12 : h % 12;
            const ampm = h >= 12 ? "PM" : "AM";
            return `${h12} ${ampm}`;
        }
        return `${h.toString().padStart(2, "0")}:00`;
    }

    function yForValue(value) {
        if (value === undefined || value === null || isNaN(value))
            return chartBottom;

        if (chartMax <= 0)
            return chartBottom;

        const clamped = Math.max(0, Math.min(chartMax, value));
        return chartBottom - clamped / chartMax * (chartBottom - chartTop);
    }

    function chartUpperBound(highest) {
        if (highest === undefined || highest === null || isNaN(highest) || highest <= 0)
            return 100;

        if (highest <= 100)
            return 100;

        if (highest <= 150)
            return 150;

        if (highest <= 250)
            return 250;

        return Math.ceil(highest / 50) * 50;
    }

    function rebuild() {
        const list = [];
        let highest = 0;
        let validCount = 0;
        const modelCount = root.sourceModel ? (typeof root.sourceModel.count === "function"
                                               ? root.sourceModel.count() : Number(root.sourceModel.count || 0)) : 0;
        const count = Math.min(root.maxHours, modelCount);
        for (let i = 0; i < count; ++i) {
            const hour = root.sourceModel.get(i) || ({});
            const aqi = root.hourlyAqiValue(hour.airQuality || ({}), hour);
            const level = root.aqiLevelIndex(aqi);
            if (!isNaN(aqi)) {
                highest = Math.max(highest, aqi);
                validCount += 1;
            }
            list.push({
                          "time": hour.time || 0,
                          "hourText": root.hourLabel(hour.time || 0),
                          "aqi": aqi,
                          "aqiText": !isNaN(aqi) ? Math.round(aqi).toString() : "--",
                          "color": root.aqiPalette(level),
                          "emphasized": i !== 0
                      });
        }
        items = list;
        chartMax = root.chartUpperBound(highest);
        hasData = validCount > 0;
        const lines = [
            { "value": 20, "label": root.aqiLevelName(1) },
            { "value": 100, "label": root.aqiLevelName(3) }
        ];
        if (chartMax >= 250)
            lines.push({ "value": 250, "label": root.aqiLevelName(5) });

        keyLines = lines;
    }

    clip: true
    onSourceModelChanged: rebuild()
    onWidthChanged: rebuildTimer.restart()
    onHeightChanged: rebuildTimer.restart()
    Component.onCompleted: rebuild()

    Timer {
        id: rebuildTimer
        interval: 0
        repeat: false
        onTriggered: rebuild()
    }



    Repeater {
        model: root.keyLines

        Item {
            required property var modelData

            x: root.sidePadding
            y: root.yForValue(modelData.value)
            width: root.chartWidth
            height: 20

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g,
                               Appearance.colors.colOutlineVariant.b, 0.44)
            }

            Item {
                anchors.left: parent.left
                anchors.bottom: parent.verticalCenter
                anchors.leftMargin: 2
                anchors.bottomMargin: 4
                width: leftValText.implicitWidth
                height: leftValText.implicitHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: 3
                    color: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
                    z: -1
                }

                Text {
                    id: leftValText
                    anchors.centerIn: parent
                    text: modelData.value
                    color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: 11
                }
            }

            Item {
                anchors.right: parent.right
                anchors.bottom: parent.verticalCenter
                anchors.rightMargin: 2
                anchors.bottomMargin: 4
                width: rightLblText.implicitWidth
                height: rightLblText.implicitHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2
                    radius: 3
                    color: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
                    z: -1
                }

                Text {
                    id: rightLblText
                    anchors.centerIn: parent
                    text: modelData.label
                    color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                    font.family: Appearance.font.family.main
                    font.pixelSize: 12
                }
            }
        }
    }

    StyledFlickable {
        id: trendFlick

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: root.sidePadding + root.leftGutter
        anchors.right: parent.right
        anchors.rightMargin: root.sidePadding + root.rightGutter
        clip: true
        interactive: true
        flickableDirection: Flickable.HorizontalFlick
        contentWidth: root.contentWidth
        contentHeight: height

        Item {
            id: trendContent
            width: trendFlick.contentWidth
            height: trendFlick.height

            Repeater {
                model: root.items

                Item {
                    required property var modelData
                    required property int index
                    readonly property real barWidth: Math.max(8, Math.min(12, width * 0.36))
                    readonly property real barHeight: !isNaN(modelData.aqi) ? Math.max(8, root.chartBottom
                                                                                       - root.yForValue(
                                                                                           modelData.aqi)) : 0
                    readonly property color hourColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant

                    x: index * root.itemWidth
                    width: root.itemWidth
                    height: root.height

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.topPadding
                        text: modelData.hourText
                        color: parent.hourColor
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 11
                    }

                    Rectangle {
                        visible: !isNaN(modelData.aqi)
                        width: parent.barWidth
                        height: parent.barHeight
                        x: (parent.width - width) / 2
                        y: root.chartBottom - height
                        radius: width / 2
                        color: Qt.rgba(Qt.color(modelData.color).r, Qt.color(modelData.color).g, Qt.color(
                                           modelData.color).b, 0.58)
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.chartBottom + 8
                        text: modelData.aqiText
                        color: Appearance.colors.colOnSurface
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 10
                    }
                }
            }

            MouseArea {
                id: dragArea
                property real lastMouseX: 0
                x: trendFlick.contentX
                y: 0
                z: 20
                width: trendFlick.width
                height: trendFlick.height
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: function (mouse) {
                    lastMouseX = mouse.x;
                }
                onPositionChanged: function (mouse) {
                    if (!pressed) return;
                    const dx = mouse.x - lastMouseX;
                    const maxX = Math.max(0, trendFlick.contentWidth - trendFlick.width);
                    trendFlick.contentX = Math.max(0, Math.min(maxX, trendFlick.contentX - dx));
                    lastMouseX = mouse.x;
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.hasData
        text: qsTr("Air quality data is unavailable")
        color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
        font.family: Appearance.font.family.main
        font.pixelSize: 16
    }
}
