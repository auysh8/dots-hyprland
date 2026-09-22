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

    property bool animateWidth: false
    property alias searchInput: searchInput
    property string searchingText
    signal accepted()

    property bool opened: false
    property bool holdSprout: false
    property real dropletProgress: 0.0
    readonly property real targetProgress: (opened && searchInput.text === "" && !holdSprout) ? 1.0 : 0.0

    Timer {
        id: openSequenceTimer
        interval: 120
        repeat: false
        onTriggered: root.opened = true
    }

    Timer {
        id: openAppDrawerTimer
        interval: 30
        repeat: false
        onTriggered: {
            GlobalStates.appDrawerOpen = true;
        }
    }

    onTargetProgressChanged: {
        dropletAnim.stop();
        dropletAnim.from = root.dropletProgress;
        dropletAnim.to = root.targetProgress;
        if (root.targetProgress === 0.0) {
            dropletAnim.duration = Math.max(1, 600 * Math.abs(root.targetProgress - root.dropletProgress));
            dropletAnim.easing.type = Easing.OutQuad;
        } else {
            dropletAnim.duration = Math.max(1, 600 * Math.abs(root.targetProgress - root.dropletProgress));
            dropletAnim.easing.type = Easing.Linear;
        }
        dropletAnim.restart();
    }

    readonly property bool hasActiveDroplets: (searchInput.text === "" && dropletProgress > 0.05)
    readonly property bool dropletsAttached: (dropletProgress <= 0.001)
    readonly property bool isAnimatingDroplets: dropletAnim.running

    function retractDroplets() {
        openSequenceTimer.stop();
        root.opened = false;
    }

    function sproutDroplets() {
        if (searchInput.text === "") {
            root.opened = false;
            openSequenceTimer.restart();
        }
    }

    function resetState() {
        openSequenceTimer.stop();
        dropletAnim.stop();
        root.opened = false;
        root.holdSprout = false;
        root.dropletProgress = 0.0;
        searchInput.text = "";
    }

    function handleActiveState(isOpen) {
        if (isOpen) {
            root.opened = false;
            root.dropletProgress = 0.0;
            openSequenceTimer.restart();
        } else {
            openSequenceTimer.stop();
            root.opened = false;
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            root.handleActiveState(GlobalStates.overviewOpen || GlobalStates.spotlightOpen);
        }
        function onSpotlightOpenChanged() {
            root.handleActiveState(GlobalStates.overviewOpen || GlobalStates.spotlightOpen);
        }
    }

    Component.onCompleted: {
        if (GlobalStates.overviewOpen || GlobalStates.spotlightOpen) {
            openSequenceTimer.restart();
        }
    }

    NumberAnimation {
        id: dropletAnim
        target: root
        property: "dropletProgress"
        from: 0.0
        to: 0.0
        duration: 620
        easing.type: Easing.Linear
    }

    function forceFocus() {
        searchInput.forceActiveFocus();
    }

    enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, DefaultSearch }

    property var searchPrefixType: {
        if (root.searchingText.startsWith(Config.options.search.prefix.action)) return SearchBar.SearchPrefixType.Action;
        if (root.searchingText.startsWith(Config.options.search.prefix.app)) return SearchBar.SearchPrefixType.App;
        if (root.searchingText.startsWith(Config.options.search.prefix.clipboard)) return SearchBar.SearchPrefixType.Clipboard;
        if (root.searchingText.startsWith(Config.options.search.prefix.emojis)) return SearchBar.SearchPrefixType.Emojis;
        if (root.searchingText.startsWith(Config.options.search.prefix.math)) return SearchBar.SearchPrefixType.Math;
        if (root.searchingText.startsWith(Config.options.search.prefix.shellCommand)) return SearchBar.SearchPrefixType.ShellCommand;
        if (root.searchingText.startsWith(Config.options.search.prefix.webSearch)) return SearchBar.SearchPrefixType.WebSearch;
        return SearchBar.SearchPrefixType.DefaultSearch;
    }

    readonly property real searchBarHeight: 48
    readonly property real dropletDiameter: 40
    readonly property real dropletGap: 8
    readonly property real totalWidth: 468
    readonly property real contractedWidth: 324
    readonly property real effectBleed: 24

    implicitWidth: totalWidth
    implicitHeight: searchBarHeight

    property bool suppressSurface: false

    SearchDropletsSurface {
        id: dropletsSurface
        anchors.fill: parent
        anchors.margins: -root.effectBleed
        railProgress: root.dropletProgress
        mainLeft: root.effectBleed
        collapsedMainWidth: root.totalWidth
        expandedMainWidth: root.contractedWidth
        shapeCenterY: height / 2
        shapeHeight: root.searchBarHeight
        buttonDiameter: root.dropletDiameter
        buttonGap: root.dropletGap
        surfaceColor: Appearance.colors.colBackgroundSurfaceContainer
        visible: (searchInput.text === "" || root.dropletProgress > 0.001) && !root.suppressSurface
    }

    Item {
        id: mainPillContainer
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        width: dropletsSurface.mainWidth
        height: root.searchBarHeight
        clip: true

        RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 8
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            spacing: 6

            MaterialShapeWrappedMaterialSymbol {
                id: searchIcon
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.huge
                shape: switch(root.searchPrefixType) {
                    case SearchBar.SearchPrefixType.Action: return MaterialShape.Shape.Pill;
                    case SearchBar.SearchPrefixType.App: return MaterialShape.Shape.Clover4Leaf;
                    case SearchBar.SearchPrefixType.Clipboard: return MaterialShape.Shape.Gem;
                    case SearchBar.SearchPrefixType.Emojis: return MaterialShape.Shape.Sunny;
                    case SearchBar.SearchPrefixType.Math: return MaterialShape.Shape.PuffyDiamond;
                    case SearchBar.SearchPrefixType.ShellCommand: return MaterialShape.Shape.PixelCircle;
                    case SearchBar.SearchPrefixType.WebSearch: return MaterialShape.Shape.SoftBurst;
                    default: return MaterialShape.Shape.Cookie7Sided;
                }
                text: switch (root.searchPrefixType) {
                    case SearchBar.SearchPrefixType.Action: return "settings_suggest";
                    case SearchBar.SearchPrefixType.App: return "apps";
                    case SearchBar.SearchPrefixType.Clipboard: return "content_paste_search";
                    case SearchBar.SearchPrefixType.Emojis: return "add_reaction";
                    case SearchBar.SearchPrefixType.Math: return "calculate";
                    case SearchBar.SearchPrefixType.ShellCommand: return "terminal";
                    case SearchBar.SearchPrefixType.WebSearch: return "travel_explore";
                    case SearchBar.SearchPrefixType.DefaultSearch: return "search";
                    default: return "search";
                }
            }

            ToolbarTextField {
                id: searchInput
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitHeight: 40
                focus: GlobalStates.spotlightOpen || GlobalStates.overviewOpen
                font.pixelSize: Appearance.font.pixelSize.small
                placeholderText: Translation.tr("Search, calculate or run")

                onTextChanged: LauncherSearch.query = text

                onAccepted: root.accepted()

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab) {
                        if (LauncherSearch.results.length === 0) return;
                        const tabbedText = LauncherSearch.results[0].name;
                        LauncherSearch.query = tabbedText;
                        searchInput.text = tabbedText;
                        event.accepted = true;
                    }
                }
            }
        }
    }

    // Google Lens Droplet Button
    Item {
        id: lensDroplet
        x: dropletsSurface.x + dropletsSurface.droplet0Shape.x - width / 2
        y: dropletsSurface.y + dropletsSurface.shapeCenterY - height / 2
        width: root.dropletDiameter
        height: root.dropletDiameter
        opacity: dropletsSurface.iconProgress(0)
        scale: 0.7 + 0.3 * dropletsSurface.iconProgress(0)
        visible: opacity > 0.01

        IconToolbarButton {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            onClicked: {
                GlobalStates.overviewOpen = false;
                GlobalStates.spotlightOpen = false;
                Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "search"]);
            }
            text: "image_search"
            StyledToolTip {
                text: Translation.tr("Google Lens")
            }
        }
    }

    // Song Recognize Droplet Button
    Item {
        id: songRecDroplet
        x: dropletsSurface.x + dropletsSurface.droplet1Shape.x - width / 2
        y: dropletsSurface.y + dropletsSurface.shapeCenterY - height / 2
        width: root.dropletDiameter
        height: root.dropletDiameter
        opacity: dropletsSurface.iconProgress(1)
        scale: 0.7 + 0.3 * dropletsSurface.iconProgress(1)
        visible: opacity > 0.01

        IconToolbarButton {
            id: songRecButton
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            toggled: SongRec.running
            onClicked: SongRec.toggleRunning()
            text: "music_cast"

            StyledToolTip {
                text: Translation.tr("Recognize music")
            }

            colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
            background: MaterialShape {
                RotationAnimation on rotation {
                    running: songRecButton.toggled
                    duration: 12000
                    easing.type: Easing.Linear
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                }
                shape: {
                    if (songRecButton.down) {
                        return songRecButton.toggled ? MaterialShape.Shape.Circle : MaterialShape.Shape.Square;
                    } else {
                        return songRecButton.toggled ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Circle;
                    }
                }
                color: {
                    if (songRecButton.toggled) {
                        return songRecButton.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary;
                    } else {
                        return songRecButton.hovered ? Appearance.colors.colSurfaceContainerHigh : "transparent";
                    }
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }

    // App Drawer Droplet Button
    Item {
        id: appDrawerDroplet
        x: dropletsSurface.x + dropletsSurface.droplet2Shape.x - width / 2
        y: dropletsSurface.y + dropletsSurface.shapeCenterY - height / 2
        width: root.dropletDiameter
        height: root.dropletDiameter
        opacity: dropletsSurface.iconProgress(2)
        scale: 0.7 + 0.3 * dropletsSurface.iconProgress(2)
        visible: opacity > 0.01

        IconToolbarButton {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            onClicked: {
                GlobalStates.overviewOpen = false;
                GlobalStates.spotlightOpen = false;
                openAppDrawerTimer.restart();
            }
            text: "apps"
            StyledToolTip {
                text: Translation.tr("App Drawer")
            }
        }
    }
}
