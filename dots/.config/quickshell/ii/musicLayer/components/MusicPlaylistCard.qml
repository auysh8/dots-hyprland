import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var rootContext
    property var playlistModel
    property color artPlaceholderColor: "transparent"

    implicitWidth: 180
    implicitHeight: 220

    // The main card button with ripple
    RippleButton {
        id: mainBtn
        anchors.fill: parent
        buttonRadius: 20
        colBackground: Appearance.colors.colLayer1
        colBackgroundHover: Appearance.colors.colLayer2
        colRipple: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.1)
        padding: 0
        
        onClicked: rootContext.openPlaylist(root.playlistModel.id)
        
        contentItem: Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                
                Rectangle {
                    id: playlistArtContainer
                    width: 60; height: 60; radius: 10
                    color: root.artPlaceholderColor

                    RoundedImage {
                        anchors.fill: parent
                        source: root.playlistModel.cover || ""
                        sourceSize.width: 120
                        sourceSize.height: 120
                        fillMode: Image.PreserveAspectCrop
                        radius: 10
                        asynchronous: true
                        cache: true
                    }
                }
                Item { Layout.fillHeight: true }
                
                StyledText {
                    text: root.playlistModel.title || ""
                    font.pixelSize: 18
                    font.weight: 700
                    color: rootContext.contentColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                }
                
                StyledText {
                    text: root.playlistModel.count !== undefined ? (root.playlistModel.count + " songs") : (root.playlistModel.artist || "")
                    font.pixelSize: 13
                    color: rootContext.secondaryContentColor
                    visible: text.length > 0 && root.playlistModel.count !== "0"
                }
            }
        }
    }

    // Play/Shuffle buttons (on top of main ripple button)
    ColumnLayout {
        z: 5
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: 14
        spacing: 8
        
                RippleButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 40; Layout.preferredHeight: 40; buttonRadius: 20
            colBackground: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface
            colBackgroundHover: colBackground
            colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.backgroundColor : Appearance.colors.colLayer0, 0.2)
            
            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; color: rootContext ? rootContext.backgroundColor : Appearance.colors.colLayer0; iconSize: 26 }
            onClicked: rootContext.openAndPlayPlaylist(root.playlistModel.id, false)
        }

                RippleButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 36; Layout.preferredHeight: 36; buttonRadius: 18
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.1)
            colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface, 0.2)
            
            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "shuffle"; color: rootContext ? rootContext.contentColor : Appearance.colors.colOnSurface; iconSize: 22 }
            onClicked: rootContext.openAndPlayPlaylist(root.playlistModel.id, true)
        }
    }
}