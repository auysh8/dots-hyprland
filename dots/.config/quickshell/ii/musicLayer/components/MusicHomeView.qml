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
    
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.4) : Appearance.colors.colLayer2
    readonly property color cardHoverColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : "transparent"

    readonly property real refreshThreshold: -100
    readonly property real refreshPullThreshold: -20
    readonly property real refreshY: -60

    anchors.fill: parent
    contentHeight: homeColumn.implicitHeight + (rootContext.currentTrack ? 120 : 32)
    flickableDirection: Flickable.VerticalFlick

    property bool show: queryText.length === 0 && rootContext.currentView === "home" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    clip: true

    onDraggingChanged: {
        if (!dragging && contentY <= refreshThreshold && !rootContext.refreshing && !rootContext.isLoading) {
            rootContext.refreshing = true
            rootContext.getHome()
        }
    }

    function handleItemClick(itemModel) {
        if (itemModel.actualVideoId) {
            rootContext.playTrack(itemModel.actualVideoId, itemModel.title, itemModel.artist, itemModel.artUrl)
        } else if (itemModel.browseId) {
            if (itemModel.browseId.startsWith("UC")) {
                rootContext.openArtist(itemModel.browseId)
            } else {
                rootContext.openPlaylist(itemModel.browseId)
            }
        } else if (itemModel.playlistId) {
            rootContext.openPlaylist(itemModel.playlistId)
        } else if (itemModel.videoId) {
            rootContext.playTrack(itemModel.videoId, itemModel.title, itemModel.artist, itemModel.artUrl)
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
                color: rootContext.pillColor
            }

            StyledText {
                text: root.contentY < refreshThreshold ? "Release to refresh" : "Pull to refresh"
                font.weight: 600
                color: rootContext.contentColor
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
            
            property bool hasData: rootContext.homeContent.count > 0
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
                        color: rootContext.contentColor
                    }

                    StyledText {
                        text: "Jump back into your favorites"
                        font.pixelSize: 14
                        color: rootContext.secondaryContentColor
                    }
                }

                Item { Layout.fillWidth: true }
            }

            GridView {
                id: recGrid
                Layout.fillWidth: true
                property int columns: Math.max(1, Math.floor(width / 240))
                Layout.preferredHeight: Math.min(2, Math.ceil(rootContext.homeContent.count / columns)) * cellHeight
                implicitHeight: Layout.preferredHeight
                cellWidth: 240
                cellHeight: 280
                flow: GridView.FlowTopToBottom
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                cacheBuffer: 1200
                interactive: true
                acceptedButtons: Qt.NoButton

                model: rootContext.homeContent

                delegate: MusicMediaCard {
                    width: recGrid.cellWidth
                    height: recGrid.cellHeight
                    rootContext: root.rootContext
                    itemData: model
                    hoverColor: root.cardHoverColor
                    artPlaceholderColor: root.artPlaceholderColor
                    onClicked: root.handleItemClick(model)
                }
            }
        }

        // 2. Quick Picks Section
        ColumnLayout {
            id: quickPicksSection
            Layout.fillWidth: true
            spacing: 16
            
            property bool hasData: rootContext.quickPicks.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 32 : -height
            
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on Layout.topMargin { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }

            StyledText {
                text: "Quick Picks"
                font.pixelSize: 20
                font.weight: 700
                color: rootContext.contentColor
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: quickPicksColumn.height + 32
                Layout.preferredHeight: implicitHeight
                radius: 24
                color: ColorUtils.transparentize(rootContext.pillColor, 0.85)

                ColumnLayout {
                    id: quickPicksColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: rootContext.quickPicks

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
            
            property bool hasData: rootContext.shortsContent.count > 0
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
                        color: rootContext.contentColor
                    }

                    StyledText {
                        text: rootContext.shortsContent.count > 0 ? "Rediscover tracks you love" : "No forgotten favorites right now."
                        font.pixelSize: 14
                        color: rootContext.secondaryContentColor
                    }
                }
            }

            GridView {
                id: shortGrid
                Layout.fillWidth: true
                property int columns: Math.max(1, Math.floor(width / 240))
                Layout.preferredHeight: Math.min(2, Math.ceil(rootContext.shortsContent.count / columns)) * cellHeight
                implicitHeight: Layout.preferredHeight
                cellWidth: 240
                cellHeight: 280
                flow: GridView.FlowTopToBottom
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                visible: rootContext.shortsContent.count > 0
                cacheBuffer: 1200
                interactive: true
                acceptedButtons: Qt.NoButton

                model: rootContext.shortsContent

                delegate: MusicMediaCard {
                    width: shortGrid.cellWidth
                    height: shortGrid.cellHeight
                    rootContext: root.rootContext
                    itemData: model
                    hoverColor: root.cardHoverColor
                    artPlaceholderColor: root.artPlaceholderColor
                    onClicked: root.handleItemClick(model)
                }
            }
        }

        // Spacer for Footer
        Item {
            Layout.fillWidth: true
            height: rootContext.currentTrack ? 80 : 32
        }
    }
}