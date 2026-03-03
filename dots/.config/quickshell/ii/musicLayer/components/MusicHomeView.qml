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
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : "#2f3239"

    anchors.fill: parent
    contentHeight: homeColumn.implicitHeight + (rootContext.currentTrack ? 120 : 32)
    flickableDirection: Flickable.VerticalFlick

    property bool show: queryText.length === 0 && rootContext.currentView === "home" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    clip: true

    onDraggingChanged: {
        if (!dragging && contentY < -120 && !rootContext.refreshing && !rootContext.isLoading) {
            rootContext.refreshing = true
            rootContext.getHome()
        }
    }

    Item {
        width: parent.width
        height: 60
        y: -60
        visible: root.contentY < -20

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            opacity: Math.min(Math.abs(root.contentY) / 100, 1.0)

            MaterialLoadingIndicator {
                implicitSize: 24
                loading: true
                color: rootContext.pillColor
            }

            StyledText {
                text: root.contentY < -100 ? "Release to refresh" : "Pull to refresh"
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
        spacing: 0 // Spacing handled by individual section margins for smoother animation

        // 1. Recommendations Section
        ColumnLayout {
            id: recommendationsSection
            Layout.fillWidth: true
            spacing: 16
            
            property bool hasData: rootContext.homeContent.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 0 : -height // Collapse when empty
            
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
                Layout.preferredHeight: rootContext.homeContent.count > 1 ? 560 : 280
                cellWidth: Math.max(1, (width - 20) / 4)
                cellHeight: 280
                flow: GridView.FlowTopToBottom
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                cacheBuffer: 1200

                model: rootContext.homeContent

                delegate: Item {
                    width: recGrid.cellWidth
                    height: recGrid.cellHeight

                        Rectangle {
                            id: recCard
                            anchors.fill: parent
                            anchors.margins: 8
                            radius: 20
                            color: recHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"
                            
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
                                    radius: 20
                                    color: root.artPlaceholderColor
                                    
                                    // Mask the entire container layer to keep corners sharp during child animations
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: artContainer.width
                                            height: artContainer.height
                                            radius: 20
                                        }
                                    }

                                    Image {
                                        id: recArt
                                        anchors.fill: parent
                                        source: model.artUrl || ""
                                        sourceSize.width: 272
                                        sourceSize.height: 272
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        visible: status === Image.Ready
                                        
                                        // Zoom effect
                                        scale: recHover.containsMouse ? 1.1 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }

                                    // Play Button Overlay
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#60000000"
                                        opacity: recHover.containsMouse ? 1.0 : 0.0
                                        
                                        Behavior on opacity { NumberAnimation { duration: 200 } }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            color: "white"
                                            iconSize: 42
                                            scale: recHover.containsMouse ? 1.0 : 0.5
                                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.title
                                        font.weight: 600
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.artist
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            MouseArea {
                                id: recHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl)
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
            
            property bool hasData: rootContext.quickPicks.count > 0
            visible: opacity > 0
            opacity: hasData ? 1.0 : 0.0
            Layout.topMargin: hasData ? 32 : -height // Collapse when empty
            
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
                color: ColorUtils.transparentize(rootContext.pillColor, 0.7)

                ColumnLayout {
                    id: quickPicksColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 8

                    Repeater {
                        model: rootContext.quickPicks

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: 12
                            color: pickHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 16

                                StyledText {
                                    text: index + 1
                                    color: rootContext.secondaryContentColor
                                    font.pixelSize: 14
                                    font.weight: 600
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Rectangle {
                                    width: 48
                                    height: 48
                                    radius: 8
                                    color: root.artPlaceholderColor

                                    RoundedImage {
                                        id: quickPickArt
                                        anchors.fill: parent
                                        source: model.artUrl || ""
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        radius: 8
                                        cache: true
                                        visible: status === Image.Ready
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#40000000"
                                        radius: 8
                                        visible: pickHover.containsMouse

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            color: "white"
                                            iconSize: 24
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.title
                                        font.weight: 600
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.artist
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                }

                                StyledText {
                                    text: model.duration
                                    color: rootContext.secondaryContentColor
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: pickHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl)
                            }
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
            Layout.topMargin: hasData ? 32 : -height // Collapse when empty
            
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
                Layout.preferredHeight: rootContext.shortsContent.count > 1 ? 560 : 280
                cellWidth: Math.max(1, (width - 20) / 4)
                cellHeight: 280
                flow: GridView.FlowTopToBottom
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                visible: rootContext.shortsContent.count > 0
                cacheBuffer: 1200

                model: rootContext.shortsContent

                delegate: Item {
                    width: shortGrid.cellWidth
                    height: shortGrid.cellHeight

                        Rectangle {
                            id: shortCard
                            anchors.fill: parent
                            anchors.margins: 8
                            radius: 20
                            color: shortHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.55) : "transparent"
                            
                            Behavior on color { ColorAnimation { duration: 200 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 12
                                anchors.bottomMargin: 16
                                spacing: 12

                                Rectangle {
                                    id: shortArtContainer
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width
                                    radius: 20
                                    color: root.artPlaceholderColor
                                    
                                    // Mask the entire container layer to keep corners sharp during child animations
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: shortArtContainer.width
                                            height: shortArtContainer.height
                                            radius: 20
                                        }
                                    }

                                    Image {
                                        id: shortArt
                                        anchors.fill: parent
                                        source: model.artUrl || ""
                                        sourceSize.width: 272
                                        sourceSize.height: 272
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        visible: status === Image.Ready
                                        
                                        // Zoom effect
                                        scale: shortHover.containsMouse ? 1.1 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }

                                    // Play Button Overlay
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#60000000"
                                        opacity: shortHover.containsMouse ? 1.0 : 0.0
                                        radius: 20
                                        
                                        Behavior on opacity { NumberAnimation { duration: 200 } }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "play_arrow"
                                            color: "white"
                                            iconSize: 42
                                            scale: shortHover.containsMouse ? 1.0 : 0.5
                                            Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.title
                                        font.weight: 600
                                        color: rootContext.contentColor
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: model.artist
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            MouseArea {
                                id: shortHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl)
                            }
                        }
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
