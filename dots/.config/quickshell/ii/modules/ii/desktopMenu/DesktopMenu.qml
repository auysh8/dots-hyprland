pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Scope {
    id: root

    function openCentered(shouldOpen) {
        if (!shouldOpen) {
            GlobalStates.desktopMenuOpen = false
            return
        }
        const focusedName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        let screen = null
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === focusedName) {
                screen = Quickshell.screens[i]
                break
            }
        }
        if (!screen && Quickshell.screens.length > 0) screen = Quickshell.screens[0]
        GlobalStates.desktopMenuScreen = screen
        GlobalStates.desktopMenuX = screen ? (screen.width / 2) : 500
        GlobalStates.desktopMenuY = screen ? (screen.height / 2) : 500
        GlobalStates.desktopMenuOpen = true
    }

    function displayPathFor(path) {
        if (!path) return path
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    // Wallpaper folder images
    FolderListModel {
        id: wallpaperFolder
        folder: {
            const wallPath = Config.options.background.wallpaperPath
            if (!wallPath || wallPath.length === 0) return ""
            const lastSlash = wallPath.lastIndexOf("/")
            return "file://" + wallPath.substring(0, lastSlash)
        }
        showDirs: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    }

    property int carouselExtraCount: 5
    property bool useDarkMode: Appearance.m3colors.darkmode
    property var randomWallpapers: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        let all = []
        for (let i = 0; i < wallpaperFolder.count; i++) {
            const fp = FileUtils.trimFileProtocol(wallpaperFolder.get(i, "filePath").toString())
            if (fp !== current) all.push(fp)
        }
        for (let i = all.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const tmp = all[i]
            all[i] = all[j]
            all[j] = tmp
        }
        return all.slice(0, carouselExtraCount)
    }

    property var carouselModel: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        if (!current || current.length === 0) return randomWallpapers.map(p => root.displayPathFor(p))
        return [root.displayPathFor(current), ...randomWallpapers.map(p => root.displayPathFor(p))]
    }

    // Sizing and positioning calculations
    readonly property var activeScreen: GlobalStates.desktopMenuScreen ? GlobalStates.desktopMenuScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    readonly property real screenWidth: activeScreen ? activeScreen.width : 1920
    readonly property real screenHeight: activeScreen ? activeScreen.height : 1080

    readonly property real menuCardWidth: 348
    readonly property real menuCardHeight: 264
    readonly property real submenuWidth: 284
    readonly property real menuGap: 8

    readonly property real defaultSubmenuHeight: 820
    readonly property real maxMenuHeight: defaultSubmenuHeight

    // Stable anchor coordinates (never oscillate with layout passes)
    readonly property real baseMenuX: Math.min(Math.max(GlobalStates.desktopMenuX - menuCardWidth / 2, 8), screenWidth - menuCardWidth - 8)
    readonly property real baseMenuY: Math.min(Math.max(GlobalStates.desktopMenuY - menuCardHeight / 2, 8), screenHeight - maxMenuHeight - 8)

    readonly property bool submenuFitsOnRight: (baseMenuX + menuCardWidth + menuGap + submenuWidth <= screenWidth - 8)
    readonly property real leftMenuX: Math.max(8, baseMenuX - menuGap - submenuWidth)

    property string activeSubmenu: ""
    readonly property bool hasSubmenu: activeSubmenu !== ""

    readonly property real windowX: submenuFitsOnRight ? baseMenuX : leftMenuX
    readonly property real windowY: baseMenuY
    readonly property real windowWidth: menuCardWidth + menuGap + submenuWidth
    readonly property real windowHeight: defaultSubmenuHeight

    readonly property real cardX: submenuFitsOnRight ? 0 : (submenuWidth + menuGap)
    readonly property real subX: submenuFitsOnRight ? (menuCardWidth + menuGap) : 0

    Timer {
        id: submenuCloseTimer
        interval: 800
        onTriggered: root.activeSubmenu = ""
    }

    // Dismiss menu on workspace change (NOT focusedmon, to avoid closing on grab)
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (GlobalStates.desktopMenuOpen && (event.name === "workspace" || event.name === "workspacev2")) {
                GlobalStates.desktopMenuOpen = false
            }
        }
    }

    Connections {
        target: WM
        function onActiveWorkspaceChanged() {
            if (GlobalStates.desktopMenuOpen) {
                GlobalStates.desktopMenuOpen = false
            }
        }
    }

    Connections {
        target: GlobalStates
        function onDesktopMenuOpenChanged() {
            if (!GlobalStates.desktopMenuOpen) {
                root.activeSubmenu = ""
            }
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            GlobalStates.desktopMenuOpen = false
            root.activeSubmenu = ""
        }
    }

    // Menu window
    PanelWindow {
        id: menuWindow
        visible: GlobalStates.desktopMenuOpen

        screen: root.activeScreen

        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:desktopMenu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        Shortcut {
            sequence: "Escape"
            onActivated: GlobalStates.desktopMenuOpen = false
        }

        anchors.top: true
        anchors.left: true
        margins {
            left: Math.round(root.windowX)
            top: Math.round(root.windowY)
        }

        implicitWidth: Math.round(root.windowWidth)
        implicitHeight: Math.round(root.windowHeight)

        mask: Region {
            item: root.hasSubmenu ? menuCluster : menuCard
        }

        HyprlandFocusGrab {
            id: focusGrab
            active: false
            windows: [menuWindow]
            onCleared: {
                GlobalStates.desktopMenuOpen = false
                root.activeSubmenu = ""
            }
        }

        Timer {
            id: focusGrabTimer
            interval: 50
            onTriggered: {
                if (GlobalStates.desktopMenuOpen) {
                    focusGrab.active = true
                }
            }
        }

        Connections {
            target: GlobalStates
            function onDesktopMenuOpenChanged() {
                if (GlobalStates.desktopMenuOpen) {
                    focusGrabTimer.restart()
                } else {
                    focusGrab.active = false
                    root.activeSubmenu = ""
                }
            }
        }

        // Click outside cards (within window bounds) immediately dismisses the entire menu
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                GlobalStates.desktopMenuOpen = false
                root.activeSubmenu = ""
            }
        }

        Item {
            id: menuCluster
            anchors.fill: parent

            // Menu card 
            Rectangle {
                id: menuCard
                x: root.cardX
                width: root.menuCardWidth
                height: root.menuCardHeight
                focus: true
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                scale: GlobalStates.desktopMenuOpen ? 1.0 : 0.95
                opacity: GlobalStates.desktopMenuOpen ? 1.0 : 0.0
                transformOrigin: Item.Center

                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }

                // Absorb clicks inside menuCard so they don't dismiss the menu
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                HoverHandler {
                    id: menuCardHover
                    onHoveredChanged: {
                        if (hovered) {
                            submenuCloseTimer.stop()
                        } else if (!submenuContainerHover.hovered) {
                            submenuCloseTimer.restart()
                        }
                    }
                }

                ColumnLayout {
                    id: menuCol
                    anchors { fill: parent; margins: 8 }
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 148
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer1
                        clip: true

                        Carousel {
                            anchors.fill: parent
                            anchors.margins: 6
                            model: root.carouselModel
                            onWallpaperSelected: (path) => {
                                Wallpapers.select(path, Appearance.m3colors.darkmode)
                                GlobalStates.desktopMenuOpen = false
                            }
                        }
                    }

                    GroupedList {
                        Layout.fillWidth: true
                        itemVerticalPadding: 6
                        bgcolor: Appearance.colors.colLayer1

                        // Wallpapers
                        RippleButton {
                            id: wallpaperRow
                            implicitHeight: 40
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "format_paint"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                                StyledText { Layout.fillWidth: true; text: Translation.tr("Wallpaper & style"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                            }
                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) {
                                        submenuCloseTimer.stop()
                                        root.activeSubmenu = "wallpaper"
                                    }
                                }
                            }
                        }

                        // Widgets Submenu
                        RippleButton {
                            id: widgetsRow
                            implicitHeight: 40
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: "widgets"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer1 }
                                StyledText { Layout.fillWidth: true; text: Translation.tr("Toggle Widgets"); font.pixelSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                                MaterialSymbol { text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1; opacity: 0.4 }
                            }

                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) {
                                        submenuCloseTimer.stop()
                                        root.activeSubmenu = "widgets"
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // SubMenu inside the same window for smooth hovering
            Item {
                id: submenuContainer
                x: root.subX
                y: 0
                width: root.submenuWidth
                height: menuWindow.implicitHeight
                visible: root.hasSubmenu
                opacity: root.hasSubmenu ? 1.0 : 0.0
                scale: root.hasSubmenu ? 1.0 : 0.95
                transformOrigin: Item.Center

                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 120 }
                }

                // Absorb clicks inside submenuContainer so they don't dismiss the menu
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                WallpaperSubmenu {
                    id: wallpaperSubmenuItem
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: implicitHeight
                    visible: root.activeSubmenu === "wallpaper"
                }

                WidgetsSubmenu {
                    id: widgetsSubmenuItem
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: implicitHeight
                    visible: root.activeSubmenu === "widgets"
                }

                HoverHandler {
                    id: submenuContainerHover
                    onHoveredChanged: {
                        if (hovered) {
                            submenuCloseTimer.stop()
                        } else if (!menuCardHover.hovered) {
                            submenuCloseTimer.restart()
                        }
                    }
                }
            }
        }
    }
}

