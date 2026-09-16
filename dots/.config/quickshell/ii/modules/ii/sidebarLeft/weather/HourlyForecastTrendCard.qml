import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "WeatherChartMath.js" as WeatherChartMath

Rectangle {
    id: root

    property var sourceModel
    property var normalsSource
    property real itemWidth: trendFlick.width > 0 ? trendFlick.width / 6 : 122
    property int maxItems: 25
    property int currentTab: 0
    property bool foreground: false
    property var displayTemperatureDomain: [0, 1]
    readonly property int normalMonth: new Date().getMonth() + 1
    readonly property real normalDaytimeC: normalTemperature(true)
    readonly property real normalNighttimeC: normalTemperature(false)

    function modelCount() {
        if (!sourceModel) return 0;
        const count = typeof sourceModel.count === "function" ? sourceModel.count() : Number(sourceModel.count || 0);
        return Math.min(maxItems, count);
    }

    function itemAt(index) {
        return sourceModel && sourceModel.get ? sourceModel.get(index) : ({});
    }

    function valueAt(map, key, fallback) {
        const v = map ? map[key] : undefined;
        return (v === undefined || v === null || isNaN(v)) ? fallback : Number(v);
    }

    function fmtTemp(value) {
        if (value === undefined || value === null || isNaN(value)) return "--";
        const temp = Weather.useUSCS ? Math.round(value * 9 / 5 + 32) : Math.round(value);
        return temp + "°";
    }

    function fmtRain(value) {
        if (value === undefined || value === null || isNaN(value) || value <= 0)
            return "";
        return Number(value).toFixed(value < 10 ? 1 : 0).replace(/\.0$/, "");
    }

    function normalTemperature(daytime) {
        const source = root.normalsSource;
        if (!source || !source.normalsAvailable)
            return NaN;
        const value = daytime ? source.normalDaytimeTemperatureC(root.normalMonth) :
                                source.normalNighttimeTemperatureC(root.normalMonth);
        return root.valueAt({ "value": value }, "value", NaN);
    }

    function forecastTemperatures() {
        const values = [];
        const count = root.modelCount();
        for (let i = 0; i < count; ++i) {
            const temperature = root.valueAt(root.itemAt(i), "temperatureC", NaN);
            if (!isNaN(temperature))
                values.push(temperature);
        }
        return values;
    }

    function updateTemperatureDomain() {
        root.displayTemperatureDomain = WeatherChartMath.temperatureDomain(root.forecastTemperatures(),
                                                                           root.normalDaytimeC,
                                                                           root.normalNighttimeC);
        if (root.foreground)
            trendCanvas.requestPaint();
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

    property int customTab: 2

    function tabLabel(tab) {
        switch(tab) {
            case 2: return qsTr("Wind");
            case 3: return qsTr("UV index");
            case 4: return qsTr("Precipitation");
            case 5: return qsTr("Feels like");
            case 6: return qsTr("Humidity");
            case 7: return qsTr("Pressure");
            case 8: return qsTr("Cloud cover");
            case 9: return qsTr("Visibility");
            default: return qsTr("Wind");
        }
    }

    function extraTabLabel() {
        return tabLabel(currentTab);
    }

    radius: Appearance.rounding.large ?? 24
    color: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
    border.width: 1
    border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42)
    clip: true

    onSourceModelChanged: updateTemperatureDomain()
    onCurrentTabChanged: {
        if (root.currentTab === 0)
            trendCanvas.requestPaint();
    }
    onForegroundChanged: {
        if (root.foreground)
            trendCanvas.requestPaint();
    }
    Timer {
        id: repaintDebounceTimer
        interval: 60
        repeat: false
        onTriggered: trendCanvas.requestPaint()
    }

    onWidthChanged: repaintDebounceTimer.restart()
    onHeightChanged: repaintDebounceTimer.restart()
    Component.onCompleted: updateTemperatureDomain()

    Connections {
        function onUseUSCSChanged() {
            trendCanvas.requestPaint();
        }
        target: Weather
    }

    Connections {
        function onNormalsChanged() {
            root.updateTemperatureDomain();
        }
        target: root.normalsSource
        ignoreUnknownSignals: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 16
            Layout.preferredHeight: 82
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "schedule"
                    color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                    iconSize: 22
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: qsTr("Hourly forecast")
                    color: Appearance.colors.colOnSurface
                    font.bold: true
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                WeatherButtonGroup {
                    currentValue: root.currentTab
                    model: [
                        { "value": 0, "label": qsTr("Conditions") },
                        { "value": 1, "label": qsTr("Air quality") },
                        { "value": root.customTab, "label": root.tabLabel(root.customTab) }
                    ]
                    onValueSelected: value => { root.currentTab = value; }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: moreButton
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    buttonRadius: 17
                    colBackground: (root.currentTab >= 3 || extraMenu.opened) ? 
                        Appearance.colors.colPrimaryContainer : (Appearance.colors.colSecondaryContainer ?? Appearance.m3colors.m3secondaryContainer)
                    colBackgroundHover: (root.currentTab >= 3 || extraMenu.opened) ? 
                        Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSecondaryContainerHover

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "more_horiz"
                        iconSize: 18
                        color: (root.currentTab >= 3 || extraMenu.opened) ? 
                            Appearance.colors.colOnPrimaryContainer : (Appearance.colors.colOnSecondaryContainer ?? Appearance.m3colors.m3onSecondaryContainer)
                    }

                    onClicked: extraMenu.toggle()

                    WeatherMetricMenu {
                        id: extraMenu
                        anchorItem: moreButton
                        selectedValue: root.currentTab
                        openAbove: true
                        options: [
                            { "value": 2, "label": qsTr("Wind"), "icon": "air" },
                            { "value": 3, "label": qsTr("UV index"), "icon": "sunny" },
                            { "value": 4, "label": qsTr("Precipitation"), "icon": "water_drop" },
                            { "value": 5, "label": qsTr("Feels like"), "icon": "thermostat" },
                            { "value": 6, "label": qsTr("Humidity / Dew point"), "icon": "humidity_percentage" },
                            { "value": 7, "label": qsTr("Pressure"), "icon": "speed" },
                            { "value": 8, "label": qsTr("Cloud cover"), "icon": "cloud" },
                            { "value": 9, "label": qsTr("Visibility"), "icon": "visibility" }
                        ]
                        onValueSelected: value => {
                            root.customTab = value;
                            root.currentTab = value;
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledFlickable {
                id: trendFlick
                anchors.fill: parent
                clip: true
                interactive: root.currentTab === 0
                flickableDirection: Flickable.HorizontalFlick
                contentWidth: Math.max(width, root.modelCount() * root.itemWidth)
                contentHeight: height
                visible: root.currentTab === 0

                Item {
                    id: trendContent

                    property real topTextY: 6
                    property real iconY: 28
                    property real iconSize: Math.max(46, Math.min(60, root.itemWidth * 0.46))
                    property real chartTopInset: 94
                    property real chartBottomInset: Math.max(chartTopInset + 72, height - 68)
                    property real rainTopInset: chartBottomInset + 17
                    property real rainBottomInset: height - 8

                    width: trendFlick.contentWidth
                    height: trendFlick.height

                    Canvas {
                        id: trendCanvas

                        property color primaryColor: Appearance.colors.colPrimary
                        property color pointInnerColor: Appearance.colors.colLayer4 ?? "#38363d"
                        property color textColor: Appearance.colors.colOnSurface
                        property color rainColor: "#64b5f6"
                        property real chartTop: trendContent.chartTopInset
                        property real chartBottom: trendContent.chartBottomInset

                        function pointX(index) {
                            return root.itemWidth * index + root.itemWidth / 2;
                        }

                        function yAt(value, minValue, maxValue) {
                            return chartBottom - (value - minValue) / (maxValue - minValue) * (chartBottom - chartTop);
                        }

                        anchors.fill: parent
                        antialiasing: true
                        onPrimaryColorChanged: requestPaint()
                        onTextColorChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const count = root.modelCount();
                            if (count < 2) return;

                            let values = [];
                            let rainValues = [];
                            for (let i = 0; i < count; ++i) {
                                const item = root.itemAt(i);
                                const temp = root.valueAt(item, "temperatureC", NaN);
                                values.push(temp);
                                rainValues.push(Math.max(0, root.valueAt(item, "rainMm", 0)));
                            }
                            if (root.forecastTemperatures().length === 0) return;

                            const domain = root.displayTemperatureDomain;
                            const minTemp = domain[0];
                            const maxTemp = domain[1];
                            const maxRain = WeatherChartMath.rainMaximum(rainValues);
                            const rainBandHeight = Math.max(0, trendContent.rainBottomInset - trendContent.rainTopInset - 16);

                            if (maxRain > 0) {
                                const barWidth = Math.max(7, Math.min(12, root.itemWidth * 0.16));
                                for (let r = 0; r < count; ++r) {
                                    const rain = rainValues[r];
                                    const barHeight = WeatherChartMath.rainBarHeight(rain, maxRain, rainBandHeight);
                                    if (barHeight <= 0) continue;

                                    const rainX = pointX(r);
                                    const rainY = trendContent.rainBottomInset - barHeight;
                                    ctx.fillStyle = Qt.rgba(rainColor.r, rainColor.g, rainColor.b, 0.62);
                                    ctx.beginPath();
                                    ctx.roundedRect(rainX - barWidth / 2, rainY, barWidth, barHeight, barWidth / 2, barWidth / 2);
                                    ctx.fill();
                                    ctx.fillStyle = rainColor;
                                    ctx.font = "bold 10px '" + (Appearance.font.family.numbers ?? "sans-serif") + "', sans-serif";
                                    ctx.textAlign = "center";
                                    ctx.fillText(root.fmtRain(rain), rainX, trendContent.rainTopInset + 10);
                                }
                            }

                            const areaGradient = ctx.createLinearGradient(0, chartTop, 0, chartBottom);
                            areaGradient.addColorStop(0, Qt.rgba(primaryColor.r, primaryColor.g, primaryColor.b, 0.2));
                            areaGradient.addColorStop(1, Qt.rgba(primaryColor.r, primaryColor.g, primaryColor.b, 0.02));
                            ctx.fillStyle = areaGradient;
                            ctx.beginPath();
                            ctx.moveTo(pointX(0), chartBottom);
                            for (let a = 0; a < count; ++a)
                                ctx.lineTo(pointX(a), yAt(values[a], minTemp, maxTemp));
                            ctx.lineTo(pointX(count - 1), chartBottom);
                            ctx.closePath();
                            ctx.fill();

                            ctx.strokeStyle = primaryColor;
                            ctx.lineWidth = 3;
                            ctx.lineJoin = "round";
                            ctx.lineCap = "round";
                            ctx.beginPath();
                            for (let j = 0; j < count; ++j) {
                                const x2 = pointX(j);
                                const y2 = yAt(values[j], minTemp, maxTemp);
                                if (j === 0)
                                    ctx.moveTo(x2, y2);
                                else
                                    ctx.lineTo(x2, y2);
                            }
                            ctx.stroke();

                            for (let p = 0; p < count; ++p) {
                                const px = pointX(p);
                                const py = yAt(values[p], minTemp, maxTemp);
                                ctx.fillStyle = primaryColor;
                                ctx.beginPath();
                                ctx.arc(px, py, 4.5, 0, Math.PI * 2);
                                ctx.fill();
                                ctx.fillStyle = pointInnerColor;
                                ctx.beginPath();
                                ctx.arc(px, py, 2.4, 0, Math.PI * 2);
                                ctx.fill();
                            }

                            ctx.fillStyle = textColor;
                            ctx.font = "bold 13px '" + (Appearance.font.family.numbers ?? "sans-serif") + "', sans-serif";
                            ctx.textAlign = "center";
                            for (let n = 0; n < count; ++n) {
                                ctx.fillText(root.fmtTemp(values[n]), pointX(n), yAt(values[n], minTemp, maxTemp) - 10);
                            }
                        }
                    }

                    Repeater {
                        model: root.modelCount()

                        delegate: Item {
                            property var hourItem: root.itemAt(index)

                            x: root.itemWidth * index
                            width: root.itemWidth
                            height: trendContent.height

                            StyledText {
                                width: parent.width
                                y: trendContent.topTextY
                                text: root.hourLabel(hourItem.time)
                                color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MeteoIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: trendContent.iconY
                                width: trendContent.iconSize
                                height: trendContent.iconSize
                                weatherCode: root.valueAt(hourItem, "weatherCode", -1)
                                iconName: hourItem.iconName || ""
                                night: hourItem.isDaylight === undefined ? false : !hourItem.isDaylight
                                style: "fill"
                                animated: false
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

            WeatherTemperatureNormalLine {
                z: 10
                visible: root.currentTab === 0 && !isNaN(root.normalDaytimeC)
                width: parent.width
                temperatureC: root.normalDaytimeC
                domainMinimumC: root.displayTemperatureDomain[0]
                domainMaximumC: root.displayTemperatureDomain[1]
                chartTop: trendContent.chartTopInset
                chartBottom: trendContent.chartBottomInset
                temperatureText: root.fmtTemp(root.normalDaytimeC)
                numericFontFamily: Appearance.font.family.numbers
                uiFontFamily: Appearance.font.family.main
                lineColor: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g,
                                   Appearance.colors.colOutlineVariant.b, 0.58)
                labelColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
            }

            WeatherTemperatureNormalLine {
                z: 10
                visible: root.currentTab === 0 && !isNaN(root.normalNighttimeC)
                width: parent.width
                temperatureC: root.normalNighttimeC
                domainMinimumC: root.displayTemperatureDomain[0]
                domainMaximumC: root.displayTemperatureDomain[1]
                chartTop: trendContent.chartTopInset
                chartBottom: trendContent.chartBottomInset
                temperatureText: root.fmtTemp(root.normalNighttimeC)
                numericFontFamily: Appearance.font.family.numbers
                uiFontFamily: Appearance.font.family.main
                lineColor: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g,
                                   Appearance.colors.colOutlineVariant.b, 0.58)
                labelColor: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
            }

            Item {
                anchors.fill: parent
                visible: root.currentTab === 1

                HourlyAirQualityTrendPane {
                    anchors.fill: parent
                    sourceModel: root.sourceModel
                }
            }

            Item {
                anchors.fill: parent
                visible: root.currentTab === 2

                HourlyWindTrendPane {
                    anchors.fill: parent
                    sourceModel: root.sourceModel
                }
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 3
                sourceModel: root.sourceModel
                metric: "uv"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 4
                sourceModel: root.sourceModel
                metric: "precipitation"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 5
                sourceModel: root.sourceModel
                metric: "feels"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 6
                sourceModel: root.sourceModel
                metric: "humidity"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 7
                sourceModel: root.sourceModel
                metric: "pressure"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 8
                sourceModel: root.sourceModel
                metric: "cloud"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 9
                sourceModel: root.sourceModel
                metric: "visibility"
            }
        }
    }


}
