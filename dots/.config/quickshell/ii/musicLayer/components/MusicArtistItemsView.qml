import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

StyledFlickable {
    id: root

    property var rootContext
    readonly property var flickable: root
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : Appearance.colors.colLayer2
    readonly property color cardHoverColor: rootContext ? rootContext.pillColorHover : "transparent"

    property bool show: rootContext && rootContext.currentView === "artist_items" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: itemsContainer.implicitHeight + (rootContext && rootContext.currentTrack ? 120 : 32)
    flickableDirection: Flickable.VerticalFlick

    ColumnLayout {
        id: itemsContainer
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // Back action
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            MusicBackButton {
                rootContext: root.rootContext
                onClicked: {
                    if (rootContext) {
                        rootContext.currentView = "artist"
                    }
                }
            }

            StyledText {
                text: rootContext ? rootContext.activeArtistItemsTitle : ""
                font.pixelSize: 22
                font.weight: 700
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
                Layout.fillWidth: true
            }
        }

        GridView {
            id: itemsGrid
            Layout.fillWidth: true
            
            property int columns: Math.max(1, Math.floor((width - 20) / 220))
            property int rows: Math.ceil((rootContext && rootContext.activeArtistItemsModel ? rootContext.activeArtistItemsModel.count : 0) / columns)
            Layout.preferredHeight: rows * cellHeight
            
            cellWidth: Math.floor(width / columns)
            cellHeight: 280
            flow: GridView.FlowLeftToRight
            clip: true
            interactive: false

            model: rootContext && rootContext.activeArtistItemsModel ? rootContext.activeArtistItemsModel : null

            delegate: MusicMediaCard {
                width: itemsGrid.cellWidth
                height: itemsGrid.cellHeight
                rootContext: root.rootContext
                itemData: model
                hoverColor: root.cardHoverColor
                artPlaceholderColor: root.artPlaceholderColor
                
                customSubtitle: {
                    let parts = []
                    if (model.year) parts.push(model.year)
                    if (model.type) parts.push(model.type)
                    return parts.join(" • ")
                }
                
                onClicked: {
                    if (model.browseId && rootContext) {
                        rootContext.openPlaylist(model.browseId)
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
