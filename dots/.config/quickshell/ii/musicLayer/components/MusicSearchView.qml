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


    anchors.fill: parent
    contentHeight: resultsColumn.implicitHeight + (rootContext.currentTrack ? 120 : 32)

    property bool show: queryText.length > 0 && rootContext.currentView !== "playlist" && rootContext.currentView !== "artist" && rootContext.currentView !== "artist_items" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    clip: true

    ColumnLayout {
        id: resultsColumn
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // Artists
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.artistResults.count > 0

            StyledText {
                text: "Artists"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext.contentColor
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 20

                Repeater {
                    model: rootContext.artistResults

                    delegate: MusicMediaCard {
                        width: 120
                        height: 140
                        rootContext: root.rootContext
                        itemData: model
                        hoverColor: ColorUtils.transparentize(rootContext.pillColor, 0.5)
                        artPlaceholderColor: ColorUtils.transparentize(rootContext.pillColor, 0.4)

                        onClicked: {
                            rootContext.openArtist(model.videoId || "")
                        }
                    }
                }
            }
        }

        // Songs
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.songResults.count > 0

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: "Songs"
                    font.pixelSize: 20
                    font.weight: 700
                    color: rootContext.contentColor
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    visible: rootContext.searchSongsHasMore
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 34
                    buttonRadius: 17
                    colBackground: rootContext ? rootContext.pillColor : Appearance.colors.colLayer2Base
                    
                    contentItem: Item {
                        anchors.fill: parent
                        StyledText {
                            anchors.centerIn: parent
                            text: "Load more"
                            font.pixelSize: 13
                            font.weight: 600
                            color: rootContext.contentColor
                        }
                    }

                    onClicked: rootContext.loadMoreSongs()
                }
            }

            Rectangle {
                id: songsContainer
                Layout.fillWidth: true
                implicitHeight: songResultsColumn.height + 32
                Layout.preferredHeight: implicitHeight
                radius: 24
                color: ColorUtils.transparentize(rootContext.pillColor, 0.85)
                clip: true

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                ColumnLayout {
                    id: songResultsColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: rootContext.songResults

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: 12
                            color: songHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 16

                                Rectangle {
                                    width: 48
                                    height: 48
                                    radius: 8
                                    color: ColorUtils.transparentize(rootContext.pillColor, 0.4)

                                    RoundedImage {
                                        anchors.fill: parent
                                        source: model.artUrl
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        radius: 8
                                        cache: true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Appearance.colors.colScrim
                                        visible: songHover.containsMouse

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            color: rootContext.contentColor
                                            iconSize: 24
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.title
                                        font.weight: 600
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.artist
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                }

                                StyledText {
                                    text: (model.duration && model.duration.length > 0) ? model.duration : "--:--"
                                    color: rootContext.secondaryContentColor
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: songHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl)
                            }
                        }
                    }
                }
            }
        }

        // Albums
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16
            visible: rootContext.albumResults.count > 0

            StyledText {
                text: "Albums"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext.contentColor
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 16

                Repeater {
                    model: rootContext.albumResults

                    delegate: ColumnLayout {
                        width: (parent.width - 64) / 5
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 12
                            color: albumHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.3) : ColorUtils.transparentize(rootContext.pillColor, 0.4)

                            RoundedImage {
                                anchors.fill: parent
                                source: model.artUrl
                                sourceSize.width: 272
                                sourceSize.height: 272
                                fillMode: Image.PreserveAspectCrop
                                radius: 12
                                cache: true
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: model.title
                            font.weight: 600
                            color: rootContext.contentColor
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: model.artist
                            font.pixelSize: 12
                            color: rootContext.secondaryContentColor
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: albumHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootContext.openPlaylist(model.videoId)
                        }
                    }
                }
            }
        }

        // Spacer
        Item {
            Layout.fillWidth: true
            height: rootContext.currentTrack ? 80 : 0
        }
    }
}
