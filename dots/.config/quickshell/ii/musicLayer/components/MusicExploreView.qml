import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    property var rootContext
    property string queryText: ""
    readonly property var flickable: root
    readonly property color sectionCardColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.7) : "#24ffffff"
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : "#2f3239"
    readonly property int releaseCount: Math.min(rootContext ? rootContext.exploreNewReleases.count : 0, 16)
    readonly property int trendingCount: Math.min(rootContext ? rootContext.exploreTrending.count : 0, 12)
    readonly property int bottomPadding: rootContext.currentTrack ? 120 : 32

    property bool show: queryText.length === 0 && rootContext.currentView === "explore" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: exploreColumn.implicitHeight + bottomPadding

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

            ListView {
                id: newReleaseRow
                Layout.fillWidth: true
                Layout.preferredHeight: 270
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                cacheBuffer: 1200
                model: root.releaseCount

                delegate: Item {
                    width: 184
                    height: 270
                    property var itemData: rootContext.exploreNewReleases.get(index)

                    Rectangle {
                        id: releaseCard
                        anchors.fill: parent
                        radius: 14
                        color: releaseHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"

                        Behavior on color { ColorAnimation { duration: 200 } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.topMargin: 8
                            anchors.bottomMargin: 14
                            spacing: 10

                            Rectangle {
                                id: releaseArtContainer
                                Layout.fillWidth: true
                                Layout.preferredHeight: 184
                                radius: 20
                                color: root.artPlaceholderColor

                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: releaseArtContainer.width
                                        height: releaseArtContainer.height
                                        radius: 20
                                        color: "white"
                                    }
                                }

                                Image {
                                    id: releaseArt
                                    anchors.fill: parent
                                    source: itemData.artUrl || ""
                                    sourceSize.width: 272
                                    sourceSize.height: 272
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    visible: status === Image.Ready
                                    scale: releaseHover.containsMouse ? 1.08 : 1.0

                                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#60000000"
                                    opacity: releaseHover.containsMouse ? 1.0 : 0.0

                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "play_arrow"
                                        color: "white"
                                        iconSize: 42
                                        scale: releaseHover.containsMouse ? 1.0 : 0.5

                                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: itemData.title || ""
                                font.pixelSize: 14
                                font.weight: 600
                                color: rootContext.contentColor
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: itemData.artist || ""
                                font.pixelSize: 12
                                color: rootContext.secondaryContentColor
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: releaseHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!itemData.videoId)
                                return
                            rootContext.playTrack(
                                itemData.videoId,
                                itemData.title || "",
                                itemData.artist || "",
                                itemData.artUrl || ""
                            )
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

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: 12
                            property var track: rootContext.exploreTrending.get(index)
                            color: trendHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 14

                                StyledText {
                                    text: index + 1
                                    color: rootContext.secondaryContentColor
                                    font.pixelSize: 14
                                    font.weight: 600
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Rectangle {
                                    width: 40
                                    height: 40
                                    radius: 8
                                    color: root.artPlaceholderColor

                                    RoundedImage {
                                        anchors.fill: parent
                                        source: track.artUrl || ""
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        radius: 8
                                        cache: true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#40000000"
                                        radius: 8
                                        visible: trendHover.containsMouse

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            color: "white"
                                            iconSize: 24
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 320
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: track.title || ""
                                        font.weight: 600
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: track.artist || ""
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                }

                                StyledText {
                                    text: (track.duration && track.duration.length > 0) ? track.duration : "--:--"
                                    color: rootContext.secondaryContentColor
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: trendHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!track.videoId)
                                        return
                                    rootContext.playTrack(
                                        track.videoId,
                                        track.title || "",
                                        track.artist || "",
                                        track.artUrl || ""
                                    )
                                }
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
