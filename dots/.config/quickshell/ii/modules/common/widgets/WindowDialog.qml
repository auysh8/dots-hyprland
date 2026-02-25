import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root

    property bool show: false
    property bool animationsEnabled: false
    default property alias data: contentColumn.data

    property bool contentReady: false
    
    Timer {
        id: delayTimer
        interval: root.openDuration + 200 
        repeat: false
        onTriggered: root.contentReady = true
    }

    onShowChanged: {
        if (show) {
            closeTimer.stop();
            dialogBackground.opacity = 1;
            // Update height only when opening
            dialogBackground.frozenHeight = root.backgroundHeight;
            delayTimer.restart(); // Start delay for content loading
        } else {
            closeTimer.restart();
            delayTimer.stop();
            contentReady = false; // Reset immediately on close
        }
    }
    
    // Source item for animation reference
    property Item sourceItem: null
    
    // Toggle dimensions - captured from sourceItem
    property real toggleWidth: 150  // Default for large toggle
    property real toggleHeight: 56  // Default height
    property real toggleRadius: Appearance.rounding.small  // Toggle button corner radius
    
    // Store the start rect when sourceItem is set (so it persists during close)
    // Default to a 100x100 rect in the center of the screen if no sourceItem is provided
    property rect storedStartRect: root.sourceItem ? Qt.rect(175, 300, toggleWidth, toggleHeight) : Qt.rect((root.width - 100) / 2, (root.height - 100) / 2, 100, 100)
    
    onSourceItemChanged: {
        if (sourceItem && sourceItem.parent) {
            try {
                const pos = sourceItem.mapToItem(root, 0, 0);
                // Capture actual toggle dimensions (fall back to implicit if width/height are 0)
                const w = sourceItem.width > 20 ? sourceItem.width : (sourceItem.implicitWidth > 20 ? sourceItem.implicitWidth : 150);
                const h = sourceItem.height > 20 ? sourceItem.height : (sourceItem.implicitHeight > 20 ? sourceItem.implicitHeight : 56);
                toggleWidth = w;
                toggleHeight = h;
                storedStartRect = Qt.rect(pos.x, pos.y, w, h);
            } catch(e) {
                // Keep previous storedStartRect
            }
        }
    }
    
    // Logic to allow overriding height while defaulting to content fit
    readonly property real _calculatedHeight: contentColumn.implicitHeight + dialogBackground.targetRadius * 2
    property real backgroundHeight: _calculatedHeight
    
    property real backgroundWidth: 350
    
    // Use stored rect for animation
    readonly property rect startRect: storedStartRect
    
    readonly property rect targetRect: Qt.rect(
        (root.width - backgroundWidth) / 2,
        (root.height - backgroundHeight) / 2,
        backgroundWidth,
        backgroundHeight
    )
    
    // Animation durations (fast but safe for content loading)
    readonly property int openDuration: 350
    readonly property int closeDuration: 250

    signal dismiss()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.dismiss();
            event.accepted = true;
        }
    }

    color: root.show ? Appearance.colors.colScrim : ColorUtils.transparentize(Appearance.colors.colScrim)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    
    // Keep visible during animation
    visible: root.show || dialogBackground.opacity > 0

    radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    MouseArea { // Clicking outside the dialog should dismiss
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.dismiss()
    }

    Rectangle {
        id: dialogBackground
        
        // Corner radius animation (Material Container Transform)
        property real targetRadius: Appearance.rounding.large
        // Start from round for center expanding, else from toggle radius
        property real startRadius: root.sourceItem ? root.toggleRadius : targetRadius
        radius: root.show ? targetRadius : startRadius
        
        Behavior on radius {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: root.show ? root.openDuration : root.closeDuration
                easing.type: root.show ? Easing.OutCubic : Easing.OutCubic
            }
        }
        
        // Color Morphing (Material Container Transform)
        // Animates from Toggle Color -> Dialog Surface Color
        // Use Surface Container (Layer 2 Base) to match the Large Toggle's base color while keeping it opaque
        property color openColor: Appearance.m3colors.m3surfaceContainer
        property color closedColor: {
            // Logic to determine the source toggle's background color
            const isToggled = root.sourceItem?.toggled ?? false;
            
            // Prefer explicitly defined toggled color if available
            if (isToggled && root.sourceItem && root.sourceItem.colBackgroundToggled !== undefined) {
                return root.sourceItem.colBackgroundToggled;
            }

            const isSmall = root.toggleWidth <= 100;
            if (isSmall) {
                // Small toggles are colored when active (Blue -> Surface)
                // Use Opaque Layer 3 Base (SurfaceContainerHigh) for inactive state to prevent transparency glitches
                return isToggled ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainerHigh;
            } else {
                // Large toggles: Use Surface Container (Layer 2 Base)
                // Opaque version of colLayer2 to prevent transparency issues
                return Appearance.m3colors.m3surfaceContainer; 
            }
        }
        
        color: root.show ? openColor : closedColor // Animate between them
        
        Behavior on color {
            enabled: root.animationsEnabled
            ColorAnimation {
                duration: root.show ? root.openDuration : root.closeDuration
                easing.type: root.show ? Easing.OutCubic : Easing.OutCubic
            }
        }
        
        // Geometry bindings
        // FREEZE HEIGHT: Prevents jitter during close animation if content resizes
        property real frozenHeight: root.backgroundHeight
        
        // Use frozenHeight for stability during animation
        readonly property rect targetRect: Qt.rect(
            (parent.width - root.width) / 2,     // Centered X (dynamic during anim)
            (parent.height - root.frozenHeight) / 2, // Centered Y based on FROZEN height
            500,                                 // Fixed Width (Dialog Width)
            root.frozenHeight                    // Fixed Height (FROZEN)
        )
        
        // ... (startRect logic remains same)

        x: root.show ? root.targetRect.x : root.startRect.x
        y: root.show ? root.targetRect.y : root.startRect.y
        width: root.show ? root.targetRect.width : root.startRect.width
        height: root.show ? root.targetRect.height : root.startRect.height
        
        // Behaviors for smooth morphing (Material Container Transform)
        // STANDARD EASING: OutCubic (Open), InCubic (Close) - No Bounce/Overshoot
        Behavior on x {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: root.show ? root.openDuration : root.closeDuration
                easing.type: root.show ? Easing.OutCubic : Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: root.show ? root.openDuration : root.closeDuration
                easing.type: root.show ? Easing.OutCubic : Easing.OutCubic
            }
        }
        Behavior on width {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: root.show ? root.openDuration : root.closeDuration
                easing.type: root.show ? Easing.OutCubic : Easing.OutCubic
            }
        }
        Behavior on height {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: root.show ? root.openDuration : root.closeDuration
                easing.type: root.show ? Easing.OutCubic : Easing.OutCubic
            }
        }
        
        opacity: 0
        // TEMP: No opacity animation at all - just geometry morph
        
        Timer {
            id: closeTimer
            interval: root.closeDuration  // Wait for shrink to complete
            repeat: false
            onTriggered: dialogBackground.opacity = 0  // Then fade out
        }

        MouseArea { // So clicking inside the dialog won't dismiss
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
        }
        
        // --- FAKE TOGGLE CONTENT (Visible during close animation) ---
        // Mimics the toggle button content (Icon + Text) to cross-fade with dialog content
        // Fills entire dialog during shrink animation
        Item {
            anchors.fill: parent  // Fill entire dialog
            
            // Cross-fade logic: Inverse of contentColumn
            opacity: root.show ? 0 : 1
            visible: opacity > 0 && root.sourceItem != null
            
            // Snap instantly on close — no animated crossfade
            // Only animate (fade out) when hiding on open
            Behavior on opacity {
                enabled: root.animationsEnabled && root.show  // Only animate on OPEN (hide fake toggle)
                NumberAnimation { 
                    duration: 100
                    easing.type: Easing.OutCubic
                }
            }
            
            // Icon and text aligned conditionally
            // Large toggles (Text): Left aligned
            // Small toggles (Icon only): Centered
            RowLayout {
                anchors.left: (root.toggleWidth > 100) ? parent.left : undefined
                anchors.horizontalCenter: (root.toggleWidth > 100) ? undefined : parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: (root.toggleWidth > 100) ? 8 : 0
                spacing: 6
                
                // SCALE UP MORE as dialog shrinks to fill the space
                // Scale = CurrentDialogWidth / ToggleWidth
                // Open: 350 / 150 = 2.33x
                // Closed: 150 / 150 = 1.0x (Matches real toggle perfectly)
                scale: dialogBackground.width / Math.max(1, root.toggleWidth)
                transformOrigin: (root.toggleWidth > 100) ? Item.Left : Item.Center
                
                // Icon container
                // ADAPTIVE: 
                // - Large Toggles (>100px): Small 44px box on left
                // - Small Toggles (<=100px): WIDE pill filling the fake toggle
                Item {
                    Layout.preferredWidth: (root.toggleWidth > 100) ? 44 : root.toggleWidth
                    Layout.preferredHeight: (root.toggleWidth > 100) ? 44 : root.toggleHeight
                    
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        
                        property bool isToggled: root.sourceItem?.toggled ?? true 
                        
                        // Radius logic:
                        // - Small Toggles: Always pill (Height/2)
                        // - Large Toggles:
                        //   - Active: Rounded Square (12)
                        //   - Inactive: Circle (Height/2 = 22)
                        radius: (root.toggleWidth > 100) ? (isToggled ? 12 : 22) : (height / 2)
                        
                        color: isToggled ? (root.sourceItem?.colBackgroundToggled ?? Appearance.colors.colPrimary) : Appearance.colors.colLayer3
                    }
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: (root.sourceItem && root.sourceItem.buttonIcon) ? root.sourceItem.buttonIcon : ""
                        iconSize: 20
                        property bool isToggled: root.sourceItem?.toggled ?? true
                        
                        // Adapt text/icon color based on source toggle's own color property if possible
                        color: {
                            if (root.sourceItem) {
                                if (isToggled && root.sourceItem.colOnPrimary !== undefined) return root.sourceItem.colOnPrimary;
                                if (isToggled && root.sourceItem.colText !== undefined) return root.sourceItem.colText;
                            }
                            return isToggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                        }
                    }
                }

                // Text column (name + statusText) - ONLY for large toggles
                Column {
                    visible: root.toggleWidth > 100
                    spacing: 0
                    Layout.alignment: Qt.AlignVCenter
                    
                    // Name (bold, larger)
                    StyledText {
                        text: (root.sourceItem && root.sourceItem.name) ? root.sourceItem.name : ""
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: 600
                        color: Appearance.colors.colOnSurface
                    }
                    
                    // Status text (lighter, smaller)
                    StyledText {
                        visible: (root.sourceItem && root.sourceItem.statusText) ? true : false
                        text: (root.sourceItem && root.sourceItem.statusText) ? root.sourceItem.statusText : ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: 100
                        color: Appearance.colors.colOnSurface
                        opacity: 0.7
                    }
                }
            }
        }

        // Content container with clipping for clean morph
        clip: true

        ColumnLayout {
            id: contentColumn
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: dialogBackground.targetRadius
            }
            // Explicitly set width to target width so content layout doesn't jump during resize
            width: root.targetRect.width - (anchors.margins * 2)
            
            spacing: 16
            
            // Scale content during open/close
            scale: root.show ? 1.0 : 0.8
            transformOrigin: Item.Top
            Behavior on scale {
                 enabled: root.animationsEnabled && root.show  // Only animate on OPEN
                 NumberAnimation { 
                     duration: root.openDuration
                     easing.type: Easing.OutCubic
                 }
            }

            // Content fade: snap invisible on close, animate on open
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                 enabled: root.animationsEnabled && root.show  // Only animate on OPEN
                 NumberAnimation { 
                     duration: 150
                     easing.type: Easing.OutCubic
                 }
            }
        }
    }
}
