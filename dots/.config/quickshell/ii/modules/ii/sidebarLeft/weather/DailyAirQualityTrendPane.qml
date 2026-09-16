import QtQuick
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var sourceModel
    property int maxItems: 16
    property var items: []
    property var keyLines: []
    property real chartMax: 150
    property bool hasData: false
    property bool initialPositionApplied: false
    property real itemWidth: trendFlick.width > 0 ? (items.length > 5 ? trendFlick.width / 5.2 : trendFlick.width / Math.max(1, items.length)) : 72

    readonly property real sidePadding: 0
    readonly property real topPadding: 16
    readonly property real chartTop: 90
    readonly property real chartBottom: height - 56
    readonly property real chartWidth: width
    readonly property real contentWidth: Math.max(width, items.length * itemWidth)

    clip: true

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

    function dailyAqiValue(air, day) {
        if (day && typeof day.aqi === "number" && !isNaN(day.aqi) && day.aqi > 0)
            return day.aqi;
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
        function onAirQualityChanged() {
            root.initialPositionApplied = false;
            root.rebuild();
            initialPositionTimer.restart();
        }
        function onDailyTrendForecastChanged() {
            root.initialPositionApplied = false;
            root.rebuild();
            initialPositionTimer.restart();
        }
    }

    function dayLabel(epoch) {
        if (!epoch)
            return "--";
        const today = new Date();
        const date = new Date(epoch * 1000);
        const midnightToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        const midnightDate = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
        const diffDays = Math.round((midnightDate - midnightToday) / (24 * 3600 * 1000));
        if (diffDays === -1)
            return qsTr("Yesterday");
        if (diffDays === 0)
            return qsTr("Today");
        if (diffDays === 1)
            return qsTr("Tomorrow");
        const week = [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat")];
        return week[date.getDay()];
    }

    function dateLabel(epoch) {
        return epoch ? Qt.formatDateTime(new Date(epoch * 1000), "M/d") : "--";
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
        const count = Math.min(root.maxItems, modelCount);
        const today = new Date();
        const midnightToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();

        for (let i = 0; i < count; ++i) {
            const day = root.sourceModel.get(i) || ({});
            const aqi = root.dailyAqiValue(day.airQuality || ({}), day);
            const level = root.aqiLevelIndex(aqi);
            if (!isNaN(aqi) && aqi > 0) {
                highest = Math.max(highest, aqi);
                validCount += 1;
                const epoch = day.time || 0;
                let diffDays = 0;
                if (epoch) {
                    const d = new Date(epoch * 1000);
                    const midnightD = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
                    diffDays = Math.round((midnightD - midnightToday) / (24 * 3600 * 1000));
                }
                list.push({
                              time: epoch,
                              dayText: root.dayLabel(epoch),
                              dateText: root.dateLabel(epoch),
                              aqi: aqi,
                              aqiText: Math.round(aqi).toString(),
                              levelText: root.aqiLevelName(level),
                              color: root.aqiPalette(level),
                              emphasized: diffDays >= 0
                          });
            }
        }
        items = list;
        chartMax = root.chartUpperBound(highest);
        hasData = validCount > 0;

        const lines = [
            { value: 20, label: root.aqiLevelName(1) },
            { value: 100, label: root.aqiLevelName(3) }
        ];
        if (chartMax >= 250) {
            lines.push({ value: 250, label: root.aqiLevelName(5) });
        }
        keyLines = lines;
    }

    function applyInitialPosition() {
        if (initialPositionApplied) return;
        if (items.length <= 5) {
            trendFlick.contentX = 0;
            initialPositionApplied = true;
            return;
        }
        const maxX = Math.max(0, trendFlick.contentWidth - trendFlick.width);
        if (maxX <= 0) {
            trendFlick.contentX = 0;
            initialPositionApplied = true;
            return;
        }
        trendFlick.contentX = Math.min(root.itemWidth, maxX);
        initialPositionApplied = true;
    }

    Timer {
        id: initialPositionTimer
        interval: 50
        repeat: false
        onTriggered: applyInitialPosition()
    }

    Timer {
        id: rebuildTimer
        interval: 0
        repeat: false
        onTriggered: {
            rebuild();
            initialPositionTimer.restart();
        }
    }

    onSourceModelChanged: {
        initialPositionApplied = false;
        rebuild();
        initialPositionTimer.restart();
    }
    onWidthChanged: rebuildTimer.restart()
    onHeightChanged: rebuildTimer.restart()
    onVisibleChanged: {
        if (visible) initialPositionTimer.restart();
    }
    Component.onCompleted: {
        rebuild();
        initialPositionTimer.restart();
    }



    Repeater {
        model: root.keyLines

        Item {
            required property var modelData

            x: 0
            y: root.yForValue(modelData.value)
            width: root.width
            height: 20
            z: 10

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
                anchors.leftMargin: 8
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
                anchors.rightMargin: 8
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

        anchors.fill: parent
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

                    x: index * root.itemWidth
                    y: 0
                    width: root.itemWidth
                    height: root.height

                    readonly property real barWidth: Math.max(12, Math.min(18, width * 0.24))
                    readonly property real barHeight: !isNaN(modelData.aqi) ? Math.max(10, root.chartBottom
                                                                                       - root.yForValue(
                                                                                           modelData.aqi)) : 0
                    readonly property color weekColor: modelData.emphasized ? Appearance.colors.colOnSurface : 
                                                                              (Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant)
                    readonly property color dateColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        y: root.topPadding
                        text: modelData.dayText
                        color: parent.weekColor
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        font.bold: modelData.dayText === qsTr("Today")
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        y: root.topPadding + 20
                        text: modelData.dateText
                        color: parent.dateColor
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        visible: !isNaN(modelData.aqi)
                        width: parent.barWidth
                        height: parent.barHeight
                        x: Math.round((parent.width - width) / 2)
                        y: root.chartBottom - height
                        radius: width / 2
                        color: Qt.rgba(Qt.color(modelData.color).r, Qt.color(modelData.color).g, Qt.color(
                                           modelData.color).b, 0.58)
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        y: root.chartBottom + 10
                        text: modelData.aqiText
                        color: Appearance.colors.colOnSurface
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 13
                        font.bold: modelData.dayText === qsTr("Today")
                        horizontalAlignment: Text.AlignHCenter
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
                enabled: trendFlick.contentWidth > trendFlick.width
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                cursorShape: (trendFlick.contentWidth > trendFlick.width) ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
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
