import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property bool foreground: true
    property bool presentationActive: true
    property bool isExtended: false
    property bool isResizing: false
    property bool dailyForecastPanelEnabled: true
    property bool hourlyForecastPanelEnabled: true
    readonly property var weatherSource: Weather

    onPresentationActiveChanged: {
        if (root.presentationActive && !root.weatherSource.loading && (root.weatherSource.status === "stale" || root.weatherSource.status === "idle" || root.weatherSource.status === "error")) {
            root.weatherSource.refresh();
        }
    }

    property int contentMargin: 16
    property int headerHeight: 62
    property bool lightHeaderPalette: currentIsNight() || (Appearance.m3colors.darkmode ?? true)
    property color headerInk: lightHeaderPalette ? Qt.rgba(0.96, 0.98, 1, 0.94) : Qt.rgba(0.09, 0.14, 0.2, 0.88)
    property color headerInkMuted: lightHeaderPalette ? Qt.rgba(0.87, 0.91, 0.98, 0.76) : Qt.rgba(0.2, 0.28, 0.38, 0.62)
    property color headerErrorInk: lightHeaderPalette ? Qt.rgba(1, 0.79, 0.82, 0.96) : Qt.rgba(0.62, 0.14, 0.18, 0.88)
    property real currentEpoch: Math.floor(Date.now() / 1000)

    function validNumber(value) {
        return value !== undefined && value !== null && !isNaN(value);
    }

    function modelCount(model) {
        if (!model) return 0;
        return typeof model.count === "function" ? model.count() : Number(model.count || 0);
    }

    function fmtTemp(value) {
        if (!validNumber(value)) return "--";
        const temp = Weather.useUSCS ? Math.round(value * 9 / 5 + 32) : Math.round(value);
        return temp + "°";
    }

    function fmtTempPlain(value) {
        if (!validNumber(value)) return "--";
        const temp = Weather.useUSCS ? Math.round(value * 9 / 5 + 32) : Math.round(value);
        return temp.toString();
    }

    function fmtTime(epoch) {
        if (!epoch) return "--";
        const d = new Date(epoch * 1000);
        const h = d.getHours();
        const m = d.getMinutes().toString().padStart(2, "0");
        if (DateTime.use12HourFormat) {
            const h12 = (h % 12 === 0) ? 12 : h % 12;
            const ampm = h >= 12 ? "PM" : "AM";
            return `${h12}:${m} ${ampm}`;
        }
        return `${h.toString().padStart(2, "0")}:${m}`;
    }

    function fmtSpeed(ms) {
        return validNumber(ms) ? ms.toFixed(1) + " m/s" : "--";
    }

    function fmtPercent(value) {
        return validNumber(value) ? Math.round(value) + "%" : "--";
    }

    function currentHour() {
        return new Date(root.currentEpoch * 1000).getHours();
    }

    function updatedText() {
        if (root.weatherSource.loading)
            return qsTr("Refreshing");
        if (root.weatherSource.status === "fresh" || root.weatherSource.status === "partial") {
            const d = new Date(root.weatherSource.lastUpdated || Date.now());
            return qsTr("Updated ") + root.fmtTime(Math.floor(d.getTime() / 1000));
        }
        if (root.weatherSource.status === "stale")
            return qsTr("Data is old");
        if (root.weatherSource.status === "error")
            return qsTr("Update failed");

        return qsTr("Updated recently");
    }

    function uvLevel(value) {
        if (!validNumber(value)) return "--";
        if (value < 3) return qsTr("Low");
        if (value < 6) return qsTr("Moderate");
        if (value < 8) return qsTr("High");
        if (value < 11) return qsTr("Very high");
        return qsTr("Extreme");
    }

    function uvIndexBucket(value) {
        if (!validNumber(value)) return -1;
        if (value < 3) return 0;
        if (value < 6) return 1;
        if (value < 8) return 2;
        if (value < 11) return 3;
        return 4;
    }

    function windAccent(ms) {
        if (!validNumber(ms)) return "#4d8d7b";
        if (ms < 4) return "#72d572";
        if (ms < 6) return "#ffca28";
        if (ms < 8) return "#ffa726";
        if (ms < 10) return "#e52f35";
        if (ms < 12) return "#99004c";
        return "#7e0023";
    }

    function directionLabel(degree) {
        if (!validNumber(degree)) return "--";
        const normalized = ((degree % 360) + 360) % 360;
        if (normalized < 22.5 || normalized >= 337.5) return "N";
        if (normalized < 67.5) return "NE";
        if (normalized < 112.5) return "E";
        if (normalized < 157.5) return "SE";
        if (normalized < 202.5) return "S";
        if (normalized < 247.5) return "SW";
        if (normalized < 292.5) return "W";
        return "NW";
    }

    function activeHalfDay() {
        const day = today();
        const hour = currentHour();
        if (hour < 5) return day.night || ({});
        if (hour < 17) return day.day || ({});
        return day.night || ({});
    }

    function precipitationValueText() {
        const half = activeHalfDay();
        const snow = validNumber(half.snowCm) ? half.snowCm : 0;
        const rain = validNumber(half.rainMm) ? half.rainMm : 0;
        const total = validNumber(half.precipitationMm) ? half.precipitationMm : NaN;
        if (snow > 0 && rain <= 0)
            return snow.toFixed(1) + " cm";

        return validNumber(total) ? total.toFixed(1) + " mm" : "--";
    }

    function precipitationDescriptionText() {
        const half = activeHalfDay();
        const snow = validNumber(half.snowCm) ? half.snowCm : 0;
        const rain = validNumber(half.rainMm) ? half.rainMm : 0;
        const hour = currentHour();
        const isDay = hour >= 5 && hour < 17;
        if (snow > 0 && rain <= 0)
            return isDay ? qsTr("Total daytime snowfall") : qsTr("Total nighttime snowfall");
        if (rain > 0 && snow <= 0)
            return isDay ? qsTr("Total daytime rainfall") : qsTr("Total nighttime rainfall");
        if (snow > 0 && rain > 0)
            return isDay ? qsTr("Total daytime precipitation") : qsTr("Total nighttime precipitation");

        return isDay ? qsTr("Total daytime precipitation") : qsTr("Total nighttime precipitation");
    }

    function aqiThresholds() {
        return [0, 20, 50, 100, 150, 250];
    }

    function pollutantIndex(value, thresholds) {
        if (!validNumber(value)) return NaN;
        let level = -1;
        for (let i = 0; i < thresholds.length; ++i) {
            if (value >= thresholds[i]) level = i;
        }
        if (level < 0) return NaN;

        const aqi = aqiThresholds();
        if (level < thresholds.length - 1) {
            const bpLo = thresholds[level];
            const bpHi = thresholds[level + 1];
            const inLo = aqi[level];
            const inHi = aqi[level + 1];
            return Math.round(((inHi - inLo) / (bpHi - bpLo)) * (value - bpLo) + inLo);
        }
        return Math.round((value * aqi[aqi.length - 1]) / thresholds[thresholds.length - 1]);
    }

    function aqiLevelIndex(value) {
        if (!validNumber(value)) return -1;
        const thresholds = aqiThresholds();
        let level = 0;
        for (let i = 0; i < thresholds.length; ++i) {
            if (value >= thresholds[i]) level = i;
        }
        return Math.min(level, 5);
    }

    function aqiPalette(level) {
        const colors = ["#00e59b", "#ffc302", "#ff712b", "#f62a55", "#c72eaa", "#9930ff"];
        return colors[Math.max(0, Math.min(colors.length - 1, level))];
    }

    function aqiLevelName(level) {
        const names = [qsTr("Excellent"), qsTr("Good"), qsTr("Poor"), qsTr("Unhealthy"), qsTr("Very unhealthy"), qsTr("Hazardous")];
        if (level < 0 || level >= names.length) return "--";
        return names[level];
    }

    function aqiSummary() {
        const air = root.weatherSource.currentAirQuality || ({});
        const values = [pollutantIndex(air.ozone, [0, 50, 100, 160, 240, 480]), 
                        pollutantIndex(air.nitrogenDioxide, [0, 10, 25, 200, 400, 1000]),
                        pollutantIndex(air.pm10, [0, 15, 45, 80, 160, 400]), 
                        pollutantIndex(air.pm2_5 || air.pm25, [0, 5, 15, 30, 60, 150])].filter(validNumber);
        if (values.length === 0)
            return { "value": NaN, "level": "--", "color": "#00e59b" };

        const value = Math.max.apply(Math, values);
        const level = aqiLevelIndex(value);
        return { "value": value, "level": aqiLevelName(level), "color": aqiPalette(level) };
    }

    function pressureValueText(value) {
        return validNumber(value) ? Math.round(value).toString() : "--";
    }

    function today() {
        const count = modelCount(root.weatherSource.dailyForecast);
        if (count <= 0) return ({});
        const todayStr = new Date().toDateString();
        for (let i = 0; i < count; ++i) {
            const item = root.weatherSource.dailyForecast.get(i);
            if (item && item.time) {
                if (new Date(item.time * 1000).toDateString() === todayStr) {
                    return item;
                }
            }
        }
        return root.weatherSource.dailyForecast.get(0);
    }

    function currentIsNight() {
        const day = today();
        const sunrise = day.sunrise || 0;
        const sunset = day.sunset || 0;
        if (sunrise > 0 && sunset > 0) {
            const now = Math.floor(root.currentEpoch);
            return now < sunrise || now >= sunset;
        }
        const name = (root.weatherSource.currentIconName || "").toLowerCase();
        if (name.indexOf("night") >= 0 || name.indexOf("_night") >= 0) return true;
        if (name.indexOf("day") >= 0 || name.indexOf("_day") >= 0) return false;
        const h = currentHour();
        return h < 6 || h >= 18;
    }

    Timer {
        interval: 60000
        running: root.foreground
        repeat: true
        onTriggered: root.currentEpoch = Math.floor(Date.now() / 1000)
    }

    Rectangle {
        id: weatherPanel

        anchors.fill: parent
        radius: Appearance.rounding.screenRounding ?? 24
        clip: true
        color: "transparent"

        Item {
            id: weatherBackgroundClip
            anchors.fill: parent
            layer.enabled: true

            WeatherBackground {
                id: weatherBackground
                anchors.fill: parent
                weatherCode: root.weatherSource.currentWeatherCode
                iconName: root.weatherSource.currentIconName
                windSpeedMs: root.weatherSource.currentWindSpeedMs
                windGustsMs: root.weatherSource.currentWindGustsMs
                night: root.currentIsNight()
                rainBounceY: flick.y + dailyForecastLoader.y - flick.contentY
                scrollProgress: Math.max(0, Math.min(1, flick.contentY / 340))
                animate: root.presentationActive && !root.isResizing
                suspended: root.isResizing
            }

            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: weatherPanel.width
                    height: weatherPanel.height
                    radius: weatherPanel.radius
                }
            }
        }

        Rectangle {
            id: fixedHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.headerHeight + root.contentMargin
            color: "transparent"
            border.width: 0

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: root.contentMargin
                anchors.topMargin: root.contentMargin
                height: root.headerHeight
                spacing: 5

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        MaterialSymbol {
                            text: "location_on"
                            color: root.headerInkMuted
                            iconSize: 20
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Text {
                            text: root.weatherSource.locationName || qsTr("Weather")
                            color: root.headerInk
                            font.family: Appearance.font.family.main
                            font.pixelSize: 18
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: refreshMouse.containsMouse ? (Appearance.colors.colLayer1Hover ?? "#2a292f") : "transparent"

                        Item {
                            id: refreshIconContainer
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            layer.enabled: root.weatherSource.loading

                            MaterialSymbol {
                                id: refreshIcon
                                anchors.centerIn: parent
                                text: "refresh"
                                iconSize: 20
                                color: root.headerInk
                                opacity: root.weatherSource.loading ? 0.75 : 1
                            }

                            RotationAnimation on rotation {
                                running: root.weatherSource.loading
                                from: 0
                                to: 360
                                loops: Animation.Infinite
                                duration: 850
                                direction: RotationAnimation.Clockwise
                            }
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.weatherSource.loading ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: {
                                if (!root.weatherSource.loading) {
                                    root.weatherSource.refresh();
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7

                    MaterialSymbol {
                        text: "schedule"
                        color: root.weatherSource.status === "stale" || root.weatherSource.status === "error"
                               ? root.headerErrorInk : root.headerInkMuted
                        iconSize: 16
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: updatedText()
                        color: root.weatherSource.status === "stale" || root.weatherSource.status === "error"
                               ? root.headerErrorInk : root.headerInk
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        StyledFlickable {
            id: flick

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: fixedHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.contentMargin
            anchors.rightMargin: root.contentMargin
            anchors.bottomMargin: root.contentMargin
            contentWidth: width
            contentHeight: contentColumn.implicitHeight + 16
            clip: true

            Column {
                id: contentColumn
                width: flick.width
                spacing: 14

                Item {
                    id: currentSummary
                    width: parent.width
                    height: 300

                    Column {
                        id: currentConditionsColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            width: parent.width
                            text: root.weatherSource.currentWeatherText || qsTr("Unknown")
                            color: Appearance.colors.colOnImage ?? "#ffffff"
                            font.family: Appearance.font.family.main
                            font.pixelSize: 24
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Item {
                            id: currentVisual
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: tempText.implicitWidth + weatherHeroIcon.width + 8
                            height: Math.max(tempText.implicitHeight, weatherHeroIcon.height + 12)

                            Text {
                                id: tempText
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                text: fmtTempPlain(root.weatherSource.currentTemperatureC)
                                color: Appearance.colors.colOnImage ?? "#ffffff"
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: root.isExtended ? 108 : 92
                                font.bold: true
                            }

                            MeteoIcon {
                                id: weatherHeroIcon
                                width: root.isExtended ? 92 : 80
                                height: width
                                anchors.right: parent.right
                                anchors.top: parent.top
                                weatherCode: root.weatherSource.currentWeatherCode
                                iconName: root.weatherSource.currentIconName
                                night: root.currentIsNight()
                                style: "fill"
                                animated: true
                            }
                        }

                        Text {
                            width: parent.width
                            text: qsTr("Feels like: ") + fmtTemp(root.weatherSource.currentFeelsLikeC)
                            color: Appearance.colors.colOnImage ?? "#ffffff"
                            font.family: Appearance.font.family.main
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: qsTr("High ") + fmtTemp(today().tempMaxC || today().temperatureMaxC) + qsTr(" · Low ") + fmtTemp(today().tempMinC || today().temperatureMinC)
                            color: Appearance.colors.colOnImageMuted ?? Qt.rgba(1, 1, 1, 0.85)
                            font.family: Appearance.font.family.main
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }

                Loader {
                    id: dailyForecastLoader
                    width: parent.width
                    height: active ? 452 : 0
                    active: root.dailyForecastPanelEnabled
                    sourceComponent: Component {
                        DailyForecastTrendCard {
                            anchors.fill: parent
                            sourceModel: root.weatherSource.dailyTrendForecast
                            normalsSource: root.weatherSource
                            foreground: root.presentationActive && dailyForecastLoader.y + dailyForecastLoader.height >= flick.contentY && dailyForecastLoader.y <= flick.contentY + flick.height
                            resizeActive: root.isResizing
                        }
                    }
                }

                Loader {
                    id: hourlyForecastLoader
                    width: parent.width
                    height: active ? 340 : 0
                    active: root.hourlyForecastPanelEnabled
                    sourceComponent: Component {
                        HourlyForecastTrendCard {
                            anchors.fill: parent
                            sourceModel: root.weatherSource.hourlyForecast
                            normalsSource: root.weatherSource
                            foreground: root.presentationActive && hourlyForecastLoader.y + hourlyForecastLoader.height >= flick.contentY && hourlyForecastLoader.y <= flick.contentY + flick.height
                            resizeActive: root.isResizing
                        }
                    }
                }

                WeatherRadarCard {
                    width: parent.width
                    presentationActive: root.presentationActive
                }

                Item {
                    id: metricCardsGrid
                    width: parent.width

                    readonly property int cardCount: 9
                    readonly property int targetColumns: root.isExtended ? 3 : 2
                    readonly property real spacing: 10
                    readonly property real availableWidth: {
                        const margins = Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin + (root.contentMargin * 2) + 20;
                        return root.isExtended 
                            ? (Appearance.sizes.sidebarWidthExtended - margins)
                            : (Appearance.sizes.sidebarWidth - margins);
                    }
                    readonly property real targetCardWidth: Math.floor((availableWidth - (targetColumns - 1) * spacing) / targetColumns)
                    readonly property real targetCardHeight: targetCardWidth

                    function cardX(index) {
                        const col = index % targetColumns;
                        return col * (targetCardWidth + spacing);
                    }

                    function cardY(index) {
                        const row = Math.floor(index / targetColumns);
                        return row * (targetCardHeight + spacing);
                    }

                    implicitHeight: {
                        const rows = Math.ceil(cardCount / targetColumns);
                        return (rows * targetCardHeight) + ((rows - 1) * spacing);
                    }

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                    }

                    WeatherRevealCard {
                        id: precipitationReveal
                        x: metricCardsGrid.cardX(0)
                        y: metricCardsGrid.cardY(0)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 0

                        WeatherPrecipitationCard {
                            anchors.fill: parent
                            valueText: precipitationValueText()
                            descriptionText: precipitationDescriptionText()
                            animationEnabled: true
                            animationActive: precipitationReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: windReveal
                        x: metricCardsGrid.cardX(1)
                        y: metricCardsGrid.cardY(1)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 1

                        WeatherWindCard {
                            anchors.fill: parent
                            directionDegrees: root.weatherSource.currentWindDirection
                            valueText: fmtSpeed(root.weatherSource.currentWindSpeedMs)
                            detailText: qsTr("Gusts ") + fmtSpeed(root.weatherSource.currentWindGustsMs) + " · " + directionLabel(root.weatherSource.currentWindDirection)
                            accent: windAccent(root.weatherSource.currentWindSpeedMs)
                            animationEnabled: true
                            animationActive: windReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: aqiReveal
                        x: metricCardsGrid.cardX(2)
                        y: metricCardsGrid.cardY(2)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 2

                        WeatherAqiCard {
                            anchors.fill: parent
                            aqiValue: aqiSummary().value
                            levelText: aqiSummary().level
                            accent: aqiSummary().color
                            animationEnabled: true
                            animationActive: aqiReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: humidityReveal
                        x: metricCardsGrid.cardX(3)
                        y: metricCardsGrid.cardY(3)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 0

                        WeatherHumidityCard {
                            anchors.fill: parent
                            humidityValue: root.weatherSource.currentRelativeHumidity
                            humidityText: fmtPercent(root.weatherSource.currentRelativeHumidity)
                            dewPointText: fmtTemp(root.weatherSource.currentDewPointC)
                            accent: "#625985"
                            animationEnabled: true
                            animationActive: humidityReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: uvReveal
                        x: metricCardsGrid.cardX(4)
                        y: metricCardsGrid.cardY(4)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 1

                        WeatherBlob {
                            anchors.fill: parent
                            title: qsTr("UV index")
                            value: root.weatherSource.currentUvIndex
                            level: uvLevel(root.weatherSource.currentUvIndex)
                            activeIndex: uvIndexBucket(root.weatherSource.currentUvIndex)
                            animationEnabled: true
                            animationActive: uvReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: visibilityReveal
                        x: metricCardsGrid.cardX(5)
                        y: metricCardsGrid.cardY(5)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 2

                        WeatherVisibilityCard {
                            anchors.fill: parent
                            visibilityMeters: root.weatherSource.currentVisibilityM
                            animationEnabled: true
                            animationActive: visibilityReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: sunReveal
                        x: metricCardsGrid.cardX(6)
                        y: metricCardsGrid.cardY(6)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 0

                        WeatherAstroCard {
                            anchors.fill: parent
                            moon: false
                            riseText: fmtTime(today().sunrise)
                            setText: fmtTime(today().sunset)
                            riseEpoch: today().sunrise || 0
                            setEpoch: today().sunset || 0
                            currentEpoch: root.currentEpoch
                            animationEnabled: true
                            animationActive: sunReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: pressureReveal
                        x: metricCardsGrid.cardX(7)
                        y: metricCardsGrid.cardY(7)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 1

                        WeatherPressureCard {
                            anchors.fill: parent
                            pressureValue: root.weatherSource.currentPressureHpa
                            valueText: pressureValueText(root.weatherSource.currentPressureHpa)
                            unitText: "hPa"
                            animationEnabled: true
                            animationActive: pressureReveal.contentAnimationActive
                        }
                    }

                    WeatherRevealCard {
                        id: moonReveal
                        x: metricCardsGrid.cardX(8)
                        y: metricCardsGrid.cardY(8)
                        width: metricCardsGrid.targetCardWidth
                        height: metricCardsGrid.targetCardHeight
                        contentTop: metricCardsGrid.y + y
                        viewportContentY: flick.contentY
                        viewportHeight: flick.height
                        activationEnabled: root.presentationActive
                        staggerIndex: 2

                        WeatherAstroCard {
                            anchors.fill: parent
                            moon: true
                            riseText: fmtTime(today().moonrise)
                            setText: fmtTime(today().moonset)
                            riseEpoch: today().moonrise || 0
                            setEpoch: today().moonset || 0
                            currentEpoch: root.currentEpoch
                            phaseAngle: today().moonPhaseAngle || 0
                            animationEnabled: true
                            animationActive: moonReveal.contentAnimationActive
                        }
                    }
                }

                Item {
                    width: 1
                    height: 20
                }
            }
        }
    }
}
