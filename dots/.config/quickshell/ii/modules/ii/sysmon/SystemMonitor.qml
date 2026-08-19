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
            fill: 1
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
    
    // Colors for stats - Using dynamic shell theme tokens
    property color cpuColor: Appearance.colors.colPrimary
    property color ramColor: Appearance.colors.colSecondary
    property color networkColor: Appearance.colors.colTertiary
    
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
                implicitHeight: Math.max(titleRow.implicitHeight, windowControlsRow.implicitHeight)
                
                RowLayout {
                    id: titleRow
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 10

                    MaterialSymbol {
                        text: "query_stats"
                        iconSize: 22
                        color: root.cpuColor
                        fill: 1
                    }

                    StyledText {
                        id: titleText
                        color: Appearance.colors.colOnLayer0
                        text: Translation.tr("System Monitor")
                        font {
                            family: Appearance.font.family.title
                            pixelSize: 18
                            weight: Font.Bold
                            variableAxes: Appearance.font.variableAxes.title
                        }
                    }
                }

                RowLayout { // Window controls row
                    id: windowControlsRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    RippleButton {
                        buttonRadius: Appearance.rounding.full
                        implicitWidth: 32
                        implicitHeight: 32
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.closeRequested()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 18
                            color: root.textColor
                            fill: 1
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
                        anchors.bottomMargin: 16
                        spacing: 8

                        RowLayout {
                            spacing: 10

                            StatIconBadge {
                                symbol: "developer_board"
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
                                fillOpacity: 0.15
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
                        anchors.bottomMargin: 16
                        spacing: 12
                        
                        RowLayout {
                            spacing: 10
                            
                            StatIconBadge {
                                symbol: "memory"
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
                        
                        // Progress bar (above labels matching reference)
                        StyledProgressBar {
                            Layout.fillWidth: true
                            valueBarHeight: 8
                            valueBarGap: 0
                            value: Math.min(1, ResourceUsage.memoryUsedPercentage)
                            highlightColor: root.ramColor
                            trackColor: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.1)
                        }

                        // RAM Info (below progress bar matching reference)
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                text: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB Used"
                                font.pixelSize: 12
                                color: root.textSecondary
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(1) + " GB Total"
                                font.pixelSize: 12
                                color: root.textSecondary
                            }
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
                        anchors.bottomMargin: 16
                        spacing: 12
                        
                        RowLayout {
                            spacing: 10
                            
                            StatIconBadge {
                                symbol: "public"
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
                        
                        // Network speeds container
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 10
                            color: Appearance.colors.colLayer3

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 16
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    
                                    RowLayout {
                                        spacing: 4
                                        StyledText {
                                            text: "↓"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: root.cpuColor
                                        }
                                        StyledText {
                                            text: "DOWN"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: root.cpuColor
                                        }
                                    }
                                    
                                    Row {
                                        spacing: 4
                                        StyledText {
                                            text: root.formatSpeed(ResourceUsage.networkDownloadSpeed).value
                                            font.pixelSize: 15
                                            font.weight: Font.Bold
                                            color: root.textColor
                                        }
                                        StyledText {
                                            text: root.formatSpeed(ResourceUsage.networkDownloadSpeed).unit
                                            font.pixelSize: 12
                                            color: root.textSecondary
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 1
                                        }
                                    }
                                }
                                
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    
                                    RowLayout {
                                        spacing: 4
                                        StyledText {
                                            text: "↑"
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            color: root.ramColor
                                        }
                                        StyledText {
                                            text: "UP"
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: root.ramColor
                                        }
                                    }
                                    
                                    Row {
                                        spacing: 4
                                        StyledText {
                                            text: root.formatSpeed(ResourceUsage.networkUploadSpeed).value
                                            font.pixelSize: 15
                                            font.weight: Font.Bold
                                            color: root.textColor
                                        }
                                        StyledText {
                                            text: root.formatSpeed(ResourceUsage.networkUploadSpeed).unit
                                            font.pixelSize: 12
                                            color: root.textSecondary
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 1
                                        }
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
                            fill: 1
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
                                fill: 1
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
                            { key: "cpu", label: "CPU", icon: "developer_board" },
                            { key: "mem", label: "RAM", icon: "memory" },
                            { key: "name", label: "Name", icon: "sort_by_alpha" }
                        ]

                        SelectionGroupButton {
                            buttonText: modelData.label
                            buttonIcon: modelData.icon
                            toggled: root.sortBy === modelData.key
                            leftmost: index === 0
                            rightmost: index === 2

                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundActive: Appearance.colors.colLayer2Active
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            colBackgroundToggledActive: Appearance.colors.colPrimaryActive

                            onClicked: root.sortBy = modelData.key
                        }
                    }
                }

                // Kill button
                RippleButton {
                    implicitWidth: 80
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: root.selectedPid > 0 ? Appearance.colors.colError : root.cardColor
                    colBackgroundHover: root.selectedPid > 0 ? Appearance.colors.colErrorHover : root.cardColorHover
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
                                fill: 1
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
                    }
                }
            }
            
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
                                anchors.leftMargin: 38
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
                        spacing: 2
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

                            width: processList.width
                            implicitHeight: 46
                            buttonRadius: 23
                            buttonText: ""
                            colBackground: root.selectedPid === pid
                                ? Appearance.colors.colPrimaryContainer
                                : "transparent"
                            colBackgroundHover: root.selectedPid === pid
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.applyAlpha(Appearance.colors.colLayer1Hover, 0.5)
                            colRipple: ColorUtils.applyAlpha(root.cpuColor, 0.2)
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
                                        font.family: Appearance.font.family.monospace
                                        font.features: { "tnum": 1 }
                                        color: root.selectedPid === pid ? Appearance.colors.colPrimary : root.textSecondary
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.pidNameGap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: {
                                            if (root.selectedPid === pid) {
                                                return ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.22);
                                            }
                                            if (processIcon.includes("browser") || processIcon.includes("firefox") || processIcon.includes("chrome") || command.includes("zen")) return Appearance.colors.colPrimaryContainer;
                                            if (processIcon.includes("hyprland") || command.toLowerCase().includes("hyprland")) return Appearance.colors.colSecondaryContainer;
                                            if (processIcon.includes("code") || command === "agy") return Appearance.colors.colPrimaryContainer;
                                            if (processIcon === "quickshell" || command === "qs") return Appearance.colors.colTertiaryContainer;
                                            if (processIcon === "terminal" || command === "nmcli" || command === "kitty" || command === "kitten") return ColorUtils.applyAlpha(Appearance.colors.colTertiary, 0.2);
                                            if (processIcon === "system-run" || command.includes("kworker")) return ColorUtils.applyAlpha(Appearance.colors.colError, 0.2);
                                            if (command.includes("wl-paste")) return ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.2);
                                            return ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.08);
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: {
                                                if (processIcon.includes("browser") || processIcon.includes("firefox") || processIcon.includes("chrome") || command.includes("zen")) return "language";
                                                if (processIcon.includes("hyprland") || command.toLowerCase().includes("hyprland")) return "grid_view";
                                                if (processIcon.includes("code") || command === "agy") return "code";
                                                if (processIcon === "quickshell" || command === "qs") return "diamond";
                                                if (processIcon === "terminal" || command === "nmcli" || command === "kitty" || command === "kitten") return "terminal";
                                                if (processIcon === "system-run" || command.includes("kworker")) return "settings";
                                                if (command.includes("wl-paste")) return "content_paste";
                                                return "terminal";
                                            }
                                            iconSize: 16
                                            fill: 1
                                            color: {
                                                if (root.selectedPid === pid) {
                                                    return Appearance.colors.colOnPrimary;
                                                }
                                                if (processIcon.includes("browser") || processIcon.includes("firefox") || processIcon.includes("chrome") || command.includes("zen")) return Appearance.colors.colOnPrimaryContainer;
                                                if (processIcon.includes("hyprland") || command.toLowerCase().includes("hyprland")) return Appearance.colors.colOnSecondaryContainer;
                                                if (processIcon.includes("code") || command === "agy") return Appearance.colors.colOnPrimaryContainer;
                                                if (processIcon === "quickshell" || command === "qs") return Appearance.colors.colOnTertiaryContainer;
                                                if (processIcon === "terminal" || command === "nmcli" || command === "kitty" || command === "kitten") return Appearance.colors.colTertiary;
                                                if (processIcon === "system-run" || command.includes("kworker")) return Appearance.colors.colError;
                                                if (command.includes("wl-paste")) return Appearance.colors.colSecondary;
                                                return Appearance.colors.colOnLayer0;
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: command
                                        font.pixelSize: 13
                                        font.weight: root.selectedPid === pid ? Font.Bold : Font.Medium
                                        color: root.selectedPid === pid ? Appearance.colors.colPrimary : root.textColor
                                        elide: Text.ElideRight
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.metricColumnWidth
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.centerIn: parent
                                        implicitHeight: 24
                                        implicitWidth: 64
                                        radius: 12
                                        color: root.selectedPid === pid
                                            ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.22)
                                            : (cpu > 20 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3)

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: cpu.toFixed(1) + "%"
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                            font.family: Appearance.font.family.monospace
                                            font.features: { "tnum": 1 }
                                            color: root.selectedPid === pid
                                                ? Appearance.colors.colOnPrimary
                                                : ((cpu > 0 || cpu > 20) ? Appearance.colors.colPrimary : root.textSecondary)
                                        }
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.metricColumnWidth
                                    Layout.fillHeight: true

                                    StyledText {
                                        anchors.fill: parent
                                        text: res_mb ? Math.round(res_mb) + " MB" : "0 MB"
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        font.family: Appearance.font.family.monospace
                                        font.features: { "tnum": 1 }
                                        color: root.selectedPid === pid ? Appearance.colors.colPrimary : root.textColor
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: root.userColumnWidth
                                    Layout.fillHeight: true

                                    StyledText {
                                        anchors.fill: parent
                                        text: user
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        color: root.selectedPid === pid ? Appearance.colors.colPrimary : root.textSecondary
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

                        // Left Pill: Showing X processes
                        Rectangle {
                            implicitHeight: 26
                            implicitWidth: processCountText.implicitWidth + 24
                            radius: 13
                            color: Appearance.colors.colLayer3

                            StyledText {
                                id: processCountText
                                anchors.centerIn: parent
                                text: "Showing " + root.getFilteredProcesses().length + " processes"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Right Pill: Refreshes every 2s
                        Rectangle {
                            implicitHeight: 26
                            implicitWidth: refreshRateText.implicitWidth + 24
                            radius: 13
                            color: Appearance.colors.colLayer3

                            StyledText {
                                id: refreshRateText
                                anchors.centerIn: parent
                                text: "Refreshes every 2s"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.textSecondary
                            }
                        }
                    }
                }
            }

        }
    }
}
