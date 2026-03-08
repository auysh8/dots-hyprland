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
    signal closeRequested()
    property bool isAppMode: false
    
    component StatIconBadge: Rectangle {
        required property string symbol
        required property color tint
        width: 32
        height: 32
        radius: 8
        color: ColorUtils.applyAlpha(tint, 0.2)
        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.symbol
            iconSize: 18
            color: parent.tint
        }
    }
    
    // UI Configuration - Using shell theme colors
    property color backgroundColor: Appearance.colors.colLayer0
    property color panelColor: Appearance.colors.colLayer1
    property color panelColorHover: Appearance.colors.colLayer1Hover
    property color cardColor: Appearance.colors.colLayer2
    property color cardColorHover: Appearance.colors.colLayer2Hover
    property color panelBorderColor: Appearance.colors.colLayer1Border
    property color textColor: Appearance.colors.colOnLayer0
    property color textSecondary: Appearance.colors.colSubtext
    property real cornerRadius: Appearance.rounding.large
    readonly property int pidColumnWidth: 80
    readonly property int metricColumnWidth: 100
    readonly property int userColumnWidth: 80
    readonly property int pidNameGap: 16
    
    // ========== M3 MOTION PRESETS ==========
    // Material 3 spring configurations
    readonly property real m3SpringDamping: 0.7      // Slightly bouncy
    readonly property real m3SpringMass: 0.8
    readonly property real m3SpringStiffness: 300
    readonly property int m3DurationFast: 150
    readonly property int m3DurationMedium: 300
    readonly property int m3DurationSlow: 500
    
    // Colors for stats - Using shell accent colors
    property color cpuColor: Appearance.colors.colPrimary
    property color ramColor: Appearance.colors.colPrimary
    property color networkColor: Appearance.colors.colPrimary
    
    // Process data
    property var processes: []
    property string searchText: ""
    property int selectedPid: -1
    property string sortBy: "cpu"
    
    function getFilteredProcesses() {
        let filtered = root.processes.filter(p => 
            p.command.toLowerCase().includes(root.searchText.toLowerCase()) ||
            p.user.toLowerCase().includes(root.searchText.toLowerCase())
        );
        
        if (sortBy === "cpu") filtered.sort((a, b) => b.cpu - a.cpu);
        else if (sortBy === "mem") filtered.sort((a, b) => b.mem - a.mem);
        else filtered.sort((a, b) => a.command.localeCompare(b.command));
        
        // Show top 50 by default, or all matches if searching
        if (root.searchText === "") {
            return filtered.slice(0, 50);
        }
        
        return filtered;
    }
    
    function formatSpeed(bytesPerSecond) {
        if (bytesPerSecond < 1024) return { value: bytesPerSecond.toFixed(0), unit: "B/s" };
        else if (bytesPerSecond < 1024 * 1024) return { value: (bytesPerSecond / 1024).toFixed(1), unit: "KB/s" };
        else return { value: (bytesPerSecond / (1024 * 1024)).toFixed(1), unit: "MB/s" };
    }

    // ListModel for stable updates
    ListModel { id: processModel }

    onProcessesChanged: updateProcessModel()
    onSortByChanged: updateProcessModel()
    onSearchTextChanged: updateProcessModel()

    function updateProcessModel() {
        var newData = getFilteredProcesses();
        var count = newData.length;
        var currentCount = processModel.count;
        
        // Update existing & Add new
        for (var i = 0; i < count; i++) {
            var item = newData[i];
            if (!item.icon && item.processIcon) {
                item.icon = item.processIcon;
            }
            if (i < currentCount) {
                processModel.set(i, item);
            } else {
                processModel.append(item);
            }
        }
        
        // Remove excess
        if (currentCount > count) {
            for (var j = currentCount - 1; j >= count; j--) {
                processModel.remove(j);
            }
        }
    }
    
    // Process scanner
    Process {
        id: processScanner
        command: ["/usr/bin/python3", "-u", Qt.resolvedUrl("get_processes.py").toString().replace("file://", "")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try { 
                    root.processes = JSON.parse(this.text); 
                } 
                catch (e) { console.error("Parse error:", e); }
            }
        }
    }
    
    Timer {
        interval: 2000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: processScanner.running = true
    }
    
    function killProcess(pid) {
        Qt.createQmlObject(`import Quickshell.Io; Process { command: ["kill", "-9", "${pid}"]; running: true }`, root, "kill");
    }
    
    // Background shadow
    StyledRectangularShadow { 
        target: background
        visible: !root.isAppMode
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: root.isAppMode ? (Appearance.rounding.windowRounding - 8) : root.cornerRadius
        color: root.isAppMode ? Appearance.m3colors.m3surfaceContainerLow : root.backgroundColor
        border.width: root.isAppMode ? 0 : 1
        border.color: Appearance.colors.colLayer0Border        
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: root.forceActiveFocus()
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.isAppMode ? 32 : 28
            spacing: 24
            
            // ========== HEADER ==========
            Item { // Titlebar
                visible: !root.isAppMode
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
                StyledText {
                    id: titleText
                    anchors {
                        left: Config.options?.windows?.centerTitle ? undefined : parent.left
                        horizontalCenter: Config.options?.windows?.centerTitle ? parent.horizontalCenter : undefined
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("System Monitor")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }
                RowLayout { // Window controls row
                    id: windowControlsRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 35
                        implicitHeight: 35
                        onClicked: root.closeRequested()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 20
                        }
                    }
                }
            }
            
            // ========== STAT CARDS ==========
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                
                                                // CPU Card
                                                RippleButton {
                                                    id: cpuCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 1
                                                    Layout.minimumWidth: 0
                                                    Layout.preferredHeight: 140
                                                    buttonRadius: 16
                                                    colBackground: root.cardColor
                                                    colBackgroundHover: root.cardColorHover
                                                    rippleEnabled: false
                                                    pointingHandCursor: false
                                
                                                    contentItem: ColumnLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 20
                                                        anchors.rightMargin: 20
                                                        anchors.topMargin: 18
                                                        anchors.bottomMargin: 24
                                                        spacing: 12
                                
                                                        RowLayout {
                                                            spacing: 10
                                
                                                            StatIconBadge {
                                                                symbol: "memory"
                                                                tint: root.cpuColor
                                                            }
                                
                                                            StyledText {
                                                                text: "CPU"
                                                                font.pixelSize: 15
                                                                font.weight: Font.Medium
                                                                color: root.textColor
                                                            }
                                
                                                            Item { Layout.fillWidth: true }
                                
                                                            StyledText {
                                                                text: Math.round(ResourceUsage.cpuUsage * 100) + "%"
                                                                font.pixelSize: 28
                                                                font.weight: Font.Bold
                                                                color: root.cpuColor
                                                            }
                                                        }
                                
                                                        // CPU Graph
                                                        Item {
                                                            Layout.fillWidth: true
                                                            Layout.fillHeight: true
                                
                                                            Graph {
                                                                anchors.fill: parent
                                                                values: ResourceUsage.cpuUsageHistory
                                                                color: root.cpuColor
                                                                fillOpacity: 0.3
                                                                alignment: Graph.Alignment.Right
                                                            }
                                                        }
                                                    }
                                                }                
                // RAM Card
                RippleButton {
                    id: ramCard
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 140
                    buttonRadius: 16
                    colBackground: root.cardColor
                    colBackgroundHover: root.cardColorHover
                    rippleEnabled: false
                    pointingHandCursor: false
                    
                    contentItem: ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.topMargin: 18
                        anchors.bottomMargin: 24
                        spacing: 12
                        
                        RowLayout {
                            spacing: 10
                            
                            StatIconBadge {
                                symbol: "memory_alt"
                                tint: root.ramColor
                            }
                            
                            StyledText {
                                text: "RAM"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: root.textColor
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            StyledText {
                                text: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%"
                                font.pixelSize: 28
                                font.weight: Font.Bold
                                color: root.ramColor
                            }
                        }
                        
                        Item { Layout.fillHeight: true }
                        
                        // RAM Info
                        RowLayout {
                            spacing: 16
                            StyledText {
                                text: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB Used"
                                font.pixelSize: 13
                                color: root.textSecondary
                            }
                            StyledText {
                                text: (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(1) + " GB Total"
                                font.pixelSize: 13
                                color: root.textSecondary
                            }
                        }
                        
                        // Progress bar
                        StyledProgressBar {
                            Layout.fillWidth: true
                            valueBarHeight: 8
                            valueBarGap: 0
                            value: Math.min(1, ResourceUsage.memoryUsedPercentage)
                            highlightColor: root.ramColor
                            trackColor: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.1)
                        }

                    }
                }
                
                // Network Card
                RippleButton {
                    id: netCard
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 140
                    buttonRadius: 16
                    colBackground: root.cardColor
                    colBackgroundHover: root.cardColorHover
                    rippleEnabled: false
                    pointingHandCursor: false
                    
                    contentItem: ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.topMargin: 18
                        anchors.bottomMargin: 24
                        spacing: 16
                        
                        RowLayout {
                            spacing: 10
                            
                            StatIconBadge {
                                symbol: "language"
                                tint: root.networkColor
                            }
                            
                            StyledText {
                                text: "Network"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: root.textColor
                            }
                        }
                        
                        Item { Layout.fillHeight: true }
                        
                        // Network speeds
                        RowLayout {
                            spacing: 32
                            
                            Column {
                                spacing: 4
                                
                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "download"
                                        iconSize: 14
                                        color: root.networkColor
                                    }
                                    StyledText {
                                        text: "DOWN"
                                        font.pixelSize: 11
                                        color: root.textSecondary
                                    }
                                }
                                
                                Row {
                                    spacing: 4
                                    StyledText {
                                        text: root.formatSpeed(ResourceUsage.networkDownloadSpeed).value
                                        font.pixelSize: 22
                                        font.weight: Font.Bold
                                        color: root.networkColor
                                    }
                                    StyledText {
                                        text: root.formatSpeed(ResourceUsage.networkDownloadSpeed).unit
                                        font.pixelSize: 12
                                        color: root.textSecondary
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                    }
                                }
                            }
                            
                            Column {
                                spacing: 4
                                
                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: "upload"
                                        iconSize: 14
                                        color: root.networkColor
                                    }
                                    StyledText {
                                        text: "UP"
                                        font.pixelSize: 11
                                        color: root.textSecondary
                                    }
                                }
                                
                                Row {
                                    spacing: 4
                                    StyledText {
                                        text: root.formatSpeed(ResourceUsage.networkUploadSpeed).value
                                        font.pixelSize: 22
                                        font.weight: Font.Bold
                                        color: root.networkColor
                                    }
                                    StyledText {
                                        text: root.formatSpeed(ResourceUsage.networkUploadSpeed).unit
                                        font.pixelSize: 12
                                        color: root.textSecondary
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                    }
                                }
                            }
                        }

                    }
                }
            }
            
            // ========== SEARCH & ACTIONS ==========
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                
                                // Search field
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 400
                                    height: 44
                                    radius: 22
                                    color: searchInput.activeFocus ? Appearance.colors.colLayer3 : root.cardColor
                
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.IBeamCursor
                                        onClicked: searchInput.forceActiveFocus()
                                    }
                
                                    RowLayout {                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        
                        MaterialSymbol {
                            text: "search"
                            iconSize: 18
                            color: root.textSecondary
                        }
                        
                        StyledTextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.pixelSize: 14
                            clip: true
                            selectByMouse: true
                            selectionColor: ColorUtils.applyAlpha(root.cpuColor, 0.5)
                            selectedTextColor: Appearance.colors.colOnPrimary
                            onTextChanged: root.searchText = text

                            StyledText {
                                anchors.fill: parent
                                text: "Search processes..."
                                font.pixelSize: 14
                                color: root.textSecondary
                                visible: !searchInput.text && !searchInput.activeFocus
                            }
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: searchInput.text.length > 0
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            buttonRadius: 12
                            padding: 0
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover

                            onClicked: {
                                searchInput.text = "";
                                searchInput.forceActiveFocus();
                            }

                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "close"
                                iconSize: 16
                                color: root.textSecondary
                            }
                        }
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                                                                                                                                // Sort buttons
                                                                                                                                ButtonGroup {
                                                                                                                                    spacing: 2
                                                                                                                                    
                                                                                                                                    Repeater {
                                                                                                                                        model: [
                                                                                                                                            { key: "cpu", label: "CPU", icon: "memory" },
                                                                                                                                            { key: "mem", label: "RAM", icon: "memory_alt" },
                                                                                                                                            { key: "name", label: "Name", icon: "sort_by_alpha" }
                                                                                                                                        ]
                                                                                                
                                                                                                                                        SelectionGroupButton {
                                                                                                                                            buttonText: modelData.label
                                                                                                                                            buttonIcon: modelData.icon
                                                                                                                                            toggled: root.sortBy === modelData.key
                                                                                                                                            leftmost: index === 0
                                                                                                                                            rightmost: index === 2
                                                                                                
                                                                                                                                            // Matching Settings module exactly
                                                                                                                                            colBackground: Appearance.colors.colLayer2
                                                                                                                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                                                                                                                            colBackgroundActive: Appearance.colors.colLayer2Active
                                                                                                                                            colBackgroundToggled: Appearance.colors.colPrimary
                                                                                                                                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                                                                                                                                            colBackgroundToggledActive: Appearance.colors.colPrimaryActive
                                                                                                
                                                                                                                                            onClicked: root.sortBy = modelData.key
                                                                                                                                        }
                                                                                                                                    }
                                                                                                                                }                                // Kill button
                                RippleButton {
                                    implicitWidth: 80
                                    implicitHeight: 32
                                    buttonRadius: 16
                                    colBackground: root.selectedPid > 0 ? Appearance.colors.colError : root.cardColor
                                    colBackgroundHover: root.selectedPid > 0 ? Appearance.colors.colError : root.cardColorHover
                                    colRipple: root.textColor
                                    opacity: root.selectedPid > 0 ? 1 : 0.5
                                    enabled: root.selectedPid > 0
                
                                    onClicked: {
                                        root.killProcess(root.selectedPid);
                                        root.selectedPid = -1;
                                    }
                
                                                                        contentItem: Item {
                                                                            implicitWidth: killRow.implicitWidth
                                                                            implicitHeight: Math.max(14, killText.implicitHeight)

                                                                            RowLayout {
                                                                                id: killRow
                                                                                anchors.centerIn: parent
                                                                                spacing: 6

                                                                                MaterialSymbol {
                                                                                    Layout.alignment: Qt.AlignVCenter
                                                                                    text: "block"
                                                                                    iconSize: 14
                                                                                    color: root.selectedPid > 0 ? Appearance.colors.colOnError : root.textSecondary
                                                                                }
                                                                                StyledText {
                                                                                    id: killText
                                                                                    Layout.alignment: Qt.AlignVCenter
                                                                                    verticalAlignment: Text.AlignVCenter
                                                                                    text: "Kill"
                                                                                    font.pixelSize: 12
                                                                                    font.weight: Font.Medium
                                                                                    color: root.selectedPid > 0 ? Appearance.colors.colOnError : root.textSecondary
                                                                                }
                                                                            }
                                                                        }                                }            }
            
            Rectangle {
                id: processPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 18
                color: root.cardColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Sticky header (stays fixed while list scrolls)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 0

                        Item {
                            Layout.preferredWidth: root.pidColumnWidth
                            StyledText {
                                anchors.fill: parent
                                text: "PID"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Item {
                            Layout.preferredWidth: root.pidNameGap
                        }

                        Item {
                            Layout.fillWidth: true
                            StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: 34
                                text: "NAME"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                                horizontalAlignment: Text.AlignLeft
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Item {
                            Layout.preferredWidth: root.metricColumnWidth
                            StyledText {
                                anchors.fill: parent
                                text: "CPU %"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Item {
                            Layout.preferredWidth: root.metricColumnWidth
                            StyledText {
                                anchors.fill: parent
                                text: "MEMORY"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Item {
                            Layout.preferredWidth: root.userColumnWidth
                            StyledText {
                                anchors.fill: parent
                                text: "USER"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // ========== PROCESS LIST ==========
                    StyledListView {
                        id: processList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 0
                        reuseItems: false
                        animateAppearance: false
                        ScrollBar.vertical: StyledScrollBar {}
                        model: processModel

                        delegate: RippleButton {
                            required property int index
                            required property int pid
                            required property string command
                            required property string user
                            required property double cpu
                            required property double res_mb
                            required property string processIcon

                            // Remove local redeclarations, we just use the required properties injected by ListModel directly.

                            width: processList.width
                            implicitHeight: 48
                            buttonText: ""
                            colBackground: root.selectedPid === pid
                                ? ColorUtils.applyAlpha(root.cpuColor, 0.12)
                                : "transparent"
                            colBackgroundHover: root.selectedPid === pid
                                ? ColorUtils.applyAlpha(root.cpuColor, 0.16)
                                : "transparent"
                            onClicked: root.selectedPid = (root.selectedPid === pid) ? -1 : pid

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 0

                                Item {
                                    Layout.preferredWidth: root.pidColumnWidth
                                    StyledText {
                                        anchors.fill: parent
                                        text: pid
                                        font.pixelSize: 13
                                        color: root.textSecondary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.pidNameGap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 4
                                        color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.08)

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: (processIcon === "application-x-python" || processIcon.includes("code")) ? "code" :
                                                  (processIcon.includes("browser") || processIcon.includes("firefox") || processIcon.includes("chrome")) ? "language" :
                                                  (processIcon.includes("hyprland")) ? "grid_view" :
                                                  (processIcon === "system-run") ? "settings" :
                                                  (processIcon === "quickshell") ? "layers" :
                                                  "terminal"
                                            iconSize: 14
                                            color: root.textSecondary
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: command
                                        font.pixelSize: 13
                                        color: root.textColor
                                        elide: Text.ElideRight
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.metricColumnWidth
                                    StyledText {
                                        anchors.fill: parent
                                        text: cpu.toFixed(1)
                                        font.pixelSize: 13
                                        font.weight: cpu > 20 ? Font.Bold : Font.Normal
                                        color: cpu > 50 ? Appearance.colors.colError : (cpu > 20 ? root.ramColor : root.textColor)
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.metricColumnWidth
                                    StyledText {
                                        anchors.fill: parent
                                        text: res_mb ? res_mb.toFixed(0) : "0"
                                        font.pixelSize: 13
                                        color: root.textColor
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.userColumnWidth
                                    StyledText {
                                        anchors.fill: parent
                                        text: user
                                        font.pixelSize: 13
                                        color: root.textSecondary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }

                        }
                    }

                    // ========== FOOTER ==========
                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            text: "Showing " + root.getFilteredProcesses().length + " processes"
                            font.pixelSize: 12
                            color: root.textSecondary
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            spacing: 6

                            Circle {
                                diameter: 8
                                color: root.ramColor
                            }

                            StyledText {
                                text: "Refreshes every 2s"
                                font.pixelSize: 12
                                color: root.textSecondary
                            }
                        }
                    }
                }
            }

        }
    }
}
