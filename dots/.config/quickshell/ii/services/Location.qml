pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Where this machine is, asked once and answered for everyone.
 *
 * Two positions are kept, because the two things reading this want different
 * answers. The weather wants the place it was told about. The night light
 * wants a place whose clock agrees with this machine's, since one that does
 * not is the shape a tunnel has and its sunrise would be wrong by that whole
 * difference. A disagreeing reply therefore moves the first and leaves the
 * second exactly as it was.
 *
 * Resolved in the main shell alone. The settings app reads the same file and
 * looks nothing up, so opening a page cannot start a second lookup.
 */
Singleton {
    id: root

    property bool lookupEnabled: false
    function load() {
        root.lookupEnabled = true;
    }

    // Scalars rather than one object, because a property holding an object can
    // be written into without the change ever being announced, and every
    // reader here is a binding.
    property real latitude: 0
    property real longitude: 0
    property string city: ""
    property string countryCode: ""
    property bool known: false

    // The last position whose clock agreed with this one, which is the only
    // kind a sunrise can be worked out from.
    property real solarLatitude: 0
    property real solarLongitude: 0
    property bool solarKnown: false

    property bool resolvedThisSession: false
    property int attempts: 0

    readonly property string cachePath: FileUtils.trimFileProtocol(`${Directories.state}/user/location.json`)

    // Where everyday temperature is quoted in Fahrenheit, as ISO 3166-1
    // alpha-2. The territories are named one by one because the lookup reports
    // them under their own codes rather than under US, so leaving them out puts
    // Puerto Rico and Guam on Celsius.
    readonly property var fahrenheitCountries: ["US", "PR", "GU", "VI", "AS", "MP", "UM", "FM", "MH", "PW", "BS", "BZ", "KY", "LR"]

    function usesFahrenheit(countryCode) {
        return root.fahrenheitCountries.indexOf(countryCode) !== -1;
    }

    // An hour of slack, so a daylight saving changeover is not read as a move.
    // Worked out per call rather than held, so a changeover mid session does
    // not leave a stale answer behind. A reply carrying no offset is taken at
    // its word, which is what a position stored by an older release looks like.
    function clockAgrees(offset) {
        if (typeof offset !== "number")
            return true;
        return Math.abs(offset - (-new Date().getTimezoneOffset() * 60)) <= 3600;
    }

    function apply(lat, lon, cityName, country, offset) {
        root.latitude = lat;
        root.longitude = lon;
        root.city = cityName;
        root.countryCode = country;
        root.known = true;
        if (root.clockAgrees(offset)) {
            root.solarLatitude = lat;
            root.solarLongitude = lon;
            root.solarKnown = true;
        }
    }

    // The directory is made in the same breath as the write, because a detached
    // mkdir has not finished by the time a separate write runs, and a position
    // that never reaches disk is looked up again on every boot, which is the
    // one thing a machine with no network cannot do. The path and the payload
    // arrive as arguments rather than inside the script, so a place name
    // carrying a quote stays data.
    function store() {
        const payload = JSON.stringify({
            lat: root.latitude,
            lon: root.longitude,
            city: root.city,
            countryCode: root.countryCode,
            solarLat: root.solarLatitude,
            solarLon: root.solarLongitude,
            solarKnown: root.solarKnown
        });
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$0")" && printf "%s" "$1" > "$0"', root.cachePath, payload]);
    }

    // Read straight across rather than through apply(), so a stored pair that
    // disagreed with this clock cannot displace the stored one that agreed.
    function adopt(text) {
        try {
            const stored = JSON.parse(text);
            if (typeof stored.lat !== "number" || typeof stored.lon !== "number")
                return;
            root.latitude = stored.lat;
            root.longitude = stored.lon;
            root.city = stored.city ?? "";
            root.countryCode = stored.countryCode ?? "";
            root.known = true;
            if (stored.solarKnown === true) {
                root.solarLatitude = stored.solarLat;
                root.solarLongitude = stored.solarLon;
                root.solarKnown = true;
            }
        } catch (e) {
            // A truncated or hand edited file just means no position yet; the
            // lookup below replaces it.
        }
    }

    FileView {
        id: cache
        path: root.cachePath
        printErrors: false
        onLoaded: root.adopt(cache.text())
    }

    function reverseGeocodeAndApply(lat, lon) {
        const xhr = new XMLHttpRequest();
        const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&addressdetails=1`;
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "QuickShellLocationService/1.0");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            let cityName = "";
            let countryCode = "";
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const addr = data.address || {};
                    const local = addr.neighbourhood || addr.suburb || addr.residential || addr.quarter || addr.road || addr.village || addr.hamlet || "";
                    const city = addr.city || addr.town || addr.municipality || addr.county || addr.state_district || "";
                    cityName = (local && city && local.toLowerCase() !== city.toLowerCase()) ? `${local}, ${city}` : (local || city || data.name || "");
                    countryCode = (addr.country_code || "").toUpperCase();
                } catch (e) {
                    console.log("[Location] reverse geocode parse error: " + e);
                }
            }
            const offset = -new Date().getTimezoneOffset() * 60;
            root.apply(lat, lon, cityName, countryCode, offset);
            root.resolvedThisSession = true;
            root.store();
        };
        xhr.send();
    }

    Process {
        id: phoneLocator
        running: false
        command: [
            "bash", "-c",
            'dev_id=$(qdbus org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices 2>/dev/null | head -n 1); ' +
            'phone_ip=$(qdbus org.kde.kdeconnect /modules/kdeconnect/devices/$dev_id org.kde.kdeconnect.device.reachableAddresses 2>/dev/null | head -n 1); ' +
            '[ -z "$phone_ip" ] && phone_ip="192.168.31.183"; ' +
            'curl -s --max-time 3 "http://$phone_ip:8080/"'
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    try {
                        const data = JSON.parse(text);
                        if (typeof data.latitude === "number" && typeof data.longitude === "number") {
                            root.reverseGeocodeAndApply(data.latitude, data.longitude);
                            return;
                        }
                    } catch (e) {
                        console.log("[Location] phone GPS parse error: " + e);
                    }
                }
                // Fallback to IP-based lookup if phone is offline/unreachable
                locator.running = true;
            }
        }
    }

    // `fields` is explicit so the offset and the country are actually in the
    // reply. The time limit matters more than it looks: a blackholed route
    // otherwise holds the process for curl's own five minutes, and every retry
    // behind it is swallowed, since assigning `running` on a process already
    // running does nothing.
    Process {
        id: locator
        running: false
        command: ["curl", "-s", "--max-time", "10", "http://ip-api.com/json/?fields=status,lat,lon,city,countryCode,offset"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return;
                try {
                    const found = JSON.parse(text);
                    if (found.status !== "success")
                        return;
                    root.apply(found.lat, found.lon, found.city ?? "", found.countryCode ?? "", typeof found.offset === "number" ? found.offset : null);
                    root.resolvedThisSession = true;
                    root.store();
                } catch (e) {
                    console.log("[Location] lookup failed: " + e);
                }
            }
        }
    }

    function syncFromPhone() {
        if (!phoneLocator.running) {
            phoneLocator.running = true;
        }
    }

    function refresh() {
        if (!root.lookupEnabled || phoneLocator.running || locator.running)
            return;
        root.attempts++;
        phoneLocator.running = true;
    }

    onLookupEnabledChanged: if (root.lookupEnabled)
        root.refresh()

    // A bounded set of retries while nothing has come back this session, since
    // the minute after login is when the network is least likely to be up. A
    // stored position stays in force throughout.
    Timer {
        interval: 30000
        repeat: true
        running: root.lookupEnabled && !root.resolvedThisSession && root.attempts < 5
        onTriggered: root.refresh()
    }
}
