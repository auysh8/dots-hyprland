import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var rootContext
    property var itemData
    property color hoverColor: "transparent"
    property color artPlaceholderColor: "transparent"
    property string customSubtitle: ""

    signal clicked()

    property bool isArtist: (itemData.browseId || "").startsWith("UC") || (itemData.videoId || "").startsWith("UC")
    property bool isAlbum: (itemData.browseId || "").startsWith("MPRE")
    property bool isPlaylist: !!(itemData.playlistId) && !(itemData.actualVideoId)
    property bool isSong: !!(itemData.actualVideoId)

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 8
        radius: 20
        color: cardHover.containsMouse ? root.hoverColor : "transparent"
        
        Behavior on color { ColorAnimation { duration: 200 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 12
            anchors.bottomMargin: 16
            spacing: 12

            Rectangle {
                id: artContainer
                Layout.fillWidth: true
                Layout.preferredHeight: width
                radius: root.isArtist ? width / 2 : 20
                color: root.artPlaceholderColor
                
                Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                
                RoundedImage {
                    id: recArt
                    anchors.fill: parent
                    source: itemData.artUrl || itemData.cover || ""
                    sourceSize.width: 272
                    sourceSize.height: 272
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready
                    radius: artContainer.radius
                }

                // Hover Overlay
                Rectangle {
                    anchors.fill: parent
                    radius: artContainer.radius
                    color: ColorUtils.applyAlpha(Appearance.colors.colShadow, 0.38)
                    opacity: cardHover.containsMouse ? 1.0 : 0.0
                    
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isArtist ? "person" : "play_arrow"
                        color: rootContext.contentColor
                        iconSize: 42
                        scale: cardHover.containsMouse ? 1.0 : 0.5
                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: itemData.title || itemData.name || ""
                    font.weight: 600
                    color: rootContext.contentColor
                    elide: Text.ElideRight
                    horizontalAlignment: root.isArtist ? Text.AlignHCenter : Text.AlignLeft
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.customSubtitle !== "" ? root.customSubtitle : (root.isArtist ? "Artist" : (root.isAlbum ? "Album" : (root.isPlaylist ? "Playlist" : itemData.artist)))
                    font.pixelSize: 12
                    color: rootContext.secondaryContentColor
                    elide: Text.ElideRight
                    horizontalAlignment: root.isArtist ? Text.AlignHCenter : Text.AlignLeft
                }
            }
        }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            hoverEnabled: true
            scrollGestureEnabled: false
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
