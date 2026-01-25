import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Scope {
    id: dynamicIslandScope

    Variants {
        // For each monitor - only show when vertical bar is enabled
        model: {
            if (!Config.options.bar.vertical) return [];
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        PanelWindow {
            id: islandRoot
            required property ShellScreen modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }

            implicitHeight: islandContainer.height + Appearance.sizes.hyprlandGapsOut * 2
            
            color: "transparent"
            
            WlrLayershell.namespace: "quickshell:dynamicIsland"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusiveZone: -1 // Don't reserve space, float over windows

            // Input mask uses the container which includes both trigger and content
            mask: Region {
                item: islandContainer
            }

            // Main Container (Includes Trigger + Island)
            Item {
                id: islandContainer
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                
                // Height is just island height (since no gap now)
                implicitHeight: Math.max(10, islandPill.height)
                implicitWidth: Math.max(300, islandPill.width)

                // Trigger area at the top (Thin strip)
                MouseArea {
                    id: triggerArea
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 300
                    height: 10
                    hoverEnabled: true
                    // Active only when island is "hidden" (collapsed & opaque 0)
                    enabled: !islandContainer.expanded && islandPill.opacity === 0
                }

                // Logic Properties
                property bool expanded: (islandMouseArea.containsMouse || expandTimer.running) && !triggerArea.containsMouse
                property bool hasMedia: Mpris.players.values.length > 0 && Mpris.players.values[0]?.playbackState === MprisPlaybackState.Playing

                Timer {
                    id: expandTimer
                    interval: 500
                    repeat: false
                }

                // The Island Pill
                Item {
                    id: islandPill
                    anchors.top: parent.top
                    anchors.topMargin: 0 // Attached to top edge (Notch style)
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    // Opacity Logic
                    opacity: (triggerArea.containsMouse || islandContainer.expanded || islandContainer.hasMedia) ? 1 : 0
                    visible: opacity > 0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    // Size Logic
                    property real collapsedWidth: 200
                    property real collapsedHeight: 36
                    property real expandedWidth: 380
                    property real expandedHeight: islandContainer.hasMedia ? 120 : 60
                    
                    width: islandContainer.expanded ? expandedWidth : collapsedWidth
                    height: islandContainer.expanded ? expandedHeight : collapsedHeight
                    
                    Behavior on width {
                        NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
                    }
                    Behavior on height {
                        NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
                    }

                    MouseArea {
                        id: islandMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: expandTimer.start()
                        onExited: expandTimer.stop()
                    }

                    // Shadow
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 16
                        samples: 33
                        color: "#40000000"
                    }

                    // Island background (Notch Shape)
                    Rectangle {
                        id: islandBackground
                        anchors.fill: parent
                        // Rounded bottom corners
                        radius: 16
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        
                        // Patch to square off top corners
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: parent.radius
                            color: parent.color
                            // Draw borders manually if needed or hide them?
                            // Actually border is on parent. This patch will hide top border. 
                            // Notch attaches to screen edge, so top border usually not visible or needed.
                        }
                        
                        // We need to redraw side borders on the patch area if we want them, 
                        // but since it connects to bezel, side borders only on the part below bezel?
                        // Let's keep it simple: Patch hides top border and top-corner curves.
                        
                        // Add side borders to patch if needed:
                        Rectangle { // Left border of patch
                            width: 1; height: parent.height; color: islandBackground.border.color
                            anchors.left: parent.left; anchors.top: parent.top
                        }
                        Rectangle { // Right border of patch
                            width: 1; height: parent.height; color: islandBackground.border.color
                            anchors.right: parent.right; anchors.top: parent.top
                        }

                    // Collapsed content
                    RowLayout {
                        id: collapsedContent
                        anchors.centerIn: parent
                        spacing: 12
                        opacity: islandContainer.expanded ? 0 : 1
                        visible: opacity > 0
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }

                        // Time
                        Text {
                            text: Qt.formatTime(new Date(), "hh:mm")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }

                        // Separator
                        Rectangle {
                            width: 1
                            height: 16
                            color: Appearance.colors.colOutlineVariant
                            visible: islandContainer.hasMedia
                        }

                        // Media indicator (collapsed)
                        RowLayout {
                            visible: islandContainer.hasMedia
                            spacing: 6
                            
                            MaterialSymbol {
                                text: {
                                    const player = Mpris.players.values[0];
                                    if (!player) return "music_note";
                                    return player.playbackState === MprisPlaybackState.Playing ? "play_arrow" : "pause";
                                }
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.m3colors.m3primary
                            }
                            
                            Text {
                                text: {
                                    const player = Mpris.players.values[0];
                                    if (!player) return "";
                                    const title = player.track?.title ?? "";
                                    return title.length > 15 ? title.substring(0, 15) + "..." : title;
                                }
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // Expanded content
                    ColumnLayout {
                        id: expandedContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        opacity: islandContainer.expanded ? 1 : 0
                        visible: opacity > 0
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                        }

                        // Top row - Time and Date
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                text: Qt.formatTime(new Date(), "hh:mm:ss")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer0
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Text {
                                text: Qt.formatDate(new Date(), "ddd, MMM d")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer0Inactive
                            }
                        }

                        // Media row (if playing)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: islandContainer.hasMedia

                            // Album art
                            Rectangle {
                                width: 48
                                height: 48
                                radius: 8
                                color: Appearance.colors.colLayer1
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: {
                                        const player = Mpris.players.values[0];
                                        return player?.track?.artUrl ?? "";
                                    }
                                    fillMode: Image.PreserveAspectCrop
                                }
                            }

                            // Track info
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const player = Mpris.players.values[0];
                                        return player?.track?.title ?? "Unknown";
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer0
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        const player = Mpris.players.values[0];
                                        return player?.track?.artist ?? "Unknown Artist";
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0Inactive
                                    elide: Text.ElideRight
                                }
                            }

                            // Controls
                            RowLayout {
                                spacing: 4

                                RippleButton {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: 16
                                    onClicked: Mpris.players.values[0]?.previous()
                                    
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "skip_previous"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    buttonRadius: 18
                                    colBackground: Appearance.m3colors.m3primary
                                    onClicked: Mpris.players.values[0]?.togglePlaying()
                                    
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: {
                                            const player = Mpris.players.values[0];
                                            return player?.playbackState === MprisPlaybackState.Playing ? "pause" : "play_arrow";
                                        }
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.m3colors.m3onPrimary
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: 16
                                    onClicked: Mpris.players.values[0]?.next()
                                    
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "skip_next"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }

            // Update time every second
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    // Force time update by reassigning
                    collapsedContent.children[0].text = Qt.formatTime(new Date(), "hh:mm");
                    if (expandedContent.children[0]) {
                        expandedContent.children[0].children[0].text = Qt.formatTime(new Date(), "hh:mm:ss");
                    }
                }
            }
        }
    }
}
