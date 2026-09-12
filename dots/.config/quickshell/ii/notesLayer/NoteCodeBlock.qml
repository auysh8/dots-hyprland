pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import org.kde.syntaxhighlighting
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Item {
    id: root

    property string segmentContent: ""
    property string segmentLang: ""

    // ── Language Detection & Definition Resolution ───────────────────────────
    readonly property string rawLang: (segmentLang && segmentLang !== "txt" && segmentLang !== "text") ? segmentLang.trim() : ""
    readonly property string detectedLang: rawLang.length > 0 ? rawLang : StringUtils.detectLanguage(segmentContent)
    readonly property string normalizedLang: {
        const langMap = {
            "c": "C",
            "c++": "C++",
            "cpp": "C++",
            "py": "Python",
            "python": "Python",
            "js": "JavaScript",
            "javascript": "JavaScript",
            "ts": "TypeScript",
            "typescript": "TypeScript",
            "sh": "Bash",
            "bash": "Bash",
            "shell": "Bash",
            "zsh": "Bash",
            "rs": "Rust",
            "rust": "Rust",
            "html": "HTML",
            "css": "CSS",
            "json": "JSON",
            "sql": "SQL",
            "qml": "QML",
            "md": "Markdown",
            "markdown": "Markdown",
            "yaml": "YAML",
            "yml": "YAML",
            "java": "Java",
            "kotlin": "Kotlin",
            "kt": "Kotlin",
            "go": "Go",
            "golang": "Go",
            "cs": "C#",
            "c#": "C#",
            "csharp": "C#",
            "swift": "Swift",
            "ruby": "Ruby",
            "rb": "Ruby",
            "lua": "Lua",
            "php": "PHP (HTML)"
        };
        const key = (detectedLang || "").toLowerCase();
        return langMap[key] || detectedLang || "plaintext";
    }

    readonly property var syntaxDef: Repository.definitionForName(normalizedLang || "plaintext")
    readonly property string displayLangName: (syntaxDef && syntaxDef.name && syntaxDef.name !== "None" && syntaxDef.name.toLowerCase() !== "plaintext") ? syntaxDef.name : ""

    readonly property bool hasHeader: displayLangName.length > 0
    property bool copied: false

    implicitHeight: mainLayout.implicitHeight
    Layout.fillWidth: true

    Timer {
        id: copyResetTimer
        interval: 1800
        repeat: false
        onTriggered: root.copied = false
    }

    function copyCode() {
        Quickshell.clipboardText = root.segmentContent;
        root.copied = true;
        copyResetTimer.restart();
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // ── Header Bar (Shown when a language is identified) ─────────────────
        Rectangle {
            id: headerBar
            visible: root.hasHeader
            Layout.fillWidth: true
            implicitHeight: root.hasHeader ? 36 : 0
            color: Appearance.colors.colSurfaceContainerHighest
            topLeftRadius: Appearance.rounding.small
            topRightRadius: Appearance.rounding.small
            bottomLeftRadius: 0
            bottomRightRadius: 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 8

                StyledText {
                    id: langLabel
                    Layout.alignment: Qt.AlignVCenter
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colPrimary
                    text: root.displayLangName
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: headerCopyButton
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Layout.alignment: Qt.AlignVCenter
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover

                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        text: root.copied ? "check" : "content_copy"
                    }

                    StyledToolTip {
                        text: root.copied ? Translation.tr("Copied!") : Translation.tr("Copy code")
                    }

                    onClicked: root.copyCode()
                }
            }
        }

        // ── Main Code Box (Line numbers + Content) ───────────────────────────
        Rectangle {
            id: codeBox
            Layout.fillWidth: true
            implicitHeight: contentRow.implicitHeight
            color: Appearance.colors.colLayer2
            topLeftRadius: root.hasHeader ? 0 : Appearance.rounding.small
            topRightRadius: root.hasHeader ? 0 : Appearance.rounding.small
            bottomLeftRadius: Appearance.rounding.small
            bottomRightRadius: Appearance.rounding.small
            clip: true

            // Floating copy button for headerless / plain code blocks
            RippleButton {
                id: floatingCopyBtn
                visible: !root.hasHeader
                z: 10
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                width: 28
                height: 28
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colLayer2Hover

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.copied ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    text: root.copied ? "check" : "content_copy"
                }

                StyledToolTip {
                    text: root.copied ? Translation.tr("Copied!") : Translation.tr("Copy code")
                }

                onClicked: root.copyCode()
            }

            RowLayout {
                id: contentRow
                anchors.fill: parent
                spacing: 0

                // ── Line numbers gutter ──────────────────────────────────────
                Rectangle {
                    id: gutter
                    Layout.fillHeight: true
                    implicitWidth: Math.max(38, (String(lineRepeater.count).length * 9) + 16)
                    color: Appearance.colors.colLayer2Active
                    opacity: 0.7

                    ColumnLayout {
                        id: gutterColumn
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 8
                        anchors.rightMargin: 8
                        spacing: 0

                        Repeater {
                            id: lineRepeater
                            model: codeTextArea.text.split("\n").length

                            Text {
                                required property int index
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                text: index + 1
                            }
                        }
                    }
                }

                // ── Code Text Area ───────────────────────────────────────────
                Flickable {
                    id: codeScrollView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    implicitHeight: codeTextArea.implicitHeight + 16
                    contentWidth: Math.max(width, codeTextArea.implicitWidth + 16)
                    contentHeight: codeTextArea.implicitHeight + 16
                    clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.horizontal: ScrollBar {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        padding: 3
                        policy: ScrollBar.AsNeeded
                        visible: size < 1.0

                        contentItem: Rectangle {
                            implicitHeight: 4
                            radius: 2
                            color: Appearance.colors.colPrimary
                            opacity: 0.6
                        }
                    }

                    TextArea {
                        id: codeTextArea
                        x: 8
                        y: 8
                        width: Math.max(parent.width - 16, implicitWidth)
                        readOnly: true
                        selectByMouse: true
                        renderType: Text.NativeRendering
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        color: Appearance.colors.colOnLayer1
                        background: null
                        padding: 0
                        wrapMode: TextEdit.NoWrap
                        text: root.segmentContent

                        SyntaxHighlighter {
                            id: highlighter
                            textEdit: codeTextArea
                            repository: Repository
                            definition: root.syntaxDef
                            theme: Appearance.syntaxHighlightingTheme
                        }
                    }
                }
            }
        }
    }
}
