import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Rectangle {
    id: root

    property var rootContext
    property bool navRailExpanded: false
    readonly property color elevatedPanelColor: rootContext
        ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.05)
        : Appearance.colors.colLayer1

    property bool isExpanding: rootContext && rootContext.currentView === "player"


    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottomMargin: isExpanding ? 0 : 24
    anchors.leftMargin: isExpanding ? 0 : ((navRailExpanded ? 150 : 80) + 32)
    anchors.rightMargin: isExpanding ? 0 : 24

    height: isExpanding ? parent.height : 80
    radius: isExpanding ? 32 : 20

    Behavior on height { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
    Behavior on anchors.bottomMargin { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    Behavior on anchors.leftMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    Behavior on anchors.rightMargin { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
    Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

    color: root.elevatedPanelColor

    visible: rootContext.currentTrack !== null
    z: 100

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.25)
        shadowBlur: 1.0
        shadowVerticalOffset: 4
    }

    transform: Translate {
        y: ((rootContext.showMusic || rootContext.closing) && rootContext.currentTrack !== null) ? 0 : 100
        Behavior on y {
            NumberAnimation {
                duration: 500
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        scrollGestureEnabled: false
        enabled: !root.isExpanding
        onClicked: {
            if (rootContext && rootContext.currentTrack) {
                rootContext.currentView = "player"
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 16
        
        opacity: root.isExpanding ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

        property string _trackId: rootContext.currentTrack ? rootContext.currentTrack.videoId : ""
        on_TrackIdChanged: {
            if (_trackId !== "") {
                miniArtAnim.restart()
                miniInfoAnim.restart()
            }
        }

        SequentialAnimation {
            id: miniArtAnim
            ParallelAnimation {
                NumberAnimation { target: miniArtRect; property: "scale"; from: 0.85; to: 1.0; duration: 500; easing.type: Easing.OutElastic; easing.amplitude: 1.2 }
                NumberAnimation { target: miniArtRect; property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
            }
        }

        SequentialAnimation {
            id: miniInfoAnim
            ParallelAnimation {
                NumberAnimation { target: miniInfoCol; property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: miniInfoCol; property: "scale"; from: 0.95; to: 1.0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
            }
        }

        Rectangle {
            id: miniArtRect
            width: 56
            height: 56
            radius: 12
            color: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : Appearance.colors.colLayer2
            clip: true
            
            RoundedImage {
                anchors.fill: parent
                source: rootContext.displayedArtFilePath
                fillMode: Image.PreserveAspectCrop
                visible: rootContext.displayedArtFilePath !== ""
                radius: 12
            }
        }

        ColumnLayout {
            id: miniInfoCol
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: rootContext.currentTrack ? rootContext.currentTrack.title : ""
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: 600
                color: rootContext.contentColor
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: rootContext.currentTrack ? rootContext.currentTrack.artist : ""
                font.pixelSize: Appearance.font.pixelSize.normal
                color: rootContext.secondaryContentColor
                elide: Text.ElideRight
            }
        }

        RowLayout {
            spacing: 8

            RippleButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                buttonRadius: 24
                rippleEnabled: false
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                horizontalPadding: 0
                verticalPadding: 0

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_previous"
                    iconSize: 24
                    fill: 1
                    color: rootContext.contentColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: rootContext.sendCommand({"command": "previous"})
            }

            RippleButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                buttonRadius: 24
                rippleEnabled: false
                pointingHandCursor: !rootContext.isTrackLoading
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                horizontalPadding: 0
                verticalPadding: 0

                contentItem: Item {
                    anchors.fill: parent

                    MaterialLoadingIndicator {
                        anchors.centerIn: parent
                        implicitSize: 24
                        loading: rootContext.isTrackLoading
                        visible: rootContext.isTrackLoading
                        color: rootContext.pillColor
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: rootContext.playbackPaused ? "play_arrow" : "pause"
                        color: rootContext.contentColor
                        iconSize: 24
                        visible: !rootContext.isTrackLoading
                    }
                }
            }

            RippleButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                buttonRadius: 24
                rippleEnabled: false
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(rootContext.contentColor, 0.08)
                colRipple: ColorUtils.applyAlpha(rootContext.contentColor, 0.2)
                horizontalPadding: 0
                verticalPadding: 0

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "skip_next"
                    iconSize: 24
                    fill: 1
                    color: rootContext.contentColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: rootContext.sendCommand({"command": "next"})
            }
        }
    }
}
