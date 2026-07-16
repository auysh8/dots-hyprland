import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    signal cancelClicked()
    signal saveClicked(string title, string content)

    property string initialTitle: ""
    property string initialContent: ""
    property bool isSaving: NotesService.saving

    onInitialTitleChanged: titleInput.text = initialTitle
    onInitialContentChanged: contentInput.text = initialContent



    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 24

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Cancel
            RippleButton {
                implicitWidth: 100
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent

                    MaterialSymbol {
                        text: "arrow_back"
                        iconSize: 18
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: "Cancel"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colPrimary
                    }
                }

                onClicked: root.cancelClicked()
                StyledToolTip { text: "Discard changes and return" }
            }

            Item { Layout.fillWidth: true }

            // More options (placeholder)
            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "more_vert"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer0
                }
                StyledToolTip { text: "More options" }
            }

            // Save Note
            RippleButton {
                implicitWidth: 120
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: root.isSaving ? "sync" : "check_circle"
                        iconSize: 17
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        text: root.isSaving ? "Saving..." : "Save Note"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                onClicked: root.saveClicked(titleInput.text, contentInput.text)
            }
        }

        // ── Editor ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Title — use StyledTextInput for consistent font/colors/selection
            StyledTextInput {
                id: titleInput
                Layout.fillWidth: true
                text: root.initialTitle
                font.pixelSize: Appearance.font.pixelSize.huge * 1.8
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
                selectByMouse: true
                clip: true

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: "Untitled"
                    font: titleInput.font
                    color: Appearance.colors.colSubtext
                    opacity: 0.5
                    visible: !titleInput.text && !titleInput.activeFocus
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.4
            }

            // Content — StyledTextArea already has proper colors
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Leave enough space at bottom for the floating toolbar
                Layout.bottomMargin: 80
                clip: true
                ScrollBar.vertical: StyledScrollBar {}

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
                    font.pixelSize: Appearance.font.pixelSize.large
                }
            }
        }
    }

    // ── Formatting Toolbar ───────────────────────────────────────────────────
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: toolbarRow.implicitWidth + 24
        implicitHeight: 52
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer2
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1

        RowLayout {
            id: toolbarRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: [
                    { icon: "format_bold",           tip: "Bold" },
                    { icon: "format_italic",          tip: "Italic" },
                    { icon: "format_underlined",      tip: "Underline" },
                    { icon: "format_list_bulleted",   tip: "Bullet list" },
                    { icon: "format_list_numbered",   tip: "Numbered list" },
                    { icon: "image",                  tip: "Insert image" }
                ]

                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.icon
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                    StyledToolTip { text: modelData.tip }
                }
            }
        }
    }
}
