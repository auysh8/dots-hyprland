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

    function applyFormat(formatType) {
        // Bold, Italic, Underline — use cursorSelection API (Qt 6.7+)
        if (formatType === "format_bold") {
            contentInput.cursorSelection.font.bold = !contentInput.cursorSelection.font.bold;
            contentInput.forceActiveFocus();
            return;
        }
        if (formatType === "format_italic") {
            contentInput.cursorSelection.font.italic = !contentInput.cursorSelection.font.italic;
            contentInput.forceActiveFocus();
            return;
        }
        if (formatType === "format_underlined") {
            contentInput.cursorSelection.font.underline = !contentInput.cursorSelection.font.underline;
            contentInput.forceActiveFocus();
            return;
        }

        // List formatting — use positional insert/remove (works in RichText mode)
        var start = contentInput.selectionStart;
        var end = contentInput.selectionEnd;
        var selected = contentInput.selectedText;

        var isBullet = formatType === "format_list_bulleted";
        var isNum = formatType === "format_list_numbered";

        if (isBullet || isNum) {
            // For RichText, selectedText gives plain text of the selection.
            // We operate line-by-line on the plain-text selection.
            var selLines = selected.split('\n');
            var newLines = [];

            var bulletRegex = /^(\s*)-\s+/;
            var numRegex = /^(\s*)\d+\.\s+/;

            for (var i = 0; i < selLines.length; i++) {
                var line = selLines[i];
                var hasBullet = bulletRegex.test(line);
                var hasNum = numRegex.test(line);

                if (isBullet) {
                    if (hasBullet) {
                        line = line.replace(bulletRegex, '$1');
                    } else if (hasNum) {
                        line = line.replace(numRegex, '$1- ');
                    } else {
                        line = "- " + line;
                    }
                } else if (isNum) {
                    if (hasNum) {
                        line = line.replace(numRegex, '$1');
                    } else if (hasBullet) {
                        line = line.replace(bulletRegex, '$1' + (i+1) + '. ');
                    } else {
                        line = (i+1) + ". " + line;
                    }
                }
                newLines.push(line);
            }

            var replacedText = newLines.join('\n');
            contentInput.remove(start, end);
            contentInput.insert(start, replacedText);
            contentInput.select(start, start + replacedText.length);
            contentInput.forceActiveFocus();
        }
    }


    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 24

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Cancel
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer2Hover

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer0
                }

                onClicked: root.cancelClicked()
                StyledToolTip { text: "Discard changes and return" }
            }

            Item { Layout.fillWidth: true }

            // More options (placeholder)
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer2Hover
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
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: Appearance.colors.colLayer2Hover

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isSaving ? "sync" : "check"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer0
                }

                StyledToolTip { text: root.isSaving ? "Saving..." : "Save Note" }

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

            // Content — RichText for visual bold/italic/underline formatting
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
                    textFormat: TextEdit.MarkdownText
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
        color: Appearance.colors.colLayer3

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
                    { icon: "format_list_numbered",   tip: "Numbered list" }
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

                    onClicked: root.applyFormat(modelData.icon)
                }
            }
        }
    }
}
