import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Reusable album art thumbnail with play button overlay
Rectangle {
    id: root

    property var rootContext
    property string artUrl: ""
    property string videoId: ""
    property int size: 48
    property int indexNumber: -1  // Optional index to display on left
    property bool showIndex: indexNumber >= 0

    width: showIndex ? (indexLabel.implicitWidth + 16 + size) : size
    height: size
    radius: 8
    color: "transparent"

    signal clicked()

    RowLayout {
        anchors.fill: parent
        spacing: 8

        // Index number (optional)
        StyledText {
            id: indexLabel
            visible: root.showIndex
            text: root.indexNumber
            color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
            font.pixelSize: 14
            font.weight: 600
            Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
        }

        // Art with play button overlay
        Rectangle {
            width: root.size
            height: root.size
            radius: 8
            color: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.4) : Appearance.colors.colLayer2

            RoundedImage {
                anchors.fill: parent
                source: root.artUrl
                sourceSize.width: root.size * 2
                sourceSize.height: root.size * 2
                fillMode: Image.PreserveAspectCrop
                radius: 8
                asynchronous: true
                cache: true
            }

            // Play button overlay
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colScrim
                radius: 8
                visible: artMouse.containsMouse || (rootContext && rootContext.currentTrack && rootContext.currentTrack.videoId === root.videoId)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: {
                        if (rootContext && rootContext.currentTrack && rootContext.currentTrack.videoId === root.videoId) {
                            return rootContext.playbackPaused ? "play_arrow" : "pause"
                        }
                        return "play_arrow"
                    }
                    color: Appearance.colors.colOnSurface
                    iconSize: 24
                }
            }

            MouseArea {
                id: artMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clicked()
            }
        }
    }
}
