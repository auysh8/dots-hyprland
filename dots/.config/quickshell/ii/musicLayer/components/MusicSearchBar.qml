import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    
    property var rootContext
    property alias text: searchInput.text
    
    z: 999
    Layout.fillWidth: true
    Layout.preferredHeight: 80
    
    Rectangle {
        id: searchContainer
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.6, 500)
        height: 48
        radius: 24
        color: rootContext.pillColor
        border.width: 0
        
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            
            MaterialSymbol {
                text: "search"
                color: rootContext.pillContentColor
                iconSize: 20
                Layout.alignment: Qt.AlignVCenter
            }
            
            TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: rootContext.pillContentColor
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: 500
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                
                StyledText {
                    text: "Search YouTube Music..."
                    color: ColorUtils.transparentize(rootContext.pillContentColor, 0.5)
                    visible: searchInput.text.length === 0
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    font: searchInput.font
                }
                
                onTextEdited: {
                    rootContext.suppressSuggestionResponses = false
                    rootContext.artistResults.clear()
                    rootContext.songResults.clear()
                    rootContext.albumResults.clear()
                    rootContext.cachedSongResults = []
                    rootContext.searchVisibleSongCount = 5
                    rootContext.searchSongsHasMore = false
                    rootContext.sendCommand({ "command": "get_suggestions", "query": text })
                }
                
                onAccepted: rootContext.search(text)
                
                onActiveFocusChanged: {
                    if (!activeFocus) {
                        hideSuggsTimer.restart()
                    } else {
                        hideSuggsTimer.stop()
                    }
                }

                Timer {
                    id: hideSuggsTimer
                    interval: 150
                    onTriggered: rootContext.searchSuggestions.clear()
                }
            }
            
            RippleButton {
                visible: searchInput.text.length > 0
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: 16
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(rootContext.pillContentColor, 0.85)
                
                contentItem: Item {
                    anchors.fill: parent
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        color: rootContext.pillContentColor
                        iconSize: 18
                    }
                }
                
                onClicked: {
                    searchInput.text = ""
                    rootContext.suppressSuggestionResponses = false
                    rootContext.artistResults.clear()
                    rootContext.songResults.clear()
                    rootContext.albumResults.clear()
                    rootContext.cachedSongResults = []
                    rootContext.searchVisibleSongCount = 5
                    rootContext.searchSongsHasMore = false
                    rootContext.searchSuggestions.clear()
                    searchInput.forceActiveFocus()
                }
            }
        }
    }
    
    Rectangle {
        id: suggestionsPopover
        anchors.top: searchContainer.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: searchContainer.horizontalCenter
        width: searchContainer.width
        height: Math.min(suggestionsList.contentHeight + 16, 300)
        color: searchContainer.color
        radius: 20
        border.width: 0
        visible: rootContext.searchSuggestions.count > 0 && searchInput.text.length > 0
        z: 200
        
        ListView {
            id: suggestionsList
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            model: rootContext.searchSuggestions
            delegate: Item {
                width: ListView.view.width
                height: 40
                
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: suggMouse.containsMouse ? ColorUtils.applyAlpha(rootContext.contentColor, 0.08) : "transparent"
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 12
                        MaterialSymbol { text: "search"; color: suggMouse.containsMouse ? rootContext.contentColor : rootContext.secondaryContentColor; iconSize: 18 }
                        StyledText { text: model.text; color: suggMouse.containsMouse ? rootContext.contentColor : rootContext.secondaryContentColor; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    
                    MouseArea {
                        id: suggMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        scrollGestureEnabled: false
                        cursorShape: Qt.PointingHandCursor
                        onPressed: {
                            hideSuggsTimer.stop()
                            searchInput.text = model.text
                            rootContext.search(model.text)
                        }
                    }
                }
            }
        }
    }
}
