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
    readonly property color elevatedPanelColor: isExpanding 
        ? (rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1)
        : (rootContext ? rootContext.miniplayerSurfaceColor : Appearance.colors.colLayer3Base)

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

    visible: rootContext && rootContext.currentTrack !== null
    z: 100

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.25)
        shadowBlur: 1.0
        shadowVerticalOffset: 4
    }

    transform: Translate {
        y: (rootContext && (rootContext.showMusic || rootContext.closing) && rootContext.currentTrack !== null) ? 0 : 100
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        opacity: root.isExpanding ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

        property string _trackId: rootContext && rootContext.currentTrack ? rootContext.currentTrack.videoId : ""
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
                NumberAnimation { target: miniInfoRow; property: "opacity"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.OutCubic }
                NumberAnimation { target: miniInfoRow; property: "scale"; from: 0.95; to: 1.0; duration: 400; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
            }
        }

        // Top row: Art + Title/Artist + Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Album Art
            Rectangle {
                id: miniArtRect
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                radius: 12
                color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer2
                clip: true

                RoundedImage {
                    anchors.fill: parent
                    source: rootContext ? rootContext.displayedArtFilePath : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: rootContext && rootContext.displayedArtFilePath !== ""
                    radius: 12
                }
            }

            // Title and Artist (left side)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 200
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: rootContext && rootContext.currentTrack ? rootContext.currentTrack.title : ""
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: 600
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rootContext && rootContext.currentTrack ? rootContext.currentTrack.artist : ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }

            // Buttons (right side)
            RowLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 6

                // Previous Button
                RippleButton {
                    id: prevBtnContainer
                    property bool isPressed: down

                    implicitWidth: 36 + (isPressed ? 10 : (playBtnContainer.isPressed ? -6 : 0))
                    implicitHeight: 36

                    Behavior on implicitWidth {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }

                    buttonRadius: 18
                    colBackground: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.2)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        fill: 1
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        text: "skip_previous"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: if (rootContext) rootContext.sendCommand({"command": "previous"})
                }

                // Play/Pause Button
                RippleButton {
                    id: playBtnContainer
                    property bool isPressed: down

                    implicitWidth: 70 + (isPressed ? 12 : (prevBtnContainer.isPressed ? -8 : (nextBtnContainer.isPressed ? -8 : 0)))
                    implicitHeight: 36

                    Behavior on implicitWidth {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }

                    buttonRadius: isPressed ? 14 : 18
                    colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colSecondaryContainer
                    colBackgroundHover: rootContext ? ColorUtils.mix(rootContext.pillColor, rootContext.pillContentColor, 0.9) : Appearance.colors.colSecondaryContainerHover
                    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer, 0.3)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        text: rootContext && rootContext.playbackPaused ? "play_arrow" : "pause"
                        color: rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer
                        iconSize: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (!rootContext) return
                        if (rootContext.isTrackLoading) return
                        if (rootContext.playbackPaused)
                            rootContext.sendCommand({"command": "resume"})
                        else
                            rootContext.sendCommand({"command": "pause"})
                    }
                }

                // Next Button
                RippleButton {
                    id: nextBtnContainer
                    property bool isPressed: down

                    implicitWidth: 36 + (isPressed ? 10 : (playBtnContainer.isPressed ? -6 : 0))
                    implicitHeight: 36

                    Behavior on implicitWidth {
                        animation: Appearance.animation.clickBounce.numberAnimation.createObject(this)
                    }
                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                            easing.overshoot: 2
                        }
                    }

                    buttonRadius: 18
                    colBackground: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.04)
                    colBackgroundHover: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.08)
                    colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.2)
                    horizontalPadding: 0
                    verticalPadding: 0

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 22
                        fill: 1
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                        text: "skip_next"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: if (rootContext) rootContext.sendCommand({"command": "next"})
                }
            }
        }
    }
}
