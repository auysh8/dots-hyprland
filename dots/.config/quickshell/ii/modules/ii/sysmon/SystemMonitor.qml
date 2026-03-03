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
    component StatIconBadge: Rectangle {
        required property string symbol
        required property color tint
        width: 32
        height: 32
        radius: 8
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.2)
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
    property color textColor: Appearance.colors.colOnLayer0
    property color textSecondary: Appearance.colors.colSubtext
    property real cornerRadius: Appearance.rounding.large
    
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
            // Normalize collector schema for delegate consumption.
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
            // Remove from the end
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
    StyledRectangularShadow { target: background }
    
    Rectangle {
        id: background
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.backgroundColor
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: root.forceActiveFocus()
        }
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 24
            
            // ========== HEADER ==========
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                
                // Icon circle
                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.2)
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "monitoring"
                        iconSize: 24
                        color: root.cpuColor
                    }
                }
                
                Column {
                    spacing: 2
                    StyledText {
                        text: "System Monitor"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: root.textColor
                    }
                    StyledText {
                        text: "Overview"
                        font.pixelSize: 13
                        color: root.textSecondary
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                                // Close button
                                RippleButton {
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    buttonRadius: 18
                                    colBackground: "transparent"
                                    colBackgroundHover: Qt.rgba(1, 1, 1, 0.1)
                                    colRipple: root.textColor
                
                                    onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "system-monitor", "close"])
                
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 20
                                        color: root.textColor
                                    }
                                }            }
            
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
                                                        anchors.margins: 20
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
                        anchors.margins: 20
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
                            trackColor: Qt.rgba(1, 1, 1, 0.1)
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
                        anchors.margins: 20
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
                                        color: root.ramColor
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
                                        color: root.textColor
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
                                        color: root.cpuColor
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
                                        color: root.textColor
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
                    color: root.panelColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    
                    RowLayout {
                        anchors.fill: parent
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
                                                    selectionColor: Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.5)
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
                                    colBackground: root.selectedPid > 0 ? Qt.rgba(0.9, 0.3, 0.3, 1) : root.cardColor
                                    colRipple: root.textColor
                                    opacity: root.selectedPid > 0 ? 1 : 0.5
                                    enabled: root.selectedPid > 0
                
                                    onClicked: {
                                        root.killProcess(root.selectedPid);
                                        root.selectedPid = -1;
                                    }
                
                                                                        contentItem: Item {
                                                                            implicitWidth: killRow.implicitWidth
                                                                            implicitHeight: killRow.implicitHeight
                                    
                                                                            RowLayout {
                                                                                id: killRow
                                                                                anchors.centerIn: parent
                                                                                spacing: 6
                                    
                                                                                MaterialSymbol {
                                                                                    text: "close"
                                                                                    iconSize: 14
                                                                                    color: root.textColor
                                                                                }
                                                                                StyledText {
                                                                                    text: "Kill"
                                                                                    font.pixelSize: 12
                                                                                    font.weight: Font.Medium
                                                                                    color: root.textColor
                                                                                }
                                                                            }
                                                                        }                                }            }
            
            StyledRectangularShadow { target: processPanel }

            Rectangle {
                id: processPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 18
                color: root.panelColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // ========== TABLE HEADER ==========
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText { Layout.preferredWidth: 80; text: "PID"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary }
                        StyledText { Layout.fillWidth: true; text: "NAME"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary }
                        StyledText { Layout.preferredWidth: 100; text: "CPU %"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary; horizontalAlignment: Text.AlignHCenter }
                        StyledText { Layout.preferredWidth: 100; text: "MEMORY"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary; horizontalAlignment: Text.AlignHCenter }
                        StyledText { Layout.preferredWidth: 80; text: "USER"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary; horizontalAlignment: Text.AlignRight }
                    }

                    // Separator
                    DashedBorder {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                        dashLength: 6
                        gapLength: 6
                        borderWidth: 1
                    }

                    // ========== PROCESS LIST ==========
                    StyledListView {
                        id: processList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 0
                        reuseItems: true
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
                            implicitHeight: 48
                            buttonRadius: 0
                            toggled: root.selectedPid === pid
                            colBackground: "transparent"
                            colBackgroundHover: Qt.rgba(1, 1, 1, 0.03)
                            colBackgroundToggled: Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.15)
                            colBackgroundToggledHover: Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.2)
                            rippleEnabled: false
                            buttonText: ""
                            onClicked: root.selectedPid = (root.selectedPid === pid) ? -1 : pid

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 0

                                StyledText {
                                    Layout.preferredWidth: 80
                                    text: pid
                                    font.pixelSize: 13
                                    color: root.textSecondary
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)

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

                                StyledText {
                                    Layout.preferredWidth: 100
                                    text: cpu.toFixed(1)
                                    font.pixelSize: 13
                                    font.weight: cpu > 20 ? Font.Bold : Font.Normal
                                    color: cpu > 50 ? "#ef4444" : (cpu > 20 ? root.ramColor : root.textColor)
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                StyledText {
                                    Layout.preferredWidth: 100
                                    text: res_mb ? res_mb.toFixed(0) : "0"
                                    font.pixelSize: 13
                                    color: root.textColor
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                StyledText {
                                    Layout.preferredWidth: 80
                                    text: user
                                    font.pixelSize: 13
                                    color: root.textSecondary
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            DashedBorder {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.04)
                                dashLength: 4
                                gapLength: 6
                                borderWidth: 1
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
