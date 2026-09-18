import QtQuick
import QtLocation
import QtPositioning
import MapLibre 3.0
import qs.modules.common

Item {
    id: root

    required property string styleUrl
    required property string overlayTileUrl
    property real centerLatitude: 0
    property real centerLongitude: 0
    property real markerLatitude: 0
    property real markerLongitude: 0
    property real zoomLevel: 10
    property real bearing: 0
    property real tilt: 0
    property bool copyrightsVisible: false
    property bool markerVisible: true
    property bool markerDraggable: false
    property real overlayOpacity: 0.72
    property real overlayMaximumDisplayZoom: -1
    readonly property bool ready: map.mapReady
    readonly property string errorString: map.error !== 0 ? map.errorString : ""

    signal mapReady
    signal mapFailed(string message)
    signal coordinateTapped(real latitude, real longitude)
    signal markerMoved(real latitude, real longitude)
    signal cameraMoved(real latitude, real longitude, real zoom, real bearing, real tilt)

    function recenter(latitudeValue, longitudeValue, zoomValue, bearingValue, tiltValue) {
        map.center = QtPositioning.coordinate(latitudeValue, longitudeValue);
        if (zoomValue !== undefined)
            map.zoomLevel = zoomValue;
        if (bearingValue !== undefined)
            map.bearing = bearingValue;
        if (tiltValue !== undefined)
            map.tilt = tiltValue;
    }

    Component.onCompleted: {
        if (root.ready)
            root.mapReady();
    }

    Plugin {
        id: mapLibrePlugin

        name: "maplibre"

        PluginParameter {
            name: "maplibre.map.styles"
            value: root.styleUrl
        }
    }

    Map {
        id: map

        anchors.fill: parent
        plugin: mapLibrePlugin
        center: QtPositioning.coordinate(root.centerLatitude, root.centerLongitude)
        zoomLevel: root.zoomLevel
        bearing: root.bearing
        tilt: root.tilt
        copyrightsVisible: root.copyrightsVisible
        color: Appearance.colors.colSurfaceContainerHigh || Appearance.colors.colLayer1

        Connections {
            target: map
            function onMapReadyChanged() {
                if (map.mapReady)
                    root.mapReady();
            }

            function onErrorChanged() {
                if (map.error !== 0)
                    root.mapFailed(map.errorString);
            }

            function onCenterChanged() {
                root.cameraMoved(map.center.latitude, map.center.longitude, map.zoomLevel,
                                 map.bearing, map.tilt);
            }

            function onZoomLevelChanged() {
                root.cameraMoved(map.center.latitude, map.center.longitude, map.zoomLevel,
                                 map.bearing, map.tilt);
            }

            function onBearingChanged() {
                root.cameraMoved(map.center.latitude, map.center.longitude, map.zoomLevel,
                                 map.bearing, map.tilt);
            }

            function onTiltChanged() {
                root.cameraMoved(map.center.latitude, map.center.longitude, map.zoomLevel,
                                 map.bearing, map.tilt);
            }
        }

        MapLibre.style: Style {
            SourceParameter {
                property var tiles: [root.overlayTileUrl]
                property int tileSize: 256
                property int maxzoom: 7
                property int minzoom: 0

                styleId: "dots-weather-overlay-source"
                type: "raster"
            }

            LayerParameter {
                property string source: "dots-weather-overlay-source"
                property real maxzoom: root.overlayMaximumDisplayZoom > 0 ? root.overlayMaximumDisplayZoom - 1 : 25

                styleId: "dots-weather-overlay-layer"
                type: "raster"
                paint: {
                    "raster-opacity": root.overlayOpacity
                }
            }
        }

        DragHandler {
            target: null
            grabPermissions: PointerHandler.TakeOverForbidden
            onTranslationChanged: (delta) => {
                map.pan(-delta.x, -delta.y);
            }
        }
    }

    MapQuickItem {
        parent: map
        visible: root.markerVisible
        coordinate: QtPositioning.coordinate(root.markerLatitude, root.markerLongitude)
        anchorPoint: Qt.point(16, 16)
        zoomLevel: 0

        sourceItem: MapCoordinateMarker {}
    }
}
