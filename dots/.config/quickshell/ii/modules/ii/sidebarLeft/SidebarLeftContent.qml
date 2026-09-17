import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.weather
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool weatherEnabled: true
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property var tabButtonList: [
        ...(root.weatherEnabled ? [{"icon": "cloud", "name": Translation.tr("Weather")}] : []),
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
    ]
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                currentIndex: swipeView.currentIndex
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: "transparent"

            SwipeView {
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex
                interactive: false

                clip: true

                contentItem: ListView {
                    id: internalListView
                    model: swipeView.contentModel
                    interactive: swipeView.interactive
                    orientation: swipeView.orientation
                    spacing: swipeView.spacing
                    snapMode: ListView.SnapOneItem
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: swipeView.currentIndex
                    highlightFollowsCurrentItem: false

                    onCurrentIndexChanged: {
                        if (!internalListView.moving && !internalListView.flicking) {
                            pageSlideAnim.to = currentIndex * (internalListView.width + internalListView.spacing)
                            pageSlideAnim.start()
                        }
                    }

                    NumberAnimation {
                        id: pageSlideAnim
                        target: internalListView
                        property: "contentX"
                        duration: 400
                        easing.type: Easing.OutBack
                        easing.amplitude: 0.55
                    }
                }

                contentChildren: [
                    ...(root.weatherEnabled ? [weatherPage.createObject()] : []),
                    ...(root.aiChatEnabled ? [aiChatPage.createObject()] : []),
                    ...(root.translatorEnabled ? [translatorPage.createObject()] : []),
                    ...((root.tabButtonList.length === 0 || (!root.weatherEnabled && !root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? [placeholder.createObject()] : []),
                    ...(root.animeEnabled && !root.animeCloset ? [animePage.createObject()] : []),
                ]
            }
        }

        component LazySwipePage: Item {
            id: pageRoot
            property Component pageComponent
            property bool visited: false

            Loader {
                id: pageLoader
                anchors.fill: parent
                active: pageRoot.visited || pageRoot.SwipeView.isCurrentItem
                sourceComponent: pageRoot.pageComponent
                onLoaded: pageRoot.visited = true
            }

            onActiveFocusChanged: {
                if (activeFocus && pageLoader.item) {
                    pageLoader.item.forceActiveFocus();
                }
            }
        }

        Component {
            id: weatherPage
            LazySwipePage { pageComponent: weatherView }
        }
        Component {
            id: aiChatPage
            LazySwipePage { pageComponent: aiChat }
        }
        Component {
            id: translatorPage
            LazySwipePage { pageComponent: translator }
        }
        Component {
            id: animePage
            LazySwipePage { pageComponent: anime }
        }

        Component {
            id: weatherView
            WeatherView {
                presentationActive: GlobalStates.sidebarLeftOpen && (swipeView.currentIndex === 0)
                isExtended: root.scopeRoot ? root.scopeRoot.extend : false
                isResizing: root.scopeRoot ? root.scopeRoot.isResizing : false
            }
        }
        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
