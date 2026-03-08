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
    readonly property color artPlaceholderColor: rootContext ? ColorUtils.mix(rootContext.surfaceColor, rootContext.pillColor, 0.7) : "#2f3239"

    property bool show: rootContext && rootContext.currentView === "artist" && !rootContext.isLoading
    opacity: show ? 1.0 : 0.0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }

    anchors.fill: parent
    contentWidth: width
    contentHeight: artistContainer.implicitHeight + 32

    onDraggingChanged: {
        if (!dragging && contentY < -120 && !rootContext.refreshing && !rootContext.isLoading) {
            rootContext.refreshing = true
            rootContext.openArtist(rootContext.activeArtistId)
        }
    }

    // Pull to refresh indicator
    Item {
        width: parent.width
        height: 60
        y: -60
        visible: root.contentY < -20

        RowLayout {
            anchors.centerIn: parent
            spacing: 12

            MaterialSymbol {
                text: root.contentY < -100 ? "refresh" : "arrow_downward"
                color: rootContext ? rootContext.contentColor : "white"
                iconSize: 20
            }

            StyledText {
                text: root.contentY < -100 ? "Release to refresh" : "Pull to refresh"
                font.weight: 600
                color: rootContext ? rootContext.contentColor : "white"
            }
        }
    }

    ColumnLayout {
        id: artistContainer
        width: parent.width
        anchors.top: parent.top
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        spacing: 32

        // Back button
        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            
            Rectangle {
                width: 40; height: 40; radius: 20
                color: backHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "transparent"
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    color: rootContext.contentColor
                    iconSize: 24
                }
                
                MouseArea {
                    id: backHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (rootContext.previousView && rootContext.previousView !== "artist")
                            rootContext.currentView = rootContext.previousView
                        else
                            rootContext.currentView = "home"
                    }
                }
            }
        }

        // ─── Artist Header ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 32

            // Circular artist photo
            Rectangle {
                width: 200
                height: 200
                radius: 100
                color: root.artPlaceholderColor
                clip: true

                RoundedImage {
                    anchors.fill: parent
                    source: rootContext ? rootContext.activeArtistThumbnail : ""
                    sourceSize.width: 400
                    sourceSize.height: 400
                    fillMode: Image.PreserveAspectCrop
                    radius: 100
                    asynchronous: true
                    cache: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 8

                StyledText {
                    text: rootContext ? rootContext.activeArtistName : ""
                    font.pixelSize: 36
                    font.weight: 800
                    color: rootContext ? rootContext.contentColor : "white"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                StyledText {
                    text: rootContext ? rootContext.activeArtistSubscribers : ""
                    font.pixelSize: 14
                    color: rootContext ? rootContext.secondaryContentColor : "gray"
                    visible: text.length > 0
                }

                // Description (truncated)
                StyledText {
                    text: rootContext ? rootContext.activeArtistDescription : ""
                    font.pixelSize: 13
                    color: rootContext ? rootContext.secondaryContentColor : "gray"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    visible: text.length > 0
                }

                Item { Layout.preferredHeight: 8 }

                // Shuffle all / Play buttons
                RowLayout {
                    spacing: 16

                    // Play button
                    RippleButton {
                        Layout.preferredWidth: playRow.implicitWidth + 32
                        Layout.preferredHeight: 48
                        buttonRadius: 24
                        property color bgColor: rootContext ? rootContext.pillColor : "#444"
                        property color txColor: rootContext ? rootContext.contentColor : "white"
                        colBackground: bgColor
                        colRipple: txColor
                        
                        contentItem: RowLayout {
                            id: playRow
                            spacing: 8
                            MaterialSymbol { text: "play_arrow"; color: parent.parent.txColor; iconSize: 24 }
                            StyledText { text: "Play"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
                        }

                        onClicked: {
                            if (rootContext && rootContext.activeArtistSongs.count > 0) {
                                let first = rootContext.activeArtistSongs.get(0)
                                let queueTracks = []
                                for (let i = 1; i < rootContext.activeArtistSongs.count; i++) {
                                    let t = rootContext.activeArtistSongs.get(i)
                                    queueTracks.push({
                                        videoId: t.videoId,
                                        title: t.title,
                                        artist: t.artist,
                                        artUrl: t.artUrl,
                                        duration: t.duration || ""
                                    })
                                }
                                rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl, queueTracks)
                            }
                        }
                    }

                    // Shuffle button
                    RippleButton {
                        Layout.preferredWidth: shuffleRow.implicitWidth + 32
                        Layout.preferredHeight: 48
                        buttonRadius: 24
                        property color bgColor: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "#333"
                        property color txColor: rootContext ? rootContext.contentColor : "white"
                        colBackground: bgColor
                        colRipple: txColor

                        contentItem: RowLayout {
                            id: shuffleRow
                            spacing: 8
                            MaterialSymbol { text: "shuffle"; color: parent.parent.txColor; iconSize: 24 }
                            StyledText { text: "Shuffle"; color: parent.parent.txColor; font.pixelSize: 16; font.weight: 800 }
                        }

                        onClicked: {
                            if (rootContext && rootContext.activeArtistSongs.count > 0) {
                                let tracksToPlay = []
                                for (let i = 0; i < rootContext.activeArtistSongs.count; i++) {
                                    let t = rootContext.activeArtistSongs.get(i)
                                    tracksToPlay.push({
                                        videoId: t.videoId,
                                        title: t.title,
                                        artist: t.artist,
                                        artUrl: t.artUrl,
                                        duration: t.duration || ""
                                    })
                                }
                                // Fisher-Yates shuffle
                                for (let i = tracksToPlay.length - 1; i > 0; i--) {
                                    const j = Math.floor(Math.random() * (i + 1));
                                    [tracksToPlay[i], tracksToPlay[j]] = [tracksToPlay[j], tracksToPlay[i]];
                                }
                                let first = tracksToPlay[0]
                                let queueTracks = tracksToPlay.slice(1)
                                rootContext.playTrack(first.videoId, first.title, first.artist, first.artUrl, queueTracks)
                            }
                        }
                    }
                }
            }
        }

        // ─── Top Songs ───────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: rootContext && rootContext.activeArtistSongs.count > 0

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Top Songs"
                    font.pixelSize: 22
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : "white"
                    Layout.fillWidth: true
                }
                RippleButton {
                    Layout.preferredWidth: seeAllSongsText.implicitWidth + 24
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "#333"
                    visible: rootContext && rootContext.activeArtistSongsBrowseId && rootContext.activeArtistSongsBrowseId.length > 0
                    
                    contentItem: StyledText {
                        id: seeAllSongsText
                        text: "See all"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (rootContext && rootContext.activeArtistId && rootContext.activeArtistSongsBrowseId) {
                            rootContext.isLoading = true
                            rootContext.sendCommand({
                                "command": "get_artist_full_songs",
                                "channelId": rootContext.activeArtistId,
                                "songsBrowseId": rootContext.activeArtistSongsBrowseId
                            })
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: songsColumn.implicitHeight + 16
                radius: 20
                color: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.7) : "#20ffffff"

                ColumnLayout {
                    id: songsColumn
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    Repeater {
                        model: rootContext ? rootContext.activeArtistSongs : null

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: 12
                            color: songHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 16

                                StyledText {
                                    text: (index + 1).toString()
                                    font.pixelSize: 14
                                    Layout.preferredWidth: 32
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.alignment: Qt.AlignVCenter
                                    color: rootContext.secondaryContentColor
                                }

                                Rectangle {
                                    width: 48; height: 48; radius: 8
                                    color: ColorUtils.transparentize(rootContext.pillColor, 0.5)

                                    RoundedImage {
                                        anchors.fill: parent
                                        source: model.artUrl || ""
                                        sourceSize.width: 96
                                        sourceSize.height: 96
                                        fillMode: Image.PreserveAspectCrop
                                        radius: 8
                                        asynchronous: true
                                        cache: true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#40000000"
                                        radius: 8
                                        visible: songHover.containsMouse || (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId)

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) ? (rootContext.playbackPaused ? "play_arrow" : "pause") : "play_arrow"
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
                                        color: (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) ? (rootContext.extractedColor || rootContext.pillColor) : rootContext.contentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            let parts = []
                                            if (model.plays) parts.push(model.plays)
                                            if (model.duration) parts.push(model.duration)
                                            return parts.join(" • ")
                                        }
                                        font.pixelSize: 12
                                        color: rootContext.secondaryContentColor
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                    }
                                }
                            }

                            MouseArea {
                                id: songHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (rootContext.currentTrack && rootContext.currentTrack.videoId === model.videoId) {
                                        rootContext.toggle()
                                    } else {
                                        let queueTracks = []
                                        for (let i = index + 1; i < rootContext.activeArtistSongs.count; i++) {
                                            let t = rootContext.activeArtistSongs.get(i)
                                            queueTracks.push({
                                                videoId: t.videoId,
                                                title: t.title,
                                                artist: t.artist,
                                                artUrl: t.artUrl,
                                                duration: t.duration || ""
                                            })
                                        }
                                        rootContext.playTrack(model.videoId, model.title, model.artist, model.artUrl, queueTracks)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ─── Albums ──────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: rootContext && rootContext.activeArtistAlbums.count > 0

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Albums"
                    font.pixelSize: 22
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : "white"
                    Layout.fillWidth: true
                }
                RippleButton {
                    Layout.preferredWidth: seeAllAlbumsText.implicitWidth + 24
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "#333"
                    visible: rootContext && rootContext.activeArtistAlbumsParams && rootContext.activeArtistAlbumsParams.length > 0
                    
                    contentItem: StyledText {
                        id: seeAllAlbumsText
                        text: "See all"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (rootContext && rootContext.activeArtistId && rootContext.activeArtistAlbumsParams) {
                            rootContext.isLoading = true
                            rootContext.sendCommand({
                                "command": "get_artist_full_items",
                                "channelId": rootContext.activeArtistId,
                                "params": rootContext.activeArtistAlbumsParams,
                                "itemType": "albums"
                            })
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 16

                Repeater {
                    model: rootContext ? rootContext.activeArtistAlbums : null

                    delegate: ColumnLayout {
                        width: (parent.width - 64) / 5
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 12
                            color: albumHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : ColorUtils.transparentize(rootContext.pillColor, 0.5)

                            RoundedImage {
                                anchors.fill: parent
                                source: model.artUrl || ""
                                sourceSize.width: 200
                                sourceSize.height: 200
                                fillMode: Image.PreserveAspectCrop
                                radius: 12
                                cache: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "#40000000"
                                radius: 12
                                visible: albumHover.containsMouse

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "play_arrow"
                                    color: "white"
                                    iconSize: 32
                                }
                            }

                            MouseArea {
                                id: albumHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.openPlaylist(model.browseId)
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
                                horizontalAlignment: Text.AlignLeft
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    let parts = []
                                    if (model.year) parts.push(model.year)
                                    if (model.type) parts.push(model.type)
                                    return parts.join(" • ")
                                }
                                font.pixelSize: 12
                                color: rootContext.secondaryContentColor
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignLeft
                            }
                        }
                    }
                }
            }
        }

        // ─── Singles ─────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: rootContext && rootContext.activeArtistSingles.count > 0

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: "Singles"
                    font.pixelSize: 22
                    font.weight: 700
                    color: rootContext ? rootContext.contentColor : "white"
                    Layout.fillWidth: true
                }
                RippleButton {
                    Layout.preferredWidth: seeAllSinglesText.implicitWidth + 24
                    Layout.preferredHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: rootContext ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "#333"
                    visible: rootContext && rootContext.activeArtistSinglesParams && rootContext.activeArtistSinglesParams.length > 0
                    
                    contentItem: StyledText {
                        id: seeAllSinglesText
                        text: "See all"
                        font.pixelSize: 14
                        font.weight: 600
                        color: rootContext ? rootContext.contentColor : "white"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    
                    onClicked: {
                        if (rootContext && rootContext.activeArtistId && rootContext.activeArtistSinglesParams) {
                            rootContext.isLoading = true
                            rootContext.sendCommand({
                                "command": "get_artist_full_items",
                                "channelId": rootContext.activeArtistId,
                                "params": rootContext.activeArtistSinglesParams,
                                "itemType": "singles"
                            })
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: childrenRect.height
                spacing: 16

                Repeater {
                    model: rootContext ? rootContext.activeArtistSingles : null

                    delegate: ColumnLayout {
                        width: (parent.width - 64) / 5
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width
                            radius: 12
                            color: singleHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.4) : ColorUtils.transparentize(rootContext.pillColor, 0.5)

                            RoundedImage {
                                anchors.fill: parent
                                source: model.artUrl || ""
                                sourceSize.width: 200
                                sourceSize.height: 200
                                fillMode: Image.PreserveAspectCrop
                                radius: 12
                                cache: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "#40000000"
                                radius: 12
                                visible: singleHover.containsMouse

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "play_arrow"
                                    color: "white"
                                    iconSize: 32
                                }
                            }

                            MouseArea {
                                id: singleHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rootContext.openPlaylist(model.browseId)
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
                                horizontalAlignment: Text.AlignLeft
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    let parts = []
                                    if (model.year) parts.push(model.year)
                                    if (model.type) parts.push(model.type)
                                    return parts.join(" • ")
                                }
                                font.pixelSize: 12
                                color: rootContext.secondaryContentColor
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignLeft
                            }
                        }
                    }
                }
            }
        }

        // ─── Related Artists ─────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: rootContext && rootContext.activeArtistRelated.count > 0

            StyledText {
                text: "Fans might also like"
                font.pixelSize: 22
                font.weight: 700
                color: rootContext ? rootContext.contentColor : "white"
            }

            Flow {
                Layout.fillWidth: true
                spacing: 16

                Repeater {
                    model: rootContext ? rootContext.activeArtistRelated : null

                    delegate: Rectangle {
                        width: 140
                        height: 200
                        radius: 16
                        color: relatedHover.containsMouse ? ColorUtils.transparentize(rootContext.pillColor, 0.5) : "transparent"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 124
                                Layout.preferredHeight: 124
                                radius: 62
                                color: root.artPlaceholderColor
                                clip: true

                                RoundedImage {
                                    anchors.fill: parent
                                    source: model.artUrl || ""
                                    sourceSize.width: 248
                                    sourceSize.height: 248
                                    fillMode: Image.PreserveAspectCrop
                                    radius: 62
                                    asynchronous: true
                                    cache: true
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: model.name || ""
                                font.pixelSize: 13
                                font.weight: 600
                                color: rootContext ? rootContext.contentColor : "white"
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: model.subscribers || ""
                                font.pixelSize: 11
                                color: rootContext ? rootContext.secondaryContentColor : "gray"
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }
                        }

                        MouseArea {
                            id: relatedHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: rootContext.openArtist(model.browseId)
                        }
                    }
                }
            }
        }

        // Bottom spacer for miniplayer
        Item {
            Layout.fillWidth: true
            height: rootContext ? (rootContext.currentTrack ? 80 : 0) : 0
        }
    }
}
