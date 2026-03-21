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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

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

            // Title and Artist (left side)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 200
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

            // Buttons (right side)
            RowLayout {
                Layout.preferredWidth: 320
                spacing: 6

                // Heart/Like button
                GroupButton {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 36
                    baseWidth: 44
                    baseHeight: 36
                    buttonRadius: 18
                    buttonRadiusPressed: 14
                    colBackground: rootContext.pillColor
                    colBackgroundHover: rootContext.pillColorHover
                    colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.15)
                    colBackgroundToggled: Appearance.colors.colError
                    colBackgroundToggledHover: ColorUtils.mix(Appearance.colors.colError, "white", 0.1)
                    colBackgroundToggledActive: ColorUtils.mix(Appearance.colors.colError, "black", 0.1)
                    toggled: rootContext.currentTrackLiked

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: rootContext.currentTrackLiked ? "favorite" : "favorite_border"
                        iconSize: 22
                        fill: rootContext.currentTrackLiked ? 1 : 0
                        color: rootContext.currentTrackLiked ? rootContext.pillContentColor : rootContext.contentColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    releaseAction: () => { rootContext.toggleCurrentTrackLike() }
                }

                // Queue/Radio button
                GroupButton {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 36
                    baseWidth: 44
                    baseHeight: 36
                    buttonRadius: 18
                    buttonRadiusPressed: 14
                    colBackground: rootContext.pillColor
                    colBackgroundHover: rootContext.pillColorHover
                    colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.15)
                    colBackgroundToggled: rootContext.pillColor
                    colBackgroundToggledHover: rootContext.pillColorHover
                    colBackgroundToggledActive: rootContext.pillColor
                    toggled: rootContext.radioTrayVisible

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "queue_music"
                        iconSize: 22
                        fill: 1
                        color: rootContext.radioTrayVisible ? rootContext.pillContentColor : rootContext.contentColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    releaseAction: () => { rootContext.radioTrayVisible = !rootContext.radioTrayVisible }
                }

                // Previous button
                GroupButton {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 36
                    baseWidth: 44
                    baseHeight: 36
                    buttonRadius: 18
                    buttonRadiusPressed: 14
                    colBackground: rootContext.pillColor
                    colBackgroundHover: rootContext.pillColorHover
                    colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.15)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_previous"
                        iconSize: 22
                        fill: 1
                        color: rootContext.contentColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    releaseAction: () => { rootContext.sendCommand({"command": "previous"}) }
                }

                // Play/Pause button
                GroupButton {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 36
                    baseWidth: 44
                    baseHeight: 36
                    buttonRadius: 18
                    buttonRadiusPressed: 14
                    colBackground: rootContext.pillColor
                    colBackgroundHover: rootContext.pillColorHover
                    colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.15)

                    contentItem: Item {
                        anchors.fill: parent

                        MaterialLoadingIndicator {
                            anchors.centerIn: parent
                            implicitSize: 20
                            loading: rootContext.isTrackLoading
                            visible: rootContext.isTrackLoading
                            color: ColorUtils.applyAlpha(rootContext.loaderAccentColor, 0.2)
                            shapeColor: rootContext.loaderAccentColor
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: rootContext.playbackPaused ? "play_arrow" : "pause"
                            color: rootContext.contentColor
                            iconSize: 22
                            visible: !rootContext.isTrackLoading
                        }
                    }

                    releaseAction: () => {
                        if (rootContext.isTrackLoading) return
                        if (rootContext.playbackPaused) {
                            rootContext.sendCommand({"command": "resume"})
                        } else {
                            rootContext.sendCommand({"command": "pause"})
                        }
                    }
                }

                // Next button
                GroupButton {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 36
                    baseWidth: 44
                    baseHeight: 36
                    buttonRadius: 18
                    buttonRadiusPressed: 14
                    colBackground: rootContext.pillColor
                    colBackgroundHover: rootContext.pillColorHover
                    colBackgroundActive: ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.15)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_next"
                        iconSize: 22
                        fill: 1
                        color: rootContext.contentColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    releaseAction: () => { rootContext.sendCommand({"command": "next"}) }
                }
            }
        }

        // Progress bar (full width at bottom)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 28

                configuration: (!rootContext.isTrackLoading && !rootContext.playbackPaused) ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.Sleek
                highlightColor: rootContext.contentColor
                trackColor: ColorUtils.applyAlpha(rootContext.contentColor, 0.3)
                handleColor: rootContext.contentColor

                value: rootContext.trackDurationSec > 0 ? rootContext.trackPositionSec / rootContext.trackDurationSec : 0
                Behavior on value { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }

                enabled: rootContext.trackDurationSec > 0
                onMoved: {
                    if (rootContext.trackDurationSec > 0) {
                        let seekPos = value * rootContext.trackDurationSec
                        rootContext.sendCommand({"command": "seek", "position": seekPos})
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(rootContext.trackPositionSec)
                    font.pixelSize: 11
                    color: rootContext.secondaryContentColor
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: StringUtils.friendlyTimeForSeconds(rootContext.trackDurationSec)
                    font.pixelSize: 11
                    color: rootContext.secondaryContentColor
                }
            }
        }
    }
}
