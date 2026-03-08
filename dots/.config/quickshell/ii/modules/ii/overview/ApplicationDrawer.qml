import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io

FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true
    property bool expanded: false
    property string searchText: ""
    property string sortMode: "name" // "name", "recent"
    property string currentCategory: "All"
    
    // --- UI Configuration ---
    property real iconSize: 64
    property real spacing: 20
    
    property color backgroundColor: Appearance.colors.colLayer0
    property color surfaceTint: Appearance.m3colors.m3primary
    
    // Hidden item to hold focus when in Grid mode
    Item { id: gridFocusHolder }
    property real cornerRadius: Appearance.rounding.large 

    property real collapsedHeight: 400
    property real availableHeight: 0
    property real availableWidth: 0
    
    property real expandedHeight: {
        if (availableHeight > 0) return availableHeight * 0.9;
        return 600;
    }
    
    // Calculate columns
    property int columns: {
        const minCellWidth = 100;
        const gridWidth = (availableWidth * 0.7) - 200; 
        if (gridWidth > 0) {
            const cols = Math.floor(gridWidth / minCellWidth);
            return Math.min(8, Math.max(4, cols));
        }
        return 5;
    }

    property var contextMenuApp: null
    property bool contextMenuVisible: false
    property point contextMenuPosition: Qt.point(0, 0)

    // --- Data ---
    property var allApps: DesktopEntries.applications.values
    property var categories: ["All"]
    property bool appsLoaded: true
    
    // Recent apps tracking (max 8 recent apps)
    property var recentAppIds: Persistent.states.appDrawer.recentApps
    property int maxRecentApps: 8
    
    // Keyboard navigation
    property int selectedGridIndex: -1
    property bool gridHasFocus: false
    
    // Focus tracking
    enum FocusArea { Sidebar, Search, Grid }
    property int currentFocusArea: ApplicationDrawer.FocusArea.Search

    Component.onCompleted: {
        extractCategories();
        appGrid.model.values = root.getFilteredApps();
    }
    
    onAllAppsChanged: {
        extractCategories();
        appGrid.model.values = root.getFilteredApps();
    }
    
    // Helper: Get app count for a category
    function getCategoryAppCount(category) {
        if (!root.allApps) return 0;
        if (category === "All") return root.allApps.length;
        return Array.from(root.allApps).filter(app => getAppMainCategory(app) === category).length;
    }
    
    // Helper: Get app ID from app object
    function getAppId(app) {
        // Try to extract app ID from the desktop entry
        if (app && app.id) return app.id.toString();
        if (app && app.name) return app.name.toLowerCase().replace(/\s+/g, '-');
        return "";
    }
    
    // Track recently launched apps
    function trackRecentApp(app) {
        const appId = getAppId(app);
        if (!appId) return;
        
        let recent = Array.from(Persistent.states.appDrawer.recentApps).filter(id => id !== appId);
        recent.unshift(appId);
        recent = recent.slice(0, root.maxRecentApps);
        
        // Persist to state
        Persistent.states.appDrawer.recentApps = recent;
    }
    
    // Focus the search field for immediate typing
    function focusSearchField() {
        root.currentFocusArea = ApplicationDrawer.FocusArea.Search;
        root.selectedGridIndex = -1;
        searchField.forceActiveFocus();
    }
    
    // Focus the grid
    function focusGrid() {
        root.currentFocusArea = ApplicationDrawer.FocusArea.Grid;
        if (root.selectedGridIndex < 0) root.selectedGridIndex = 0;
        gridFocusHolder.forceActiveFocus();
    }
    
    // Keyboard navigation - using dedicated handlers for reliability
    Keys.onEscapePressed: event => {
        GlobalStates.appDrawerOpen = false;
        event.accepted = true;
    }
    
    Keys.onTabPressed: event => {
        // Cycle focus: Search -> Grid -> Search
        if (currentFocusArea === ApplicationDrawer.FocusArea.Search) {
            focusGrid();
        } else {
            focusSearchField();
        }
        event.accepted = true;
    }
    
    Keys.onRightPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            const totalApps = appGrid.model.values.length;
            if (selectedGridIndex < totalApps - 1) {
                selectedGridIndex++;
                appGrid.positionViewAtIndex(selectedGridIndex, GridView.Contain);
            }
            event.accepted = true;
        }
    }
    
    Keys.onLeftPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            if (selectedGridIndex > 0) {
                selectedGridIndex--;
                appGrid.positionViewAtIndex(selectedGridIndex, GridView.Contain);
            }
            event.accepted = true;
        }
    }
    
    Keys.onDownPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Search) {
            // Enter grid from search
            focusGrid();
            event.accepted = true;
        } else if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            const totalApps = appGrid.model.values.length;
            if (totalApps === 0) return;
            
            // Calculate next row index
            const currentRow = Math.floor(selectedGridIndex / root.columns);
            const currentCol = selectedGridIndex % root.columns;
            const nextRowIndex = (currentRow + 1) * root.columns + currentCol;
            
            if (nextRowIndex < totalApps) {
                selectedGridIndex = nextRowIndex;
                appGrid.positionViewAtIndex(selectedGridIndex, GridView.Contain);
            } else if (currentRow * root.columns + currentCol < totalApps - 1) {
                // Go to last app if we can't go to exact position
                selectedGridIndex = totalApps - 1;
                appGrid.positionViewAtIndex(selectedGridIndex, GridView.Contain);
            }
            event.accepted = true;
        }
    }
    
    Keys.onUpPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            const currentRow = Math.floor(selectedGridIndex / root.columns);
            
            // If on first row, return focus to search
            if (currentRow === 0) {
                focusSearchField();
                event.accepted = true;
                return;
            }
            
            // Move to previous row, same column
            const currentCol = selectedGridIndex % root.columns;
            const prevRowIndex = (currentRow - 1) * root.columns + currentCol;
            selectedGridIndex = prevRowIndex;
            appGrid.positionViewAtIndex(selectedGridIndex, GridView.Contain);
            event.accepted = true;
        }
    }
    
    Keys.onReturnPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            const totalApps = appGrid.model.values.length;
            if (selectedGridIndex >= 0 && selectedGridIndex < totalApps) {
                const app = appGrid.model.values[selectedGridIndex];
                GlobalStates.appDrawerOpen = false;
                GlobalStates.overviewOpen = false;
                root.trackRecentApp(app);
                root.executeApp(app);
            }
            event.accepted = true;
        }
    }
    
    implicitHeight: root.expanded ? root.expandedHeight : root.collapsedHeight

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Appearance.animation.elementResize.type
            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
        }
    }

    function extractCategories() {
        const cats = new Set(["All"]);
        root.allApps.forEach(app => {
            const appCats = app.categories || [];
            let mainCat = null;
            // Iterate and find first matching main category
            for (const c of appCats) {
                 mainCat = getMainCategory(c);
                 if (mainCat !== "Other") break;
            }
            if (mainCat) cats.add(mainCat);
        });
        root.categories = Array.from(cats).sort();
    }

    function getMainCategory(catString) {
        if (!catString) return "Other";
        const s = catString; 
        if (s === "Audio" || s === "Video" || s === "AudioVideo") return "Multimedia";
        if (s === "Development") return "Development";
        if (s === "Education") return "Education";
        if (s === "Game") return "Games";
        if (s === "Graphics") return "Graphics";
        if (s === "Network") return "Internet";
        if (s === "Office") return "Office";
        if (s === "Settings") return "Settings";
        if (s === "System") return "System";
        if (s === "Utility") return "Utilities";
        return "Other";
    }

    function getAppMainCategory(app) {
        const appCats = app.categories || [];
        for (const c of appCats) {
             const main = getMainCategory(c);
             if (main !== "Other") return main;
        }
        return "Other";
    }

    function getFilteredApps() {
        if (!root.allApps) {
            console.warn("No apps found in DesktopEntries.");
            return [];
        }

        let apps = Array.from(root.allApps);
        console.log("Total apps from DesktopEntries:", apps.length);

        // Filter by Search
        if (root.searchText.length > 0) {
            const searchLower = root.searchText.toLowerCase();
            apps = apps.filter(app => 
                (app.name && app.name.toLowerCase().includes(searchLower)) ||
                (app.comment && app.comment.toLowerCase().includes(searchLower)) ||
                (app.genericName && app.genericName.toLowerCase().includes(searchLower))
            );
        } 
        // Filter by Category (only if no search)
        else if (root.currentCategory !== "All") {
            apps = apps.filter(app => {
                return getAppMainCategory(app) === root.currentCategory;
            });
        }

        // Sort
        if (root.sortMode === "name") {
            apps.sort((a, b) => (a.name || "").localeCompare(b.name || ""));
        }

        // Map to JS objects for ScriptModel
        return apps.map(app => {
            return {
                name: app.name,
                icon: app.icon,
                execute: app.execute,
                category: app.categories ? app.categories[0] : "", // For basic checking
                categories: app.categories || []
            };
        });
    }
    
    function executeApp(app) {
        if (!app) return;
        if (app.execute) {
            app.execute();
        } else {
             console.warn("App has no execute method:", app.name);
        }
    }

    StyledRectangularShadow { target: drawerBackground }

    Rectangle {
        id: drawerBackground
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.backgroundColor
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            // --- Top Header ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                StyledText {
                    anchors.centerIn: parent
                    text: root.searchText ? "Search Results" : (root.currentCategory === "All" ? "All Applications" : root.currentCategory)
                    font.pixelSize: 16
                    font.weight: Font.Normal
                    color: Appearance.colors.colOnLayer0
                }

                RippleButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    padding: 0
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer0
                    }

                    onClicked: {
                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "app-drawer", "close"])
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

            // --- Sidebar ---
            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: 200
                
                ColumnLayout {
                    anchors.fill: parent
                    
                    StyledText {
                        text: Translation.tr("Categories")
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        Layout.bottomMargin: 10
                        Layout.leftMargin: 20
                    }

                    Item {
                        id: categoryListContainer
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        NavigationRail {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 0
                            expanded: true

                            NavigationRailTabArray {
                                currentIndex: Math.max(0, root.categories.indexOf(root.currentCategory))
                                expanded: true
                                Layout.topMargin: 0

                                Repeater {
                                    model: root.categories

                                    NavigationRailButton {
                                        required property int index
                                        required property string modelData

                                        toggled: modelData === root.currentCategory
                                        showToggledHighlight: false
                                        expanded: true
                                        baseSize: 44
                                        baseHighlightHeight: 44

                                        buttonIcon: {
                                            switch (modelData) {
                                                case "All": return "widgets";
                                                case "Multimedia": return "movie";
                                                case "Development": return "laptop_mac";
                                                case "Education": return "school";
                                                case "Games": return "sports_esports";
                                                case "Graphics": return "palette";
                                                case "Internet": return "explore";
                                                case "Office": return "description";
                                                case "Settings": return "settings";
                                                case "System": return "desktop_windows";
                                                case "Utilities": return "home_repair_service";
                                                default: return "category";
                                            }
                                        }
                                        buttonText: modelData + " (" + root.getCategoryAppCount(modelData) + ")"

                                        onPressed: {
                                            root.currentCategory = modelData;
                                            root.searchText = "";
                                            searchField.text = "";
                                            appGrid.model.values = root.getFilteredApps();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Vertical Divider

            }

            // --- Main Content ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.large

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // Header & Search
                RowLayout {
                    Layout.fillWidth: true
                    
                    RowLayout {
                        spacing: 8
                        MaterialSymbol {
                            text: "grid_view"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: "Applications Grid"
                            font.pixelSize: 16
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 300
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignVCenter
                        radius: 22
                        color: searchField.activeFocus ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: searchField.forceActiveFocus()
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "search"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer0
                            }

                            StyledTextInput {
                                id: searchField
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                font.pixelSize: 15
                                color: Appearance.colors.colOnSurface
                                selectByMouse: true
                                clip: true

                                onTextChanged: {
                                    root.searchText = text;
                                    appGrid.model.values = root.getFilteredApps();
                                }

                                StyledText {
                                    anchors.fill: parent
                                    text: "Search apps..."
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: 15
                                    visible: !searchField.text && !searchField.activeFocus
                                }

                                // Forward navigation keys to root
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Escape) {
                                        GlobalStates.appDrawerOpen = false;
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Tab) {
                                        focusGrid();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Down) {
                                        focusGrid();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (appGrid.model.values.length > 0) {
                                            const app = appGrid.model.values[0];
                                            GlobalStates.appDrawerOpen = false;
                                            GlobalStates.overviewOpen = false;
                                            root.trackRecentApp(app);
                                            root.executeApp(app);
                                        }
                                        event.accepted = true;
                                    }
                                }
                            }

                            RippleButton {
                                Layout.alignment: Qt.AlignVCenter
                                visible: searchField.text.length > 0
                                padding: 0
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: 12
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover

                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "close"
                                    iconSize: 16
                                    color: Appearance.colors.colOnLayer0
                                }

                                onClicked: {
                                    searchField.text = "";
                                    searchField.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Grid Container
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledFlickable {
                        id: appGrid
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        
                        ScrollBar.vertical: StyledScrollBar {}
                        
                        property real cellWidth: width / root.columns
                    property real cellHeight: cellWidth * 1.3
                    contentWidth: width
                    contentHeight: gridContent.implicitHeight
                    property var model: appGridModel

                    function positionViewAtIndex(index, mode) {
                        if (index < 0) return;
                        const row = Math.floor(index / root.columns);
                        const rowTop = row * cellHeight;
                        const rowBottom = rowTop + cellHeight;
                        const viewportTop = contentY;
                        const viewportBottom = contentY + height;
                        let targetY = contentY;

                        if (rowTop < viewportTop) targetY = rowTop;
                        else if (rowBottom > viewportBottom) targetY = rowBottom - height;

                        const maxY = Math.max(0, contentHeight - height);
                        contentY = Math.max(0, Math.min(targetY, maxY));
                    }

                    ScriptModel {
                        id: appGridModel
                        values: []
                    }

                    Grid {
                        id: gridContent
                        width: appGrid.width
                        columns: root.columns
                        // No spacing needed as the cells are fixed sizes

                        Repeater {
                            model: appGrid.model.values

                            delegate: Item {
                                required property int index
                                required property var modelData
                                width: appGrid.cellWidth
                                height: appGrid.cellHeight

                                RippleButton {
                                    id: appButton
                                    property bool isPinned: TaskbarApps.isPinned(root.getAppId(modelData))

                                    anchors.centerIn: parent
                                    width: appGrid.cellWidth - 10
                                    height: appGrid.cellHeight - 10
                                    buttonRadius: 12
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colSecondaryContainer
                                    toggled: root.currentFocusArea === ApplicationDrawer.FocusArea.Grid && root.selectedGridIndex === index
                                    colBackgroundToggled: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.18)
                                    colBackgroundToggledHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.24)
                                    colRippleToggled: ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.88)

                                    onClicked: {
                                        GlobalStates.appDrawerOpen = false;
                                        GlobalStates.overviewOpen = false;
                                        root.trackRecentApp(modelData);
                                        root.executeApp(modelData);
                                    }

                                    // Right-click context menu
                                    altAction: () => {
                                        root.contextMenuApp = modelData;
                                        root.contextMenuVisible = true;
                                        let globalPos = appButton.mapToItem(drawerBackground, appButton.width / 2, appButton.height / 2);
                                        root.contextMenuPosition = Qt.point(globalPos.x, globalPos.y);
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        width: parent.width - 16
                                        spacing: 8

                                        IconImage {
                                            Layout.alignment: Qt.AlignHCenter
                                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                                            implicitSize: root.iconSize
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            horizontalAlignment: Text.AlignHCenter
                                            color: Appearance.colors.colOnLayer0
                                            font.pixelSize: 13
                                            font.weight: appButton.isPinned ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
            }
        }
    }

        // Context Menu Overlay (positioned outside layout to not affect grid)
    Item {
        id: contextMenuOverlay
        visible: root.contextMenuVisible || contextMenu.opacity > 0
        anchors.fill: drawerBackground
        z: 100
        
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.contextMenuVisible = false
        }
        
        Rectangle {
            id: contextMenu
            x: Math.min(root.contextMenuPosition.x, parent.width - width - 10)
            y: Math.min(root.contextMenuPosition.y, parent.height - height - 10)
            width: 240
            implicitHeight: contextMenuColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2Base
            scale: root.contextMenuVisible ? 1 : 0.95
            opacity: root.contextMenuVisible ? 1 : 0
            transformOrigin: Item.TopLeft

            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: contextMenuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                
                // Pin to Dock
                DialogListItem {
                    id: pinToDockButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    buttonRadius: Appearance.rounding.small
                    
                    property bool isPinned: root.contextMenuApp ? TaskbarApps.isPinned(root.getAppId(root.contextMenuApp)) : false
                    
                    onClicked: {
                        if (root.contextMenuApp) {
                            const appId = root.getAppId(root.contextMenuApp);
                            const wasPinned = TaskbarApps.isPinned(appId); // Check BEFORE toggling
                            console.log("Toggling pin for:", appId, "Was pinned:", wasPinned);
                            TaskbarApps.togglePin(appId);
                            
                            const appName = root.contextMenuApp.name;
                            const isPinnedNow = !wasPinned;
                            
                            const msg = isPinnedNow 
                                ? "Pinned " + appName + " to dock" 
                                : "Unpinned " + appName + " from dock";
                            
                            const line = "neutral|Dock|" + msg + "|notification|" + (isPinnedNow ? "pinned" : "unpinned");
                            const safeLine = StringUtils.shellSingleQuoteEscape(line);
                            Quickshell.execDetached(["bash", "-c", "echo '" + safeLine + "' >> /tmp/qs_popup.log"]);
                        }
                        root.contextMenuVisible = false;
                    }
                    
                    contentItem: Item {
                        implicitWidth: pinToDockRow.implicitWidth
                        implicitHeight: Math.max(18, pinToDockText.implicitHeight)
                        
                        RowLayout {
                            id: pinToDockRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "push_pin"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                id: pinToDockText
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                verticalAlignment: Text.AlignVCenter
                                text: pinToDockButton.isPinned ? Translation.tr("Unpin from Dock") : Translation.tr("Pin to Dock")
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                // Uninstall
                DialogListItem {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    buttonRadius: Appearance.rounding.small
                    
                    onClicked: {
                        if (root.contextMenuApp) {
                            const desktopFile = root.contextMenuApp.fileName;
                            const appId = root.getAppId(root.contextMenuApp);
                            const appName = root.contextMenuApp.name;
                            const scriptPath = Directories.scriptPath + "/uninstall_app.sh";
                            
                            // Launch terminal to run the script
                            // Using bash -c wrapper to ensure args are handled and window stays open
                            const term = Config.options.apps.terminal; 
                            const fullCmd = term + " bash -c \"'" + scriptPath + "' '" + desktopFile + "' '" + appId + "' '" + StringUtils.shellSingleQuoteEscape(appName) + "'; echo; echo Press Enter to close...; read\"";
                            
                            Quickshell.execDetached(["bash", "-c", fullCmd]);
                        }
                        root.contextMenuVisible = false;
                        GlobalStates.appDrawerOpen = false;
                        GlobalStates.overviewOpen = false;
                    }
                    
                    contentItem: Item {
                        implicitWidth: uninstallRow.implicitWidth
                        implicitHeight: Math.max(18, uninstallText.implicitHeight)
                        
                        RowLayout {
                            id: uninstallRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 10

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "delete"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                id: uninstallText
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("Uninstall")
                                color: Appearance.colors.colOnLayer1
}
}
}
}
}
}
}
}
