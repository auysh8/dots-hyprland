import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property int weatherCode: -1
    property string iconName: ""
    property bool night: false
    property string style: "fill"
    property bool smooth: true
    property bool animated: false
    property bool playing: visible
    property real baseSize: 128
    property color color: Appearance.colors.colOnSurface

    readonly property string resolvedSlug: iconSlug()
    readonly property url svgSource: Qt.resolvedUrl("../../../../assets/icons/weather/meteocons/svg/" + normalizedStyle() + "/" + resolvedSlug + ".svg")

    function normalizedStyle() {
        if (style === "fill" || style === "line" || style === "monochrome" || style === "flat") return style;
        return "fill";
    }

    function slugForCode(code, isNight) {
        if (code === 0) return isNight ? "clear-night" : "clear-day";
        if (code === 1) return isNight ? "mostly-clear-night" : "mostly-clear-day";
        if (code === 2) return isNight ? "partly-cloudy-night" : "partly-cloudy-day";
        if (code === 3) return "cloudy";
        if (code === 45 || code === 48) return isNight ? "fog-night" : "fog-day";
        if (code >= 51 && code <= 57) return "drizzle";
        if (code === 61 || code === 63 || code === 65) return isNight ? "overcast-night-rain" : "overcast-day-rain";
        if (code === 66 || code === 67) return isNight ? "overcast-night-sleet" : "overcast-day-sleet";
        if (code >= 71 && code <= 77) return isNight ? "overcast-night-snow" : "overcast-day-snow";
        if (code >= 80 && code <= 82) return isNight ? "partly-cloudy-night-rain" : "partly-cloudy-day-rain";
        if (code === 85 || code === 86) return isNight ? "partly-cloudy-night-snow" : "partly-cloudy-day-snow";
        if (code === 95) return isNight ? "thunderstorms-night" : "thunderstorms-day";
        if (code === 96 || code === 99) return isNight ? "thunderstorms-night-hail" : "thunderstorms-day-hail";
        return "not-available";
    }

    function slugFromName(name, isNight) {
        if (!name || name.length === 0) return "";
        if (name.indexOf("clear_night") >= 0) return "clear-night";
        if (name.indexOf("sun") >= 0) return "clear-day";
        if (name.indexOf("partly") >= 0) return isNight ? "partly-cloudy-night" : "partly-cloudy-day";
        if (name.indexOf("cloud") >= 0) return "cloudy";
        if (name.indexOf("fog") >= 0) return isNight ? "fog-night" : "fog-day";
        if (name.indexOf("drizzle") >= 0) return "drizzle";
        if (name.indexOf("rain") >= 0) return isNight ? "overcast-night-rain" : "overcast-day-rain";
        if (name.indexOf("snow") >= 0) return isNight ? "overcast-night-snow" : "overcast-day-snow";
        if (name.indexOf("thunder") >= 0) return isNight ? "thunderstorms-night" : "thunderstorms-day";
        return "";
    }

    function iconSlug() {
        const byCode = slugForCode(weatherCode, night);
        if (byCode !== "not-available") return byCode;
        const byName = slugFromName(iconName, night);
        return byName.length > 0 ? byName : "not-available";
    }

    function symbolForCode(code, isNight) {
        if (code === 0) return isNight ? "bedtime" : "wb_sunny";
        if (code === 1 || code === 2) return isNight ? "nights_stay" : "partly_cloudy_day";
        if (code === 3) return "cloud";
        if (code === 45 || code === 48) return "foggy";
        if (code >= 51 && code <= 57) return "rainy";
        if (code >= 61 && code <= 67) return "rainy";
        if (code >= 71 && code <= 77) return isNight ? "cloudy_snowing" : "weather_snowy";
        if (code >= 80 && code <= 82) return "rainy";
        if (code === 85 || code === 86) return "snowing_heavy";
        if (code >= 95) return "thunderstorm";

        if (weatherCode < 0 && iconName && iconName.length > 0) {
            if (iconName.indexOf("clear_night") >= 0) return "bedtime";
            if (iconName.indexOf("sun") >= 0) return "wb_sunny";
            if (iconName.indexOf("partly") >= 0) return isNight ? "nights_stay" : "partly_cloudy_day";
            if (iconName.indexOf("cloud") >= 0) return "cloud";
            if (iconName.indexOf("fog") >= 0) return "foggy";
            if (iconName.indexOf("rain") >= 0) return "rainy";
            if (iconName.indexOf("snow") >= 0) return "weather_snowy";
            if (iconName.indexOf("thunder") >= 0) return "thunderstorm";
        }

        const wCode = Weather.wmoToWwo(code);
        const mapped = Icons.getWeatherIcon(wCode);
        return mapped || (isNight ? "bedtime" : "wb_sunny");
    }

    readonly property string iconSymbol: symbolForCode(weatherCode, night)

    Image {
        id: svgImage
        anchors.fill: parent
        visible: status === Image.Ready
        source: root.svgSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: root.smooth
        mipmap: true
        sourceSize.width: 128
        sourceSize.height: 128

        property bool hasEverLoaded: false
        onStatusChanged: {
            if (status === Image.Ready)
                hasEverLoaded = true;
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: svgImage.status === Image.Error || (!svgImage.hasEverLoaded && svgImage.status !== Image.Ready)
        iconSize: Math.min(root.width, root.height)
        text: root.iconSymbol
        color: root.color
        fill: (root.style === "fill" || root.style === "solid") ? 1 : 0
    }
}
