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

    // Toast Notification
    property string toastMessage: ""
    property bool toastVisible: false

    function showToast(message) {
        toastMessage = message;
        toastVisible = true;
        toastTimer.restart();
    }

    Timer {
        id: toastTimer
        interval: 2500
        onTriggered: root.toastVisible = false
    }
    
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

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 0

            // --- Sidebar ---
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 200
                color: "transparent"
                
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
                        
                        property int selectedIndex: root.categories.indexOf(root.currentCategory)
                        property real itemHeight: 44
                        
                        // Animated pill highlight
                        Rectangle {
                            id: pillHighlight
                            anchors.left: categoryColumn.left
                            anchors.leftMargin: 8
                            y: categoryListContainer.selectedIndex * categoryListContainer.itemHeight
                            width: categoryColumn.width - 16
                            height: categoryListContainer.itemHeight
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSecondaryContainer
                            
                            Behavior on y {
                                NumberAnimation {
                                    duration: Appearance.animationCurves.expressiveFastSpatialDuration
                                    easing.type: Appearance.animation.elementMove.type
                                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                                }
                            }
                        }
                        
                        ColumnLayout {
                            id: categoryColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: 0
                            
                            Repeater {
                                model: root.categories
                                
                                RippleButton {
                                    required property int index
                                    required property string modelData
                                    
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    Layout.rightMargin: 8
                                    Layout.preferredHeight: categoryListContainer.itemHeight
                                    buttonRadius: Appearance.rounding.small
                                    
                                    property bool isSelected: modelData === root.currentCategory
                                    colBackground: "transparent"
                                    colBackgroundHover: isSelected ? "transparent" : Appearance.colors.colLayer1
                                    
                                    onClicked: {
                                        root.currentCategory = modelData;
                                        root.searchText = ""; 
                                        searchField.text = "";
                                        appGrid.model.values = root.getFilteredApps();
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 16
                                        spacing: 6
                                        
                                        Item {
                                            Layout.preferredWidth: 24
                                            Layout.preferredHeight: 32
                                            Layout.alignment: Qt.AlignVCenter
                                            
                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: {
                                                    switch(modelData) {
                                                        case "All": return "apps";
                                                        case "Multimedia": return "movie";
                                                        case "Development": return "code";
                                                        case "Education": return "school";
                                                        case "Games": return "sports_esports";
                                                        case "Graphics": return "palette";
                                                        case "Internet": return "public";
                                                        case "Office": return "description";
                                                        case "Settings": return "settings";
                                                        case "System": return "dns";
                                                        case "Utilities": return "build";
                                                        default: return "category";
                                                    }
                                                }
                                                iconSize: 20
                                                color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                                            }
                                        }

                                        StyledText {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignLeft
                                            text: modelData + " (" + root.getCategoryAppCount(modelData) + ")"
                                            color: isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
                                            font.weight: isSelected ? Font.DemiBold : Font.Normal
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
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20
                spacing: 16

                // Header & Search
                RowLayout {
                    Layout.fillWidth: true
                    
                    StyledText {
                        text: root.searchText ? "Search Results" : (root.currentCategory === "All" ? "All Applications" : root.currentCategory)
                        font.pixelSize: 24
                        font.weight: Font.Normal
                        color: Appearance.colors.colOnLayer0
                    }
                    
                    Item { Layout.fillWidth: true }

                    TextField {
                        id: searchField
                        Layout.preferredWidth: 300
                        Layout.preferredHeight: 44
                        placeholderText: "Search apps..."
                        
                        background: Rectangle {
                            radius: 22
                            color: Appearance.colors.colLayer2
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                            
                            MaterialSymbol {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "search"
                                color: Appearance.colors.colOnLayer0
                                iconSize: 20
                            }
                        }
                        
                        font.pixelSize: 15
                        color: Appearance.m3colors.m3onSurface
                        leftPadding: 42
                        
                        onTextChanged: {
                            root.searchText = text;
                            appGrid.model.values = root.getFilteredApps();
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
                                // Move to grid on arrow down
                                focusGrid();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                // Launch first app in filtered results
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
                }

                // Grid
                GridView {
                    id: appGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    cellWidth: width / root.columns
                    cellHeight: cellWidth * 1.3
                    
                    model: ScriptModel { values: [] }

                    delegate: RippleButton {
                        id: appButton
                        required property int index
                        required property var modelData
                        
                        width: appGrid.cellWidth - 10
                        height: appGrid.cellHeight - 10
                        buttonRadius: 12
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colSecondaryContainer
                        
                        // Keyboard selection highlight
                        property bool isKeyboardSelected: root.currentFocusArea === ApplicationDrawer.FocusArea.Grid && root.selectedGridIndex === index
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.width: appButton.isKeyboardSelected ? 2 : 0
                            border.color: Appearance.colors.colPrimary
                            
                            Behavior on border.width {
                                NumberAnimation { duration: 100 }
                            }
                        }
                        
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
                            // Position relative to drawerBackground
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
                            
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                horizontalAlignment: Text.AlignHCenter
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                            }
                        }
                    }
                    
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        active: appGrid.moving || appGrid.flickableItem.contentHeight > appGrid.height
                        
                        contentItem: Rectangle {
                            implicitWidth: 6
                            radius: 3
                            color: Appearance.colors.colPrimary
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
            onClicked: root.contextMenuVisible = false
        }
        
        // Shadow behind context menu
        Rectangle {
            x: contextMenu.x + 4
            y: contextMenu.y + 4
            width: contextMenu.width
            height: contextMenu.height
            radius: contextMenu.radius
            color: Qt.rgba(0, 0, 0, 0.2)
            opacity: contextMenu.opacity
        }
        
        Rectangle {
            id: contextMenu
            x: Math.min(root.contextMenuPosition.x, parent.width - width - 10)
            y: Math.min(root.contextMenuPosition.y, parent.height - height - 10)
            width: 220
            implicitHeight: contextMenuColumn.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2Base
            
            scale: root.contextMenuVisible ? 1 : 0.5
            opacity: root.contextMenuVisible ? 1 : 0
            transformOrigin: Item.TopLeft
            
            Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
            Behavior on opacity { NumberAnimation { duration: 200 } }
            
            border.width: 1
            border.color: Appearance.colors.colLayer1Border
            
            ColumnLayout {
                id: contextMenuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                
                // Pin to Dock
                RippleButton {
                    id: pinToDockButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    
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
                            
                            console.log("Showing toast:", msg);
                            root.showToast(msg);
                        }
                        root.contextMenuVisible = false;
                    }
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10
                        
                        MaterialSymbol {
                            text: "push_pin"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer1
                        }
                        
                        StyledText {
                            Layout.fillWidth: true
                            text: pinToDockButton.isPinned ? Translation.tr("Unpin from Dock") : Translation.tr("Pin to Dock")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                // Uninstall
                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    
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
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        spacing: 10
                        
                        MaterialSymbol {
                            text: "delete"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer1
                        }
                        
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Uninstall")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }


                

            }
        }
    }

    // Toast Component - moved to root for Z-indexing
    Rectangle {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        width: toastTextMetrics.width + 40
        height: 44
        radius: 22
        z: 200 // Ensure it's on top of everything
        
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colLayer2Border
        
        // Elevation shadow
        layer.enabled: true
        layer.effect: StyledRectangularShadow {
            blur: 16
            opacity: 0.3
        }
        
        // Animation
        opacity: root.toastVisible ? 1 : 0
        transform: Translate {
            y: root.toastVisible ? 0 : 20
        }
        
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on transform { NumberAnimation { target: toast.transform; property: "y"; duration: 200; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.centerIn: parent
            spacing: 12
            
            MaterialSymbol {
                text: "info"
                iconSize: 20
                color: Appearance.colors.colPrimary
            }
            
            Text {
                id: toastTextItem
                text: root.toastMessage
                color: Appearance.colors.colOnLayer1
                font.pixelSize: 14
                font.weight: Font.Medium
            }
        }
        
        TextMetrics {
            id: toastTextMetrics
            text: root.toastMessage
            font: toastTextItem.font
        }
    }
}
