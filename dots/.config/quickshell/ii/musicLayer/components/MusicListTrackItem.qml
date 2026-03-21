import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Reusable track list item with index, art, and title/artist
Item {
    id: root

    property var rootContext
    property var track
    property int indexNumber: -1 // Optional number to display on the left

    Layout.fillWidth: true
    height: 64

    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: trackHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 14

        // Index number (optional)
        StyledText {
            visible: root.indexNumber >= 0
            text: root.indexNumber
            color: rootContext.secondaryContentColor
            font.pixelSize: 14
            font.weight: 600
            Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
        }

        // Art with play button
        Rectangle {
            width: 40
            height: 40
            radius: 8
            color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer2

            RoundedImage {
                anchors.fill: parent
                source: root.track.artUrl || ""
                sourceSize.width: 96
                sourceSize.height: 96
                fillMode: Image.PreserveAspectCrop
                radius: 8
                cache: true
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.25)
                radius: 8
                visible: trackHover.containsMouse || (rootContext && rootContext.currentTrack && rootContext.currentTrack.videoId === root.track.videoId)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: (rootContext && rootContext.currentTrack && rootContext.currentTrack.videoId === root.track.videoId) ? (rootContext.playbackPaused ? "play_arrow" : "pause") : "play_arrow"
                    color: rootContext.contentColor
                    iconSize: 24
                }
            }
        }

        // Text details
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 320
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.track.title || ""
                font.weight: 600
                color: (rootContext && rootContext.currentTrack && rootContext.currentTrack.videoId === root.track.videoId) ? (rootContext.extractedColor || rootContext.pillColor) : rootContext.contentColor
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }

            StyledText {
                Layout.fillWidth: true
                text: root.track.artist || ""
                font.pixelSize: 12
                color: rootContext.secondaryContentColor
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }
        }

    }

    MouseArea {
        id: trackHover
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.clicked()
    }
}
