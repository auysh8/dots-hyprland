import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    
    property string playerName: ""
    property bool isSpotify: false
    property var activePlayer: null
    property var availablePlayers: []
    property color contentColor: "white"
    property color secondaryContentColor: "gray"
    property color pillContentColor: "black"
    property color pillColor: "white"
    
    // Controlled by parent
    property bool showPlayerPicker: false
    
    property bool isFullscreen: false
    property bool forceCenteredMode: false
    
    signal playerSelected(var player)
    signal modeToggled()
    signal switchingStarted() 
    
    // New signals for state control
    signal togglePicker()
    
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: isFullscreen ? 60 : 30
    
    implicitWidth: contentRow.width
    implicitHeight: contentRow.height
    
    z: 100
    
    Row {
        id: contentRow
        spacing: 8
        
        // Player indicator badge (top-left) - clickable for switching
        RippleButton {
            id: playerBadge
            implicitHeight: 36
            implicitWidth: playerRow.implicitWidth + 24
            buttonRadius: 18
            padding: 0
            
            colBackground: ColorUtils.applyAlpha(root.contentColor, 0.1)
            colBackgroundHover: root.availablePlayers.length > 1 ? ColorUtils.applyAlpha(root.contentColor, 0.2) : colBackground
            colRipple: root.contentColor
            
            onClicked: {
            if (root.availablePlayers.length > 1) {
                root.togglePicker()
            }
        }

            contentItem: Item {
                implicitWidth: playerRow.implicitWidth
                implicitHeight: playerRow.implicitHeight
                RowLayout {
                    id: playerRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "music_note"
                        iconSize: 16
                        color: root.contentColor
                    }

                    StyledText {
                        text: root.playerName || "No Player"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: root.contentColor
                    }

                    MaterialSymbol {
                        text: root.showPlayerPicker ? "expand_less" : "expand_more"
                        iconSize: 18
                        color: root.contentColor
                        visible: root.availablePlayers.length > 1
                    }
                }
            }
        }
        
        // Lyrics visibility toggle button (fullscreen only)
        RippleButton {
            implicitHeight: 36
            implicitWidth: 36
            buttonRadius: 18
            padding: 0
            visible: root.isFullscreen
            
            colBackground: ColorUtils.applyAlpha(root.contentColor, 0.1)
            colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.2)
            colRipple: root.contentColor

            onClicked: root.modeToggled()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.forceCenteredMode ? "splitscreen_left" : "notes"
                iconSize: 18
                color: root.contentColor
            }
        }
    }
    
    // Player picker dropdown
    Item { // Container
        id: popupContainer
        anchors.top: contentRow.bottom // aligned to content row
        anchors.topMargin: 4
        anchors.left: contentRow.left
        width: 260
        height: playerPickerColumn.height + 16  // Account for 8px margins on each side
        visible: popupOpacity > 0 || root.showPlayerPicker
        
        // Animation properties
        property real popupOpacity: root.showPlayerPicker ? 1 : 0
        property real popupScale: root.showPlayerPicker ? 1 : 0.92
        property real popupY: root.showPlayerPicker ? 0 : -8
        
        opacity: popupOpacity
        scale: popupScale
        transformOrigin: Item.TopLeft
        
        // Smooth spring-like animations
        Behavior on popupOpacity { 
            NumberAnimation { 
                duration: root.showPlayerPicker ? 200 : 150
                easing.type: root.showPlayerPicker ? Easing.OutCubic : Easing.InCubic
            } 
        }
        Behavior on popupScale { 
            NumberAnimation { 
                duration: root.showPlayerPicker ? 250 : 150
                easing.type: root.showPlayerPicker ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.5
            } 
        }
        Behavior on popupY { 
            NumberAnimation { 
                duration: root.showPlayerPicker ? 200 : 150
                easing.type: Easing.OutCubic
            } 
        }
        
        // Y offset animation
        transform: Translate { y: popupContainer.popupY }
        
        // Clean colored background with shadow (Material Design style)
        Rectangle {
            id: popupBackground
            anchors.fill: parent
            radius: 16
            color: ColorUtils.mix(root.pillColor, Appearance.colors.colLayer0, 0.8)
            
            // Stronger shadow
            layer.enabled: popupContainer.popupScale >= 1.0
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Appearance.colors.colShadow
                shadowBlur: 1.0
                shadowVerticalOffset: 4
                shadowHorizontalOffset: 0
            }
        }
        
        // Subtle border for definition
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: "transparent"
            border.color: Appearance.colors.colLayer0Border
            border.width: 1
        }
        
        // Clean Material Design menu content
        Column {
            id: playerPickerColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            spacing: 0
            
            Repeater {
                model: root.availablePlayers
                
                Item {
                    width: parent.width
                    height: 48
                    
                    RippleButton {
                        anchors.fill: parent
                        anchors.margins: 2
                        buttonRadius: 12
                        
                        colBackground: root.activePlayer === modelData ? ColorUtils.applyAlpha(root.contentColor, 0.08) : "transparent"
                        colBackgroundHover: ColorUtils.applyAlpha(root.contentColor, 0.12)
                        colRipple: root.contentColor
                        
                        onClicked: {
                            if (root.activePlayer !== modelData) {
                                root.switchingStarted()
                                root.playerSelected(modelData)
                            } else {
                                root.togglePicker() // Emitting signal to let parent manage state
                            }
                        }
                        
                        contentItem: Item {
                            anchors.fill: parent

                            // Content row: Text left, Icon right
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.identity || "Unknown Player"
                                    font.pixelSize: 14
                                    font.weight: root.activePlayer === modelData ? Font.Bold : Font.Medium
                                    color: root.activePlayer === modelData
                                        ? root.contentColor
                                        : ColorUtils.applyAlpha(root.contentColor, 0.8)
                                }

                                MaterialSymbol {
                                    text: {
                                        let id = (modelData.identity || "").toLowerCase()
                                        if (id.includes("spotify")) return "music_note"
                                        if (id.includes("firefox") || id.includes("chrome") || id.includes("brave") || id.includes("edge")) return "language"
                                        if (id.includes("vlc") || id.includes("mpv")) return "play_circle"
                                        if (id.includes("kdeconnect")) return "smartphone"
                                        return "headphones"
                                    }
                                    iconSize: 20
                                    color: root.activePlayer === modelData
                                        ? root.contentColor
                                        : ColorUtils.applyAlpha(root.contentColor, 0.7)
                                }
                            }

                            // Active selection indicator (left edge)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: 20
                                radius: 1.5
                                color: root.contentColor
                                visible: root.activePlayer === modelData
                            }
                        }
                    }
                }
            }
        }
    }
}
