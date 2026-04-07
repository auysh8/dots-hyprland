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
    readonly property color artPlaceholderColor: rootContext ? rootContext.surfaceColor : Appearance.colors.colLayer1
    readonly property color cardHoverColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.contentColor, 0.92) : "transparent"

    property bool show: rootContext && rootContext.currentView === "artist_items" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    enabled: show
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    clip: true
    contentHeight: itemsContainer.implicitHeight + (rootContext && rootContext.currentTrack ? 120 : 32)
    contentWidth: width
    flickableDirection: Flickable.VerticalFlick
    // This view is dense with full-card tap targets, so give the page flick
    // a bit more time to win before card taps are recognized.
    pressDelay: 250

    Behavior on width {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

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

        Flow {
            id: itemsGrid
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            width: parent.width
            spacing: 0
            property int targetCellWidth: 220
            property int columns: Math.max(1, Math.floor(width / targetCellWidth))
            property int cellWidth: Math.floor(width / columns)
            // Cards use square art based on width, so row height must grow with width.
            property int cellHeight: Math.max(280, cellWidth + 72)

            Repeater {
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
        }
        
        // Spacer for Footer
        Item {
            Layout.fillWidth: true
            height: rootContext && rootContext.currentTrack ? 80 : 32
        }
    }
}
