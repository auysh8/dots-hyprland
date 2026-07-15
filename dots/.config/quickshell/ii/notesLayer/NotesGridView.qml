import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    signal addClicked()
    signal noteClicked(string noteId)

    property string searchQuery: ""
    property bool showSearch: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 20

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Title — only visible when search is collapsed
            StyledText {
                visible: !root.showSearch
                text: "Notes"
                font.pixelSize: Appearance.font.pixelSize.huge * 1.8
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            // Animated inline search bar
            Revealer {
                id: searchRevealer
                reveal: root.showSearch
                Layout.fillWidth: true

                Rectangle {
                    width: searchRevealer.width
                    height: 44
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        MaterialSymbol {
                            text: "search"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }

                        StyledTextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                            clip: true
                            onTextChanged: root.searchQuery = text
                            focus: root.showSearch

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Search notes..."
                                font: searchInput.font
                                color: Appearance.colors.colSubtext
                                visible: !searchInput.text && !searchInput.activeFocus
                            }
                        }

                        // Clear search button
                        RippleButton {
                            visible: searchInput.text.length > 0
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 16
                                color: Appearance.colors.colSubtext
                            }
                            onClicked: {
                                searchInput.text = ""
                                root.searchQuery = ""
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Search toggle
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                toggled: root.showSearch
                colBackground: root.showSearch
                    ? Appearance.colors.colSecondaryContainer
                    : "transparent"
                colBackgroundHover: root.showSearch
                    ? Appearance.colors.colSecondaryContainerHover
                    : Appearance.colors.colLayer1Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "search"
                    iconSize: 22
                    color: root.showSearch
                        ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnLayer0
                }
                onClicked: {
                    root.showSearch = !root.showSearch
                    if (!root.showSearch) {
                        searchInput.text = ""
                        root.searchQuery = ""
                    }
                }
                StyledToolTip { text: "Search notes" }
            }

            // Settings (placeholder — no functionality yet)
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "settings"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer0
                }
                StyledToolTip { text: "Settings (coming soon)" }
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
                contentHeight: notesFlow.implicitHeight + 100 // Extra room above FAB
                // topMargin gives the first row's rounded corners room to breathe
                // so they aren't cut off by the flickable's clip boundary
                topMargin: Appearance.rounding.verylarge
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                Flow {
                    id: notesFlow
                    width: gridScroll.width
                    spacing: 16

                    Repeater {
                        id: notesRepeater
                        model: {
                            const sorted = NotesService.getSortedNotes()
                            if (root.searchQuery.length > 0) {
                                const q = root.searchQuery.toLowerCase()
                                return sorted.filter(n =>
                                    n.title.toLowerCase().includes(q) ||
                                    n.content.toLowerCase().includes(q))
                            }
                            return sorted
                        }

                        delegate: NoteCard {
                            // 3-column layout, with spacing
                            width: Math.floor((notesFlow.width - 32) / 3)

                            noteId: modelData.id
                            noteTitle: modelData.title
                            noteContent: modelData.content
                            noteModified: modelData.modified
                            cardIndex: index

                            onClicked: root.noteClicked(modelData.id)
                            onDeleteRequested: NotesService.deleteNote(modelData.id)
                        }
                    }
                }

                // Empty state
                Item {
                    anchors.fill: parent
                    visible: notesRepeater.count === 0

                    Column {
                        anchors.centerIn: parent
                        spacing: 16

                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "note_stack"
                            iconSize: 64
                            color: Appearance.colors.colSubtext
                            opacity: 0.5
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.searchQuery.length > 0
                                ? "No notes match your search."
                                : "No notes yet. Tap + to create one!"
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // ── Floating Action Button ───────────────────────────────────────────────
    // Use the shared FloatingActionButton component (qs.modules.common.widgets)
    FloatingActionButton {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 32
        }
        iconText: "add"
        onClicked: root.addClicked()
        StyledToolTip { text: "New note" }
    }
}
