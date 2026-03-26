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

    property color primaryBgColor: rootContext ? rootContext.pillColor : Appearance.colors.colPrimaryContainer
    property color primaryContentColor: rootContext ? rootContext.pillContentColor : Appearance.colors.colOnSecondaryContainer
    property color secondaryBgColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer2

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // Play button
        RippleButton {
            Layout.preferredWidth: playRow.implicitWidth + 32
            Layout.preferredHeight: 48
            buttonRadius: 24
            colBackground: root.primaryBgColor
            colBackgroundHover: ColorUtils.mix(root.primaryBgColor, root.primaryContentColor, 0.85)
            colRipple: ColorUtils.applyAlpha(root.primaryContentColor, 0.2)

            contentItem: RowLayout {
                id: playRow
                spacing: 8
                MaterialSymbol {
                    text: "play_arrow"
                    color: root.primaryContentColor
                    iconSize: 24
                    fill: 1
                }
                StyledText {
                    text: "Play"
                    color: root.primaryContentColor
                    font.pixelSize: 16
                    font.weight: 800
                }
            }

            onClicked: {
                if (rootContext && tracksModel && tracksModel.count > 0) {
                    let first = tracksModel.get(0)
                    let queueTracks = []
                    for (let i = 1; i < tracksModel.count; i++) {
                        let t = tracksModel.get(i)
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
            colBackground: root.secondaryBgColor
            colBackgroundHover: ColorUtils.mix(root.secondaryBgColor, rootContext ? rootContext.contentColor : root.primaryContentColor, 0.9)
            colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : root.primaryContentColor, 0.2)

            contentItem: RowLayout {
                id: shuffleRow
                spacing: 8
                MaterialSymbol {
                    text: "shuffle"
                    color: rootContext ? rootContext.contentColor : root.primaryContentColor
                    iconSize: 24
                }
                StyledText {
                    text: "Shuffle"
                    color: rootContext ? rootContext.contentColor : root.primaryContentColor
                    font.pixelSize: 16
                    font.weight: 800
                }
            }

            onClicked: {
                if (rootContext && tracksModel && tracksModel.count > 0) {
                    let tracksToPlay = []
                    for (let i = 0; i < tracksModel.count; i++) {
                        let t = tracksModel.get(i)
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
