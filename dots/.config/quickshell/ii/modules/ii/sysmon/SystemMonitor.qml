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
    
    // UI Configuration - Using shell theme colors
    property color backgroundColor: Appearance.colors.colLayer0
    property color cardColor: Appearance.colors.colLayer1
    property color cardColorHover: Appearance.colors.colLayer1Hover
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
                    Text {
                        text: "System Monitor"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: root.textColor
                    }
                    Text {
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
                
                                    onClicked: Qt.createQmlObject(`import Quickshell.Io; Process { command: ["qs", "-c", "ii", "ipc", "call", "system-monitor", "close"]; running: true }`, root, "closer")
                
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
                                
                                                            Rectangle {
                                                                width: 32
                                                                height: 32
                                                                radius: 8
                                                                color: Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.2)
                                
                                                                MaterialSymbol {
                                                                    anchors.centerIn: parent
                                                                    text: "memory"
                                                                    iconSize: 18
                                                                    color: root.cpuColor
                                                                }
                                                            }
                                
                                                            Text {
                                                                text: "CPU"
                                                                font.pixelSize: 15
                                                                font.weight: Font.Medium
                                                                color: root.textColor
                                                            }
                                
                                                            Item { Layout.fillWidth: true }
                                
                                                            Text {
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
                Rectangle {
                    id: ramCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: root.cardColor
                    
                    // M3 hover animation
                    scale: ramCardMouse.containsMouse ? 1.02 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: root.m3SpringStiffness / 100
                            damping: root.m3SpringDamping
                            mass: root.m3SpringMass
                        }
                    }
                    
                    MouseArea {
                        id: ramCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 12
                        
                        RowLayout {
                            spacing: 10
                            
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 8
                                color: Qt.rgba(root.ramColor.r, root.ramColor.g, root.ramColor.b, 0.2)
                                
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "memory_alt"
                                    iconSize: 18
                                    color: root.ramColor
                                }
                            }
                            
                            Text {
                                text: "RAM"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: root.textColor
                            }
                            
                            Item { Layout.fillWidth: true }
                            
                            Text {
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
                            Text {
                                text: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB Used"
                                font.pixelSize: 13
                                color: root.textSecondary
                            }
                            Text {
                                text: (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(1) + " GB Total"
                                font.pixelSize: 13
                                color: root.textSecondary
                            }
                        }
                        
                        // Progress bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: 8
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.1)
                            
                            Rectangle {
                                width: parent.width * Math.min(1, ResourceUsage.memoryUsedPercentage)
                                height: parent.height
                                radius: 4
                                color: root.ramColor
                            }
                        }
                    }
                }
                
                // Network Card
                Rectangle {
                    id: netCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: root.cardColor
                    
                    // M3 hover animation
                    scale: netCardMouse.containsMouse ? 1.02 : 1.0
                    Behavior on scale {
                        SpringAnimation {
                            spring: root.m3SpringStiffness / 100
                            damping: root.m3SpringDamping
                            mass: root.m3SpringMass
                        }
                    }
                    
                    MouseArea {
                        id: netCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16
                        
                        RowLayout {
                            spacing: 10
                            
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 8
                                color: Qt.rgba(root.networkColor.r, root.networkColor.g, root.networkColor.b, 0.2)
                                
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "language"
                                    iconSize: 18
                                    color: root.networkColor
                                }
                            }
                            
                            Text {
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
                                    Text {
                                        text: "DOWN"
                                        font.pixelSize: 11
                                        color: root.textSecondary
                                    }
                                }
                                
                                Row {
                                    spacing: 4
                                    Text {
                                        text: root.formatSpeed(ResourceUsage.networkDownloadSpeed).value
                                        font.pixelSize: 22
                                        font.weight: Font.Bold
                                        color: root.textColor
                                    }
                                    Text {
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
                                    Text {
                                        text: "UP"
                                        font.pixelSize: 11
                                        color: root.textSecondary
                                    }
                                }
                                
                                Row {
                                    spacing: 4
                                    Text {
                                        text: root.formatSpeed(ResourceUsage.networkUploadSpeed).value
                                        font.pixelSize: 22
                                        font.weight: Font.Bold
                                        color: root.textColor
                                    }
                                    Text {
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
                    color: root.cardColor
                    
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
                        
                                                TextInput {
                                                    id: searchInput
                                                    Layout.fillWidth: true
                                                    font.pixelSize: 14
                                                    color: root.textColor
                                                    clip: true
                                                    selectByMouse: true
                                                    selectionColor: Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.5)
                                                    selectedTextColor: Appearance.colors.colOnPrimary
                                                    onTextChanged: root.searchText = text
                        
                                                    Text {
                                                        anchors.fill: parent
                                                        text: "Search processes..."
                                                        font.pixelSize: 14
                                                        color: root.textSecondary
                                                        visible: !searchInput.text && !searchInput.activeFocus
                                                    }
                                                }                    }
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
                                                                                Text {
                                                                                    text: "Kill"
                                                                                    font.pixelSize: 12
                                                                                    font.weight: Font.Medium
                                                                                    color: root.textColor
                                                                                }
                                                                            }
                                                                        }                                }            }
            
            // ========== TABLE HEADER ==========
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                spacing: 0
                
                Text { Layout.preferredWidth: 80; text: "PID"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary }
                Text { Layout.fillWidth: true; text: "NAME"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary }
                Text { Layout.preferredWidth: 100; text: "CPU %"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary; horizontalAlignment: Text.AlignHCenter }
                Text { Layout.preferredWidth: 100; text: "MEMORY"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary; horizontalAlignment: Text.AlignHCenter }
                Text { Layout.preferredWidth: 80; text: "USER"; font.pixelSize: 12; font.weight: Font.Medium; color: root.textSecondary; horizontalAlignment: Text.AlignRight }
            }
            
            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }
            
            // ========== PROCESS LIST ==========
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                
                ListView {
                    id: processList
                    anchors.fill: parent
                    model: processModel
                    spacing: 0
                    reuseItems: true
                    
                    delegate: Rectangle {
                        required property int index
                        required property int pid
                        required property string command
                        required property string user
                        required property double cpu
                        required property double res_mb
                        required property string icon
                        
                        width: processList.width
                        height: 48
                        color: root.selectedPid === pid ? Qt.rgba(root.cpuColor.r, root.cpuColor.g, root.cpuColor.b, 0.15) : 
                               (delegateMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.03) : "transparent")
                        
                        MouseArea {
                            id: delegateMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedPid = (root.selectedPid === pid) ? -1 : pid
                        }
                        
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 0
                            
                            // PID
                            Text { 
                                Layout.preferredWidth: 80
                                text: pid
                                font.pixelSize: 13
                                color: root.textSecondary
                            }
                            
                            // Command with icon
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
                                        text: (icon === "application-x-python" || icon.includes("code")) ? "code" :
                                              (icon.includes("browser") || icon.includes("firefox") || icon.includes("chrome")) ? "language" :
                                              (icon.includes("hyprland")) ? "grid_view" :
                                              (icon === "system-run") ? "settings" :
                                              (icon === "quickshell") ? "layers" :
                                              "terminal"
                                        iconSize: 14
                                        color: root.textSecondary
                                    }
                                }
                                
                                Text { 
                                    Layout.fillWidth: true
                                    text: command
                                    font.pixelSize: 13
                                    color: root.textColor
                                    elide: Text.ElideRight
                                }
                            }
                            
                            // CPU %
                            Text { 
                                Layout.preferredWidth: 100
                                text: cpu.toFixed(1)
                                font.pixelSize: 13
                                font.weight: cpu > 20 ? Font.Bold : Font.Normal
                                color: cpu > 50 ? "#ef4444" : (cpu > 20 ? root.ramColor : root.textColor)
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            // RAM MB
                            Text { 
                                Layout.preferredWidth: 100
                                text: res_mb ? res_mb.toFixed(0) : "0"
                                font.pixelSize: 13
                                color: root.textColor
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            // User
                            Text { 
                                Layout.preferredWidth: 80
                                text: user
                                font.pixelSize: 13
                                color: root.textSecondary
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        
                        // Bottom border
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Qt.rgba(1, 1, 1, 0.04)
                        }
                    }
                }
            }
            
            // ========== FOOTER ==========
            RowLayout {
                Layout.fillWidth: true
                
                Text {
                    text: "Showing " + root.getFilteredProcesses().length + " processes"
                    font.pixelSize: 12
                    color: root.textSecondary
                }
                
                Item { Layout.fillWidth: true }
                
                RowLayout {
                    spacing: 6
                    
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: root.ramColor
                    }
                    
                    Text {
                        text: "Refreshes every 2s"
                        font.pixelSize: 12
                        color: root.textSecondary
                    }
                }
            }
        }
    }
}
