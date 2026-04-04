import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common.widgets

Item {
    id: root

    // Injected from parent
    property var sendCommand: null
    property color contentColor: "#ffffff"
    property color surfaceColor: "#1e1e2e"
    property color pillColor: "#cba6f7"
    property color pillContentColor: "#1e1e2e"
    property color subtleColor: Qt.rgba(contentColor.r, contentColor.g, contentColor.b, 0.45)

    // Cache stats data (populated by backend response)
    property real audioCount: 0
    property real audioSizeMb: 0
    property real artCount: 0
    property real artSizeMb: 0
    property real canvasVideoCount: 0
    property real canvasVideoSizeMb: 0
    property real totalSizeMb: 0
    property real maxSizeMb: 500
    property real utilization: 0
    property bool loading: true

    signal navigateBack()

    function loadStats() {
        root.loading = true
        if (sendCommand) sendCommand({ "command": "cache_stats" })
    }

    function onCacheStats(data) {
        root.loading = false
        root.audioCount = data.audio_count || 0
        root.audioSizeMb = (data.audio_size_mb || 0)
        root.artCount = data.art_count || 0
        root.artSizeMb = (data.art_size_mb || 0)
        root.canvasVideoCount = data.canvas_video_count || 0
        root.canvasVideoSizeMb = (data.canvas_video_size_mb || 0)
        root.totalSizeMb = (data.total_size_mb || 0)
        root.maxSizeMb = (data.max_size_mb || 500)
        root.utilization = (data.utilization || 0)
    }

    Component.onCompleted: {
        // Don't auto-load — wait until visible to avoid timing issues with backend startup
    }

    onVisibleChanged: {
        if (visible) loadStats()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Back button
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: 18
                colBackground: "transparent"
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.20)
                onClicked: root.navigateBack()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 20
                    color: root.contentColor
                }
            }

            StyledText {
                text: "Cache"
                font.pixelSize: 22
                font.weight: Font.Medium
                color: root.contentColor
            }

            Item { Layout.fillWidth: true }

            // Refresh button
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: 18
                colBackground: "transparent"
                colBackgroundHover: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                colRipple: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.20)
                onClicked: root.loadStats()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 20
                    color: root.contentColor
                    rotation: root.loading ? 360 : 0
                    Behavior on rotation { NumberAnimation { duration: 600 } }
                }
            }
        }

        // Total usage bar
        Rectangle {
            Layout.fillWidth: true
            height: 80
            radius: 16
            color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.06)

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: "Total Used"
                        font.pixelSize: 13
                        color: root.subtleColor
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: root.totalSizeMb.toFixed(1) + " MB / " + root.maxSizeMb.toFixed(0) + " MB"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: root.contentColor
                    }
                }

                // Progress bar
                Item {
                    Layout.fillWidth: true
                    height: 6
                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.12)
                    }
                    Rectangle {
                        width: parent.width * Math.min(root.utilization / 100, 1)
                        height: parent.height
                        radius: 3
                        color: root.utilization > 85 ? "#f38ba8" : root.pillColor
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        // Stat rows
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            component StatRow: Rectangle {
                property string icon: "folder"
                property string label: ""
                property real count: 0
                property string sizeText: ""
                property string clearWhat: ""

                Layout.fillWidth: true
                height: 56
                radius: 12
                color: Qt.rgba(root.contentColor.r, root.contentColor.g, root.contentColor.b, 0.05)

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 12; topMargin: 0; bottomMargin: 0 }
                    spacing: 12

                    MaterialSymbol {
                        text: parent.parent.icon
                        iconSize: 20
                        color: root.pillColor
                    }
                    ColumnLayout {
                        spacing: 1
                        StyledText {
                            text: parent.parent.parent.label
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: root.contentColor
                        }
                        StyledText {
                            text: parent.parent.parent.count + " items · " + parent.parent.parent.sizeText
                            font.pixelSize: 11
                            color: root.subtleColor
                        }
                    }
                    Item { Layout.fillWidth: true }

                    // Clear button
                    RippleButton {
                        implicitWidth: 60; implicitHeight: 28
                        buttonRadius: 14
                        colBackground: Qt.rgba(0.94, 0.54, 0.66, 0.10)
                        colBackgroundHover: Qt.rgba(0.94, 0.54, 0.66, 0.25)
                        colRipple: Qt.rgba(0.94, 0.54, 0.66, 0.35)
                        visible: parent.parent.parent.count > 0 && parent.parent.parent.clearWhat !== ""
                        onClicked: {
                            if (root.sendCommand)
                                root.sendCommand({ "command": "clear_cache", "what": parent.parent.parent.clearWhat })
                        }
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "Clear"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: "#f38ba8"
                        }
                    }
                }
            }

            StatRow {
                icon: "music_note"
                label: "Audio files"
                count: root.audioCount
                sizeText: root.audioSizeMb.toFixed(1) + " MB"
                clearWhat: "audio"
            }
            StatRow {
                icon: "image"
                label: "Album art"
                count: root.artCount
                sizeText: root.artSizeMb.toFixed(1) + " MB"
                clearWhat: "art"
            }
            StatRow {
                icon: "videocam"
                label: "Canvas videos"
                count: root.canvasVideoCount
                sizeText: root.canvasVideoSizeMb.toFixed(1) + " MB"
                clearWhat: "canvas"
            }
        }

        Item { Layout.fillHeight: true }

        // Clear all button
        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 44
            buttonRadius: 12
            visible: root.totalSizeMb > 0
            colBackground: Qt.rgba(0.94, 0.54, 0.66, 0.12)
            colBackgroundHover: Qt.rgba(0.94, 0.54, 0.66, 0.22)
            colRipple: Qt.rgba(0.94, 0.54, 0.66, 0.32)
            
            onClicked: {
                if (root.sendCommand)
                    root.sendCommand({ "command": "clear_cache", "what": "all" })
            }
            contentItem: StyledText {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "Clear All Cache"
                font.pixelSize: 13
                font.weight: Font.Medium
                color: "#f38ba8"
            }
        }

        Item { height: 8 }
    }
}
