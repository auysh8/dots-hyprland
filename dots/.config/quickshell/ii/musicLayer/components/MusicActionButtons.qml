import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Reusable Play/Shuffle action buttons for playlist and artist views
Item {
    id: root

    property var rootContext
    property var tracksModel: null
    property string coverUrl: ""
    property string authorName: ""

    implicitHeight: 48

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // Play button
        RippleButton {
            Layout.preferredWidth: playRow.implicitWidth + 32
            Layout.preferredHeight: 48
            buttonRadius: 24
            property color bgColor: rootContext ? rootContext.pillColor : Appearance.colors.colPrimaryContainer
            property color txColor: rootContext ? rootContext.contentColor : Appearance.colors.colOnSecondaryContainer
            colBackground: bgColor
            colRipple: txColor

            contentItem: RowLayout {
                id: playRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "play_arrow"; color: parent.parent.txColor; iconSize: 24 }
                StyledText { Layout.alignment: Qt.AlignVCenter; text: "Play"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
            }

            onClicked: {
                if (rootContext && rootContext.tracksModel && rootContext.tracksModel.count > 0) {
                    let first = rootContext.tracksModel.get(0)
                    let queueTracks = []
                    for (let i = 1; i < rootContext.tracksModel.count; i++) {
                        let t = rootContext.tracksModel.get(i)
                        queueTracks.push({
                            videoId: t.videoId,
                            title: t.title,
                            artist: t.artist,
                            artUrl: t.artUrl || root.coverUrl,
                            duration: t.duration || ""
                        })
                    }
                    rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl || root.coverUrl, queueTracks)
                }
            }
        }

        // Shuffle button
        RippleButton {
            Layout.preferredWidth: shuffleRow.implicitWidth + 32
            Layout.preferredHeight: 48
            buttonRadius: 24
            property color bgColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : Appearance.colors.colLayer2Base
            property color txColor: rootContext ? rootContext.contentColor : Appearance.colors.colOnSecondaryContainer
            colBackground: bgColor
            colRipple: txColor

            contentItem: RowLayout {
                id: shuffleRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol { Layout.alignment: Qt.AlignVCenter; text: "shuffle"; color: parent.parent.txColor; iconSize: 24 }
                StyledText { Layout.alignment: Qt.AlignVCenter; text: "Shuffle"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
            }

            onClicked: {
                if (rootContext && rootContext.tracksModel && rootContext.tracksModel.count > 0) {
                    let tracksToPlay = []
                    for (let i = 0; i < rootContext.tracksModel.count; i++) {
                        let t = rootContext.tracksModel.get(i)
                        tracksToPlay.push({
                            videoId: t.videoId,
                            title: t.title,
                            artist: t.artist,
                            artUrl: t.artUrl || root.coverUrl,
                            duration: t.duration || ""
                        })
                    }
                    // Fisher-Yates shuffle
                    for (let i = tracksToPlay.length - 1; i > 0; i--) {
                        const j = Math.floor(Math.random() * (i + 1));
                        [tracksToPlay[i], tracksToPlay[j]] = [tracksToPlay[j], tracksToPlay[i]];
                    }
                    let first = tracksToPlay[0]
                    let queueTracks = tracksToPlay.slice(1)
                    rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl || root.coverUrl, queueTracks)
                }
            }
        }
    }
}
