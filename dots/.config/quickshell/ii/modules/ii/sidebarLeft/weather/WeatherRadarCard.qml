import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.map

Rectangle {
    id: root

    property bool presentationActive: true
    property real currentLatitude: (Weather && Weather.latitude) ? Number(Weather.latitude) : 28.6139
    property real currentLongitude: (Weather && Weather.longitude) ? Number(Weather.longitude) : 77.2090
    property string radarTileUrl: ""
    property int radarTimestamp: 0
    property bool loadingRadar: false
    property string radarError: ""
    property real zoomLevel: 6.5

    implicitWidth: parent ? parent.width : 340
    implicitHeight: 270
    radius: Appearance.rounding.large ?? 24
    color: ColorUtils.applyAlpha(Appearance.colors.colLayer2, 0.6)
    border.width: 1
    border.color: ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, 0.25)
    clip: true

    function fetchRadarMetadata() {
        if (loadingRadar) return;
        loadingRadar = true;
        radarError = "";

        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.rainviewer.com/public/weather-maps.json");
        xhr.setRequestHeader("User-Agent", "QuickShellRadar/1.0");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            loadingRadar = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText);
                    const host = data.host || "https://tilecache.rainviewer.com";
                    const past = (data.radar && data.radar.past && data.radar.past.length > 0)
                                 ? data.radar.past : [];
                    if (past.length > 0) {
                        const latest = past[past.length - 1];
                        root.radarTimestamp = latest.time || 0;
                        const tileTemplate = `${host}${latest.path}/256/{z}/{x}/{y}/2/1_1.png`;
                        root.radarTileUrl = tileTemplate;
                        radarMap.reload();
                    } else {
                        root.radarError = Translation.tr("Radar data unavailable");
                    }
                } catch (e) {
                    root.radarError = Translation.tr("Failed to parse radar");
                }
            } else {
                root.radarError = Translation.tr("Radar network error");
            }
        };
        xhr.send();
    }

    function timeAgoText(epoch) {
        if (!epoch) return Translation.tr("Live Snapshot");
        const diffSeconds = Math.max(0, Math.floor(Date.now() / 1000) - epoch);
        const mins = Math.floor(diffSeconds / 60);
        if (mins <= 1) return Translation.tr("Just now");
        if (mins < 60) return `${mins}m ago`;
        return `${Math.floor(mins / 60)}h ago`;
    }

    function recenterMap() {
        radarMap.recenter(root.currentLatitude, root.currentLongitude, root.zoomLevel);
    }

    onPresentationActiveChanged: {
        if (presentationActive && root.radarTileUrl === "") {
            fetchRadarMetadata();
        }
    }

    Component.onCompleted: {
        if (presentationActive) {
            fetchRadarMetadata();
        }
    }

    // Refresh every 10 minutes when presentation is active
    Timer {
        interval: 10 * 60 * 1000
        running: root.presentationActive
        repeat: true
        onTriggered: root.fetchRadarMetadata()
    }

    // Map View Container with rounded mask
    Item {
        id: mapContainer
        anchors.fill: parent
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: mapContainer.width
                height: mapContainer.height
                radius: root.radius
            }
        }

        MapLibreView {
            id: radarMap
            anchors.fill: parent
            active: root.presentationActive && root.radarTileUrl !== ""
            styleUrl: (Appearance.m3colors.darkmode ?? true)
                      ? "https://tiles.openfreemap.org/styles/dark"
                      : "https://tiles.openfreemap.org/styles/positron"
            centerLatitude: root.currentLatitude
            centerLongitude: root.currentLongitude
            markerLatitude: root.currentLatitude
            markerLongitude: root.currentLongitude
            zoomLevel: root.zoomLevel
            markerVisible: true
            overlayTileUrl: root.radarTileUrl
            overlayOpacity: 0.82
            overlayMaximumDisplayZoom: 8.5
        }

        // Top Gradient Shadow for readability of header controls
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 70
            gradient: Gradient {
                GradientStop { position: 0.0; color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 0.85) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Bottom Gradient Shadow for legend readability
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 44
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 0.75) }
            }
        }
    }

    // Header Overlay: Title, Timestamp, and Zoom/Recenter Controls
    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 8
        z: 6

        MaterialSymbol {
            text: "radar"
            iconSize: 20
            color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            spacing: 1
            StyledText {
                text: Translation.tr("Precipitation Radar")
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                text: root.loadingRadar ? Translation.tr("Updating...") : root.timeAgoText(root.radarTimestamp)
                font.pixelSize: 11
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        Item { Layout.fillWidth: true }

        // Recenter Button
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: 15
            colBackground: ColorUtils.applyAlpha(Appearance.colors.colLayer3Base, 0.8)
            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colLayer3Base, 1.0)
            onClicked: root.recenterMap()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "my_location"
                iconSize: 16
                color: Appearance.colors.colOnSurface
            }
        }

        // Zoom Out
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: 15
            colBackground: ColorUtils.applyAlpha(Appearance.colors.colLayer3Base, 0.8)
            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colLayer3Base, 1.0)
            onClicked: {
                root.zoomLevel = Math.max(3.0, root.zoomLevel - 1.0);
                radarMap.recenter(root.currentLatitude, root.currentLongitude, root.zoomLevel);
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "remove"
                iconSize: 16
                color: Appearance.colors.colOnSurface
            }
        }

        // Zoom In
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: 15
            colBackground: ColorUtils.applyAlpha(Appearance.colors.colLayer3Base, 0.8)
            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colLayer3Base, 1.0)
            onClicked: {
                root.zoomLevel = Math.min(8.0, root.zoomLevel + 1.0);
                radarMap.recenter(root.currentLatitude, root.currentLongitude, root.zoomLevel);
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "add"
                iconSize: 16
                color: Appearance.colors.colOnSurface
            }
        }
    }

    // Bottom Intensity Legend Bar
    RowLayout {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 10
        spacing: 6
        z: 6

        StyledText {
            text: Translation.tr("Rain")
            font.pixelSize: 10
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurfaceVariant
        }

        Rectangle {
            implicitWidth: 90
            implicitHeight: 6
            radius: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#4fc3f7" } // light rain
                GradientStop { position: 0.35; color: "#0288d1" } // moderate rain
                GradientStop { position: 0.65; color: "#ffb300" } // heavy rain
                GradientStop { position: 0.85; color: "#e53935" } // storm
                GradientStop { position: 1.0; color: "#8e24aa" } // severe/hail
            }
        }

        StyledText {
            text: Translation.tr("Heavy")
            font.pixelSize: 10
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    // Provider Badge
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 10
        spacing: 4
        z: 6

        StyledText {
            text: "RainViewer · OpenFreeMap"
            font.pixelSize: 10
            color: ColorUtils.applyAlpha(Appearance.colors.colOnSurfaceVariant, 0.7)
        }
    }

    // Loading / Offline Overlay
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.loadingRadar && root.radarTileUrl === ""
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 0.8)
        z: 7

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8
            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignHCenter
                loading: true
                implicitSize: 32
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Loading live radar...")
                font.pixelSize: 12
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    // Crisp Rounded Border Outline
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, 0.3)
        z: 5
    }
}
