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
    property int maxItems: 16
    property int currentTab: 0
    property bool foreground: false
    readonly property bool hasExtraTabs: true
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

    function fmtPercent(value) {
        return value !== undefined && value !== null && !isNaN(value) ? Math.round(value) + "%" : "--";
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
            const item = root.itemAt(i);
            const day = item.day || ({});
            const night = item.night || ({});
            const dayTemp = root.valueAt(day, "temperatureC", root.valueAt(item, "temperatureMaxC", NaN));
            const nightTemp = root.valueAt(night, "temperatureC", root.valueAt(item, "temperatureMinC", NaN));
            if (!isNaN(dayTemp)) values.push(dayTemp);
            if (!isNaN(nightTemp)) values.push(nightTemp);
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

    property int customTab: 2

    function tabLabel(tab) {
        switch(tab) {
            case 2: return qsTr("Wind");
            case 3: return qsTr("UV index");
            case 4: return qsTr("Precipitation");
            case 5: return qsTr("Sunshine");
            case 6: return qsTr("Feels like");
            default: return qsTr("Wind");
        }
    }

    function extraTabLabel() {
        return tabLabel(currentTab);
    }

    function applyInitialPosition() {
        if (trendFlick.initialPositionApplied) return;
        const count = root.modelCount();
        if (count < 2) {
            trendFlick.contentX = 0;
            trendFlick.initialPositionApplied = true;
            return;
        }
        const maxX = Math.max(0, trendFlick.contentWidth - trendFlick.width);
        if (maxX <= 0) {
            trendFlick.contentX = 0;
            trendFlick.initialPositionApplied = true;
            return;
        }
        trendFlick.contentX = Math.min(root.itemWidth, maxX);
        trendFlick.initialPositionApplied = true;
    }

    function dayLabel(index, epoch) {
        if (index === 0) return qsTr("Yesterday");
        if (index === 1) return qsTr("Today");
        if (index === 2) return qsTr("Tomorrow");
        if (!epoch) return "--";
        const week = [qsTr("Sun"), qsTr("Mon"), qsTr("Tue"), qsTr("Wed"), qsTr("Thu"), qsTr("Fri"), qsTr("Sat")];
        return week[new Date(epoch * 1000).getDay()];
    }

    function dateLabel(epoch) {
        return epoch ? Qt.formatDateTime(new Date(epoch * 1000), "M/d") : "--";
    }

    radius: Appearance.rounding.large ?? 24
    color: Appearance.m3colors.m3surfaceContainerLowest ?? "#0f0e0e"
    border.width: 1
    border.color: Qt.rgba(Appearance.colors.colOutlineVariant.r, Appearance.colors.colOutlineVariant.g, Appearance.colors.colOutlineVariant.b, 0.42)
    clip: true

    onSourceModelChanged: {
        trendFlick.initialPositionApplied = false;
        initialPositionTimer.restart();
        updateTemperatureDomain();
    }
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

    Timer {
        id: initialPositionTimer
        interval: 0
        repeat: false
        onTriggered: applyInitialPosition()
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
                    text: "calendar_month"
                    color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                    iconSize: 22
                    Layout.alignment: Qt.AlignVCenter
                }

                StyledText {
                    text: qsTr("Daily forecast")
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
                    id: extraTabButton
                    visible: root.hasExtraTabs
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    buttonRadius: 17
                    colBackground: (root.currentTab >= 3 || extraMenu.opened) ? Appearance.colors.colPrimaryContainer : (Appearance.colors.colSecondaryContainer ?? Appearance.m3colors.m3secondaryContainer)
                    colBackgroundHover: (root.currentTab >= 3 || extraMenu.opened) ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSecondaryContainerHover

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
                        anchorItem: extraTabButton
                        selectedValue: root.currentTab
                        options: [
                            { "value": 2, "label": qsTr("Wind"), "icon": "air" },
                            { "value": 3, "label": qsTr("UV index"), "icon": "sunny" },
                            { "value": 4, "label": qsTr("Precipitation"), "icon": "water_drop" },
                            { "value": 5, "label": qsTr("Sunshine"), "icon": "wb_sunny" },
                            { "value": 6, "label": qsTr("Feels like"), "icon": "thermostat" }
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

                property bool initialPositionApplied: false

                anchors.fill: parent
                clip: true
                interactive: root.currentTab === 0
                flickableDirection: Flickable.HorizontalFlick
                contentWidth: Math.max(width, root.modelCount() * root.itemWidth)
                contentHeight: height
                visible: root.currentTab === 0
                Component.onCompleted: initialPositionTimer.restart()
                onContentWidthChanged: initialPositionTimer.restart()
                onWidthChanged: initialPositionTimer.restart()
                onVisibleChanged: {
                    if (visible) initialPositionTimer.restart();
                }

                Item {
                    id: trendContent

                    property real columnWidth: root.itemWidth
                    property real topTextY: 8
                    property real topLabelSpacing: 2
                    property real dayIconSize: Math.max(40, Math.min(52, columnWidth * 0.40))
                    property real dayIconY: 50
                    property real highTempTextY: 96
                    property real chartTopInset: 130
                    property real chartBottomInset: Math.max(chartTopInset + 60, height - 148)
                    property real rainLabelY: chartBottomInset + 16
                    property real lowTempTextY: rainLabelY + 18
                    property real nightIconSize: dayIconSize
                    property real nightIconY: Math.max(lowTempTextY + 28, height - nightIconSize - 10)

                    width: trendFlick.contentWidth
                    height: trendFlick.height

                    Canvas {
                        id: trendCanvas

                        property color primaryColor: Appearance.colors.colPrimary
                        property color secondaryColor: Appearance.colors.colSecondary ?? "#a08cb5"
                        property real chartTop: trendContent.chartTopInset
                        property real chartBottom: trendContent.chartBottomInset

                        function pointX(index) {
                            return root.itemWidth * index + root.itemWidth / 2;
                        }

                        function yAt(value, minValue, maxValue) {
                            return chartBottom - (value - minValue) / (maxValue - minValue) * (chartBottom - chartTop);
                        }

                        function drawSeries(ctx, values, minValue, maxValue, color, lineWidth) {
                            for (let i = 1; i < values.length; ++i) {
                                const prevX = pointX(i - 1);
                                const prevY = yAt(values[i - 1], minValue, maxValue);
                                const x = pointX(i);
                                const y = yAt(values[i], minValue, maxValue);
                                const faded = i - 1 === 0 || i === 0;
                                ctx.save();
                                if (ctx.setLineDash && i === 1)
                                    ctx.setLineDash([4, 3]);

                                ctx.strokeStyle = withAlpha(color, faded ? 0.26 : 1);
                                ctx.lineWidth = lineWidth;
                                ctx.lineJoin = "round";
                                ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.moveTo(prevX, prevY);
                                ctx.lineTo(x, y);
                                ctx.stroke();
                                ctx.restore();
                            }
                        }

                        function withAlpha(color, factor) {
                            return Qt.rgba(color.r, color.g, color.b, color.a * factor);
                        }

                        function roundedRect(ctx, x, y, w, h, r) {
                            ctx.moveTo(x + r, y);
                            ctx.lineTo(x + w - r, y);
                            ctx.quadraticCurveTo(x + w, y, x + w, y + r);
                            ctx.lineTo(x + w, y + h - r);
                            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
                            ctx.lineTo(x + r, y + h);
                            ctx.quadraticCurveTo(x, y + h, x, y + h - r);
                            ctx.lineTo(x, y + r);
                            ctx.quadraticCurveTo(x, y, x + r, y);
                        }

                        anchors.fill: parent
                        antialiasing: true
                        onPrimaryColorChanged: requestPaint()
                        onSecondaryColorChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const count = root.modelCount();
                            if (count < 2) return;

                            let dayValues = [];
                            let nightValues = [];
                            let precipitationValues = [];
                            for (let i = 0; i < count; ++i) {
                                const item = root.itemAt(i);
                                const day = item.day || ({});
                                const night = item.night || ({});
                                const dayTemp = root.valueAt(day, "temperatureC", root.valueAt(item, "temperatureMaxC", NaN));
                                const nightTemp = root.valueAt(night, "temperatureC", root.valueAt(item, "temperatureMinC", NaN));
                                const pop = Math.max(root.valueAt(day, "precipitationProbability", 0),
                                                     root.valueAt(night, "precipitationProbability", 0));
                                dayValues.push(dayTemp);
                                nightValues.push(nightTemp);
                                precipitationValues.push(pop);
                            }
                            if (root.forecastTemperatures().length === 0) return;

                            const domain = root.displayTemperatureDomain;
                            const minTemp = domain[0];
                            const maxTemp = domain[1];
                            ctx.beginPath();
                            for (let f = 0; f < count; ++f) {
                                const xFill = pointX(f);
                                const yFill = yAt(dayValues[f], minTemp, maxTemp);
                                if (f === 0)
                                    ctx.moveTo(xFill, yFill);
                                else
                                    ctx.lineTo(xFill, yFill);
                            }
                            for (let r = count - 1; r >= 0; --r) {
                                ctx.lineTo(pointX(r), yAt(nightValues[r], minTemp, maxTemp));
                            }
                            ctx.closePath();
                            const fillGradient = ctx.createLinearGradient(0, chartTop, 0, chartBottom);
                            fillGradient.addColorStop(0, "rgba(" + Math.round(primaryColor.r * 255) + "," + Math.round(
                                                          primaryColor.g * 255) + "," + Math.round(
                                                          primaryColor.b * 255) + ",0.12)");
                            fillGradient.addColorStop(1, "rgba(" + Math.round(primaryColor.r * 255) + "," + Math.round(
                                                          primaryColor.g * 255) + "," + Math.round(
                                                          primaryColor.b * 255) + ",0.02)");
                            ctx.fillStyle = fillGradient;
                            ctx.fill();

                            for (let p = 0; p < count; ++p) {
                                const popValue = precipitationValues[p];
                                if (popValue <= 0) continue;

                                const x = pointX(p);
                                const fadedBar = p === 0;
                                const barTop = chartBottom - (chartBottom - chartTop) * Math.min(100, popValue) / 100;
                                ctx.fillStyle = fadedBar ? Qt.rgba(secondaryColor.r, secondaryColor.g,
                                                                   secondaryColor.b, 0.1) : Qt.rgba(
                                                               secondaryColor.r, secondaryColor.g,
                                                               secondaryColor.b, 0.18);
                                ctx.beginPath();
                                roundedRect(ctx, x - 5, barTop, 10, chartBottom - barTop, 5);
                                ctx.fill();
                                ctx.fillStyle = fadedBar ? Qt.rgba(primaryColor.r, primaryColor.g,
                                                                   primaryColor.b, 0.42) : primaryColor;
                                ctx.font = "bold 11px '" + (Appearance.font.family.numbers ?? "sans-serif") + "', sans-serif";
                                ctx.textAlign = "center";
                                ctx.fillText(root.fmtPercent(popValue), x, trendContent.rainLabelY);
                            }
                            drawSeries(ctx, dayValues, minTemp, maxTemp, primaryColor, 4);
                            drawSeries(ctx, nightValues, minTemp, maxTemp, secondaryColor, 4);
                        }
                    }

                    Repeater {
                        model: root.modelCount()

                        delegate: Item {
                            property var dayItem: root.itemAt(index)
                            property var dayPart: dayItem.day || ({})
                            property var nightPart: dayItem.night || ({})

                            x: root.itemWidth * index
                            width: root.itemWidth
                            height: trendContent.height
                            opacity: index === 0 ? 0.45 : 1

                            Column {
                                y: trendContent.topTextY
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                spacing: trendContent.topLabelSpacing

                                StyledText {
                                    width: parent.width
                                    text: root.dayLabel(index, dayItem.time)
                                    color: Appearance.colors.colOnSurface
                                    font.pixelSize: 16
                                    font.bold: index === 1
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.dateLabel(dayItem.time)
                                    color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                                    font.pixelSize: 13
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            MeteoIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: trendContent.dayIconY
                                width: trendContent.dayIconSize
                                height: trendContent.dayIconSize
                                weatherCode: root.valueAt(dayPart, "weatherCode", -1)
                                iconName: dayPart.iconName || ""
                                night: false
                                style: "fill"
                                animated: false
                            }

                            StyledText {
                                width: parent.width
                                y: trendContent.highTempTextY
                                text: root.fmtTemp(root.valueAt(dayPart, "temperatureC", root.valueAt(dayItem, "temperatureMaxC", NaN)))
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: 19
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            StyledText {
                                width: parent.width
                                y: trendContent.lowTempTextY
                                text: root.fmtTemp(root.valueAt(nightPart, "temperatureC", root.valueAt(dayItem, "temperatureMinC", NaN)))
                                color: Appearance.colors.colOnSurfaceVariant ?? Appearance.m3colors.m3onSurfaceVariant
                                font.pixelSize: 18
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MeteoIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: trendContent.nightIconY
                                width: trendContent.nightIconSize
                                height: trendContent.nightIconSize
                                weatherCode: root.valueAt(nightPart, "weatherCode", -1)
                                iconName: nightPart.iconName || ""
                                night: true
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

                DailyAirQualityTrendPane {
                    anchors.fill: parent
                    sourceModel: root.sourceModel
                }
            }

            Item {
                anchors.fill: parent
                visible: root.currentTab === 2

                DailyWindTrendPane {
                    anchors.fill: parent
                    sourceModel: root.sourceModel
                }
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 3
                sourceModel: root.sourceModel
                daily: true
                metric: "uv"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 4
                sourceModel: root.sourceModel
                daily: true
                metric: "precipitation"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 5
                sourceModel: root.sourceModel
                daily: true
                metric: "sunshine"
            }

            WeatherMetricTrendPane {
                anchors.fill: parent
                visible: root.currentTab === 6
                sourceModel: root.sourceModel
                daily: true
                metric: "feels"
            }
        }
    }


}
