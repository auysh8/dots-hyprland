pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

import qs.modules.common

Singleton {
    id: root

    property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000

    // Rescheduled without re-firing. The timer starts on its own, so restarting
    // it here would put a request behind every step of the interval spin box.
    onFetchIntervalChanged: refreshTimer.interval = root.fetchInterval

    readonly property bool gps: Config.options.bar.weather.enableGPS
    readonly property string pinnedCity: Config.options.bar.weather.city.trim()

    // A typed city is what this follows when the lookup is switched off. Off
    // with nothing typed has named no place at all, so the looked up one still
    // stands rather than leaving the weather with nowhere to be.
    readonly property bool usePinned: !root.gps && root.pinnedCity.length > 0

    property real pinnedLat: 0
    property real pinnedLon: 0
    property string pinnedName: ""
    property string pinnedCountry: ""
    property bool pinnedValid: false

    readonly property bool locationValid: root.usePinned ? root.pinnedValid : Location.known
    readonly property real latitude: root.usePinned ? root.pinnedLat : Location.latitude
    readonly property real longitude: root.usePinned ? root.pinnedLon : Location.longitude
    readonly property string cityName: root.usePinned ? root.pinnedName : Location.city
    readonly property string countryCode: root.usePinned ? root.pinnedCountry : Location.countryCode

    // The reply that produced what is on screen, kept so that a change of unit
    // is a re-read of what is already here. Asking again would put a round trip
    // behind every change of mind and would leave the choice dead with no
    // network.
    property var lastReply: null

    // Resolved on every read rather than written into the settings file, so a
    // location landing after login writes nothing. "auto" is the shipped value
    // and means no unit has been named; naming one puts it in the file and this
    // last branch is never reached again.
    readonly property bool useUSCS: Config.options.bar.weather.units === "uscs" ? true : Config.options.bar.weather.units === "metric" ? false : Location.usesFahrenheit(root.countryCode)

    // One key for the whole position, so a coordinate pair arriving as two
    // assignments asks for one fetch rather than two.
    readonly property string fetchKey: root.locationValid ? `${root.latitude},${root.longitude}` : ""
    onFetchKeyChanged: if (root.fetchKey.length > 0) {
        root.getData();
    }

    // Status and state flags
    property bool loading: false
    property string status: "idle" // "idle", "loading", "fresh", "stale", "error"
    property string errorMessage: ""
    property string lastUpdated: ""
    readonly property alias locationName: root.cityName
    readonly property alias hasManualLocation: root.usePinned

    // Rich current conditions (matching Clavis WeatherPlugin properties)
    property double currentTemperatureC: 0.0
    property double currentFeelsLikeC: 0.0
    property int currentWeatherCode: -1
    property string currentWeatherText: "Unknown"
    property string currentIconName: "cloud"
    property double currentWindSpeedMs: 0.0
    property double currentWindDirection: 0.0
    property double currentWindGustsMs: 0.0
    property double currentUvIndex: 0.0
    property double currentRelativeHumidity: 0.0
    property double currentDewPointC: 0.0
    property double currentPressureHpa: 0.0
    property double currentCloudCover: 0.0
    property double currentVisibilityM: 0.0
    property var currentAirQuality: ({})
    property var airQuality: ({})
    property var detailedCurrent: ({})

    // Models for views & charts (with .get(i) and .count support)
    property var hourlyForecast: []
    property var dailyForecast: []
    property var dailyTrendForecast: []

    property var lastAqiReply: null

    readonly property bool normalsAvailable: true
    signal normalsChanged()

    function normalDaytimeTemperatureC(month) {
        if (root.dailyForecast && root.dailyForecast.length > 0) {
            let sum = 0, count = 0;
            for (let i = 0; i < root.dailyForecast.length; ++i) {
                const item = root.dailyForecast.get(i);
                if (item && item.temperatureMaxC !== undefined && !isNaN(item.temperatureMaxC)) {
                    sum += item.temperatureMaxC;
                    count++;
                }
            }
            if (count > 0) return Math.round(sum / count);
        }
        return root.currentTemperatureC || 20;
    }

    function normalNighttimeTemperatureC(month) {
        if (root.dailyForecast && root.dailyForecast.length > 0) {
            let sum = 0, count = 0;
            for (let i = 0; i < root.dailyForecast.length; ++i) {
                const item = root.dailyForecast.get(i);
                if (item && item.temperatureMinC !== undefined && !isNaN(item.temperatureMinC)) {
                    sum += item.temperatureMinC;
                    count++;
                }
            }
            if (count > 0) return Math.round(sum / count);
        }
        return (root.currentTemperatureC ? root.currentTemperatureC - 8 : 12);
    }

    function refresh() {
        root.getData();
    }

    function makeModel(arr) {
        if (!arr) arr = [];
        Object.defineProperty(arr, "count", {
            get: function() { return this.length; },
            configurable: true
        });
        arr.get = function(idx) {
            return this[idx] || ({});
        };
        return arr;
    }

    function weatherText(code) {
        switch (code) {
        case 0: return "Clear";
        case 1: return "Mainly clear";
        case 2: return "Partly cloudy";
        case 3: return "Overcast";
        case 45: return "Fog";
        case 48: return "Rime fog";
        case 51: case 53: case 55: return "Drizzle";
        case 56: case 57: return "Freezing drizzle";
        case 61: case 63: case 65: return "Rain";
        case 66: case 67: return "Freezing rain";
        case 71: case 73: case 75: return "Snow";
        case 77: return "Snow grains";
        case 80: case 81: case 82: return "Showers";
        case 85: case 86: return "Snow showers";
        case 95: return "Thunderstorm";
        case 96: case 99: return "Thunderstorm with hail";
        default: return "Unknown";
        }
    }

    function iconName(code) {
        if (code === 0) return "sunny";
        if (code === 1 || code === 2) return "partly_cloudy_day";
        if (code === 3) return "cloud";
        if (code === 45 || code === 48) return "foggy";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "rainy";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "weather_snowy";
        if (code >= 95) return "thunderstorm";
        return "cloud";
    }

    function moonPhaseAngle(date) {
        const knownNewMoon = new Date(Date.UTC(2000, 0, 6));
        const diffDays = (date.getTime() - knownNewMoon.getTime()) / 86400000.0;
        const lunations = diffDays / 29.53058867;
        const fraction = lunations - Math.floor(lunations);
        return Math.round(fraction * 360.0);
    }

    // Nothing known yet says so. A zero reads as a reading, and a bar reporting
    // 0 degrees for a machine that has never reached the network is worse than
    // one reporting nothing at all.
    property var data: ({
        uv: "--",
        humidity: "--",
        sunrise: "--:--",
        sunset: "--:--",
        windDir: "",
        wCode: "113",
        city: "",
        wind: "--",
        precip: "--",
        visib: "--",
        press: "--",
        temp: "--°",
        tempFeelsLike: "--°",
        lastRefresh: "Never",
    })

    function wmoToWwo(wmoCode) {
        const mapping = {
            0: "113", // Clear
            1: "116", // Partly Cloudy
            2: "119", // Cloudy
            3: "122", // Overcast
            45: "143", // Fog
            48: "248", // Fog
            51: "266", // Drizzle
            53: "266",
            55: "266",
            56: "281", // Freezing Drizzle
            57: "284",
            90: "296", // Rain
            61: "296",
            63: "302",
            65: "308",
            66: "311", // Freezing Rain
            67: "314",
            71: "326", // Snow
            73: "332",
            75: "338",
            77: "335", // Snow Grains
            80: "353", // Showers
            81: "356",
            82: "359",
            85: "368", // Snow Showers
            86: "371",
            95: "386", // Thunderstorm
            96: "389",
            99: "392"
        };
        return mapping[wmoCode] || "113";
    }

    function mergeAqiIntoForecasts(targetHList, targetDList, aqiJson) {
        if (!aqiJson) return;
        const cur = aqiJson.current || {};
        const aqiMap = {
            "pm10": Number(cur.pm10 || 0),
            "pm2_5": Number(cur.pm2_5 || 0),
            "pm25": Number(cur.pm2_5 || 0),
            "carbonMonoxide": Number(cur.carbon_monoxide || 0),
            "nitrogenDioxide": Number(cur.nitrogen_dioxide || 0),
            "sulphurDioxide": Number(cur.sulphur_dioxide || 0),
            "ozone": Number(cur.ozone || 0),
            "usAqi": Number(cur.us_aqi || 0),
            "europeanAqi": Number(cur.european_aqi || 0),
            "aqi": Number(cur.us_aqi || cur.european_aqi || 0)
        };
        root.airQuality = aqiMap;
        root.currentAirQuality = aqiMap;

        if (root.detailedCurrent) {
            root.detailedCurrent.airQuality = aqiMap;
        }

        if (!targetHList || !aqiJson.hourly || !aqiJson.hourly.time) return;
        const hAqi = aqiJson.hourly;
        const aqiByTime = {};
        for (let i = 0; i < hAqi.time.length; ++i) {
            const uAqi = Number(hAqi.us_aqi ? hAqi.us_aqi[i] : (hAqi.european_aqi ? hAqi.european_aqi[i] : 0));
            const p10 = Number(hAqi.pm10 ? hAqi.pm10[i] : 0);
            const p25 = Number(hAqi.pm2_5 ? hAqi.pm2_5[i] : 0);
            const co = Number(hAqi.carbon_monoxide ? hAqi.carbon_monoxide[i] : 0);
            const no2 = Number(hAqi.nitrogen_dioxide ? hAqi.nitrogen_dioxide[i] : 0);
            const so2 = Number(hAqi.sulphur_dioxide ? hAqi.sulphur_dioxide[i] : 0);
            const o3 = Number(hAqi.ozone ? hAqi.ozone[i] : 0);
            aqiByTime[hAqi.time[i]] = {
                pm10: p10,
                pm2_5: p25,
                pm25: p25,
                carbonMonoxide: co,
                nitrogenDioxide: no2,
                sulphurDioxide: so2,
                ozone: o3,
                aqi: uAqi,
                usAqi: uAqi
            };
        }

        for (let j = 0; j < targetHList.length; ++j) {
            const item = targetHList[j];
            const match = aqiByTime[item.time];
            if (match) {
                item.pm10 = match.pm10;
                item.pm2_5 = match.pm2_5;
                item.pm25 = match.pm25;
                item.carbonMonoxide = match.carbonMonoxide;
                item.nitrogenDioxide = match.nitrogenDioxide;
                item.sulphurDioxide = match.sulphurDioxide;
                item.ozone = match.ozone;
                item.aqi = match.aqi;
                item.airQuality = match;
            }
        }

        if (targetDList && targetDList.length > 0) {
            const dailyAqiByDate = {};
            for (let hIdx = 0; hIdx < hAqi.time.length; ++hIdx) {
                const hDateStr = new Date(hAqi.time[hIdx] * 1000).toDateString();
                if (!dailyAqiByDate[hDateStr]) {
                    dailyAqiByDate[hDateStr] = { aqiMax: 0, pm10Max: 0, pm25Max: 0, o3Max: 0, no2Max: 0 };
                }
                const rec = dailyAqiByDate[hDateStr];
                const hVal = Number(hAqi.us_aqi ? hAqi.us_aqi[hIdx] : (hAqi.european_aqi ? hAqi.european_aqi[hIdx] : 0));
                if (hVal > rec.aqiMax) rec.aqiMax = hVal;
                const p10 = Number(hAqi.pm10 ? hAqi.pm10[hIdx] : 0);
                if (p10 > rec.pm10Max) rec.pm10Max = p10;
                const p25 = Number(hAqi.pm2_5 ? hAqi.pm2_5[hIdx] : 0);
                if (p25 > rec.pm25Max) rec.pm25Max = p25;
                const o3 = Number(hAqi.ozone ? hAqi.ozone[hIdx] : 0);
                if (o3 > rec.o3Max) rec.o3Max = o3;
                const no2 = Number(hAqi.nitrogen_dioxide ? hAqi.nitrogen_dioxide[hIdx] : 0);
                if (no2 > rec.no2Max) rec.no2Max = no2;
            }

            for (let dIdx = 0; dIdx < targetDList.length; ++dIdx) {
                const day = targetDList[dIdx];
                const dayDateStr = new Date(day.time * 1000).toDateString();
                const rec = dailyAqiByDate[dayDateStr];

                if (rec && rec.aqiMax > 0) {
                    day.aqi = rec.aqiMax;
                    day.airQuality = {
                        aqi: rec.aqiMax,
                        usAqi: rec.aqiMax,
                        pm10: rec.pm10Max,
                        pm25: rec.pm25Max,
                        pm2_5: rec.pm25Max,
                        ozone: rec.o3Max,
                        nitrogenDioxide: rec.no2Max
                    };
                } else if (dIdx === 0 && aqiMap.aqi > 0) {
                    day.aqi = aqiMap.aqi;
                    day.airQuality = aqiMap;
                }
            }
        }
    }

    function refineAqi(aqiJson) {
        if (!aqiJson) return;
        root.lastAqiReply = aqiJson;
        if (!root.hourlyForecast || root.hourlyForecast.length === 0) return;

        const updatedHourly = root.hourlyForecast.map(item => Object.assign({}, item));
        const updatedDaily = root.dailyForecast ? root.dailyForecast.map(item => Object.assign({}, item)) : [];
        root.mergeAqiIntoForecasts(updatedHourly, updatedDaily, aqiJson);
        root.makeModel(updatedHourly);
        root.hourlyForecast = updatedHourly;
        if (updatedDaily.length > 0) {
            root.makeModel(updatedDaily);
            root.dailyForecast = updatedDaily;
            root.dailyTrendForecast = updatedDaily;
        }
    }

    // `isRerender` is a change of unit rather than a new reading, and the
    // time shown is the time the reading was taken.
    function refineData(weatherJson, isRerender) {
        if (!weatherJson || !weatherJson.current) return;

        let temp = {};
        const current = weatherJson.current;
        const daily = weatherJson.daily;

        temp.uv = current.uv_index || 0;
        temp.humidity = (current.relative_humidity_2m || 0) + "%";
        
        // Extract time from Unix timestamp or ISO string
        const formatTime = (val) => {
            if (!val) return "0:00";
            if (typeof val === "number") {
                const d = new Date(val * 1000);
                return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
            }
            const str = String(val);
            return str.includes("T") ? str.split("T")[1].substring(0, 5) : str;
        };

        temp.sunrise = (daily && daily.sunrise && daily.sunrise[0]) ? formatTime(daily.sunrise[0]) : "--:--";
        temp.sunset = (daily && daily.sunset && daily.sunset[0]) ? formatTime(daily.sunset[0]) : "--:--";
        
        // Wind direction simplified
        const degToDir = (deg) => {
            const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
            return dirs[Math.round(deg / 45) % 8];
        };
        temp.windDir = degToDir(current.wind_direction_10m || 0);
        
        temp.wCode = root.wmoToWwo(current.weather_code);
        temp.city = root.cityName;

        const curTemp = Number(current.temperature_2m || 0);
        const curFeels = Number(current.apparent_temperature !== undefined ? current.apparent_temperature : curTemp);
        const curWindMs = Number(current.wind_speed_10m || 0);
        const curPrecip = Number(current.precipitation || 0);
        const curVisib = Number(current.visibility || 0);
        const curPress = Number(current.pressure_msl || 1013);
        const curCode = Number(current.weather_code || 0);

        if (root.useUSCS) {
            temp.wind = Math.round(curWindMs * 2.23694) + " mph";
            temp.precip = (curPrecip / 25.4).toFixed(2) + " in";
            temp.visib = Math.round(curVisib / 1609.34) + " mi";
            temp.press = (curPress * 0.02953).toFixed(2) + " inHg";
            temp.temp = Math.round(curTemp * 9/5 + 32) + "°F";
            temp.tempFeelsLike = Math.round(curFeels * 9/5 + 32) + "°F";
        } else {
            temp.wind = Math.round(curWindMs * 3.6) + " km/h";
            temp.precip = curPrecip + " mm";
            temp.visib = Math.round(curVisib / 1000) + " km";
            temp.press = Math.round(curPress) + " hPa";
            temp.temp = Math.round(curTemp) + "°C";
            temp.tempFeelsLike = Math.round(curFeels) + "°C";
        }
        
        temp.lastRefresh = isRerender ? root.data.lastRefresh : (DateTime.time + " • " + DateTime.date);
        root.data = temp;

        // Populate rich conditions
        root.currentTemperatureC = curTemp;
        root.currentFeelsLikeC = curFeels;
        root.currentWeatherCode = curCode;
        root.currentWeatherText = root.weatherText(curCode);
        root.currentIconName = root.iconName(curCode);
        root.currentWindSpeedMs = curWindMs;
        root.currentWindDirection = Number(current.wind_direction_10m || 0);
        root.currentWindGustsMs = Number(current.wind_gusts_10m || curWindMs);
        root.currentUvIndex = Number(current.uv_index || 0);
        root.currentRelativeHumidity = Number(current.relative_humidity_2m || 0);
        root.currentDewPointC = Number(current.dew_point_2m || 0);
        root.currentPressureHpa = curPress;
        root.currentCloudCover = Number(current.cloud_cover || 0);
        root.currentVisibilityM = curVisib;
        loadingSafetyTimer.stop();
        root.lastUpdated = new Date().toISOString();
        root.status = "fresh";
        root.loading = false;

        root.detailedCurrent = {
            temperatureC: curTemp,
            feelsLikeC: curFeels,
            weatherCode: curCode,
            weatherText: root.weatherText(curCode),
            iconName: root.iconName(curCode),
            windSpeedMs: curWindMs,
            windDirection: Number(current.wind_direction_10m || 0),
            windGustsMs: Number(current.wind_gusts_10m || curWindMs),
            uvIndex: Number(current.uv_index || 0),
            relativeHumidity: Number(current.relative_humidity_2m || 0),
            dewPointC: Number(current.dew_point_2m || 0),
            pressureHpa: curPress,
            cloudCover: Number(current.cloud_cover || 0),
            visibilityM: curVisib,
            precipitationMm: curPrecip,
            sunrise: daily && daily.sunrise ? daily.sunrise[0] : null,
            sunset: daily && daily.sunset ? daily.sunset[0] : null,
            airQuality: root.airQuality || ({})
        };

        let hList = [];
        // Parse hourly forecast
        if (weatherJson.hourly && weatherJson.hourly.time) {
            const h = weatherJson.hourly;
            const count = h.time.length;
            for (let i = 0; i < count; ++i) {
                const itemTime = h.time[i];
                const itemTemp = Number(h.temperature_2m ? h.temperature_2m[i] : 0);
                const itemCode = Number(h.weather_code ? h.weather_code[i] : 0);
                hList.push({
                    time: itemTime,
                    temperatureC: itemTemp,
                    feelsLikeC: Number(h.apparent_temperature ? h.apparent_temperature[i] : itemTemp),
                    weatherCode: itemCode,
                    weatherText: root.weatherText(itemCode),
                    iconName: root.iconName(itemCode),
                    precipitationProbability: Number(h.precipitation_probability ? h.precipitation_probability[i] : 0),
                    precipitationMm: Number(h.precipitation ? h.precipitation[i] : 0),
                    windSpeedMs: Number(h.wind_speed_10m ? h.wind_speed_10m[i] : 0),
                    windDirection: Number(h.wind_direction_10m ? h.wind_direction_10m[i] : 0),
                    windGustsMs: Number(h.wind_gusts_10m ? h.wind_gusts_10m[i] : 0),
                    uvIndex: Number(h.uv_index ? h.uv_index[i] : 0),
                    isDaylight: h.is_day ? (h.is_day[i] === 1) : true,
                    relativeHumidity: Number(h.relative_humidity_2m ? h.relative_humidity_2m[i] : 0),
                    dewPointC: Number(h.dew_point_2m ? h.dew_point_2m[i] : 0),
                    pressureHpa: Number(h.pressure_msl ? h.pressure_msl[i] : 1013),
                    cloudCover: Number(h.cloud_cover ? h.cloud_cover[i] : 0),
                    visibilityM: Number(h.visibility ? h.visibility[i] : 10000),
                    aqi: 0,
                    pm2_5: 0,
                    pm10: 0
                });
            }
        }

        let dList = [];
        // Parse daily forecast
        if (weatherJson.daily && weatherJson.daily.time) {
            const d = weatherJson.daily;
            const hoursByDay = {};
            for (let hi = 0; hi < hList.length; ++hi) {
                const dKey = new Date(hList[hi].time * 1000).toDateString();
                if (!hoursByDay[dKey]) hoursByDay[dKey] = [];
                hoursByDay[dKey].push(hList[hi]);
            }

            const dCount = d.time.length;
            for (let j = 0; j < dCount; ++j) {
                const dayTime = d.time[j];
                const dayDate = new Date(dayTime * 1000);
                const dayCode = Number(d.weather_code ? d.weather_code[j] : 0);
                const tempMax = Number(d.temperature_2m_max ? d.temperature_2m_max[j] : 0);
                const tempMin = Number(d.temperature_2m_min ? d.temperature_2m_min[j] : 0);
                const feelsMax = Number(d.apparent_temperature_max ? d.apparent_temperature_max[j] : tempMax);
                const feelsMin = Number(d.apparent_temperature_min ? d.apparent_temperature_min[j] : tempMin);
                const sunriseTime = d.sunrise ? d.sunrise[j] : 0;
                const sunsetTime = d.sunset ? d.sunset[j] : 0;
                const moonriseTime = d.moonrise ? d.moonrise[j] : 0;
                const moonsetTime = d.moonset ? d.moonset[j] : 0;
                const moonPhaseFrac = (d.moon_phase && d.moon_phase[j] !== undefined && !isNaN(d.moon_phase[j])) ? Number(d.moon_phase[j]) : null;
                const calculatedPhase = moonPhaseFrac !== null ? (moonPhaseFrac * 360) : root.moonPhaseAngle(dayDate);
                const precipSum = Number(d.precipitation_sum ? d.precipitation_sum[j] : 0);
                const uvMax = Number(d.uv_index_max ? d.uv_index_max[j] : 0);
                const windMax = Number(d.wind_speed_10m_max ? d.wind_speed_10m_max[j] : 0);
                const windDirDom = Number(d.wind_direction_10m_dominant ? d.wind_direction_10m_dominant[j] : 0);

                const dayHours = hoursByDay[dayDate.toDateString()] || [];

                const aggregateHalfDay = (items, isDay) => {
                    const slice = items.filter(it => {
                        const hr = new Date(it.time * 1000).getHours();
                        return isDay ? (hr >= 6 && hr < 18) : (hr < 6 || hr >= 18);
                    });
                    if (slice.length === 0) {
                        return {
                            temperatureC: isDay ? tempMax : tempMin,
                            feelsLikeC: isDay ? feelsMax : feelsMin,
                            precipitationMm: precipSum / 2,
                            rainMm: precipSum / 2,
                            snowCm: 0,
                            precipitationProbability: 0,
                            windSpeedMs: windMax,
                            windDirection: windDirDom,
                            windGustsMs: windMax,
                            weatherCode: dayCode,
                            weatherText: root.weatherText(dayCode),
                            iconName: root.iconName(dayCode)
                        };
                    }
                    let t = isDay ? -999 : 999;
                    let f = isDay ? -999 : 999;
                    let pr = 0, pop = 0, w = 0, g = 0, c = slice[0].weatherCode;
                    let dir = windDirDom;
                    for (let s = 0; s < slice.length; ++s) {
                        const it = slice[s];
                        t = isDay ? Math.max(t, it.temperatureC) : Math.min(t, it.temperatureC);
                        f = isDay ? Math.max(f, it.feelsLikeC) : Math.min(f, it.feelsLikeC);
                        pr += it.precipitationMm;
                        pop = Math.max(pop, it.precipitationProbability);
                        if (it.windSpeedMs >= w) {
                            w = it.windSpeedMs;
                            dir = it.windDirection;
                        }
                        g = Math.max(g, it.windGustsMs);
                        if (it.weatherCode >= 95 || (it.weatherCode >= 61 && it.weatherCode <= 86))
                            c = it.weatherCode;
                    }
                    return {
                        temperatureC: t,
                        feelsLikeC: f,
                        precipitationMm: pr,
                        rainMm: pr,
                        snowCm: 0,
                        precipitationProbability: pop,
                        windSpeedMs: w,
                        windDirection: dir,
                        windGustsMs: g,
                        weatherCode: c,
                        weatherText: root.weatherText(c),
                        iconName: root.iconName(c)
                    };
                };

                const daylightSecs = (sunsetTime && sunriseTime && sunsetTime > sunriseTime)
                    ? (sunsetTime - sunriseTime)
                    : (d.sunshine_duration ? d.sunshine_duration[j] : 43200);

                dList.push({
                    time: dayTime,
                    date: dayDate.toISOString().split("T")[0],
                    weatherCode: dayCode,
                    weatherText: root.weatherText(dayCode),
                    iconName: root.iconName(dayCode),
                    tempMaxC: tempMax,
                    tempMinC: tempMin,
                    temperatureC: tempMax,
                    feelsLikeMaxC: feelsMax,
                    feelsLikeMinC: feelsMin,
                    precipitationMm: precipSum,
                    precipitationProbability: 0,
                    uvIndexMax: uvMax,
                    sunrise: sunriseTime,
                    sunset: sunsetTime,
                    moonrise: moonriseTime,
                    moonset: moonsetTime,
                    daylightDurationSeconds: daylightSecs,
                    daylightHours: daylightSecs / 3600,
                    moonPhaseAngle: calculatedPhase,
                    day: aggregateHalfDay(dayHours, true),
                    night: aggregateHalfDay(dayHours, false),
                    aqi: 0,
                    airQuality: null
                });
            }
        }

        if (root.lastAqiReply) {
            root.mergeAqiIntoForecasts(hList, dList, root.lastAqiReply);
        }

        if (hList.length > 0) {
            root.makeModel(hList);
            root.hourlyForecast = hList;
        }
        if (dList.length > 0) {
            root.makeModel(dList);
            root.dailyForecast = dList;
            root.dailyTrendForecast = dList;
            root.normalsChanged();
        }
    }

    Timer {
        id: loadingSafetyTimer
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.loading) {
                console.warn("[WeatherService] Fetch timeout reached, clearing loading state.");
                root.loading = false;
                if (root.status === "loading")
                    root.status = root.lastReply ? "fresh" : "stale";
            }
        }
    }

    // A refresh with nothing to fetch against asks for the thing that is
    // missing. A typed name goes through the same wait typing does, so a start
    // and a keystroke cannot both ask for it.
    function getData() {
        root.loading = true;
        root.status = "loading";
        loadingSafetyTimer.restart();
        if (root.usePinned) {
            if (root.pinnedValid) {
                weatherFetcher.fetch();
                aqiFetcher.fetch();
            } else {
                pinnedDebounce.restart();
            }
            return;
        }
        if (root.locationValid) {
            weatherFetcher.fetch();
            aqiFetcher.fetch();
        } else {
            Location.refresh();
        }
    }

    // The name is a URL query value and reaches curl as an argument, so one
    // carrying a space or an ampersand stays one name. The reply carries the
    // country too, which is what lets a typed city decide its own unit with no
    // second request. Keyed on country_code and never on country, which is
    // absent entirely for some territories.
    Process {
        id: geocoder
        running: false
        property string pending: ""
        function fetch(name) {
            // Assigning `running` on a process already running does nothing, so
            // a query issued while one is in flight would be swallowed.
            geocoder.pending = name;
            if (geocoder.running)
                return;
            geocoder.command = ["curl", "-s", "--max-time", "10", `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=1`];
            geocoder.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const asked = geocoder.pending;
                if (text.length === 0)
                    return;
                try {
                    // A name matching nothing comes back with no results key at
                    // all. The pin is cleared rather than left pointing at the
                    // last place that did match, which would quietly report the
                    // weather somewhere the user has stopped naming.
                    const found = JSON.parse(text)?.results?.[0];
                    if (!found) {
                        root.pinnedValid = false;
                        return;
                    }
                    root.pinnedLat = found.latitude;
                    root.pinnedLon = found.longitude;
                    root.pinnedName = found.name ?? asked;
                    root.pinnedCountry = found.country_code ?? "";
                    root.pinnedValid = true;
                } catch (e) {
                    console.log("[Weather] city lookup failed: " + e);
                }
            }
        }
    }

    // The settings field writes a key at a time, so a name is not looked up
    // until it has stopped changing. That is what keeps a half typed name from
    // being fetched as a place.
    Timer {
        id: pinnedDebounce
        interval: 700
        repeat: false
        onTriggered: if (root.usePinned)
            geocoder.fetch(root.pinnedCity)
    }
    onPinnedCityChanged: {
        root.pinnedValid = false;
        if (root.usePinned)
            pinnedDebounce.restart();
        else
            pinnedDebounce.stop();
    }
    onUsePinnedChanged: if (root.usePinned && !root.pinnedValid)
        pinnedDebounce.restart()

    Process {
        id: weatherFetcher
        function fetch() {
            if (running) return;
            if (!root.locationValid) return;
            const currentFields = "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,visibility,dew_point_2m,cloud_cover";
            const hourlyFields = "temperature_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,is_day,relative_humidity_2m,dew_point_2m,pressure_msl,cloud_cover,visibility";
            const dailyFields = "sunrise,sunset,weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,sunshine_duration,uv_index_max,precipitation_sum,relative_humidity_2m_mean,wind_speed_10m_max,wind_direction_10m_dominant,moonrise,moonset,moon_phase";
            const url = `https://api.open-meteo.com/v1/forecast?latitude=${root.latitude}&longitude=${root.longitude}&current=${currentFields}&hourly=${hourlyFields}&daily=${dailyFields}&timezone=auto&timeformat=unixtime&windspeed_unit=ms&forecast_days=7`;
            command = ["curl", "-s", "--connect-timeout", "3", "--max-time", "6", url];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    fallbackFetcher.fetch();
                    return;
                }
                try {
                    const weather = JSON.parse(text);
                    if (weather.error === true || !weather.current)
                        throw new Error(weather.reason ?? "no current conditions");
                    root.lastReply = weather;
                    root.refineData(weather, false);
                } catch (e) {
                    console.error(`[WeatherService] Weather Error: ${e.message}`);
                    root.status = "error";
                    root.errorMessage = e.message;
                    fallbackFetcher.fetch();
                }
            }
        }
    }

    Process {
        id: aqiFetcher
        running: false
        function fetch() {
            if (!root.locationValid || running) return;
            const fields = "pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,us_aqi,european_aqi";
            const url = `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${root.latitude}&longitude=${root.longitude}&current=${fields}&hourly=${fields}&timezone=auto&timeformat=unixtime&forecast_days=7`;
            command = ["curl", "-s", "--connect-timeout", "3", "--max-time", "6", url];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                try {
                    const aqiJson = JSON.parse(text);
                    if (aqiJson && !aqiJson.error) {
                        root.lastAqiReply = aqiJson;
                        root.refineAqi(aqiJson);
                    }
                } catch (e) {
                    console.error(`[WeatherService] AQI Error: ${e.message}`);
                }
            }
        }
    }

    // A second forecaster, asked only when the first one has nothing. Its reply
    // is reshaped into the first's form on the way in, so everything downstream
    // goes on reading one kind of answer. Kept as a fallback rather than a
    // choice: the first carries readings this one does not, and an outage is
    // the only reason to accept the shorter answer.
    //
    // Speeds arrive in metres per second here and in kilometres per hour there,
    // and the conditions are named rather than numbered, so both are converted
    // rather than passed along to be read as something they are not.
    readonly property string fallbackReshaper: `
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
t=d["properties"]["timeseries"][0]
i=t["data"]["instant"]["details"]
n=t["data"].get("next_1_hours") or t["data"].get("next_6_hours") or {}
sym=(n.get("summary") or {}).get("symbol_code","")
code=0
for k,v in [("thunder",95),("snow",71),("sleet",68),("rainshowers",80),("heavyrain",65),("lightrain",51),("rain",61),("fog",45),("cloudy",3),("partlycloudy",2),("fair",1),("clearsky",0)]:
    if k in sym: code=v; break
print(json.dumps({"current":{
 "temperature_2m":i.get("air_temperature"),
 "relative_humidity_2m":i.get("relative_humidity"),
 "apparent_temperature":i.get("air_temperature"),
 "precipitation":(n.get("details") or {}).get("precipitation_amount",0),
 "weather_code":code,
 "pressure_msl":i.get("air_pressure_at_sea_level"),
 "surface_pressure":i.get("air_pressure_at_sea_level"),
 "wind_speed_10m":round((i.get("wind_speed") or 0)*3.6,1),
 "wind_direction_10m":i.get("wind_from_direction"),
 "uv_index":i.get("ultraviolet_index_clear_sky",0),
 "visibility":0}}))
`

    Process {
        id: fallbackFetcher
        function fetch() {
            if (running) return;
            const url = `https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${root.latitude}&lon=${root.longitude}`;
            // The service asks callers to identify themselves and turns away
            // those that do not. URL and program arrive as arguments so neither
            // is read as shell.
            command = ["bash", "-c",
                'curl -s --connect-timeout 3 --max-time 6 -H "User-Agent: MainstreamOS/2.0 (https://mainstreamos.org)" "$1" | python3 -c "$2"',
                "weather", url, root.fallbackReshaper];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    root.loading = false;
                    root.status = "error";
                    return;
                }
                try {
                    const weather = JSON.parse(text);
                    // This forecaster reports no sun times, and the reader
                    // downstream expects the stamped form the other one sends.
                    // The sun is worked out here from the position anyway, so
                    // it is dressed in that form rather than left missing.
                    const stamp = t => t ? `1970-01-01T${t}` : "";
                    weather.daily = {
                        sunrise: [stamp(SolarSchedule.sunrise)],
                        sunset: [stamp(SolarSchedule.sunset)]
                    };
                    root.lastReply = weather;
                    root.refineData(weather, false);
                    console.log("[WeatherService] Served by the fallback forecaster.");
                } catch (e) {
                    console.error(`[WeatherService] Fallback Error: ${e.message}`);
                    root.loading = false;
                    root.status = "error";
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: root.fetchInterval
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.getData()
    }

    // Both units are already in the reply that produced what is on screen, so
    // a change of mind is a re-read. Before the first reply there is nothing to
    // re-read.
    onUseUSCSChanged: if (root.lastReply)
        root.refineData(root.lastReply, true)

    IpcHandler {
        target: "weather"
        function refresh(): void {
            root.refresh();
        }
    }

    Component.onCompleted: {
        console.info("[WeatherService] Initialized with ip-api and Open-Meteo.");
    }
}
