import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io

FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true
    signal closeRequested()
    signal appDragStarted(var app, real sceneX, real sceneY)
    signal appDragUpdate(real sceneX, real sceneY)
    signal appDropped(var app, real sceneX, real sceneY)
    signal appDragCancelled()

    property bool dockedInOverview: false
    property bool _isDraggingApp: false
    property bool expanded: false
    property string searchText: ""
    property string sortMode: "name" // "name", "recent"
    property string currentCategory: "All"

    // --- Uninstaller State ---
    property bool uninstallModalVisible: false
    property var uninstallApp: null
    property string uninstallPkg: ""
    property string uninstallKind: "" // "native", "flatpak", "local"
    property string uninstallInst: "user" // "user" or "system"
    property string uninstallSize: ""
    property bool uninstallBlocked: false
    property string uninstallReason: ""
    property bool uninstallBusy: false
    property string uninstallStatus: ""

    function startUninstall(app) {
        if (!app) return;
        root.uninstallApp = app;
        root.uninstallPkg = "";
        root.uninstallKind = "";
        root.uninstallInst = "user";
        root.uninstallSize = "";
        root.uninstallBlocked = false;
        root.uninstallReason = "";
        root.uninstallBusy = true;
        root.uninstallStatus = Translation.tr("Checking app…");
        root.uninstallModalVisible = true;
        
        const did = root.getAppId(app) || "";
        const name = app.name || "";
        const fileName = (app.fileName && app.fileName.length > 0) ? app.fileName : "";
        
        resolveAppProc.fileName = fileName;
        resolveAppProc.did = did;
        resolveAppProc.appName = name;
        resolveAppProc.command = [
            "bash", "-c",
            'ID="$1"; NAME="$2"; FILE="$3"; FOUND=""; ' +
            'if [ -n "$FILE" ] && [ -f "$FILE" ]; then ' +
            '  FOUND="$FILE"; ' +
            'else ' +
            '  for LOC in /usr/share/applications "$HOME/.local/share/applications" /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do ' +
            '    [ ! -d "$LOC" ] && continue; ' +
            '    FOUND=$(find "$LOC" -maxdepth 1 -iname "${ID}.desktop" -print -quit 2>/dev/null); ' +
            '    [ -z "$FOUND" ] && FOUND=$(find "$LOC" -maxdepth 1 -iname "${ID}" -print -quit 2>/dev/null); ' +
            '    [ -z "$FOUND" ] && [ -n "$NAME" ] && FOUND=$(find "$LOC" -maxdepth 1 -iname "*${NAME// /*}*.desktop" -print -quit 2>/dev/null); ' +
            '    [ -z "$FOUND" ] && FOUND=$(find "$LOC" -maxdepth 1 -iname "*${ID}*.desktop" -print -quit 2>/dev/null); ' +
            '    [ -n "$FOUND" ] && break; ' +
            '  done; ' +
            'fi; ' +
            'if [[ "$FOUND" == *"/flatpak/"* ]] || (command -v flatpak &>/dev/null && flatpak info "$ID" &>/dev/null); then ' +
            '  INST="system"; [[ "$FOUND" == *"$HOME"* ]] && INST="user"; ' +
            '  echo "KIND:flatpak"; echo "PKG:$ID"; echo "INST:$INST"; exit 0; ' +
            'fi; ' +
            'if [ -n "$FOUND" ] && [ -f "$FOUND" ]; then ' +
            '  PKG=$(pacman -Qoq "$FOUND" 2>/dev/null || pacman -Qq "$ID" 2>/dev/null || echo ""); ' +
            '  if [ -n "$PKG" ]; then ' +
            '    echo "KIND:native"; echo "PKG:$PKG"; ' +
            '    SIZE=$(pacman -Qi "$PKG" 2>/dev/null | awk -F\': *\' \'/^Installed Size/{print $2; exit}\'); ' +
            '    echo "SIZE:$SIZE"; ' +
            '    PREVIEW=$(app-remover preview "$PKG" 2>&1 || true); ' +
            '    if echo "$PREVIEW" | grep -qE "ERROR:|protected"; then ' +
            '      echo "BLOCKED:1"; echo "REASON:$(echo "$PREVIEW" | sed "s/.*ERROR: //")"; ' +
            '    else ' +
            '      echo "BLOCKED:0"; ' +
            '    fi; ' +
            '    exit 0; ' +
            '  fi; ' +
            '  echo "KIND:local"; echo "PKG:$FOUND"; exit 0; ' +
            'fi; ' +
            'PKG=$(pacman -Qq "$ID" 2>/dev/null || echo ""); ' +
            'if [ -n "$PKG" ]; then ' +
            '  echo "KIND:native"; echo "PKG:$PKG"; ' +
            '  SIZE=$(pacman -Qi "$PKG" 2>/dev/null | awk -F\': *\' \'/^Installed Size/{print $2; exit}\'); ' +
            '  echo "SIZE:$SIZE"; ' +
            '  echo "BLOCKED:0"; exit 0; ' +
            'fi; ' +
            'echo "KIND:unknown"',
            "_", did, name, fileName
        ];
        resolveAppProc.running = true;
    }

    function confirmUninstall() {
        if (root.uninstallBlocked) return;
        const targetPkg = root.uninstallPkg || root.getAppId(root.uninstallApp) || root.uninstallApp?.name;
        if (!targetPkg) return;
        const appName = root.uninstallApp?.name || targetPkg;
        const did = root.getAppId(root.uninstallApp) || "";
        
        root.uninstallModalVisible = false;
        GlobalStates.appDrawerOpen = false;
        GlobalStates.overviewOpen = false;
        
        let cmd = "";
        if (root.uninstallKind === "flatpak") {
            cmd = (root.uninstallInst === "user")
                ? `flatpak uninstall -y --noninteractive '${targetPkg}'`
                : `pkexec flatpak uninstall -y --noninteractive '${targetPkg}'`;
        } else if (root.uninstallKind === "native") {
            cmd = `pkexec pacman -Rns --noconfirm '${targetPkg}'`;
        } else {
            if (targetPkg.endsWith(".desktop") || targetPkg.includes("/")) {
                cmd = `rm -f '${targetPkg}'`;
            } else {
                cmd = `pkexec pacman -Rns --noconfirm '${targetPkg}'`;
            }
        }
        
        const cleanName = StringUtils.shellSingleQuoteEscape(appName);
        const fullScript = `nice -n 10 bash -c "${cmd} && rm -f ~/.local/share/applications/'${did}.desktop' && update-desktop-database ~/.local/share/applications 2>/dev/null && echo 'success|Uninstall|${cleanName} was uninstalled|delete|success' >> /tmp/qs_popup.log || echo 'error|Uninstall|Failed to uninstall ${cleanName}|error|error' >> /tmp/qs_popup.log"`;
        
        Quickshell.execDetached(["bash", "-c", fullScript]);
    }

    Process {
        id: resolveAppProc
        property string fileName: ""
        property string did: ""
        property string appName: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                for (const line of lines) {
                    const trimmed = line.trim();
                    if (trimmed.startsWith("KIND:")) root.uninstallKind = trimmed.slice(5);
                    else if (trimmed.startsWith("PKG:")) root.uninstallPkg = trimmed.slice(4);
                    else if (trimmed.startsWith("INST:")) root.uninstallInst = trimmed.slice(5);
                    else if (trimmed.startsWith("SIZE:")) root.uninstallSize = trimmed.slice(5);
                    else if (trimmed.startsWith("BLOCKED:")) root.uninstallBlocked = (trimmed.slice(8) === "1");
                    else if (trimmed.startsWith("REASON:")) root.uninstallReason = trimmed.slice(7);
                }
                root.uninstallBusy = false;
                root.uninstallStatus = "";
            }
        }
        onExited: (code) => {
            root.uninstallBusy = false;
        }
    }

    Process {
        id: execUninstallProc
        property string appName: ""
        property string did: ""
        property string errBuf: ""
        stderr: StdioCollector { onStreamFinished: execUninstallProc.errBuf = this.text }
        onExited: (exitCode) => {
            root.uninstallBusy = false;
            if (exitCode === 0) {
                if (execUninstallProc.did) {
                    Quickshell.execDetached(["bash", "-c", "rm -f ~/.local/share/applications/'" + execUninstallProc.did + ".desktop'; update-desktop-database ~/.local/share/applications 2>/dev/null || true"]);
                }
                root.uninstallModalVisible = false;
                const msg = execUninstallProc.appName + " " + Translation.tr("was uninstalled.");
                const line = "success|Uninstall|" + msg + "|delete|success";
                Quickshell.execDetached(["bash", "-c", "echo '" + StringUtils.shellSingleQuoteEscape(line) + "' >> /tmp/qs_popup.log"]);
            } else if (exitCode === 126 || exitCode === 127) {
                root.uninstallStatus = Translation.tr("Removal cancelled.");
            } else {
                root.uninstallStatus = Translation.tr("Couldn't remove ") + execUninstallProc.appName;
            }
        }
    }
    
    // --- UI Configuration ---
    property real iconSize: root.dockedInOverview ? 48 : 56
    property real spacing: root.dockedInOverview ? 12 : 16
    
    property color backgroundColor: Appearance.colors.colLayer0Base
    property color surfaceTint: Appearance.m3colors.m3primary
    
    // Hidden item to hold focus when in Grid mode
    Item { id: gridFocusHolder }
    property real cornerRadius: Appearance.rounding.verylarge 

    property real collapsedHeight: 400
    property real availableHeight: 0
    property real availableWidth: 0
    
    property real expandedHeight: {
        if (availableHeight > 0) return availableHeight * 0.9;
        return 600;
    }
    
    // Calculate columns (stable regardless of sidebar expanded/collapsed state)
    property int columns: {
        const totalWidth = root.width > 0 ? root.width : (availableWidth > 0 ? availableWidth : 1000);
        if (root.dockedInOverview) {
            const targetCellWidth = 110;
            return Math.max(6, Math.min(12, Math.floor(totalWidth / targetCellWidth)));
        } else {
            const baseGridWidth = totalWidth - 220 - 64;
            const targetCellWidth = 130;
            if (baseGridWidth > 0) {
                return Math.max(5, Math.min(8, Math.floor(baseGridWidth / targetCellWidth)));
            }
            return 6;
        }
    }

    property var contextMenuApp: null
    property bool contextMenuVisible: false
    property point contextMenuPosition: Qt.point(0, 0)

    // --- Data ---
    property var allApps: DesktopEntries.applications.values
    property var allAppsList: root.allApps ? Array.from(root.allApps).sort((a, b) => (a.name || "").localeCompare(b.name || "")) : []
    property var filteredAppsList: []
    property var appPositions: ({})
    property real totalGridContentHeight: 0
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

    onSearchTextChanged: {
        updateFilteredApps();
        if (appGrid) appGrid.contentY = 0;
    }
    onCurrentCategoryChanged: updateFilteredApps()
    onSortModeChanged: updateFilteredApps()
    onColumnsChanged: recomputeAppPositions()

    Timer {
        id: appListDebounceTimer
        interval: 150
        repeat: false
        onTriggered: {
            extractCategories();
            updateFilteredApps();
        }
    }

    Component.onCompleted: {
        extractCategories();
        updateFilteredApps();
    }
    
    onAllAppsChanged: {
        appListDebounceTimer.restart();
    }

    function updateFilteredApps() {
        root.filteredAppsList = root.getFilteredApps();
        root.recomputeAppPositions();
    }

    function recomputeAppPositions() {
        if (!appGrid || appGrid.width <= 0) return;
        const filtered = root.filteredAppsList;
        const cols = root.columns;
        const cellW = appGrid.width / cols;
        const cellH = root.dockedInOverview ? 105 : Math.max(120, cellW * 1.05);
        const newPos = {};
        for (let i = 0; i < filtered.length; i++) {
            const app = filtered[i];
            const key = root.getAppId(app);
            const col = i % cols;
            const row = Math.floor(i / cols);
            const x = col * cellW;
            const y = row * cellH;
            newPos[key] = { x: x, y: y, width: cellW, height: cellH, index: i };
        }
        const totalRows = Math.ceil(filtered.length / cols);
        root.totalGridContentHeight = totalRows * cellH + (root.dockedInOverview ? 8 : 24);
        root.appPositions = newPos;
    }
    
    // Helper: Get app count for a category
    function getCategoryAppCount(category) {
        if (!root.allApps) return 0;
        if (category === "All") return root.allApps.length;
        return Array.from(root.allApps).filter(app => getAppMainCategory(app) === category).length;
    }
    
    // Helper: Get app ID from app object
    function getAppId(app) {
        if (!app) return "";
        if (app.fileName) return app.fileName;
        if (app.id) return app.id.toString();
        if (app.name) return app.name.toLowerCase().replace(/\s+/g, '-');
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
            const totalApps = root.filteredAppsList.length;
            if (selectedGridIndex < totalApps - 1) {
                selectedGridIndex++;
                appGrid.positionViewAtIndex(selectedGridIndex);
            }
            event.accepted = true;
        }
    }
    
    Keys.onLeftPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            if (selectedGridIndex > 0) {
                selectedGridIndex--;
                appGrid.positionViewAtIndex(selectedGridIndex);
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
            const totalApps = root.filteredAppsList.length;
            if (totalApps === 0) return;
            
            // Calculate next row index
            const currentRow = Math.floor(selectedGridIndex / root.columns);
            const currentCol = selectedGridIndex % root.columns;
            const nextRowIndex = (currentRow + 1) * root.columns + currentCol;
            
            if (nextRowIndex < totalApps) {
                selectedGridIndex = nextRowIndex;
                appGrid.positionViewAtIndex(selectedGridIndex);
            } else if (currentRow * root.columns + currentCol < totalApps - 1) {
                // Go to last app if we can't go to exact position
                selectedGridIndex = totalApps - 1;
                appGrid.positionViewAtIndex(selectedGridIndex);
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
            appGrid.positionViewAtIndex(selectedGridIndex);
            event.accepted = true;
        }
    }
    
    Keys.onReturnPressed: event => {
        if (currentFocusArea === ApplicationDrawer.FocusArea.Grid) {
            const totalApps = root.filteredAppsList.length;
            if (selectedGridIndex >= 0 && selectedGridIndex < totalApps) {
                const app = root.filteredAppsList[selectedGridIndex];
                GlobalStates.appDrawerOpen = false;
                GlobalStates.overviewOpen = false;
                root.trackRecentApp(app);
                root.executeApp(app);
            }
            event.accepted = true;
        }
    }
    
    implicitWidth: root.dockedInOverview ? width : 1000
    implicitHeight: root.dockedInOverview ? 320 : (root.expanded ? root.expandedHeight : root.collapsedHeight)

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

        return apps;
    }
    
    function executeApp(app) {
        if (!app) return;
        if (typeof app.execute === "function") {
            app.execute();
            return;
        }
        if (app.command && app.command.length > 0) {
            Quickshell.execDetached(app.command);
            return;
        }
        if (typeof app.exec === "string") {
            Quickshell.execDetached(["bash", "-c", app.exec]);
            return;
        }
    }

    StyledRectangularShadow { target: drawerBackground }

    Rectangle {
        id: drawerBackground
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.backgroundColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 24

            // --- Top Header ---
            Item {
                visible: !root.dockedInOverview
                Layout.fillWidth: true
                Layout.preferredHeight: root.dockedInOverview ? 0 : 32

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
                        root.closeRequested();
                        GlobalStates.appDrawerOpen = false;
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

            // --- Sidebar ---
            Item {
                id: navRailWrapper
                visible: !root.dockedInOverview
                Layout.fillHeight: true
                implicitWidth: root.dockedInOverview ? 0 : (categoryNavRail.expanded ? 220 : 80)

                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }

                NavigationRail {
                    id: categoryNavRail
                    anchors.fill: parent
                    expanded: true
                    spacing: 8

                    NavigationRailExpandButton {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                    }

                    StyledText {
                        text: Translation.tr("Categories")
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer0
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.bottomMargin: categoryNavRail.expanded ? 8 : 0
                        opacity: categoryNavRail.expanded ? 1 : 0
                        Layout.preferredHeight: categoryNavRail.expanded ? implicitHeight : 0

                        Behavior on opacity { 
                            NumberAnimation { 
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            } 
                        }
                        Behavior on Layout.preferredHeight { 
                            NumberAnimation { 
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            } 
                        }
                        Behavior on Layout.bottomMargin { 
                            NumberAnimation { 
                                duration: Appearance.animation.elementResize.duration
                                easing.type: Appearance.animation.elementResize.type
                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                            } 
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        ColumnLayout {
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: root.categories

                                Item {
                                    id: categoryItem
                                    required property int index
                                    required property string modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44

                                    property bool isActive: modelData === root.currentCategory
                                    property color fgColor: isActive ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                    property int appCount: root.getCategoryAppCount(modelData)

                                    property string catIcon: {
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

                                    Rectangle {
                                        id: buttonBg
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        width: categoryNavRail.expanded ? parent.width - 20 : 44
                                        height: parent.height
                                        radius: categoryNavRail.expanded ? 12 : 22
                                        color: categoryItem.isActive ? Appearance.m3colors.m3secondaryContainer : "transparent"

                                        Behavior on width { 
                                            NumberAnimation { 
                                                duration: Appearance.animation.elementResize.duration
                                                easing.type: Appearance.animation.elementResize.type
                                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                                            } 
                                        }
                                        Behavior on radius { 
                                            NumberAnimation { 
                                                duration: Appearance.animation.elementResize.duration
                                                easing.type: Appearance.animation.elementResize.type
                                                easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                                            } 
                                        }
                                        Behavior on color { 
                                            ColorAnimation { 
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Appearance.animation.elementMoveFast.type
                                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                            } 
                                        }

                                        transform: Scale {
                                            id: squishScale
                                            origin.x: buttonBg.width / 2
                                            origin.y: buttonBg.height / 2
                                            yScale: 1.0
                                            xScale: 1.0
                                        }

                                        Connections {
                                            target: categoryItem
                                            function onIsActiveChanged() {
                                                if (categoryItem.isActive) {
                                                    selectAnim.restart();
                                                }
                                            }
                                        }

                                        SequentialAnimation {
                                            id: selectAnim
                                            ParallelAnimation {
                                                NumberAnimation { 
                                                    target: squishScale; 
                                                    property: "yScale"; 
                                                    to: 0.75; 
                                                    duration: Appearance.animation.elementMoveFast.duration
                                                    easing.type: Appearance.animation.elementMoveFast.type
                                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                                }
                                                NumberAnimation { 
                                                    target: squishScale; 
                                                    property: "xScale"; 
                                                    to: 1.08; 
                                                    duration: Appearance.animation.elementMoveFast.duration
                                                    easing.type: Appearance.animation.elementMoveFast.type
                                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                                }
                                            }
                                            ParallelAnimation {
                                                NumberAnimation { 
                                                    target: squishScale; 
                                                    property: "yScale"; 
                                                    to: 1.0; 
                                                    duration: Appearance.animation.elementMoveFast.duration
                                                    easing.type: Appearance.animation.elementMoveFast.type
                                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                                }
                                                NumberAnimation { 
                                                    target: squishScale; 
                                                    property: "xScale"; 
                                                    to: 1.0; 
                                                    duration: Appearance.animation.elementMoveFast.duration
                                                    easing.type: Appearance.animation.elementMoveFast.type
                                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                                }
                                            }
                                        }

                                        RippleButton {
                                            anchors.fill: parent
                                            buttonRadius: parent.radius
                                            onClicked: {
                                                root.currentCategory = modelData;
                                                root.searchText = "";
                                                searchField.text = "";
                                                appGrid.model.values = root.getFilteredApps();
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 0

                                                Item {
                                                    Layout.preferredWidth: 44
                                                    Layout.fillHeight: true

                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: catIcon
                                                        iconSize: 20
                                                        fill: categoryItem.isActive ? 1 : 0
                                                        font.weight: categoryItem.isActive ? Font.DemiBold : Font.Normal
                                                        color: fgColor
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    clip: true
                                                    visible: categoryNavRail.expanded

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        spacing: 10
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8

                                                        StyledText {
                                                            text: modelData
                                                            font.pixelSize: 14
                                                            font.weight: categoryItem.isActive ? Font.DemiBold : Font.Normal
                                                            color: fgColor
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                            opacity: categoryNavRail.expanded ? 1.0 : 0.0
                                                            Behavior on opacity { 
                                                                NumberAnimation { 
                                                                    duration: Appearance.animation.elementMoveFast.duration
                                                                    easing.type: Appearance.animation.elementMoveFast.type
                                                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                                                } 
                                                            }
                                                        }

                                                        Rectangle {
                                                            Layout.alignment: Qt.AlignVCenter
                                                            Layout.preferredWidth: countText.implicitWidth + 14
                                                            Layout.preferredHeight: 22
                                                            radius: 11
                                                            color: categoryItem.isActive
                                                                ? ColorUtils.applyAlpha(Appearance.colors.colOnSecondaryContainer, 0.18)
                                                                : ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.10)
                                                            opacity: categoryNavRail.expanded ? 1.0 : 0.0
                                                            Behavior on opacity { 
                                                                NumberAnimation { 
                                                                    duration: Appearance.animation.elementMoveFast.duration
                                                                    easing.type: Appearance.animation.elementMoveFast.type
                                                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                                                } 
                                                            }

                                                            StyledText {
                                                                id: countText
                                                                anchors.centerIn: parent
                                                                text: appCount
                                                                font.pixelSize: 11
                                                                font.weight: Font.DemiBold
                                                                color: fgColor
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

            // --- Main Content ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: root.dockedInOverview ? 0 : 8
                color: root.dockedInOverview ? "transparent" : Appearance.colors.colLayer1
                radius: Appearance.rounding.large

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.dockedInOverview ? 4 : 16
                    spacing: root.dockedInOverview ? 4 : 20

                    // Header & Search
                RowLayout {
                    visible: !root.dockedInOverview
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
                        radius: Appearance.rounding.full
                        color: searchField.activeFocus ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

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
                                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.6)
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
                                    text: "Search applications..."
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
                        anchors.margins: root.dockedInOverview ? 8 : 24
                        clip: true
                        interactive: !root._isDraggingApp

                        ScrollBar.vertical: StyledScrollBar {}

                        contentHeight: root.totalGridContentHeight
                        contentWidth: width

                        onWidthChanged: {
                            if (width > 0) root.recomputeAppPositions();
                        }

                        function positionViewAtIndex(index) {
                            if (index < 0) return;
                            const cellH = (appGrid.width / root.columns) * 1.18;
                            const row = Math.floor(index / root.columns);
                            const rowTop = row * cellH;
                            const rowBottom = rowTop + cellH;
                            const viewportTop = contentY;
                            const viewportBottom = contentY + height;
                            let targetY = contentY;

                            if (rowTop < viewportTop) targetY = rowTop;
                            else if (rowBottom > viewportBottom) targetY = rowBottom - height;

                            const maxY = Math.max(0, contentHeight - height);
                            contentY = Math.max(0, Math.min(targetY, maxY));
                        }

                        Item {
                            id: gridContent
                            width: appGrid.width
                            implicitHeight: root.totalGridContentHeight

                            Repeater {
                                model: root.allAppsList

                                delegate: Item {
                                    id: appItem
                                    required property int index
                                    required property var modelData

                                    readonly property string appKey: root.getAppId(modelData)
                                    readonly property var pos: root.appPositions[appKey] || null
                                    readonly property bool isMatched: pos !== null

                                    property real targetX: pos ? pos.x : targetX
                                    property real targetY: pos ? pos.y : targetY
                                    property real targetWidth: pos ? pos.width : targetWidth
                                    property real targetHeight: pos ? pos.height : targetHeight

                                    x: targetX
                                    y: targetY
                                    width: targetWidth
                                    height: targetHeight

                                    visible: opacity > 0
                                    opacity: isMatched ? 1 : 0
                                    scale: isMatched ? 1 : 0.85

                                    Behavior on x {
                                        enabled: appItem.opacity > 0.05
                                        NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on y {
                                        enabled: appItem.opacity > 0.05
                                        NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 200
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 200
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 200
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 200
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Item {
                                        id: appButton
                                        property bool isPinned: TaskbarApps.isPinned(root.getAppId(modelData))
                                        property bool isKeyboardSelected: root.currentFocusArea === ApplicationDrawer.FocusArea.Grid && pos && root.selectedGridIndex === pos.index

                                        anchors.centerIn: parent
                                        width: root.dockedInOverview ? Math.min(parent.width - 6, 96) : (parent.width - 12)
                                        height: root.dockedInOverview ? (parent.height - 6) : (parent.height - 12)

                                        scale: itemDragArea.containsMouse ? 1.05 : 1.0
                                        y: itemDragArea.containsMouse ? -2 : 0

                                        Behavior on scale {
                                            SpringAnimation { spring: 3; damping: 0.7; mass: 1.0 }
                                        }
                                        Behavior on y {
                                            SpringAnimation { spring: 3; damping: 0.7; mass: 1.0 }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Appearance.rounding.verylarge
                                            color: appButton.isKeyboardSelected
                                                ? (itemDragArea.containsMouse ? ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colOnSecondaryContainer, 0.08) : Appearance.colors.colSecondaryContainer)
                                                : (itemDragArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1)

                                            Behavior on color {
                                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                            }
                                        }

                                        MouseArea {
                                            id: itemDragArea
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor

                                            property real startX: 0
                                            property real startY: 0
                                            property bool isDragging: false

                                            onPressed: (mouse) => {
                                                if (mouse.button === Qt.RightButton) {
                                                    root.contextMenuApp = modelData;
                                                    root.contextMenuVisible = true;
                                                    let globalPos = appButton.mapToItem(drawerBackground, appButton.width / 2, appButton.height / 2);
                                                    root.contextMenuPosition = Qt.point(globalPos.x, globalPos.y);
                                                    return;
                                                }
                                                startX = mouse.x;
                                                startY = mouse.y;
                                                isDragging = false;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressedButtons & Qt.LeftButton) {
                                                    const dx = mouse.x - startX;
                                                    const dy = mouse.y - startY;
                                                    if (!isDragging && (dx * dx + dy * dy > 324)) {
                                                        isDragging = true;
                                                        root._isDraggingApp = true;
                                                        const sp = itemDragArea.mapToItem(null, mouse.x, mouse.y);
                                                        root.appDragStarted(modelData, sp.x, sp.y);
                                                    }
                                                    if (isDragging) {
                                                        const sp = itemDragArea.mapToItem(null, mouse.x, mouse.y);
                                                        root.appDragUpdate(sp.x, sp.y);
                                                    }
                                                }
                                            }

                                            onClicked: (mouse) => {
                                                if (!isDragging && mouse.button === Qt.LeftButton) {
                                                    GlobalStates.appDrawerOpen = false;
                                                    GlobalStates.overviewOpen = false;
                                                    root.trackRecentApp(modelData);
                                                    root.executeApp(modelData);
                                                }
                                            }

                                            onReleased: (mouse) => {
                                                if (isDragging) {
                                                    isDragging = false;
                                                    root._isDraggingApp = false;
                                                    const sp = itemDragArea.mapToItem(null, mouse.x, mouse.y);
                                                    root.appDropped(modelData, sp.x, sp.y);
                                                }
                                            }

                                            onCanceled: {
                                                if (isDragging) {
                                                    isDragging = false;
                                                    root._isDraggingApp = false;
                                                    root.appDragCancelled();
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            width: parent.width - 20
                                            spacing: 10

                                            Item {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredWidth: root.iconSize
                                                Layout.preferredHeight: root.iconSize

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: Appearance.rounding.large
                                                    color: "transparent"
                                                    clip: true

                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                                                        implicitSize: root.iconSize
                                                    }
                                                }
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData.name || ""
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                color: Appearance.colors.colOnLayer0
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                lineHeight: 1.15
                                                elide: Text.ElideNone
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty State Placeholder
                    PagePlaceholder {
                        shown: root.filteredAppsList.length === 0
                        icon: "search_off"
                        title: root.searchText.length > 0 ? Translation.tr("No applications match your search.") : Translation.tr("No applications found.")
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
                        const target = root.contextMenuApp;
                        root.contextMenuVisible = false;
                        if (target) {
                            root.startUninstall(target);
                        }
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

    // ── In-Drawer Uninstall Confirmation Modal ──
    Rectangle {
        id: uninstallModalScrim
        anchors.fill: parent
        z: 200
        visible: root.uninstallModalVisible
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {
                if (!root.uninstallBusy) root.uninstallModalVisible = false;
            }
        }

        Rectangle {
            id: uninstallCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 420)
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            implicitHeight: uninstallCardCol.implicitHeight + 40

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: {}
            }

            ColumnLayout {
                id: uninstallCardCol
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                // Icon / Header
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    IconImage {
                        source: root.uninstallApp ? Quickshell.iconPath(root.uninstallApp.icon, "application-x-executable") : ""
                        width: 44
                        height: 44
                        visible: source != ""
                    }

                    MaterialSymbol {
                        visible: !root.uninstallApp || !root.uninstallApp.icon
                        text: root.uninstallBlocked ? "block" : "delete_forever"
                        iconSize: 44
                        color: root.uninstallBlocked ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3error
                    }
                }

                // Title
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.uninstallBlocked
                        ? (Translation.tr("Can't remove ") + (root.uninstallApp?.name || root.uninstallPkg))
                        : (Translation.tr("Remove ") + (root.uninstallApp?.name || root.uninstallPkg) + "?")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.WordWrap
                }

                // Status message / Info
                StyledText {
                    Layout.fillWidth: true
                    visible: root.uninstallBlocked
                    text: root.uninstallReason || Translation.tr("This is a protected system component.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !root.uninstallBlocked && !root.uninstallBusy
                    text: Translation.tr("The app and anything only it uses will be removed.")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                // Package details & size badge
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !root.uninstallBlocked && (root.uninstallPkg.length > 0 || root.uninstallSize.length > 0)
                    spacing: 8

                    Rectangle {
                        visible: root.uninstallKind.length > 0
                        radius: 6
                        color: Appearance.m3colors.m3secondaryContainer
                        implicitWidth: kindText.implicitWidth + 12
                        implicitHeight: 22
                        StyledText {
                            id: kindText
                            anchors.centerIn: parent
                            text: root.uninstallKind.toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }

                    Rectangle {
                        visible: root.uninstallSize.length > 0
                        radius: 6
                        color: Appearance.colors.colLayer2Base
                        implicitWidth: sizeText.implicitWidth + 12
                        implicitHeight: 22
                        StyledText {
                            id: sizeText
                            anchors.centerIn: parent
                            text: root.uninstallSize
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Progress Bar
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.uninstallBusy
                    spacing: 6

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.uninstallStatus
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                    }
                }

                // Action Buttons
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    spacing: 10
                    visible: !root.uninstallBusy

                    RippleButton {
                        implicitWidth: 100
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.uninstallModalVisible = false
                        contentItem: Item {
                            StyledText {
                                anchors.centerIn: parent
                                text: root.uninstallBlocked ? Translation.tr("Close") : Translation.tr("Cancel")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }

                    RippleButton {
                        visible: !root.uninstallBlocked
                        implicitWidth: 120
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.m3colors.m3error
                        colBackgroundHover: Qt.darker(Appearance.m3colors.m3error, 1.15)
                        onClicked: root.confirmUninstall()
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol { text: "delete"; iconSize: 18; color: Appearance.m3colors.m3onError }
                            StyledText {
                                text: Translation.tr("Remove")
                                color: Appearance.m3colors.m3onError
                            }
                        }
                    }
                }
            }
        }
    }
}
}
