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

    // ── Card overflow menu ───────────────────────────────────────────────
    property string cardMenuNoteId: ""
    property bool cardMenuOpen: false
    property point cardMenuPos: Qt.point(0, 0)
    readonly property int cardMenuWidth: 200
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
            NotesService.deleteNote(root.cardMenuNoteId);
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

    function visibleNotes() {
        let sorted = NotesService.getSortedNotes();
        if (root.searchQuery.length > 0) {
            const q = root.searchQuery.toLowerCase();
            sorted = sorted.filter((n) => {
                return n.title.toLowerCase().includes(q) || n.content.toLowerCase().includes(q);
            });
        }
        if (root.sortOrder === "title") {
            sorted = sorted.slice().sort((a, b) =>
                (a.title || "").localeCompare(b.title || ""));
        }
        return sorted;
    }

    function pinnedNotes() {
        return root.visibleNotes().filter(n => n.pinned);
    }

    function unpinnedNotes() {
        return root.visibleNotes().filter(n => !n.pinned);
    }

    function predictedNoteHeight(note) {
        if (!note) return 120;
        const title = note.title || "";
        const content = (note.content || "").split("\n").filter((l) => {
            return l.trim().length > 0;
        }).join("\n");
        const titleLines = Math.min(3, Math.max(1, Math.ceil(title.length / 24)));
        const previewLines = Math.min(10, Math.max(1, Math.ceil(content.length / 36)));
        return 56 + titleLines * 24 + 12 + previewLines * 20;
    }

    property var measuredCardHeights: ({})
    property real totalContainerHeight: 0
    property real othersHeaderY: 0

    function reportCardHeight(noteId, height) {
        if (!noteId || height < 60) return;
        const current = root.measuredCardHeights[noteId] || 0;
        if (Math.abs(current - height) > 2) {
            const copy = Object.assign({}, root.measuredCardHeights);
            copy[noteId] = height;
            root.measuredCardHeights = copy;
            root.updateModels();
        }
    }

    ListModel { id: allNotesModel }

    function updateModels() {
        const currentIds = new Set(root.visibleNotes().map(n => n.id));
        const heightKeys = Object.keys(root.measuredCardHeights);
        for (const key of heightKeys) {
            if (!currentIds.has(key)) {
                delete root.measuredCardHeights[key];
            }
        }

        const sorted = root.visibleNotes();
        const pinnedList = sorted.filter(n => n.pinned);
        const unpinnedList = sorted.filter(n => !n.pinned);

        const spacing = 16;
        const w = gridScroll.width > 100 ? gridScroll.width : Math.max(300, root.width - 64);
        const colWidth = (w - spacing * (root.columnCount - 1)) / root.columnCount;
        const positions = {};

        // Pinned notes start below PINNED header at y = 48 (M3 headlineMedium space)
        let pinnedMaxY = 0;
        if (pinnedList.length > 0) {
            const colHeights = Array(root.columnCount).fill(48);
            for (const note of pinnedList) {
                let minCol = 0;
                for (let c = 1; c < root.columnCount; c++) {
                    if (colHeights[c] < colHeights[minCol]) minCol = c;
                }
                const posX = minCol * (colWidth + spacing);
                const posY = colHeights[minCol];
                const h = root.measuredCardHeights[note.id] || root.predictedNoteHeight(note);
                colHeights[minCol] += h + spacing;
                positions[note.id] = { x: posX, y: posY, width: colWidth };
            }
            pinnedMaxY = Math.max(...colHeights, 48);
        }

        let othersHeaderY = pinnedList.length > 0 ? pinnedMaxY + 24 : 0;
        let othersMaxY = othersHeaderY;

        if (unpinnedList.length > 0) {
            const startY = pinnedList.length > 0 ? othersHeaderY + 48 : 0;
            const colHeights = Array(root.columnCount).fill(startY);
            for (const note of unpinnedList) {
                let minCol = 0;
                for (let c = 1; c < root.columnCount; c++) {
                    if (colHeights[c] < colHeights[minCol]) minCol = c;
                }
                const posX = minCol * (colWidth + spacing);
                const posY = colHeights[minCol];
                const h = root.measuredCardHeights[note.id] || root.predictedNoteHeight(note);
                colHeights[minCol] += h + spacing;
                positions[note.id] = { x: posX, y: posY, width: colWidth };
            }
            othersMaxY = Math.max(...colHeights, startY);
        }

        root.totalContainerHeight = othersMaxY + 40;
        root.othersHeaderY = othersHeaderY;

        root.syncListModel(allNotesModel, sorted, positions);
    }

    function syncListModel(targetModel, list, positions) {
        if (!targetModel) return;

        const newIdSet = new Set(list.map(n => n.id));

        for (let i = targetModel.count - 1; i >= 0; i--) {
            if (!newIdSet.has(targetModel.get(i).id)) {
                targetModel.remove(i);
            }
        }

        for (let i = 0; i < list.length; i++) {
            const note = list[i];
            const pos = positions[note.id] || { x: 0, y: 0, width: 200 };

            if (i < targetModel.count) {
                const current = targetModel.get(i);
                if (current.id === note.id) {
                    targetModel.setProperty(i, "posX", pos.x);
                    targetModel.setProperty(i, "posY", pos.y);
                    targetModel.setProperty(i, "cardWidth", pos.width);
                    targetModel.setProperty(i, "title", note.title || "");
                    targetModel.setProperty(i, "content", note.content || "");
                    targetModel.setProperty(i, "color", note.color || "default");
                    targetModel.setProperty(i, "pinned", !!note.pinned);
                    targetModel.setProperty(i, "modified", note.modified || 0);
                } else {
                    let found = -1;
                    for (let j = i + 1; j < targetModel.count; j++) {
                        if (targetModel.get(j).id === note.id) {
                            found = j;
                            break;
                        }
                    }
                    if (found !== -1) {
                        targetModel.move(found, i, 1);
                        targetModel.setProperty(i, "posX", pos.x);
                        targetModel.setProperty(i, "posY", pos.y);
                        targetModel.setProperty(i, "cardWidth", pos.width);
                        targetModel.setProperty(i, "title", note.title || "");
                        targetModel.setProperty(i, "content", note.content || "");
                        targetModel.setProperty(i, "color", note.color || "default");
                        targetModel.setProperty(i, "pinned", !!note.pinned);
                        targetModel.setProperty(i, "modified", note.modified || 0);
                    } else {
                        targetModel.insert(i, {
                            "id": note.id || "",
                            "title": note.title || "",
                            "content": note.content || "",
                            "modified": note.modified || 0,
                            "created": note.created || 0,
                            "color": note.color || "default",
                            "pinned": !!note.pinned,
                            "posX": pos.x,
                            "posY": pos.y,
                            "cardWidth": pos.width
                        });
                    }
                }
            } else {
                targetModel.append({
                    "id": note.id || "",
                    "title": note.title || "",
                    "content": note.content || "",
                    "modified": note.modified || 0,
                    "created": note.created || 0,
                    "color": note.color || "default",
                    "pinned": !!note.pinned,
                    "posX": pos.x,
                    "posY": pos.y,
                    "cardWidth": pos.width
                });
            }
        }
    }

    Component.onCompleted: updateModels()

    Connections {
        target: NotesService
        function onNotesChanged() {
            root.updateModels();
        }
    }

    onSearchQueryChanged: updateModels()
    onSortOrderChanged: updateModels()

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && (root.cardMenuOpen || root.filterMenuOpen)) {
            root.cardMenuOpen = false;
            root.filterMenuOpen = false;
            event.accepted = true;
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
                            const shown = root.visibleNotes().length;
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
                implicitHeight: 56
                radius: Appearance.rounding.full // Full pill shape
                color: Appearance.colors.colSurfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 12
                    spacing: 14

                    MaterialSymbol {
                        text: "search"
                        iconSize: 22
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        background: null
                        padding: 0
                        placeholderText: "Search notes..."
                        placeholderTextColor: Appearance.colors.colOnSurfaceVariant
                        color: Appearance.colors.colOnSurface
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        renderType: Text.NativeRendering
                        onTextChanged: root.searchQuery = text

                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.normal // ~16px ≈ bodyLarge
                            hintingPreference: Font.PreferFullHinting
                            variableAxes: Appearance.font.variableAxes.main
                        }
                    }

                    RippleButton {
                        id: filterButton
                        implicitWidth: 40
                        implicitHeight: 40
                        Layout.alignment: Qt.AlignVCenter
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colOnSecondaryContainer
                        onClicked: root.filterMenuOpen = !root.filterMenuOpen

                        StyledToolTip { text: "Sort notes" }

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

                onWidthChanged: {
                    if (width > 0) root.updateModels();
                }

                Item {
                    id: mainContainer
                    width: gridScroll.width
                    implicitHeight: root.totalContainerHeight

                    // M3 Expressive: headlineMedium section headers
                    StyledText {
                        text: "PINNED"
                        font.pixelSize: Appearance.font.pixelSize.larger // ~19px ≈ headlineMedium
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                        visible: root.pinnedNotes().length > 0
                        y: 0
                    }

                    StyledText {
                        text: "OTHERS"
                        font.pixelSize: Appearance.font.pixelSize.larger // ~19px ≈ headlineMedium
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurfaceVariant
                        visible: root.pinnedNotes().length > 0 && root.unpinnedNotes().length > 0
                        y: root.othersHeaderY

                        Behavior on y {
                            NumberAnimation {
                                duration: 350
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Repeater {
                        model: allNotesModel

                        delegate: NoteCard {
                            id: noteCard
                            required property string id
                            required property string title
                            required property string content
                            required property int modified
                            required property string color
                            required property bool pinned
                            required property real posX
                            required property real posY
                            required property real cardWidth
                            required property int index

                            targetX: posX
                            targetY: posY
                            width: cardWidth

                            noteId: id
                            noteTitle: title
                            noteContent: content
                            noteModified: modified
                            noteColor: color
                            notePinned: pinned
                            cardIndex: index
                            onClicked: root.noteClicked(id)
                            onMoreClicked: root.openCardMenu(id, noteCard)
                            onDeleteRequested: NotesService.deleteNote(id)
                            onHeightReported: (id, h) => root.reportCardHeight(id, h)
                        }
                    }
                }

                // Empty state
                PagePlaceholder {
                    shown: root.visibleNotes().length === 0
                    icon: "note_stack"
                    title: root.searchQuery.length > 0 ? "No notes match your search." : "No notes yet. Tap + to create one!"
                }
            }
        }
    }

    // ── M3 Expressive Floating Action Button ────────────────────────────────
    // Prominent primary-colored squircle FAB with level-3 elevation shadow.
    Item {
        implicitWidth: fabWidget.implicitWidth
        implicitHeight: fabWidget.implicitHeight

        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 32
        }

        // Elevation shadow (level-3)
        RectangularShadow {
            anchors.fill: fabWidget
            radius: fabWidget.buttonRadius
            blur: fabWidget.hovered ? 18 : 12
            offset: Qt.vector2d(0, 3)
            spread: 1
            color: ColorUtils.transparentize(Appearance.colors.colShadow, 0.3)
            cached: true

            Behavior on blur {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        FloatingActionButton {
            id: fabWidget
            iconText: "add"
            buttonText: "New note"
            expanded: true
            baseSize: 56
            buttonRadius: Appearance.rounding.large
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colOnPrimary
            colOnBackground: Appearance.colors.colOnPrimary
            onClicked: root.addClicked()

            StyledToolTip {
                text: "New note"
            }
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
                                    text: root.cardMenuLabel(modelData)
                                    horizontalAlignment: Text.AlignLeft
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: parent.parent.isDestructive ?
                                        Appearance.colors.colError :
                                        Appearance.colors.colOnSurface
                                }
                            }

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
}
