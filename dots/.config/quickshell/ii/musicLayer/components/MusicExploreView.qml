import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    property var rootContext
    property string queryText: ""
    readonly property var flickable: root
    readonly property color sectionCardColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    readonly property color artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    readonly property int releaseCount: Math.min(rootContext ? rootContext.exploreNewReleases.count : 0, 16)
    readonly property int trendingCount: Math.min(rootContext ? rootContext.exploreTrending.count : 0, 12)
    readonly property int bottomPadding: rootContext.currentTrack ? 120 : 32

    property bool show: queryText.length === 0 && rootContext.currentView === "explore" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: exploreColumn.implicitHeight + bottomPadding
    contentWidth: width
    pressDelay: 150

    function handlePlayTrack(trackData) {
        if (!trackData || !trackData.videoId) return;
        rootContext.playTrack(
            trackData.videoId,
            trackData.title || "",
            trackData.artist || "",
            trackData.artUrl || ""
        )
    }

    ColumnLayout {
        id: exploreColumn
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // New Releases
        Item {
            id: newReleasesWrapper
            Layout.fillWidth: true
            Layout.preferredHeight: root.releaseCount > 0 ? newReleaseContent.implicitHeight : 0
            visible: Layout.preferredHeight > 0 || opacity > 0
            opacity: root.releaseCount > 0 ? 1 : 0
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: newReleaseContent
                width: parent.width
                spacing: 16
                y: root.releaseCount > 0 ? 0 : 40
                Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: "New Releases"
                    font.pixelSize: 24
                    font.weight: 700
                    color: rootContext.contentColor
                }
            }

            MusicHorizontalFlickable {
                id: newReleaseRow
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                implicitHeight: 280
                contentWidth: newReleaseContentRow.implicitWidth
                contentHeight: newReleaseContentRow.implicitHeight
                clip: true
                interactive: contentWidth > width

                Row {
                    id: newReleaseContentRow
                    spacing: 0

                    Repeater {
                        model: root.releaseCount

                        delegate: MusicMediaCard {
                            width: 240
                            height: 280
                            rootContext: root.rootContext
                            itemData: rootContext.exploreNewReleases.get(index)
                            hoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"
                            artPlaceholderColor: root.artPlaceholderColor

                            onClicked: {
                                root.handlePlayTrack(itemData)
                            }
                        }
                    }
                }
            }
        }
        }

        // Trending Now
        Item {
            id: trendingWrapper
            Layout.fillWidth: true
            Layout.preferredHeight: root.trendingCount > 0 ? trendingContent.implicitHeight : 0
            visible: Layout.preferredHeight > 0 || opacity > 0
            opacity: root.trendingCount > 0 ? 1 : 0
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: trendingContent
                width: parent.width
                spacing: 16
                y: root.trendingCount > 0 ? 0 : 40
                Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

            StyledText {
                text: "Trending Now"
                font.pixelSize: 24
                font.weight: 700
                color: rootContext.contentColor
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: trendingColumn.height + 24
                Layout.preferredHeight: implicitHeight
                radius: 24
                color: root.sectionCardColor
                border.width: 0

                ColumnLayout {
                    id: trendingColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 4

                    Repeater {
                        model: root.trendingCount

                        delegate: MusicListTrackItem {
                            rootContext: root.rootContext
                            track: rootContext.exploreTrending.get(index)
                            indexNumber: index + 1
                            
                            onClicked: {
                                root.handlePlayTrack(track)
                            }
                        }
                    }
                }
            }
        }
        }

        Item {
            Layout.fillWidth: true
            height: root.bottomPadding
        }
    }
}
