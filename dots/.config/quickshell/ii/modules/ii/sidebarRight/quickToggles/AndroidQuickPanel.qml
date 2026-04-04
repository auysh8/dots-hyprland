import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    // Sizes
    implicitHeight: (editMode ? contentItem.implicitHeight : (usedRowsStaticLoader.item?.implicitHeight ?? 0)) + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        // This is the wrong calculation, but it looks correct in reality???
        // (theoretically spacing should be multiplied by 1 column less)
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    // Toggles
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang"]
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []
    readonly property list<var> toggleRows: toggleRowsForList(toggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)
    readonly property var draggedToggleData: {
        if (!dragType) return null;
        for (let i = 0; i < toggles.length; i++) {
            if (toggles[i]?.type === dragType) return toggles[i];
        }
        return null;
    }

    property int dragIndex: -1  // flat config index of item being dragged (-1 = none)
    property string dragType: ""
    property real dragCursorX: 0
    property real dragCursorY: 0
    property real dragPressOffsetX: 0
    property real dragPressOffsetY: 0
    property bool dragHideLiveItem: false
    property bool dragPreviewReady: false
    property url dragPreviewUrl: ""
    property real dragPreviewWidth: 0
    property real dragPreviewHeight: 0
    property real dragPreviewSourceWidth: 0
    property real dragPreviewSourceHeight: 0
    property real dragPreviewScale: 1.06
    property int dragSessionId: 0
    readonly property real dragPreviewScaledWidth: dragPreviewWidth * dragPreviewScale
    readonly property real dragPreviewScaledHeight: dragPreviewHeight * dragPreviewScale
    readonly property real dragPreviewMinX: root.padding + (dragPreviewScaledWidth - dragPreviewWidth) / 2
    readonly property real dragPreviewMinY: root.padding + (dragPreviewScaledHeight - dragPreviewHeight) / 2
    readonly property real dragPreviewMaxX: root.padding + Math.max(0, (usedRowsEditLoader.item?.width ?? 0) - dragPreviewWidth - (dragPreviewScaledWidth - dragPreviewWidth) / 2)
    readonly property real dragPreviewMaxY: root.padding + Math.max(0, (usedRowsEditLoader.item?.height ?? 0) - dragPreviewHeight - (dragPreviewScaledHeight - dragPreviewHeight) / 2)
    readonly property real dragPreviewClampedX: Math.max(dragPreviewMinX, Math.min(dragPreviewMaxX, root.padding + root.dragCursorX - root.dragPressOffsetX))
    readonly property real dragPreviewClampedY: Math.max(dragPreviewMinY, Math.min(dragPreviewMaxY, root.padding + root.dragCursorY - root.dragPressOffsetY))

    // Map (x, y) in usedRows coordinates → flat config index.
    // Uses the same stride math as the RowLayout so no item references are needed.
    function toggleIndexAt(x, y) {
        const rowH = root.baseCellHeight + root.spacing
        const rowIdx = Math.max(0, Math.min(root.toggleRows.length - 1, Math.floor(y / rowH)))
        if (root.toggleRows.length === 0) return -1
        let flatStart = 0
        for (let r = 0; r < rowIdx; r++) flatStart += root.toggleRows[r].length
        const row = root.toggleRows[rowIdx]
        if (!row || row.length === 0) return -1
        // Each column slot is (baseCellWidth + spacing) wide; a size-2 button takes 2 slots.
        const stride = root.baseCellWidth + root.spacing
        let accumulated = 0
        for (let c = 0; c < row.length; c++) {
            accumulated += row[c].size * stride
            // Drop target switches at the midpoint of the gap between buttons
            if (x < accumulated - root.spacing / 2 || c === row.length - 1) return flatStart + c
        }
        return flatStart + row.length - 1
    }

    function swapToggles(fromIdx, toIdx) {
        const list = Config.options.sidebar.quickToggles.android.toggles
        const temp = list[fromIdx]
        list[fromIdx] = list[toIdx]
        list[toIdx] = temp
    }

    function removeToggleAt(index) {
        Config.options.sidebar.quickToggles.android.toggles.splice(index, 1)
    }

    function resizeToggleAt(index) {
        const list = Config.options.sidebar.quickToggles.android.toggles
        if (index < 0 || index >= list.length) return
        list[index] = { type: list[index].type, size: 3 - list[index].size }
    }

    function beginDragPreview(item) {
        dragSessionId += 1
        const sessionId = dragSessionId
        dragPreviewReady = false
        dragHideLiveItem = false
        dragPreviewUrl = ""
        dragPreviewWidth = item?.width ?? 0
        dragPreviewHeight = item?.height ?? 0
        dragPreviewSourceWidth = Math.max(1, Math.round(dragPreviewWidth * 2))
        dragPreviewSourceHeight = Math.max(1, Math.round(dragPreviewHeight * 2))
        if (!item || typeof item.grabToImage !== "function") return
        item.grabToImage(function(result) {
            if (root.dragSessionId !== sessionId || root.dragType === "")
                return;
            if (!result || !result.url)
                return;
            root.dragPreviewUrl = result.url;
            root.dragPreviewReady = true;
            root.dragHideLiveItem = true;
        }, Qt.size(dragPreviewSourceWidth, dragPreviewSourceHeight));
    }

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0; // Total cols taken in current row
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12
        
        Loader {
            id: usedRowsStaticLoader
            active: !root.editMode
            visible: active
            sourceComponent: Column {
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.toggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: toggleRowStatic
                        required property int index
                        property var modelData: root.toggleRows[index]
                        property int startingIndex: {
                            const rows = root.toggleRows;
                            let sum = 0;
                            for (let i = 0; i < index; i++) {
                                sum += rows[i].length;
                            }
                            return sum;
                        }
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: modelData ?? []
                                objectProp: "type"
                            }
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: toggleRowStatic.startingIndex
                                editMode: false
                                dragIndex: -1
                                dragType: ""
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                                onOpenAudioOutputDialog: (sourceItem) => root.openAudioOutputDialog(sourceItem)
                                onOpenAudioInputDialog: (sourceItem) => root.openAudioInputDialog(sourceItem)
                                onOpenBluetoothDialog: (sourceItem) => root.openBluetoothDialog(sourceItem)
                                onOpenNightLightDialog: (sourceItem) => root.openNightLightDialog(sourceItem)
                                onOpenWifiDialog: (sourceItem) => root.openWifiDialog(sourceItem)
                            }
                        }
                    }
                }
            }
        }

        Loader {
            id: usedRowsEditLoader
            active: root.editMode
            visible: active
            sourceComponent: FlowButtonGroup {
                id: usedRows
                width: contentItem.width
                spacing: root.spacing
                function itemAt(index) {
                    return usedTogglesRepeater.itemAt(index);
                }
                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                Repeater {
                    id: usedTogglesRepeater
                    model: ScriptModel {
                        values: root.toggles
                        objectProp: "type"
                    }
                    delegate: AndroidToggleDelegateChooser {
                        startingIndex: 0
                        editMode: root.editMode
                        dragIndex: root.dragIndex
                        dragType: root.dragType
                        hideWhileDragging: root.dragHideLiveItem
                        dragCursorX: root.dragCursorX
                        dragCursorY: root.dragCursorY
                        dragPressOffsetX: root.dragPressOffsetX
                        dragPressOffsetY: root.dragPressOffsetY
                        baseCellWidth: root.baseCellWidth
                        baseCellHeight: root.baseCellHeight
                        spacing: root.spacing
                        onOpenAudioOutputDialog: (sourceItem) => root.openAudioOutputDialog(sourceItem)
                        onOpenAudioInputDialog: (sourceItem) => root.openAudioInputDialog(sourceItem)
                        onOpenBluetoothDialog: (sourceItem) => root.openBluetoothDialog(sourceItem)
                        onOpenNightLightDialog: (sourceItem) => root.openNightLightDialog(sourceItem)
                        onOpenWifiDialog: (sourceItem) => root.openWifiDialog(sourceItem)
                    }
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        FadeLoader {
            shown: root.editMode
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.unusedToggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var modelData: root.unusedToggleRows[index]
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: unusedToggleRow?.modelData ?? []
                                objectProp: "type"
                            }
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: -1
                                editMode: root.editMode
                                dragType: ""
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Edit-mode drag overlay ───────────────────────────────────────────────
    // Direct child of root so it floats above contentItem (z:100).
    // Positioned to exactly cover usedRows in root's coordinate space:
    //   contentItem has margins=root.padding, usedRows is contentItem's first child.
    // Intercepts all pointer events on the used-section buttons so drag, click,
    // and resize are all handled here. Unused-section buttons sit below this
    // overlay's height, so their own editModeInteraction MouseArea still fires.
    MouseArea {
        id: editDragOverlay
        z: 100
        x: root.padding
        y: root.padding
        width:  usedRowsEditLoader.item?.width ?? 0
        height: usedRowsEditLoader.item?.height ?? 0
        visible: root.editMode
        enabled: root.editMode
        hoverEnabled: true
        cursorShape: root.dragIndex >= 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property int  sourceIndex:   -1
        property bool dragActive:    false
        property real pressX:        0
        property real pressY:        0
        property int  pressedButton: Qt.NoButton
        readonly property real dragThreshold: 6

        function resetDragState() {
            root.dragSessionId += 1
            root.dragIndex = -1
            root.dragType = ""
            root.dragCursorX = 0
            root.dragCursorY = 0
            root.dragPressOffsetX = 0
            root.dragPressOffsetY = 0
            root.dragHideLiveItem = false
            root.dragPreviewReady = false
            root.dragPreviewUrl = ""
            root.dragPreviewWidth = 0
            root.dragPreviewHeight = 0
            root.dragPreviewSourceWidth = 0
            root.dragPreviewSourceHeight = 0
            sourceIndex = -1
            dragActive = false
            pressedButton = Qt.NoButton
        }

        onPressed: (mouse) => {
            pressX        = mouse.x
            pressY        = mouse.y
            root.dragCursorX = mouse.x
            root.dragCursorY = mouse.y
            root.dragPressOffsetX = 0
            root.dragPressOffsetY = 0
            dragActive    = false
            pressedButton = mouse.button
            sourceIndex   = root.toggleIndexAt(mouse.x, mouse.y)
            const draggedItem = sourceIndex >= 0 ? usedRowsEditLoader.item?.itemAt(sourceIndex) : null
            if (draggedItem) {
                root.dragPressOffsetX = mouse.x - draggedItem.x
                root.dragPressOffsetY = mouse.y - draggedItem.y
            }
            if (mouse.button === Qt.RightButton && sourceIndex >= 0) {
                root.resizeToggleAt(sourceIndex)
                sourceIndex = -1
            }
        }

        onPositionChanged: (mouse) => {
            if (!dragActive && pressedButton === Qt.LeftButton) {
                const dx = mouse.x - pressX
                const dy = mouse.y - pressY
                if (Math.sqrt(dx * dx + dy * dy) > dragThreshold) {
                    const draggedItem = sourceIndex >= 0 ? usedRowsEditLoader.item?.itemAt(sourceIndex) : null
                    dragActive     = true
                    root.dragIndex = sourceIndex
                    root.dragType = sourceIndex >= 0 ? (root.toggles[sourceIndex]?.type ?? "") : ""
                    root.beginDragPreview(draggedItem)
                }
            }
            if (dragActive && root.dragIndex >= 0) {
                root.dragCursorX = mouse.x
                root.dragCursorY = mouse.y
                const targetIdx = root.toggleIndexAt(mouse.x, mouse.y)
                if (targetIdx >= 0 && targetIdx !== root.dragIndex) {
                    root.swapToggles(root.dragIndex, targetIdx)
                    root.dragIndex = targetIdx   // follow the dragged item
                }
            }
        }

        onPressAndHold: {
            if (sourceIndex >= 0 && !dragActive) {
                root.resizeToggleAt(sourceIndex)
                sourceIndex = -1   // suppress the upcoming release click
            }
        }

        onReleased: (mouse) => {
            if (!dragActive && mouse.button === Qt.LeftButton && sourceIndex >= 0)
                root.removeToggleAt(sourceIndex)
            resetDragState()
        }

        onCanceled: resetDragState()

        // Consume wheel events — scroll-to-reorder is replaced by drag
        onWheel: (wheel) => wheel.accepted = true
    }

    Image {
        z: 101
        visible: root.editMode && root.dragPreviewReady && root.dragPreviewUrl !== ""
        source: root.dragPreviewUrl
        smooth: true
        asynchronous: false
        cache: false
        width: root.dragPreviewWidth
        height: root.dragPreviewHeight
        sourceSize.width: root.dragPreviewSourceWidth
        sourceSize.height: root.dragPreviewSourceHeight
        x: root.dragPreviewClampedX
        y: root.dragPreviewClampedY
        scale: root.dragPreviewScale
    }
}
