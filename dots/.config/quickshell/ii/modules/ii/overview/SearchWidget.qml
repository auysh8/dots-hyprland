
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.text = "";
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            return;

        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            return;
        }

        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    Item {
        id: searchWidgetContent
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin
        }
        implicitWidth: searchBar.totalWidth
        implicitHeight: unifiedCard.implicitHeight

        StyledRectangularShadow {
            target: unifiedCard
            visible: root.showResults
        }

        Rectangle {
            id: unifiedCard
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: searchBar.totalWidth
            implicitHeight: root.showResults ? (searchBar.height + resultsContainer.implicitHeight) : searchBar.height
            height: implicitHeight
            radius: 20
            color: root.showResults ? Appearance.colors.colBackgroundSurfaceContainer : "transparent"
            clip: root.showResults

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                SearchBar {
                    id: searchBar
                    Layout.alignment: Qt.AlignHCenter
                    Synchronizer on searchingText {
                        property alias source: root.searchingText
                    }
                    onAccepted: {
                        if (appResults.count > 0) {
                            let firstItem = appResults.itemAtIndex(0);
                            if (firstItem && firstItem.clicked) {
                                firstItem.clicked();
                            }
                        }
                    }
                }

                Item {
                    id: resultsContainer
                    visible: root.showResults
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: root.showResults ? Math.min(520, appResults.contentHeight + 16) : 0
                    Layout.preferredHeight: implicitHeight

                    ListView {
                        id: appResults
                        anchors.fill: parent
                        anchors.topMargin: 4
                        anchors.bottomMargin: 8
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        clip: true
                        spacing: 2
                        KeyNavigation.up: searchBar
                        highlightMoveDuration: 100

                        onFocusChanged: {
                            if (focus)
                                appResults.currentIndex = 1;
                        }

                        Connections {
                            target: root
                            function onSearchingTextChanged() {
                                if (appResults.count > 0)
                                    appResults.currentIndex = 0;
                            }
                        }

                        Timer {
                            id: debounceTimer
                            interval: root.typingDebounceInterval
                            onTriggered: {
                                resultModel.values = LauncherSearch.results ?? [];
                            }
                        }

                        Connections {
                            target: LauncherSearch
                            function onResultsChanged() {
                                resultModel.values = LauncherSearch.results.slice(0, root.typingResultLimit);
                                root.focusFirstItem();
                                debounceTimer.restart();
                            }
                        }

                        model: ScriptModel {
                            id: resultModel
                            objectProp: "key"
                        }

                        delegate: SearchItem {
                            id: searchItem
                            required property var modelData
                            anchors.left: parent ? parent.left : undefined
                            anchors.right: parent ? parent.right : undefined
                            entry: modelData
                            query: StringUtils.cleanOnePrefix(root.searchingText, [
                                Config.options.search.prefix.action,
                                Config.options.search.prefix.app,
                                Config.options.search.prefix.clipboard,
                                Config.options.search.prefix.emojis,
                                Config.options.search.prefix.math,
                                Config.options.search.prefix.shellCommand,
                                Config.options.search.prefix.webSearch
                            ])

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Tab) {
                                    if (LauncherSearch.results.length === 0)
                                        return;
                                    const tabbedText = searchItem.modelData.name;
                                    LauncherSearch.query = tabbedText;
                                    searchBar.searchInput.text = tabbedText;
                                    event.accepted = true;
                                    root.focusSearchInput();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
