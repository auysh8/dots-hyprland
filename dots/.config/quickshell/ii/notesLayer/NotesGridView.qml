import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string searchQuery: ""
    // Google Keep-style masonry settings
    property int columnCount: 3
    // ── Card overflow menu (MD3 note card action: more_vert) ───────────────
    // Hosted here (a sibling of the flickable) so the menu can never be
    // clipped by the grid's scroll clip. Same pattern as NotesEditorView's
    // overflow menu: fade + scale reveal, colLayer2Base surface, shadow.
    property string cardMenuNoteId: ""
    property bool cardMenuOpen: false
    property point cardMenuPos: Qt.point(0, 0)
    readonly property int cardMenuWidth: 200
    // Config-driven action list (same style as NotesEditorView.menuItems).
    // Items with id "pin" have a dynamic label handled in the delegate.
    property var cardMenuItems: [{
        "id": "pin",
        "label": "Pin note",
        "icon": "push_pin",
        "action": function() {
            const note = NotesService.getNote(root.cardMenuNoteId);
            if (note)
                NotesService.setPinned(note.id, !note.pinned);
        }
    }, {
        "id": "delete",
        "label": "Delete note",
        "icon": "delete",
        "action": function() {
            NotesService.deleteNote(root.cardMenuNoteId);
        }
    }]

    signal addClicked()
    signal noteClicked(string noteId)

    // A pin action also needs to update the menu row's label
    function cardMenuLabel(item) {
        const note = NotesService.getNote(root.cardMenuNoteId);
        if (item.id === "pin")
            return note && note.pinned ? "Unpin note" : "Pin note";

        return item.label;
    }

    // Active accent color of the note the card menu is open for
    function cardMenuActiveColor() {
        const note = NotesService.getNote(root.cardMenuNoteId);
        return note ? note.color : "default";
    }

    // Position the menu just below the card's more_vert button (top-right of
    // the card), clamped to stay on-screen. `card` is the NoteCard delegate.
    function openCardMenu(noteId, card) {
        root.cardMenuNoteId = noteId;
        // Map top-right of card (card.width, 36) to root item coordinates
        const mapped = card.mapToItem(root, card.width, 36);
        let menuX = mapped.x - root.cardMenuWidth;
        let menuY = mapped.y;

        // Clamp cleanly inside window boundaries
        menuX = Math.max(16, Math.min(menuX, root.width - root.cardMenuWidth - 16));
        menuY = Math.max(16, Math.min(menuY, root.height - 250));

        root.cardMenuPos = Qt.point(menuX, menuY);
        root.cardMenuOpen = true;
    }

    // Notes visible in the current view (sorted, then filtered by search).
    function visibleNotes() {
        const sorted = NotesService.getSortedNotes();
        if (root.searchQuery.length > 0) {
            const q = root.searchQuery.toLowerCase();
            return sorted.filter((n) => {
                return n.title.toLowerCase().includes(q) || n.content.toLowerCase().includes(q);
            });
        }
        return sorted;
    }

    function pinnedNotes() {
        return root.visibleNotes().filter(n => n.pinned);
    }

    function unpinnedNotes() {
        return root.visibleNotes().filter(n => !n.pinned);
    }

    // Content-derived height estimate for masonry layout column balancing fallback
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
        const sorted = root.visibleNotes();
        const pinnedList = sorted.filter(n => n.pinned);
        const unpinnedList = sorted.filter(n => !n.pinned);

        const spacing = 16;
        const w = gridScroll.width > 100 ? gridScroll.width : Math.max(300, root.width - 64);
        const colWidth = (w - spacing * (root.columnCount - 1)) / root.columnCount;
        const positions = {};

        // 1. Position Pinned Notes (starting below PINNED header at y = 36)
        let pinnedMaxY = 0;
        if (pinnedList.length > 0) {
            const colHeights = [36, 36, 36];
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
            pinnedMaxY = Math.max(...colHeights, 36);
        }

        // 2. Position Others (Unpinned) Notes
        let othersHeaderY = pinnedList.length > 0 ? pinnedMaxY + 20 : 0;
        let othersMaxY = othersHeaderY;

        if (unpinnedList.length > 0) {
            const startY = pinnedList.length > 0 ? othersHeaderY + 36 : 0;
            const colHeights = [startY, startY, startY];
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

        // Remove deleted items
        for (let i = targetModel.count - 1; i >= 0; i--) {
            const id = targetModel.get(i).id;
            if (!list.some(n => n.id === id)) {
                targetModel.remove(i);
            }
        }

        // Insert or update items and target coordinates incrementally
        for (let i = 0; i < list.length; i++) {
            const note = list[i];
            const pos = positions[note.id] || { x: 0, y: 0, width: 200 };
            const dataObj = {
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
            };

            if (i < targetModel.count) {
                const current = targetModel.get(i);
                if (current.id === note.id) {
                    targetModel.setProperty(i, "posX", dataObj.posX);
                    targetModel.setProperty(i, "posY", dataObj.posY);
                    targetModel.setProperty(i, "cardWidth", dataObj.cardWidth);
                    targetModel.setProperty(i, "title", dataObj.title);
                    targetModel.setProperty(i, "content", dataObj.content);
                    targetModel.setProperty(i, "color", dataObj.color);
                    targetModel.setProperty(i, "pinned", dataObj.pinned);
                } else {
                    let existingIndex = -1;
                    for (let j = i + 1; j < targetModel.count; j++) {
                        if (targetModel.get(j).id === note.id) {
                            existingIndex = j;
                            break;
                        }
                    }
                    if (existingIndex !== -1) {
                        targetModel.move(existingIndex, i, 1);
                        targetModel.setProperty(i, "posX", dataObj.posX);
                        targetModel.setProperty(i, "posY", dataObj.posY);
                        targetModel.setProperty(i, "cardWidth", dataObj.cardWidth);
                        targetModel.setProperty(i, "title", dataObj.title);
                        targetModel.setProperty(i, "content", dataObj.content);
                        targetModel.setProperty(i, "color", dataObj.color);
                        targetModel.setProperty(i, "pinned", dataObj.pinned);
                    } else {
                        targetModel.insert(i, dataObj);
                    }
                }
            } else {
                targetModel.append(dataObj);
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

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && root.cardMenuOpen) {
            root.cardMenuOpen = false;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Top app bar (MD3 medium: title row + docked search bar) ─────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 18

            // Title row — Title Large typography
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: 2

                    StyledText {
                        text: "Notes"
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.family: Appearance.font.family.title
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
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
                        color: Appearance.colors.colSubtext
                    }

                }

                Item {
                    Layout.fillWidth: true
                }

            }

            // Docked search bar — full pill on surface_container_highest
            // (colLayer3Base) with a leading search icon.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer3Base

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 12
                    spacing: 12

                    MaterialSymbol {
                        text: "search"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchInput

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        background: null
                        padding: 0
                        placeholderText: "Search notes..."
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer0
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        renderType: Text.NativeRendering
                        onTextChanged: root.searchQuery = text

                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.small
                            hintingPreference: Font.PreferFullHinting
                            variableAxes: Appearance.font.variableAxes.main
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
                contentHeight: mainContainer.implicitHeight + 100 // Extra room above FAB
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

                    StyledText {
                        text: "PINNED"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                        opacity: 0.8
                        visible: root.pinnedNotes().length > 0
                        y: 0
                    }

                    StyledText {
                        text: "OTHERS"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.title
                        font.weight: Font.Bold
                        color: Appearance.colors.colSubtext
                        opacity: 0.8
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

    // ── Floating Action Button ───────────────────────────────────────────────
    // Shared FloatingActionButton (qs.modules.common.widgets) with an MD3
    // level-3 elevation shadow behind it that separates the button from the
    // grid content.
    Item {
        implicitWidth: fabWidget.implicitWidth
        implicitHeight: fabWidget.implicitHeight

        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 32
        }

        // Elevation shadow (level-3) lifting FAB high above scrolling container
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
            onClicked: root.addClicked()

            StyledToolTip {
                text: "New note"
            }

        }

    }

    // ── Card overflow menu popup ─────────────────────────────────────────────
    // Positioned via measured coordinates (same as NotesEditorView's overflow
    // menu): placed just below the card's more_vert button, right-aligned to
    // it, clamped to stay on-screen. Visuals + reveal animation match the
    // shell's context menus (fade + scale + slide with elementMoveFast easing,
    // shadow fading in with it). Surface follows COLOR_RULES.md (elevated
    // floater -> colLayer2Base).
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
            radius: Appearance.rounding.normal
            // Highest surface (colLayer3Base) so the menu clearly contrasts the
            // cards beneath it — including pinned cards sitting on colLayer2.
            color: Appearance.colors.colLayer3Base
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            opacity: cardMenu.revealProgress
            scale: 0.96 + cardMenu.revealProgress * 0.04
            transformOrigin: Item.TopRight
            visible: opacity > 0

            StyledRectangularShadow {
                target: cardMenu
                opacity: cardMenu.revealProgress
                visible: opacity > 0
            }

            ColumnLayout {
                id: cardMenuColumn

                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: root.cardMenuItems

                    // Shared MenuButton (extended with optional iconText)
                    MenuButton {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 44 // Standard MD3 menu item height
                        buttonRadius: Appearance.rounding.small
                        iconText: modelData.icon
                        buttonText: root.cardMenuLabel(modelData)
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        onClicked: {
                            root.cardMenuOpen = false;
                            modelData.action();
                        }
                    }

                }

                // ── Note color section ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    Layout.topMargin: 6
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.3
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: "Color"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8

                    Repeater {
                        model: NotesService.noteColors

                        delegate: RippleButton {
                            required property var modelData

                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.full
                            colBackground: modelData.color
                            colBackgroundHover: modelData.color
                            colRipple: ColorUtils.transparentize(modelData.color, 0.5)
                            onClicked: {
                                NotesService.setNoteColor(root.cardMenuNoteId, modelData.id);
                            }

                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 14
                                fill: 1
                                // Contrast-aware check: light check on dark swatches (e.g. "default"),
                                // dark check on the pastel accent swatches
                                color: root.cardMenuActiveColor() === modelData.id ? (ColorUtils.isDark(modelData.color) ? Qt.lighter(modelData.color, 2.5) : Qt.darker(modelData.color, 3)) : "transparent"
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
