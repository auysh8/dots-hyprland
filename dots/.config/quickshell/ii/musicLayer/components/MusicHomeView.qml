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
    
    readonly property color artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    readonly property color cardHoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"

    readonly property real refreshThreshold: -100
    readonly property real refreshPullThreshold: -20
    readonly property real refreshY: -60

    anchors.fill: parent
    contentHeight: homeColumn.implicitHeight + ((rootContext && rootContext.currentTrack) ? 120 : 32)
    contentWidth: width
    flickableDirection: Flickable.VerticalFlick
    pressDelay: 150

    property bool show: queryText.length === 0 && rootContext && rootContext.currentView === "home" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    clip: true

    onDraggingChanged: {
        if (!dragging && rootContext && contentY <= refreshThreshold && !rootContext.refreshing && !rootContext.isLoading) {
            rootContext.refreshing = true
            rootContext.getHome()
        }
    }

    function handleItemClick(itemModel) {
        if (!rootContext) return
        if (itemModel.actualVideoId) {
            rootContext.playTrack(itemModel.actualVideoId, itemModel.title, itemModel.artist, itemModel.artUrl, undefined, itemModel.artistId, itemModel.albumId)
        } else if (itemModel.browseId) {
            if (itemModel.browseId.startsWith("UC")) {
                rootContext.openArtist(itemModel.browseId)
            } else {
                rootContext.openPlaylist(itemModel.browseId)
            }
        } else if (itemModel.playlistId) {
            rootContext.openPlaylist(itemModel.playlistId)
        } else if (itemModel.videoId) {
            rootContext.playTrack(itemModel.videoId, itemModel.title, itemModel.artist, itemModel.artUrl, undefined, itemModel.artistId, itemModel.albumId)
        }
    }

    Item {
        width: parent.width
        height: -refreshY
        y: refreshY
        visible: root.contentY < refreshPullThreshold

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            opacity: Math.min(Math.abs(root.contentY) / Math.abs(refreshThreshold), 1.0)

            MaterialLoadingIndicator {
                implicitSize: 24
                loading: true
                color: rootContext ? ColorUtils.applyAlpha(rootContext.loaderAccentColor, 0.2) : Appearance.colors.colPrimaryContainer
                shapeColor: rootContext ? rootContext.loaderAccentColor : Appearance.colors.colPrimary
            }

            StyledText {
                text: root.contentY < refreshThreshold ? "Release to refresh" : "Pull to refresh"
                font.weight: 600
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }
        }
    }

    ColumnLayout {
        id: homeColumn
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 0

        // 1. Recommendations Section
        ColumnLayout {
            id: recommendationsSection
            Layout.fillWidth: true
            spacing: 16
            
            property bool hasData: rootContext && rootContext.homeContent.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 0 : -height
            
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4

                    StyledText {
                        text: "Listen Again"
                        font.pixelSize: 24
                        font.weight: 700
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: "Jump back into your favorites"
                        font.pixelSize: 14
                        color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                    }
                }

                Item { Layout.fillWidth: true }
            }

            MusicHorizontalFlickable {
                id: recGrid
                Layout.fillWidth: true
                Layout.preferredHeight: recContent.implicitHeight
                implicitHeight: recContent.implicitHeight
                contentWidth: recContent.implicitWidth
                contentHeight: recContent.implicitHeight
                clip: true
                interactive: contentWidth > width

                Grid {
                    id: recContent
                    rows: Math.min(2, Math.max(1, rootContext ? rootContext.homeContent.count : 0))
                    flow: Grid.TopToBottom
                    rowSpacing: 0
                    columnSpacing: 0

                    Repeater {
                        model: rootContext ? rootContext.homeContent : null

                        delegate: MusicMediaCard {
                            width: 240
                            height: 280
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: root.cardHoverColor
                            artPlaceholderColor: root.artPlaceholderColor
                            onClicked: root.handleItemClick(model)
                        }
                    }
                }
            }
        }

        // 2. Quick Picks Section
        ColumnLayout {
            id: quickPicksSection
            Layout.fillWidth: true
            spacing: 16
            
            property bool hasData: rootContext && rootContext.quickPicks.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 32 : -height
            
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            StyledText {
                text: "Quick Picks"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: quickPicksColumn.height + 32
                Layout.preferredHeight: implicitHeight
                radius: 24
                color: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1

                ColumnLayout {
                    id: quickPicksColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: rootContext ? rootContext.quickPicks : null

                        delegate: MusicListTrackItem {
                            rootContext: root.rootContext
                            track: model
                            indexNumber: index + 1
                            
                            onClicked: root.handleItemClick(model)
                        }
                    }
                }
            }
        }

        // 3. Shorts / Discover Section
        ColumnLayout {
            id: discoverSection
            Layout.fillWidth: true
            spacing: 16
            
            property bool hasData: rootContext && rootContext.shortsContent.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 32 : -height
            
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    spacing: 4

                    StyledText {
                        text: "Forgotten favourites"
                        font.pixelSize: 24
                        font.weight: 700
                        color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: rootContext && rootContext.shortsContent.count > 0 ? "Rediscover tracks you love" : "No forgotten favorites right now."
                        font.pixelSize: 14
                        color: rootContext ? rootContext.secondaryContentColor : Appearance.colors.colSubtext
                    }
                }
            }

            MusicHorizontalFlickable {
                id: shortGrid
                Layout.fillWidth: true
                Layout.preferredHeight: shortContent.implicitHeight
                implicitHeight: shortContent.implicitHeight
                visible: rootContext && rootContext.shortsContent.count > 0
                contentWidth: shortContent.implicitWidth
                contentHeight: shortContent.implicitHeight
                clip: true
                interactive: contentWidth > width

                Grid {
                    id: shortContent
                    rows: Math.min(2, Math.max(1, rootContext ? rootContext.shortsContent.count : 0))
                    flow: Grid.TopToBottom
                    rowSpacing: 0
                    columnSpacing: 0

                    Repeater {
                        model: rootContext ? rootContext.shortsContent : null

                        delegate: MusicMediaCard {
                            width: 240
                            height: 280
                            rootContext: root.rootContext
                            itemData: model
                            hoverColor: root.cardHoverColor
                            artPlaceholderColor: root.artPlaceholderColor
                            onClicked: root.handleItemClick(model)
                        }
                    }
                }
            }
        }

        // Spacer for Footer
        Item {
            Layout.fillWidth: true
            height: rootContext && rootContext.currentTrack ? 80 : 32
        }
    }
}
