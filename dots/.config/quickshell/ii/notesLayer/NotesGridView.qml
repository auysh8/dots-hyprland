import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * M3 Expressive Notes Dashboard Grid View.
 *
 * Surface hierarchy: Uses deep tonal background from parent window.
 * Typography: headlineLarge for main title, headlineMedium for section headers,
 *   titleMedium for card titles.
 * Search bar: Fully pill-shaped surfaceContainerHigh container.
 * FAB: Prominent M3 Expressive squircle shape in primary accent.
 */
Item {
    id: root

    property string searchQuery: ""
    property bool filterMenuOpen: false
    property string sortOrder: "recent"
    readonly property int columnCount: 3

    // Declarative note lists for filtering
    property var visibleNotesList: []
    property var pinnedNotesList: []
    property var unpinnedNotesList: []

    // 2D Masonry position & height tracking
    property var cachedHeights: ({})
    property var positions: ({})
    property real totalContainerHeight: 0
    property real othersHeaderY: 0
    property bool isTyping: false

    Timer {
        id: typingTimer
        interval: 180
        repeat: false
        onTriggered: root.isTyping = false
    }

    Timer {
        id: relayoutTimer
        interval: 16
        repeat: false
        onTriggered: root.recomputePositions()
    }

    // Update filtered lists when dependencies change
    onSearchQueryChanged: {
        root.isTyping = true;
        typingTimer.restart();
        updateFilteredLists();
    }
    onSortOrderChanged: updateFilteredLists()
    
    Connections {
        target: NotesService
        function onNotesChanged() {
            updateFilteredLists();
        }
    }

    function getEstimatedHeight(note) {
        if (!note) return 120;
        if (root.cachedHeights[note.id] && root.cachedHeights[note.id] > 50) {
            return root.cachedHeights[note.id];
        }
        const title = note.title || "";
        const content = (note.content || "").trim();
        const titleLines = Math.min(3, Math.max(1, Math.ceil(title.length / 22)));
        const contentLines = Math.min(8, Math.max(1, Math.ceil(content.length / 32)));
        return 56 + titleLines * 22 + 10 + contentLines * 18;
    }

    function reportCardHeight(noteId, h) {
        if (!noteId || h < 50) return;
        const current = root.cachedHeights[noteId] || 0;
        if (Math.abs(current - h) > 3) {
            root.cachedHeights[noteId] = h;
            relayoutTimer.restart();
        }
    }

    function recomputePositions() {
        const sorted = root.visibleNotesList;
        const pinnedList = sorted.filter(n => n.pinned);
        const unpinnedList = sorted.filter(n => !n.pinned);

        const spacing = 16;
        const w = gridScroll.width > 100 ? gridScroll.width : (root.width > 100 ? root.width - 64 : 800);
        const colWidth = Math.max(150, (w - spacing * (root.columnCount - 1)) / root.columnCount);
        const newPos = {};

        // Pinned section
        let pinnedMaxY = 0;
        if (pinnedList.length > 0) {
            const colHeights = Array(root.columnCount).fill(48); // below PINNED header at y=0
            for (let i = 0; i < pinnedList.length; i++) {
                const note = pinnedList[i];
                let minCol = 0;
                for (let c = 1; c < root.columnCount; c++) {
                    if (colHeights[c] < colHeights[minCol]) minCol = c;
                }
                const posX = minCol * (colWidth + spacing);
                const posY = colHeights[minCol];
                const h = root.getEstimatedHeight(note);
                colHeights[minCol] += h + spacing;
                newPos[note.id] = { x: posX, y: posY, width: colWidth, index: i, pinned: true };
            }
            pinnedMaxY = Math.max(...colHeights);
        }

        // Others section
        let othersHeaderY = pinnedList.length > 0 ? pinnedMaxY + 24 : 0;
        let othersStartY = pinnedList.length > 0 ? othersHeaderY + 48 : 0;
        let othersMaxY = othersStartY;

        if (unpinnedList.length > 0) {
            const colHeights = Array(root.columnCount).fill(othersStartY);
            for (let i = 0; i < unpinnedList.length; i++) {
                const note = unpinnedList[i];
                let minCol = 0;
                for (let c = 1; c < root.columnCount; c++) {
                    if (colHeights[c] < colHeights[minCol]) minCol = c;
                }
                const posX = minCol * (colWidth + spacing);
                const posY = colHeights[minCol];
                const h = root.getEstimatedHeight(note);
                colHeights[minCol] += h + spacing;
                newPos[note.id] = { x: posX, y: posY, width: colWidth, index: pinnedList.length + i, pinned: false };
            }
            othersMaxY = Math.max(...colHeights);
        }

        root.totalContainerHeight = (unpinnedList.length > 0 ? othersMaxY : (pinnedList.length > 0 ? pinnedMaxY : 0)) + 60;
        root.othersHeaderY = othersHeaderY;
        root.positions = newPos;
    }

    function updateFilteredLists() {
        let sorted = NotesService.getSortedNotes();
        if (root.searchQuery.length > 0) {
            const q = root.searchQuery.toLowerCase();
            sorted = sorted.filter((n) => {
                return (n.title && n.title.toLowerCase().includes(q)) || (n.content && n.content.toLowerCase().includes(q));
            });
        }
        if (root.sortOrder === "title") {
            sorted = sorted.slice().sort((a, b) =>
                (a.title || "").localeCompare(b.title || ""));
        }
        root.visibleNotesList = sorted;
        root.pinnedNotesList = sorted.filter(n => n.pinned);
        root.unpinnedNotesList = sorted.filter(n => !n.pinned);
        root.recomputePositions();
    }

    Component.onCompleted: updateFilteredLists()

    // ── Card overflow menu ───────────────────────────────────────────────
    property string cardMenuNoteId: ""
    property bool cardMenuOpen: false
    property point cardMenuPos: Qt.point(0, 0)
    readonly property int cardMenuWidth: 200
    // ── Delete confirmation modal state ──────────────────────────────────
    property bool showDeleteDialog: false
    property string deleteTargetNoteId: ""

    property var cardMenuItems: [{
        "id": "pin",
        "label": "Pin note",
        "icon": "push_pin",
        "isDestructive": false,
        "action": function() {
            const note = NotesService.getNote(root.cardMenuNoteId);
            if (note)
                NotesService.setPinned(note.id, !note.pinned);
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
            root.deleteTargetNoteId = root.cardMenuNoteId;
            root.showDeleteDialog = true;
        }
    }]

    signal addClicked()
    signal noteClicked(string noteId)

    function cardMenuLabel(item) {
        if (item.id === "divider")
            return "";
        const note = NotesService.getNote(root.cardMenuNoteId);
        if (item.id === "pin")
            return note && note.pinned ? "Unpin note" : "Pin note";
        return item.label;
    }

    function openCardMenu(noteId, card) {
        root.cardMenuNoteId = noteId;
        const mapped = card.mapToItem(root, card.width, 36);
        let menuX = mapped.x - root.cardMenuWidth;
        let menuY = mapped.y;
        menuX = Math.max(16, Math.min(menuX, root.width - root.cardMenuWidth - 16));
        menuY = Math.max(16, Math.min(menuY, root.height - 250));
        root.cardMenuPos = Qt.point(menuX, menuY);
        root.cardMenuOpen = true;
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (root.showDeleteDialog) {
                root.showDeleteDialog = false;
                event.accepted = true;
            } else if (root.cardMenuOpen || root.filterMenuOpen) {
                root.cardMenuOpen = false;
                root.filterMenuOpen = false;
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Top app bar (M3 Expressive: headlineLarge title + pill search) ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 16

            // Title row — M3 headlineLarge typography
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: 4

                    StyledText {
                        text: "Notes"
                        font.pixelSize: Appearance.font.pixelSize.hugeass // ~23px ≈ headlineLarge
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: {
                            const total = NotesService.notes.length;
                            const shown = root.visibleNotesList.length;
                            if (root.searchQuery.length > 0)
                                return shown + " of " + total + (total === 1 ? " note" : " notes");
                            return total + (total === 1 ? " note" : " notes");
                        }
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // M3 Expressive: Fully pill-shaped search bar on surfaceContainerHigh
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 8
                    spacing: 12

                    MaterialSymbol {
                        text: "search"
                        iconSize: 22
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    ToolbarTextField {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        placeholderText: Translation.tr("Search notes...")
                        colBackground: "transparent"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        onTextChanged: root.searchQuery = text
                    }

                    RippleButton {
                        id: filterButton
                        implicitWidth: 38
                        implicitHeight: 38
                        Layout.alignment: Qt.AlignVCenter
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colOnSecondaryContainer, 0.88)
                        colRipple: Appearance.colors.colOnSecondaryContainer
                        onClicked: root.filterMenuOpen = !root.filterMenuOpen

                        StyledToolTip { text: Translation.tr("Sort notes") }

                        contentItem: MaterialSymbol {
                            anchors.fill: parent
                            text: "filter_list"
                            iconSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }

        // ── Notes Grid ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledFlickable {
                id: gridScroll
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: mainContainer.implicitHeight + 100
                topMargin: Appearance.rounding.verylarge
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds



                Item {
                    id: mainContainer
                    width: gridScroll.width
                    implicitHeight: root.totalContainerHeight

                    // Pinned Section Header
                    StyledText {
                        text: "PINNED"
                        font.pixelSize: Appearance.font.pixelSize.larger // ~19px ≈ headlineMedium
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                        visible: root.pinnedNotesList.length > 0
                        y: 0
                    }

                    // Others Section Header
                    StyledText {
                        text: "OTHERS"
                        font.pixelSize: Appearance.font.pixelSize.larger // ~19px ≈ headlineMedium
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurfaceVariant
                        visible: root.pinnedNotesList.length > 0 && root.unpinnedNotesList.length > 0
                        y: root.othersHeaderY

                        Behavior on y {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Repeater {
                        model: NotesService.notes

                        delegate: NoteCard {
                            id: noteCard
                            required property var modelData

                            readonly property string noteKey: modelData ? modelData.id : ""
                            readonly property var pos: root.positions[noteKey] || null
                            readonly property bool isMatched: pos !== null

                            targetX: pos ? pos.x : targetX
                            targetY: pos ? pos.y : targetY
                            cardWidth: pos ? pos.width : cardWidth
                            animateMovement: isMatched

                            noteId: noteKey
                            noteTitle: modelData ? modelData.title : ""
                            noteContent: modelData ? modelData.content : ""
                            noteModified: modelData ? modelData.modified : 0
                            noteColor: modelData ? modelData.color : "default"
                            notePinned: modelData ? modelData.pinned : false
                            cardIndex: pos ? pos.index : 0

                            visible: opacity > 0
                            opacity: isMatched ? 1 : 0
                            scale: isMatched ? 1 : 0.85

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

                            onClicked: root.noteClicked(noteKey)
                            onMoreClicked: root.openCardMenu(noteKey, noteCard)
                            onDeleteRequested: NotesService.deleteNote(noteKey)
                            onHeightReported: (id, h) => root.reportCardHeight(id, h)
                        }
                    }
                }

                // Empty state
                PagePlaceholder {
                    shown: root.visibleNotesList.length === 0
                    icon: "note_stack"
                    title: root.searchQuery.length > 0 ? "No notes match your search." : "No notes yet. Tap + to create one!"
                }
            }
        }
    }

    // ── M3 Expressive Floating Action Button ────────────────────────────────
    FloatingActionButton {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 32
        }
        iconText: "add"
        buttonText: "New note"
        expanded: true
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, 0.88)
        colRipple: Appearance.colors.colOnPrimary
        colOnBackground: Appearance.colors.colOnPrimary
        onClicked: root.addClicked()

        StyledToolTip {
            text: "New note"
        }
    }

    // ── Search sort/filter menu ────────────────────────────────────────────
    Rectangle {
        id: filterMenu
        z: 12
        visible: root.filterMenuOpen
        width: 196
        implicitHeight: filterMenuContent.implicitHeight + 16
        x: Math.max(16, Math.min(filterButton.mapToItem(root, 0, filterButton.height).x + filterButton.width - width, root.width - width - 16))
        y: Math.max(16, filterButton.mapToItem(root, 0, filterButton.height).y + 8)
        radius: 18 // M3 Expressive large rounded corners (16-20px)
        color: Appearance.m3colors.m3surfaceContainerHighest
        border.width: 0 // Remove hard boundary stroke - use elevation instead

        StyledRectangularShadow {
            target: filterMenu
        }

        ColumnLayout {
            id: filterMenuContent
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 0

            MenuButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: 8 // Rounded corners for individual menu items
                iconText: "schedule"
                buttonText: "Sort by recent"
                colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                onClicked: {
                    root.sortOrder = "recent";
                    root.filterMenuOpen = false;
                }

                MaterialSymbol {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "check"
                    iconSize: 18
                    visible: root.sortOrder === "recent"
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            MenuButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: 8 // Rounded corners for individual menu items
                iconText: "sort_by_alpha"
                buttonText: "Sort A–Z"
                colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                onClicked: {
                    root.sortOrder = "title";
                    root.filterMenuOpen = false;
                }

                MaterialSymbol {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "check"
                    iconSize: 18
                    visible: root.sortOrder === "title"
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

        }
    }

    // ── Card overflow menu popup ─────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: root.cardMenuOpen
        z: 10
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.cardMenuOpen = false
    }

    Item {
        id: cardMenuOverlay
        visible: root.cardMenuOpen || cardMenu.opacity > 0
        z: 11
        anchors.fill: parent

        Rectangle {
            id: cardMenu
            property real revealProgress: root.cardMenuOpen ? 1 : 0

            x: root.cardMenuPos.x
            y: root.cardMenuPos.y
            width: root.cardMenuWidth
            implicitHeight: cardMenuColumn.implicitHeight + 16
            radius: 18 // M3 Expressive large rounded corners (16-20px)
            // Elevated surface container background for natural visual separation
            color: Appearance.m3colors.m3surfaceContainerHighest
            border.width: 0 // Remove hard boundary stroke - use elevation instead
            opacity: cardMenu.revealProgress
            scale: 0.96 + cardMenu.revealProgress * 0.04
            transformOrigin: Item.TopRight
            visible: opacity > 0

            // M3 elevation shadow for surface depth
            StyledRectangularShadow {
                target: cardMenu
                opacity: cardMenu.revealProgress
                visible: opacity > 0
            }

            ColumnLayout {
                id: cardMenuColumn
                anchors.fill: parent
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 0

                Repeater {
                    model: root.cardMenuItems

                    Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.id === "divider" ? 9 : 40

                        // Section divider
                        Rectangle {
                            visible: modelData.id === "divider"
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: 0.3
                        }

                        MenuButton {
                            visible: modelData.id !== "divider"
                            anchors.fill: parent
                            buttonRadius: 8
                            iconText: modelData.icon || ""
                            buttonText: root.cardMenuLabel(modelData)
                            property bool isDestructive: modelData.isDestructive || false
                            colBackgroundHover: isDestructive ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHigh
                            onClicked: {
                                root.cardMenuOpen = false;
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

    // ── Delete confirmation modal (Shared ConfirmationDialog) ──────────────
    ConfirmationDialog {
        show: root.showDeleteDialog
        title: Translation.tr("Delete note?")
        text: Translation.tr("This will permanently delete this note. This action cannot be undone.")
        confirmText: Translation.tr("Delete")
        cancelText: Translation.tr("Cancel")
        isDestructive: true
        onCanceled: root.showDeleteDialog = false
        onConfirmed: {
            root.showDeleteDialog = false;
            if (root.deleteTargetNoteId.length > 0) {
                NotesService.deleteNote(root.deleteTargetNoteId);
                root.deleteTargetNoteId = "";
            }
        }
    }
}
