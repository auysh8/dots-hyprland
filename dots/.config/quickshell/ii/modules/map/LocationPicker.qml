import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.map

ColumnLayout {
    id: root

    function getSavedLatitude() {
        if (!Config.options.bar.weather.enableGPS && Config.options.bar.weather.latitude && Config.options.bar.weather.latitude !== 0) {
            return Number(Config.options.bar.weather.latitude);
        }
        if (!Config.options.bar.weather.enableGPS && Weather.pinnedLat !== 0) {
            return Number(Weather.pinnedLat);
        }
        if (Weather.hasManualLocation && Weather.latitude !== 0) {
            return Number(Weather.latitude);
        }
        if (Location.known && Location.latitude !== 0) {
            return Number(Location.latitude);
        }
        return Number(Weather.latitude || 28.6139);
    }

    function getSavedLongitude() {
        if (!Config.options.bar.weather.enableGPS && Config.options.bar.weather.longitude && Config.options.bar.weather.longitude !== 0) {
            return Number(Config.options.bar.weather.longitude);
        }
        if (!Config.options.bar.weather.enableGPS && Weather.pinnedLon !== 0) {
            return Number(Weather.pinnedLon);
        }
        if (Weather.hasManualLocation && Weather.longitude !== 0) {
            return Number(Weather.longitude);
        }
        if (Location.known && Location.longitude !== 0) {
            return Number(Location.longitude);
        }
        return Number(Weather.longitude || 77.2090);
    }

    property real candidateLatitude: getSavedLatitude()
    property real candidateLongitude: getSavedLongitude()
    property real cameraLatitude: candidateLatitude
    property real cameraLongitude: candidateLongitude
    property string candidateCity: Config.options.bar.weather.city || Weather.cityName || ""
    readonly property var mapStyles: [
        { id: "liberty", name: "Liberty (Standard)", url: "https://tiles.openfreemap.org/styles/liberty" },
        { id: "positron", name: "Positron (Light)", url: "https://tiles.openfreemap.org/styles/positron" },
        { id: "fiord", name: "Fiord (Slate)", url: "https://tiles.openfreemap.org/styles/fiord" },
        { id: "dark", name: "Dark (Night)", url: "https://tiles.openfreemap.org/styles/dark" }
    ]
    property int currentStyleIndex: 0
    readonly property string activeStyleUrl: mapStyles[currentStyleIndex].url
    readonly property real initialZoom: 14.5
    readonly property real focusedZoom: 14.5
    readonly property real initialBearing: 0
    readonly property real initialTilt: 0
    property real mapZoom: initialZoom
    property real mapBearing: initialBearing
    property real mapTilt: initialTilt
    property string coordinateError: ""
    property bool geocoding: false
    property bool syncingPhone: phoneSyncProcess.running

    Process {
        id: phoneSyncProcess
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
                if (text.length === 0) {
                    root.coordinateError = Translation.tr("Phone unreachable or GPS server not running");
                    phoneSetupDialog.show = true;
                    return;
                }
                try {
                    const data = JSON.parse(text);
                    if (typeof data.latitude === "number" && typeof data.longitude === "number") {
                        root.setCandidate(data.latitude, data.longitude, true);
                        root.cameraLatitude = data.latitude;
                        root.cameraLongitude = data.longitude;
                        root.mapZoom = root.focusedZoom;
                        embeddedMap.recenter(data.latitude, data.longitude, root.focusedZoom);
                        if (pickerModal.show) {
                            pickerModal.recenter(data.latitude, data.longitude, root.focusedZoom, 0, 0);
                        }
                        root.coordinateError = "";
                        phoneSetupDialog.show = false;
                        return;
                    }
                } catch (e) {
                    console.log("[LocationPicker] phone GPS parse error: " + e);
                }
                root.coordinateError = Translation.tr("Failed to read location from phone");
                phoneSetupDialog.show = true;
            }
        }
    }

    function syncFromPhone() {
        if (!phoneSyncProcess.running) {
            root.coordinateError = "";
            phoneSyncProcess.running = true;
        }
    }

    function coordinateText(lat, lon) {
        return Number(lat).toFixed(6) + ", " + Number(lon).toFixed(6);
    }

    function setCandidate(lat, lon, resolveCity) {
        root.candidateLatitude = lat;
        root.candidateLongitude = lon;
        coordinateField.text = root.coordinateText(lat, lon);
        root.coordinateError = "";

        if (resolveCity) {
            reverseGeocode(lat, lon);
        }
    }

    function formatAddress(data) {
        if (!data) return "";
        const addr = data.address || {};
        const local = addr.neighbourhood || addr.suburb || addr.residential || addr.quarter || addr.road || addr.village || addr.hamlet || "";
        const city = addr.city || addr.town || addr.municipality || addr.county || addr.state_district || "";
        if (local && city && local.toLowerCase() !== city.toLowerCase()) {
            return `${local}, ${city}`;
        }
        if (local) return local;
        if (city) return city;
        if (data.name) return data.name;
        if (data.display_name) {
            return data.display_name.split(",").slice(0, 2).map(s => s.trim()).join(", ");
        }
        return "";
    }

    function reverseGeocode(lat, lon) {
        root.geocoding = true;
        const xhr = new XMLHttpRequest();
        const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&addressdetails=1`;
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "QuickShellWeather/1.0");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.geocoding = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const foundName = root.formatAddress(data);
                    if (foundName.length > 0) {
                        root.candidateCity = foundName;
                        cityField.text = foundName;
                    }
                } catch (e) {
                    console.log("[LocationPicker] reverse geocode parse error: " + e);
                }
            }
        };
        xhr.send();
    }

    function searchCityFallback(query) {
        const xhr = new XMLHttpRequest();
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(query.trim())}&count=1`;
        xhr.open("GET", url);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            root.geocoding = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const result = (data && data.results && data.results.length > 0) ? data.results[0] : null;
                    if (result && !isNaN(result.latitude) && !isNaN(result.longitude)) {
                        root.setCandidate(result.latitude, result.longitude, false);
                        root.cameraLatitude = result.latitude;
                        root.cameraLongitude = result.longitude;
                        root.candidateCity = result.name;
                        cityField.text = result.name;
                        embeddedMap.recenter(result.latitude, result.longitude, root.focusedZoom);
                    } else {
                        root.coordinateError = Translation.tr("Location not found");
                    }
                } catch (e) {
                    console.log("[LocationPicker] fallback search error: " + e);
                }
            }
        };
        xhr.send();
    }

    function searchCity(query) {
        if (!query || query.trim().length === 0) return;
        root.geocoding = true;
        const xhr = new XMLHttpRequest();
        const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query.trim())}&format=json&limit=1&addressdetails=1`;
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "QuickShellWeather/1.0");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const result = (data && data.length > 0) ? data[0] : null;
                    if (result && !isNaN(result.lat) && !isNaN(result.lon)) {
                        root.geocoding = false;
                        const lat = Number(result.lat);
                        const lon = Number(result.lon);
                        const foundName = root.formatAddress(result) || result.name || query.trim();
                        root.setCandidate(lat, lon, false);
                        root.cameraLatitude = lat;
                        root.cameraLongitude = lon;
                        root.candidateCity = foundName;
                        cityField.text = foundName;
                        embeddedMap.recenter(lat, lon, root.focusedZoom);
                    } else {
                        root.searchCityFallback(query);
                    }
                } catch (e) {
                    root.searchCityFallback(query);
                }
            } else {
                root.searchCityFallback(query);
            }
        };
        xhr.send();
    }

    function commitCoordinate() {
        const values = coordinateField.text.trim().split(/[\s,]+/);
        if (values.length !== 2 || values[0] === "" || values[1] === "") {
            root.coordinateError = Translation.tr("Enter latitude and longitude");
            return;
        }
        const lat = Number(values[0]);
        const lon = Number(values[1]);
        if (!isFinite(lat) || lat < -90 || lat > 90) {
            root.coordinateError = Translation.tr("Latitude must be between -90 and 90");
            return;
        }
        if (!isFinite(lon) || lon < -180 || lon > 180) {
            root.coordinateError = Translation.tr("Longitude must be between -180 and 180");
            return;
        }
        root.setCandidate(lat, lon, true);
        root.cameraLatitude = lat;
        root.cameraLongitude = lon;
        embeddedMap.recenter(lat, lon, root.mapZoom);
    }

    function returnToSavedLocation() {
        const lat = root.getSavedLatitude();
        const lon = root.getSavedLongitude();
        root.setCandidate(lat, lon, false);
        root.candidateCity = Config.options.bar.weather.city || Weather.cityName || "";
        cityField.text = root.candidateCity;
        root.cameraLatitude = lat;
        root.cameraLongitude = lon;
        root.mapZoom = root.focusedZoom;
        root.mapBearing = root.initialBearing;
        root.mapTilt = root.initialTilt;
        embeddedMap.recenter(lat, lon, root.focusedZoom, root.initialBearing, root.initialTilt);
    }

    function saveCoordinate() {
        root.commitCoordinate();
        if (root.coordinateError !== "")
            return;

        Config.options.bar.weather.enableGPS = false;
        Config.options.bar.weather.latitude = Number(root.candidateLatitude);
        Config.options.bar.weather.longitude = Number(root.candidateLongitude);
        const cityName = root.candidateCity.length > 0 ? root.candidateCity : root.coordinateText(root.candidateLatitude, root.candidateLongitude);
        Config.options.bar.weather.city = cityName;

        if (typeof Weather.setManualLocation === "function") {
            Weather.setManualLocation(root.candidateLatitude, root.candidateLongitude, cityName);
        }
    }

    function useAutomaticLocation() {
        Config.options.bar.weather.enableGPS = true;
        Config.options.bar.weather.latitude = 0;
        Config.options.bar.weather.longitude = 0;
        if (typeof Weather.clearManualLocation === "function") {
            Weather.clearManualLocation();
        }
        root.returnToSavedLocation();
    }

    function cycleStyle() {
        root.currentStyleIndex = (root.currentStyleIndex + 1) % root.mapStyles.length;
    }

    spacing: 12

    // Search and Coordinate Inputs
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        MaterialTextField {
            id: cityField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search city name...")
            text: root.candidateCity
            onAccepted: root.searchCity(text)

            Timer {
                id: searchDebounce
                interval: 800
                repeat: false
                onTriggered: root.searchCity(cityField.text)
            }
            onTextChanged: {
                root.coordinateError = "";
                if (cityField.activeFocus) {
                    searchDebounce.restart();
                }
            }
        }

        MaterialTextField {
            id: coordinateField
            Layout.preferredWidth: 210
            placeholderText: Translation.tr("Latitude, Longitude")
            text: root.coordinateText(root.candidateLatitude, root.candidateLongitude)
            onAccepted: root.commitCoordinate()
            onEditingFinished: root.commitCoordinate()
        }
    }

    // Error Feedback
    StyledText {
        visible: root.coordinateError.length > 0
        text: root.coordinateError
        font.pixelSize: 12
        color: Appearance.colors.colError
        Layout.fillWidth: true
    }

    // Map Card Frame
    Rectangle {
        id: mapFrame
        Layout.fillWidth: true
        Layout.preferredHeight: 270
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Item {
            id: mapWrapper
            anchors.fill: parent
            anchors.margins: 1
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: mapWrapper.width
                    height: mapWrapper.height
                    radius: Math.max(0, mapFrame.radius - 1)
                }
            }

            MapLibreView {
                id: embeddedMap
                anchors.fill: parent
                active: root.visible && !pickerModal.show
                styleUrl: root.activeStyleUrl
                centerLatitude: root.cameraLatitude
                centerLongitude: root.cameraLongitude
                markerLatitude: root.candidateLatitude
                markerLongitude: root.candidateLongitude
                markerVisible: true
                markerDraggable: true
                zoomLevel: root.mapZoom
                bearing: root.mapBearing
                tilt: root.mapTilt

                onReadyChanged: {
                    if (ready) {
                        embeddedMap.recenter(root.candidateLatitude, root.candidateLongitude, root.mapZoom);
                    }
                }

                onCameraMoved: (latitudeValue, longitudeValue, zoom, bearingValue, tiltValue) => {
                    root.mapZoom = zoom;
                    root.cameraLatitude = latitudeValue;
                    root.cameraLongitude = longitudeValue;
                    root.mapBearing = bearingValue;
                    root.mapTilt = tiltValue;
                }
                onMarkerMoved: (latitudeValue, longitudeValue) => {
                    root.setCandidate(latitudeValue, longitudeValue, true);
                }
            }
        }

        // Floating Control Buttons on top-right of the map
        Rectangle {
            id: floatingControls
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            implicitHeight: 38
            implicitWidth: controlsRow.implicitWidth + 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3Base
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            RowLayout {
                id: controlsRow
                anchors.centerIn: parent
                spacing: 2

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                    onClicked: root.cycleStyle()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "layers"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Style: ") + root.mapStyles[root.currentStyleIndex].name }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                    onClicked: {
                        root.cameraLatitude = root.candidateLatitude;
                        root.cameraLongitude = root.candidateLongitude;
                        root.mapZoom = root.focusedZoom;
                        embeddedMap.recenter(root.candidateLatitude, root.candidateLongitude, root.focusedZoom);
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "my_location"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Center marker") }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                    onClicked: root.syncFromPhone()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "smartphone"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Sync from phone GPS") }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                    onClicked: root.returnToSavedLocation()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "restore"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Reset location") }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                    onClicked: {
                        root.cameraLatitude = root.candidateLatitude;
                        root.cameraLongitude = root.candidateLongitude;
                        root.mapZoom = Math.max(root.mapZoom, root.focusedZoom);
                        pickerModal.show = true;
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_full"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Expand map") }
                }
            }
        }

        // Attribution tag on bottom-left
        MapAttribution {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 10
        }
    }

    // Action Buttons Row
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        MaterialLoadingIndicator {
            visible: root.geocoding || Weather.loading || root.syncingPhone
            loading: visible
            implicitSize: 32
        }

        Item { Layout.fillWidth: true }

        RippleButtonWithIcon {
            mainText: Translation.tr("Sync Phone GPS")
            materialIcon: "smartphone"
            colBackground: Appearance.colors.colLayer2
            iconColor: Appearance.colors.colOnSecondaryContainer
            textColor: Appearance.colors.colOnSecondaryContainer
            onClicked: root.syncFromPhone()
        }

        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: 18
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
            onClicked: phoneSetupDialog.show = true

            MaterialSymbol {
                anchors.centerIn: parent
                text: "help_outline"
                iconSize: 20
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledToolTip { text: Translation.tr("Phone GPS setup guide") }
        }

        RippleButtonWithIcon {
            mainText: Translation.tr("Save Location")
            materialIcon: "save"
            colBackground: Appearance.colors.colPrimary
            iconColor: Appearance.colors.colOnPrimary
            textColor: Appearance.colors.colOnPrimary
            onClicked: root.saveCoordinate()
        }

        RippleButtonWithIcon {
            mainText: Translation.tr("Use GPS Location")
            materialIcon: "my_location"
            colBackground: Appearance.colors.colLayer2
            iconColor: Appearance.colors.colOnSecondaryContainer
            textColor: Appearance.colors.colOnSecondaryContainer
            enabled: !Config.options.bar.weather.enableGPS
            onClicked: root.useAutomaticLocation()
        }
    }

    // Modal overlay for expanding
    LocationPickerModal {
        id: pickerModal
        z: 9999
        show: false
        centerLatitude: root.cameraLatitude
        centerLongitude: root.cameraLongitude
        markerLatitude: root.candidateLatitude
        markerLongitude: root.candidateLongitude
        zoomLevel: root.mapZoom
        bearing: root.mapBearing
        tilt: root.mapTilt
        locationName: root.candidateCity
        styleUrl: root.activeStyleUrl
        styleName: root.mapStyles[root.currentStyleIndex].name

        onCycleStyleRequested: root.cycleStyle()
        onSyncFromPhoneRequested: root.syncFromPhone()
        onShowPhoneGuideRequested: phoneSetupDialog.show = true

        onCameraChanged: (lat, lon, zoom, bearingVal, tiltVal) => {
            root.mapZoom = zoom;
            root.mapBearing = bearingVal;
            root.mapTilt = tiltVal;
            root.cameraLatitude = lat;
            root.cameraLongitude = lon;
        }

        onMarkerChanged: (lat, lon) => {
            root.setCandidate(lat, lon, true);
        }

        onSaveRequested: root.saveCoordinate()
        onRestoreRequested: root.returnToSavedLocation()
    }

    // Modal overlay for Phone GPS Setup Guide
    PhoneGpsSetupDialog {
        id: phoneSetupDialog
        show: false
        onTestRequested: root.syncFromPhone()
    }

    Component.onCompleted: {
        root.returnToSavedLocation();
    }

    Component.onDestruction: {
        if (pickerModal) {
            pickerModal.destroy();
        }
        if (phoneSetupDialog) {
            phoneSetupDialog.destroy();
        }
    }
}
