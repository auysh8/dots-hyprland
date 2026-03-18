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
    property color secondaryBgColor: rootContext ? ColorUtils.mix(rootContext.pillColor, rootContext.surfaceColor, 0.3) : Appearance.colors.colLayer2

    property color playButtonHover: rootContext ? ColorUtils.mix(rootContext.pillColor, rootContext.pillContentColor, 0.15) : Appearance.colors.colPrimaryContainerHover
    property color shuffleButtonHover: rootContext ? ColorUtils.mix(rootContext.secondaryBgColor, rootContext.pillContentColor, 0.15) : Appearance.colors.colLayer2Hover

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // Play button
        RippleButtonWithIcon {
            Layout.preferredWidth: playContent.implicitWidth + 32
            Layout.preferredHeight: 48
            buttonRadius: 24
            materialIcon: "play_arrow"
            materialIconFill: true
            colBackground: root.primaryBgColor
            colBackgroundHover: root.playButtonHover
            colRipple: ColorUtils.applyAlpha(root.primaryContentColor, 0.2)

            mainContentComponent: Component {
                id: playContent
                StyledText {
                    text: "Play"
                    color: root.primaryContentColor
                    font.pixelSize: 16
                    font.weight: 800
                }
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
        RippleButtonWithIcon {
            Layout.preferredWidth: shuffleContent.implicitWidth + 32
            Layout.preferredHeight: 48
            buttonRadius: 24
            materialIcon: "shuffle"
            materialIconFill: false
            colBackground: root.secondaryBgColor
            colBackgroundHover: root.shuffleButtonHover
            colRipple: ColorUtils.applyAlpha(root.primaryContentColor, 0.2)

            mainContentComponent: Component {
                id: shuffleContent
                StyledText {
                    text: "Shuffle"
                    color: root.primaryContentColor
                    font.pixelSize: 16
                    font.weight: 800
                }
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
