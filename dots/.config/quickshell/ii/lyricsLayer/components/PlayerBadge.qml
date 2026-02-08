import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Row {
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
    spacing: 8
    z: 100
    
    // Player indicator badge (top-left) - clickable for switching
    Rectangle {
        id: playerBadge
        height: 36
        width: playerRow.width + 24
        radius: 18
        color: playerBadgeArea.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
        visible: root.playerName !== ""
    
        Behavior on color { ColorAnimation { duration: 150 } }
        
        Row {
            id: playerRow
            anchors.centerIn: parent
            
            spacing: 8
            
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.isSpotify ? "music_note" : "headphones"
                iconSize: 18
                color: root.secondaryContentColor
            }
            
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.playerName
                color: root.secondaryContentColor
                font.pixelSize: 13
                font.weight: Font.Medium
                font.family: "Inter, Segoe UI, sans-serif"
            }
            
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.showPlayerPicker ? "expand_less" : "expand_more"
                iconSize: 14
                color: root.secondaryContentColor
                visible: root.availablePlayers.length > 1
            }
        }
        
        MouseArea {
            id: playerBadgeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.availablePlayers.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.availablePlayers.length > 1) {
                   root.togglePicker()
                }
            }
        }
    }
    
    // Player picker dropdown
    Item { // Container
        id: popupContainer
        anchors.top: root.bottom // relative to Row
        anchors.topMargin: 4
        anchors.left: root.left
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
            color: ColorUtils.mix(root.pillColor, "#151515", 0.5)
            
            // Stronger shadow
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.4)
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
            border.color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
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
                    
                    // Hover/selection background
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 12
                        color: playerItemArea.containsMouse 
                            ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                            : (root.activePlayer === modelData 
                                ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.08)
                                : "transparent")
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    
                    // Content row: Text left, Icon right
                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        
                        // Player name (left aligned)
                        Text {
                            anchors.left: parent.left
                            anchors.right: playerIcon.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.identity || "Unknown Player"
                            // Ensure contrast against dark popup background
                            color: root.contentColor
                            font.pixelSize: 14
                            font.weight: root.activePlayer === modelData ? Font.DemiBold : Font.Normal
                            font.family: "Inter, Segoe UI, sans-serif"
                            elide: Text.ElideRight
                        }
                        
                        // Icon (right aligned)
                        MaterialSymbol {
                            id: playerIcon
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                let id = (modelData.identity || "").toLowerCase()
                                if (id.includes("spotify")) return "music_note"
                                if (id.includes("firefox") || id.includes("chrome") || id.includes("browser")) return "language"
                                if (id.includes("vlc") || id.includes("mpv")) return "movie"
                                return "headphones"
                            }
                            iconSize: 20
                            color: root.activePlayer === modelData 
                                ? root.contentColor
                                : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.7)
                        }
                    }
                    
                    // Active selection indicator (left edge)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 20
                        radius: 1.5
                        color: root.pillContentColor
                        visible: root.activePlayer === modelData
                        
                        Behavior on visible { 
                            NumberAnimation { 
                                target: parent
                                property: "opacity"
                                from: 0; to: 1
                                duration: 200
                            } 
                        }
                    }
                    
                    MouseArea {
                        id: playerItemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.switchingStarted() // Notify switching
                            root.playerSelected(modelData)
                            // We don't close here locally, let parent handle it via binding update usually, 
                            // BUT since we want instant feedback, the parent should update `showPlayerPicker` immediately when receiving `playerSelected`.
                        }
                    }
                }
            }
        }
    }
    
    // Lyrics visibility toggle button (fullscreen only)
    Rectangle {
        height: 36
        width: 36
        radius: 18
        color: lyricsToggleArea.containsMouse ? Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.2) : Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.1)
        visible: root.isFullscreen
        
        Behavior on color { ColorAnimation { duration: 150 } }
        
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.forceCenteredMode ? "lyrics" : "notes"
            iconSize: 14
            color: root.secondaryContentColor
        }
        
        MouseArea {
            id: lyricsToggleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.modeToggled()
            }
        }
    }
}
