import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.map

Item {
    id: root

    property bool show: false
    property real centerLatitude: 0
    property real centerLongitude: 0
    property real markerLatitude: 0
    property real markerLongitude: 0
    property real zoomLevel: 14.5
    readonly property real focusedZoom: 14.5
    property real bearing: 0
    property real tilt: 0
    property string locationName: ""
    property string styleUrl: "https://tiles.openfreemap.org/styles/liberty"
    property string styleName: "Liberty"

    onShowChanged: {
        if (show) {
            root.centerLatitude = root.markerLatitude;
            root.centerLongitude = root.markerLongitude;
            root.zoomLevel = Math.max(root.zoomLevel, root.focusedZoom);
            modalMap.recenter(root.markerLatitude, root.markerLongitude, root.zoomLevel, 0, 0);
        }
    }

    signal cameraChanged(real latitude, real longitude, real zoom, real bearing, real tilt)
    signal markerChanged(real latitude, real longitude)
    signal cycleStyleRequested()
    signal syncFromPhoneRequested()
    signal showPhoneGuideRequested()
    signal restoreRequested
    signal saveRequested
    signal closed

    function recenter(latitudeValue, longitudeValue, zoomValue, bearingValue, tiltValue) {
        modalMap.recenter(latitudeValue, longitudeValue, zoomValue, bearingValue, tiltValue);
    }

    Component.onCompleted: {
        if (Window.window && Window.window.contentItem) {
            for (let i = Window.window.contentItem.children.length - 1; i >= 0; i--) {
                const child = Window.window.contentItem.children[i];
                if (child && child !== root && child.objectName === "locationPickerModalOverlay") {
                    child.destroy();
                }
            }
            objectName = "locationPickerModalOverlay";
            parent = Window.window.contentItem;
            anchors.fill = parent;
        }
    }

    visible: opacity > 0
    opacity: show ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Scrim backdrop
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.show = false;
                root.closed();
            }
        }
    }

    // Main Modal Card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 920)
        height: Math.min(parent.height - 48, 640)
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer4Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        scale: root.show ? 1 : 0.94
        Behavior on scale {
            NumberAnimation { duration: 250; easing.type: Easing.OutBack }
        }

        // Prevent clicking backdrop when clicking dialog
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Modal Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "map"
                    iconSize: 24
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    text: Translation.tr("Select Location")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer4
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: Appearance.colors.colLayer2Base
                    onClicked: {
                        root.show = false;
                        root.closed();
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer4
                    }
                }
            }

            // Map Frame
            Rectangle {
                id: mapFrame
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer0Base
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                Item {
                    id: modalMapWrapper
                    anchors.fill: parent
                    anchors.margins: 1
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: modalMapWrapper.width
                            height: modalMapWrapper.height
                            radius: Math.max(0, mapFrame.radius - 1)
                        }
                    }

                    MapLibreView {
                        id: modalMap
                        anchors.fill: parent
                        active: root.show
                        styleUrl: root.styleUrl
                        centerLatitude: root.centerLatitude
                        centerLongitude: root.centerLongitude
                        markerLatitude: root.markerLatitude
                        markerLongitude: root.markerLongitude
                        markerVisible: true
                        markerDraggable: true
                        zoomLevel: root.zoomLevel
                        bearing: root.bearing
                        tilt: root.tilt

                        onReadyChanged: {
                            if (ready && root.show) {
                                modalMap.recenter(root.markerLatitude, root.markerLongitude, root.zoomLevel);
                            }
                        }

                        onCameraMoved: (latitudeValue, longitudeValue, zoom, bearingValue, tiltValue) => {
                            root.cameraChanged(latitudeValue, longitudeValue, zoom, bearingValue, tiltValue);
                        }
                        onMarkerMoved: (latitudeValue, longitudeValue) => {
                            root.markerChanged(latitudeValue, longitudeValue);
                        }
                    }
                }

                // Floating Action Controls
                Rectangle {
                    id: modalFloatingControls
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    implicitHeight: 38
                    implicitWidth: modalControlsRow.implicitWidth + 8
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer3Base
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    RowLayout {
                        id: modalControlsRow
                        anchors.centerIn: parent
                        spacing: 2

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: 16
                            colBackground: "transparent"
                            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                            onClicked: root.cycleStyleRequested()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "layers"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip { text: Translation.tr("Style: ") + root.styleName }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: 16
                            colBackground: "transparent"
                            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                            onClicked: {
                                root.centerLatitude = root.markerLatitude;
                                root.centerLongitude = root.markerLongitude;
                                root.zoomLevel = root.focusedZoom;
                                modalMap.recenter(root.markerLatitude, root.markerLongitude, root.focusedZoom);
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "my_location"
                                iconSize: 20
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
                            onClicked: root.syncFromPhoneRequested()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "smartphone"
                                iconSize: 20
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
                            onClicked: root.showPhoneGuideRequested()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "help_outline"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip { text: Translation.tr("Phone GPS setup guide") }
                        }

                        RippleButton {
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: 16
                            colBackground: "transparent"
                            colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.12)
                            onClicked: root.restoreRequested()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "restore"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip { text: Translation.tr("Reset to current location") }
                        }
                    }
                }

                // Attribution Chip
                MapAttribution {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                }
            }

            // Modal Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true

                    StyledText {
                        text: root.locationName.length > 0 ? root.locationName : Translation.tr("Selected coordinates")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer4
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: Number(root.markerLatitude).toFixed(6) + ", " + Number(root.markerLongitude).toFixed(6)
                        font.pixelSize: 11
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButtonWithIcon {
                    mainText: Translation.tr("Cancel")
                    materialIcon: "cancel"
                    colBackground: Appearance.colors.colLayer2Base
                    iconColor: Appearance.colors.colOnSecondaryContainer
                    textColor: Appearance.colors.colOnSecondaryContainer
                    onClicked: {
                        root.show = false;
                        root.closed();
                    }
                }

                RippleButtonWithIcon {
                    mainText: Translation.tr("Save Location")
                    materialIcon: "check"
                    colBackground: Appearance.colors.colPrimary
                    iconColor: Appearance.colors.colOnPrimary
                    textColor: Appearance.colors.colOnPrimary
                    onClicked: {
                        root.saveRequested();
                        root.show = false;
                    }
                }
            }
        }
    }
}
