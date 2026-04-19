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
    readonly property color elevatedPanelColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottomMargin: 24
    anchors.leftMargin: (navRailExpanded ? 150 : 80) + 32
    anchors.rightMargin: 24

    height: 80
    radius: 20

    Behavior on anchors.leftMargin { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    color: rootContext ? rootContext.miniplayerSurfaceColor : Appearance.colors.colLayer3Base

    visible: rootContext && rootContext.currentTrack !== null
    z: 100

    property bool shadowEnabled: false
    layer.enabled: visible && shadowEnabled
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.25)
        shadowBlur: 1.0
        shadowVerticalOffset: 4
    }

    onVisibleChanged: {
        if (visible) shadowTimer.restart()
    }

    Timer {
        id: shadowTimer
        interval: 400
        onTriggered: { root.shadowEnabled = true }
    }

    transform: Translate {
        y: (rootContext && (rootContext.showMusic || rootContext.closing) && rootContext.currentTrack !== null) ? 0 : 100
        Behavior on y {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        scrollGestureEnabled: false
        enabled: true
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

        opacity: 1.0

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

                Rectangle {
                    visible: rootContext && rootContext.currentTrack && rootContext.currentTrack.quality !== ""
                    radius: 4
                    color: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colPrimary, 0.2)
                    Layout.preferredWidth: miniQualityLabel.implicitWidth + 8
                    Layout.preferredHeight: miniQualityLabel.implicitHeight + 2

                    StyledText {
                        id: miniQualityLabel
                        anchors.centerIn: parent
                        text: rootContext && rootContext.currentTrack ? rootContext.currentTrack.quality.toUpperCase() : ""
                        font.pixelSize: 8
                        font.weight: 900
                        font.letterSpacing: 0.5
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colPrimary
                    }
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
