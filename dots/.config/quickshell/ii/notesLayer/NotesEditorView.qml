import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * M3 Expressive Notes Editor View.
 *
 * Surface: Inherits deep tonal background from parent window.
 * Typography: Display scale (32px DemiBold) for title input, bodyLarge for content.
 * Header actions: Secondary container for Back/Options, Primary container for Save.
 * Footer metadata: Tonal pill chips with subtle leading icons.
 */
Item {
    id: root

    property string noteId: ""
    property string initialTitle: ""
    property string initialContent: ""
    property int initialModified: 0
    property bool initialPinned: false
    property string initialColor: "default"
    property bool isSaving: NotesService.saving
    property bool pinned: false
    property string activeColor: "default"
    property string editedLabel: ""

    // ── Overflow menu ────────────────────────────────────────────────────────
    property bool menuOpen: false
    property bool showDeleteDialog: false
    property point menuPosition: Qt.point(0, 0)
    property var menuItems: [{
        "id": "pin",
        "label": "Pin note",
        "icon": "push_pin",
        "isDestructive": false,
        "action": function() {
            root.pinned = !root.pinned;
            NotesService.setPinned(root.noteId, root.pinned);
        }
    }, {
        "id": "duplicate",
        "label": "Duplicate note",
        "icon": "file_copy",
        "isDestructive": false,
        "action": function() {
            const newId = NotesService.createNote(titleInput.text, contentInput.text, root.pinned);
            NotesService.setNoteColor(newId, root.activeColor);
        }
    }, {
        "id": "copy",
        "label": "Copy to clipboard",
        "icon": "content_copy",
        "isDestructive": false,
        "action": function() {
            Quickshell.clipboardText = contentInput.text;
        }
    }, {
        "id": "divider",
        "label": "",
        "icon": "",
        "isDestructive": false,
        "action": function() {}
    }, {
        "id": "delete",
        "label": "Delete note",
        "icon": "delete",
        "isDestructive": true,
        "action": function() {
            root.showDeleteDialog = true;
        }
    }]

    signal cancelClicked()
    signal saveClicked(string title, string content)

    function formatEdited() {
        if (root.initialModified <= 0)
            return "";
        const diff = Math.max(0, Math.floor(Date.now() / 1000) - root.initialModified);
        if (diff < 60) return "Edited just now";
        if (diff < 3600) return "Edited " + Math.floor(diff / 60) + "m ago";
        if (diff < 86400) return "Edited " + Math.floor(diff / 3600) + "h ago";
        if (diff < 604800) return "Edited " + Math.floor(diff / 86400) + "d ago";
        return "Edited " + NotesService.formatDate(root.initialModified);
    }

    function menuLabel(item) {
        if (item.id === "pin")
            return root.pinned ? "Unpin note" : "Pin note";
        return item.label;
    }

    function updateMenuPosition() {
        const pos = moreButton.mapToItem(root, 0, 0);
        root.menuPosition = Qt.point(pos.x, pos.y);
    }

    function formatStats() {
        const text = ((titleInput ? titleInput.text : "") + " " + (contentInput ? contentInput.text : "")).trim();
        if (!text) return "0 words • 0 chars";
        const words = text.split(/\s+/).filter(w => w.length > 0).length;
        const chars = text.length;
        return words + (words === 1 ? " word" : " words") + " • " + chars + " chars";
    }

    onNoteIdChanged: {
        titleInput.text = root.initialTitle;
        contentInput.text = root.initialContent;
        root.pinned = root.initialPinned;
        root.activeColor = root.initialColor;
        root.editedLabel = root.formatEdited();
    }

    onInitialPinnedChanged: root.pinned = root.initialPinned
    onInitialColorChanged: root.activeColor = root.initialColor
    onInitialTitleChanged: titleInput.text = initialTitle
    onInitialContentChanged: contentInput.text = initialContent
    onInitialModifiedChanged: editedLabel = formatEdited()

    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
            root.saveClicked(titleInput.text, contentInput.text);
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.saveClicked(titleInput.text, contentInput.text);
            root.cancelClicked();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            if (root.menuOpen) {
                root.menuOpen = false;
            } else if (root.showDeleteDialog) {
                root.showDeleteDialog = false;
            } else {
                root.cancelClicked();
            }
            event.accepted = true;
        }
    }

    Timer {
        id: autoSaveTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.noteId.length > 0) {
                NotesService.updateNote(root.noteId, titleInput.text, contentInput.text);
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.initialModified > 0
        onTriggered: editedLabel = root.formatEdited()
    }

    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        z: 10
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.menuOpen = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Header (M3 Expressive: primary save action, subtle secondary buttons) ─────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Back button — subtle tonal container
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                onClicked: root.cancelClicked()

                StyledToolTip { text: "Discard changes and return" }

                contentItem: MaterialSymbol {
                    anchors.fill: parent
                    text: "arrow_back"
                    iconSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnSurface
                }
            }

            Item { Layout.fillWidth: true }

            // More options — subtle tonal container
            RippleButton {
                id: moreButton
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                onClicked: {
                    root.menuOpen = !root.menuOpen;
                    if (root.menuOpen) root.updateMenuPosition();
                }

                StyledToolTip { text: "More options" }

                contentItem: MaterialSymbol {
                    anchors.fill: parent
                    text: "more_vert"
                    iconSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnSurface
                }
            }

            // Save button — prominent primary action with accent container
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colOnPrimaryContainer
                onClicked: root.saveClicked(titleInput.text, contentInput.text)

                StyledToolTip { text: root.isSaving ? "Saving..." : "Save Note" }

                contentItem: MaterialSymbol {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.isSaving ? "sync" : "save"
                    iconSize: 22
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        // ── Editor ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            // Title — M3 Expressive display scale typography
            StyledTextInput {
                id: titleInput
                Layout.fillWidth: true
                text: root.initialTitle
                font.pixelSize: 32
                font.family: Appearance.font.family.title
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                selectByMouse: true
                clip: true
                onTextChanged: autoSaveTimer.restart()

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Untitled"
                    font: titleInput.font
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.5
                    visible: !titleInput.text && !titleInput.activeFocus
                }
            }

            // Content — M3 bodyLarge plain text
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 64
                clip: true

                StyledTextArea {
                    id: contentInput
                    width: parent.width
                    text: root.initialContent
                    wrapMode: TextEdit.WrapAnywhere
                    placeholderText: "Start typing your thoughts here..."
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.PlainText
                    background: null
                    padding: 0
                    font.family: Appearance.font.family.reading
                    font.pixelSize: Appearance.font.pixelSize.large // ~17px ≈ bodyLarge
                    color: Appearance.colors.colOnSurface
                    onTextChanged: autoSaveTimer.restart()
                }

                ScrollBar.vertical: StyledScrollBar {}
            }
        }
    }

    // ── Overflow menu popup ──────────────────────────────────────────────────
    Item {
        id: overflowMenuOverlay
        visible: root.menuOpen || overflowMenu.opacity > 0
        z: 11
        anchors.fill: parent

        Rectangle {
            id: overflowMenu
            property real revealProgress: root.menuOpen ? 1 : 0

            x: Math.max(8, Math.min(root.menuPosition.x + moreButton.width - width, parent.width - width - 8))
            y: Math.max(8, Math.min(root.menuPosition.y + moreButton.height + 8 + (1 - overflowMenu.revealProgress) * 10, parent.height - height - 8))
            width: 220
            implicitHeight: overflowMenuColumn.implicitHeight + 16
            radius: 18 // M3 Expressive large rounded corners (16-20px)
            // Elevated surface container background for natural visual separation
            color: Appearance.m3colors.m3surfaceContainerHighest
            border.width: 0 // Remove hard boundary stroke - use elevation instead
            opacity: overflowMenu.revealProgress
            scale: 0.96 + overflowMenu.revealProgress * 0.04
            transformOrigin: Item.TopRight
            visible: opacity > 0

            // M3 elevation shadow for surface depth
            StyledRectangularShadow {
                target: overflowMenu
                opacity: overflowMenu.revealProgress
                visible: opacity > 0
            }

            ColumnLayout {
                id: overflowMenuColumn
                anchors.fill: parent
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 0

                Repeater {
                    model: root.menuItems

                    Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.id === "divider" ? 11 : 44

                        // Section divider - 1px hairline separator
                        Rectangle {
                            visible: modelData.id === "divider"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 1
                            height: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: 0.4 // More subtle divider
                        }

                        // Menu item
                        RippleButton {
                            visible: modelData.id !== "divider"
                            anchors.fill: parent
                            buttonRadius: 8 // Rounded corners for individual menu items
                            implicitHeight: 44
                            
                            // Destructive action styling
                            property bool isDestructive: modelData.isDestructive || false
                            // Subtle low-opacity error container background for destructive actions
                            colBackgroundHover: isDestructive ? 
                                Appearance.colors.colErrorContainer :
                                Appearance.colors.colSurfaceContainerHigh
                            
                            contentItem: Item {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                // Icon slot
                                Item {
                                    id: iconSlot
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20
                                    height: 20
                                    visible: modelData.icon !== ""
                                    clip: true

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        width: 20
                                        height: 20
                                        text: modelData.icon
                                        iconSize: 20
                                        color: parent.parent.isDestructive ? 
                                            Appearance.colors.colError : 
                                            Appearance.colors.colOnSurface
                                    }
                                }

                                // Text label
                                StyledText {
                                    anchors.left: iconSlot.right
                                    anchors.leftMargin: modelData.icon !== "" ? 12 : 0
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.menuLabel(modelData)
                                    horizontalAlignment: Text.AlignLeft
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: parent.parent.isDestructive ? 
                                        Appearance.colors.colError : 
                                        Appearance.colors.colOnSurface
                                }
                            }

                            onClicked: {
                                root.menuOpen = false;
                                modelData.action();
                            }
                        }
                    }
                }

            }

            Behavior on revealProgress {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }

    // ── Delete confirmation modal ─────────────────────────────────────────────
    Rectangle {
        id: deleteConfirmDialog
        anchors.fill: parent
        z: 20
        visible: root.showDeleteDialog
        radius: Appearance.rounding.screenRounding // Match screen/window rounding
        
        // Smooth opacity fade for backdrop
        color: Appearance.colors.colScrim
        opacity: root.showDeleteDialog ? 1 : 0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 250
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        
        // Click outside to dismiss
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: root.showDeleteDialog = false
        }
        
        // Dialog container
        Rectangle {
            id: dialogContainer
            anchors.centerIn: parent
            width: Math.max(320, Math.min(parent.width * 0.9, 400))
            height: dialogColumn.implicitHeight + 48 // 24px padding top + bottom
            radius: Appearance.rounding.verylarge // 28-30px - M3 Expressive
            color: Appearance.colors.colLayer3
            clip: true
            
            // M3 elevation shadow
            StyledRectangularShadow {
                target: dialogContainer
            }
            
            // Entry/Exit animation using expressive curves
            property real animProgress: root.showDeleteDialog ? 1 : 0
            opacity: animProgress
            scale: 0.95 + animProgress * 0.05
            transformOrigin: Item.Center
            
            Behavior on animProgress {
                NumberAnimation {
                    duration: 280
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            
            // Prevent clicks on dialog from dismissing
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onPressed: {} // Consume clicks
            }
            
            // Content column with 24px padding
            ColumnLayout {
                id: dialogColumn
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0
                
                // Dialog title - M3 Expressive typography
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignLeft
                    Layout.bottomMargin: 16
                    text: Translation.tr("Delete note?")
                    color: Appearance.colors.colOnSurface
                    wrapMode: Text.Wrap
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.hugeass
                        weight: Font.DemiBold
                    }
                }
                
                // Body text - readable with explicit word wrapping
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignLeft
                    Layout.bottomMargin: 24
                    text: Translation.tr("This will permanently delete this note. This action cannot be undone.")
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.WordWrap
                    font {
                        family: Appearance.font.family.main
                        pixelSize: Appearance.font.pixelSize.small
                    }
                    lineHeight: 1.5
                }
                
                // Spacer to push buttons to bottom
                Item {
                    Layout.fillHeight: true
                    Layout.preferredHeight: 24
                }
                
                // Actions row - M3 Expressive pill buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    
                    // Spacer to push buttons to the right
                    Item {
                        Layout.fillWidth: true
                    }
                    
                    // Cancel button - transparent with hover state
                    RippleButton {
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: cancelText.implicitWidth + 32 // 16px padding each side
                        buttonRadius: Appearance.rounding.full // Pill shape
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        
                        contentItem: StyledText {
                            id: cancelText
                            anchors.fill: parent
                            text: Translation.tr("Cancel")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            color: Appearance.colors.colPrimary
                        }
                        
                        onClicked: root.showDeleteDialog = false
                    }
                    
                    // Delete button - destructive with error background
                    RippleButton {
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: deleteText.implicitWidth + 32 // 16px padding each side
                        buttonRadius: Appearance.rounding.full // Pill shape
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colErrorHover
                        
                        contentItem: StyledText {
                            id: deleteText
                            anchors.fill: parent
                            text: Translation.tr("Delete")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            color: Appearance.colors.colOnError
                        }
                        
                        onClicked: {
                            root.showDeleteDialog = false;
                            NotesService.deleteNote(root.noteId);
                        }
                    }
                }
            }
        }
        
        // Handle keyboard focus
        Connections {
            target: deleteConfirmDialog
            function onVisibleChanged() {
                if (deleteConfirmDialog.visible) {
                    deleteConfirmDialog.forceActiveFocus();
                }
            }
        }
        
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.showDeleteDialog = false;
                event.accepted = true;
            }
        }
    }

    // ── Footer Stats (M3 tonal pill chips) ───────────────────────────────────
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.rightMargin: 36
        anchors.bottomMargin: 16
        spacing: 12

        // Timestamp chip
        Rectangle {
            implicitHeight: 28
            implicitWidth: timestampRow.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHigh
            visible: root.editedLabel.length > 0

            Row {
                id: timestampRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "schedule"
                    iconSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.7
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.editedLabel
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.8
                }
            }
        }

        // Word/character count chip
        Rectangle {
            implicitHeight: 28
            implicitWidth: statsRow.implicitWidth + 24
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHigh

            Row {
                id: statsRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "short_text"
                    iconSize: 14
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.7
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatStats()
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.8
                }
            }
        }
    }
}
