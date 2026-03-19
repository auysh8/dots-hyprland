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
    property bool hovered: cardHover.containsMouse

    implicitWidth: 180
    implicitHeight: 220

    Rectangle {
        id: mainCard
        anchors.fill: parent
        radius: 20
        color: root.hovered
            ? (rootContext ? ColorUtils.mix(rootContext.pillColor, rootContext.contentColor, 0.08) : Appearance.colors.colLayer1Hover)
            : (rootContext ? rootContext.pillColor : Appearance.colors.colLayer1)

        Behavior on color { ColorAnimation { duration: 150 } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            
            Rectangle {
                id: playlistArtContainer
                width: 60; height: 60; radius: 10
                color: root.playlistModel.isLikedSongs 
                       ? (rootContext ? ColorUtils.applyAlpha(rootContext.contentColor, 0.15) : ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.15)) 
                       : root.artPlaceholderColor

                RoundedImage {
                    anchors.fill: parent
                    source: root.playlistModel.cover || ""
                    sourceSize.width: 120
                    sourceSize.height: 120
                    fillMode: Image.PreserveAspectCrop
                    radius: 10
                    asynchronous: true
                    cache: true
                    visible: !root.playlistModel.isLikedSongs
                }
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "favorite"
                    color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer1
                    iconSize: 32
                    fill: 1
                    visible: root.playlistModel.isLikedSongs === true
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
                elide: Text.ElideRight
                Layout.fillWidth: true
                maximumLineCount: 1
                visible: text.length > 0 && root.playlistModel.count !== "0"
            }
        }

        MouseArea {
            id: cardHover
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: rootContext.openPlaylist(root.playlistModel.id)
        }
    }

    // Play/Shuffle buttons (on top of main ripple button)
    ColumnLayout {
        z: 5
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: 14
        spacing: 8

        // Play button - highly contrasting adapted white with punched-out icon
        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            buttonRadius: 20
            colBackground: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer1
            colBackgroundHover: rootContext ? ColorUtils.mix(rootContext.contentColor, rootContext.pillColor, 0.15) : Appearance.colors.colOnLayer1Hover
            colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.pillColor : Appearance.colors.colLayer0, 0.2)
            horizontalPadding: 0
            verticalPadding: 0

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "play_arrow"
                color: rootContext ? rootContext.pillColor : Appearance.colors.colLayer1Base
                iconSize: 26
                fill: 1
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: rootContext.openAndPlayPlaylist(root.playlistModel.id, false)
        }

        // Shuffle button
        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            buttonRadius: 18
            colBackground: "transparent"
            colBackgroundHover: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer1, 0.15)
            colRipple: ColorUtils.applyAlpha(rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer1, 0.2)
            horizontalPadding: 0
            verticalPadding: 0

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "shuffle"
                color: rootContext ? rootContext.contentColor : Appearance.colors.colOnLayer1
                iconSize: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: rootContext.openAndPlayPlaylist(root.playlistModel.id, true)
        }
    }
}
