pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import org.kde.syntaxhighlighting

Item {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var segmentLang: "txt"
    property var messageData: {}
    property bool isCommandRequest: segmentLang === "command"
    property var displayLang: (isCommandRequest ? "bash" : segmentLang)
    property ListView chatListView

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: 0 // Allow layout to manage width
    Layout.fillWidth: true

    Rectangle { // Floating Button Container (Sticky)
        id: stickyButtonContainer
        z: 10
        anchors.right: parent.right
        
        // Match header height and color
        height: stickyButtonsRow.implicitHeight + codeBlockHeaderPadding * 2
        width: stickyButtonsRow.implicitWidth + codeBlockHeaderPadding * 2 
        color: "transparent"
        
        // Sticky logic
        y: {
            if (!chatListView) return 0;
            const scrollTrigger = chatListView.contentY;
            const map = root.mapToItem(chatListView, 0, 0);
            const topMargin = chatListView.topMargin;
            const distFromTop = map.y;
            const stickyOffset = Math.max(0, topMargin - distFromTop);
            
            // Allow sticking until the bottom of the code text area
            // We want it to stop before it exits the block.
            const maxOffset = root.height - stickyButtonContainer.height;
            return Math.min(stickyOffset, maxOffset);
        }

        RowLayout {
            id: stickyButtonsRow
            anchors.centerIn: parent
            spacing: 5
            
            ButtonGroup {
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    colBackground: Appearance.m3colors.m3surfaceContainerHighest
                    buttonRadius: Appearance.rounding.small

                    onClicked: {
                        Quickshell.clipboardText = segmentContent
                        copyCodeButton.activated = true
                        copyIconTimer.restart()
                    }

                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy code")
                    }
                }
                AiMessageControlButton {
                    id: saveCodeButton
                    buttonIcon: activated ? "check" : "save"
                    colBackground: Appearance.m3colors.m3surfaceContainerHighest
                    buttonRadius: Appearance.rounding.small

                    onClicked: {
                        const downloadPath = FileUtils.trimFileProtocol(Directories.downloads)
                        Quickshell.execDetached(["bash", "-c", 
                            `echo '${StringUtils.shellSingleQuoteEscape(segmentContent)}' > '${downloadPath}/code.${segmentLang || "txt"}'`
                        ])
                        Quickshell.execDetached(["notify-send", 
                            Translation.tr("Code saved to file"), 
                            Translation.tr("Saved to %1").arg(`${downloadPath}/code.${segmentLang || "txt"}`),
                            "-a", "Shell"
                        ])
                        saveCodeButton.activated = true
                        saveIconTimer.restart()
                    }

                    Timer {
                        id: saveIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            saveCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Save to Downloads")
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: codeBlockComponentSpacing
    
        Rectangle { // Static Header text
            id: staticHeader
            Layout.fillWidth: true
            implicitHeight: staticHeaderRow.implicitHeight + codeBlockHeaderPadding * 2
            color: Appearance.colors.colSurfaceContainerHighest
            
            topRightRadius: codeBlockBackgroundRounding
            topLeftRadius: codeBlockBackgroundRounding
            bottomLeftRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen

            RowLayout {
                id: staticHeaderRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: codeBlockHeaderPadding
                anchors.rightMargin: codeBlockHeaderPadding // Leave space is implicit, but sticky covers it anyway

                StyledText {
                    id: codeBlockLanguage
                    Layout.alignment: Qt.AlignLeft
                    Layout.fillWidth: false
                    Layout.topMargin: 7
                    Layout.bottomMargin: 7
                    Layout.leftMargin: 10
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    text: root.displayLang ? Repository.definitionForName(root.displayLang).name : "plain"
                }
            }
        }

        RowLayout { // Line numbers and code
            spacing: codeBlockComponentSpacing

            Rectangle { // Line numbers
                implicitWidth: 40
                implicitHeight: lineNumberColumnLayout.implicitHeight
                Layout.fillHeight: true
                Layout.fillWidth: false
                topLeftRadius: Appearance.rounding.unsharpen
                bottomLeftRadius: codeBlockBackgroundRounding
                topRightRadius: Appearance.rounding.unsharpen
                bottomRightRadius: Appearance.rounding.unsharpen
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: lineNumberColumnLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        rightMargin: 5
                        top: parent.top
                        topMargin: 6
                    }
                    spacing: 0
                    
                    Repeater {
                        model: codeTextArea.text.split("\n").length
                        Text {
                            required property int index
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignRight
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            horizontalAlignment: Text.AlignRight
                            text: index + 1
                        }
                    }
                }
            }

            Rectangle { // Code background
                Layout.fillWidth: true
                topLeftRadius: Appearance.rounding.unsharpen
                bottomLeftRadius: Appearance.rounding.unsharpen
                topRightRadius: Appearance.rounding.unsharpen
                bottomRightRadius: codeBlockBackgroundRounding
                color: Appearance.colors.colLayer2
                implicitHeight: codeColumnLayout.implicitHeight

                ColumnLayout {
                    id: codeColumnLayout
                    anchors.fill: parent
                    spacing: 0
                    Flickable {
                        id: codeScrollView
                        Layout.fillWidth: true
                        implicitWidth: parent.width
                        implicitHeight: codeTextArea.implicitHeight + 2
                        contentWidth: Math.max(width, codeTextArea.implicitWidth)
                        contentHeight: codeTextArea.implicitHeight
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.horizontal: ScrollBar {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            padding: 5
                            policy: ScrollBar.AsNeeded
                            opacity: visualSize == 1 ? 0 : 1
                            visible: opacity > 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                            
                            contentItem: Rectangle {
                                implicitHeight: 6
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2Active
                            }
                        }

                        TextArea { // Code
                            id: codeTextArea
                            width: Math.max(parent.width, implicitWidth)
                            readOnly: !editing
                            selectByMouse: enableMouseSelection || editing
                            renderType: Text.NativeRendering
                            font.family: Appearance.font.family.monospace
                            font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                            font.pixelSize: Appearance.font.pixelSize.small
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            selectionColor: Appearance.colors.colSecondaryContainer
                            // wrapMode: TextEdit.Wrap
                            color: messageData.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1

                            text: segmentContent
                            onTextChanged: {
                                segmentContent = text
                            }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Tab) {
                                    // Insert 4 spaces at cursor
                                    const cursor = codeTextArea.cursorPosition;
                                    codeTextArea.insert(cursor, "    ");
                                    codeTextArea.cursorPosition = cursor + 4;
                                    event.accepted = true;
                                } else if ((event.key === Qt.Key_C) && event.modifiers == Qt.ControlModifier) {
                                    codeTextArea.copy();
                                    event.accepted = true;
                                }
                            }

                            SyntaxHighlighter {
                                id: highlighter
                                textEdit: codeTextArea
                                repository: Repository
                                definition: Repository.definitionForName(root.displayLang || "plaintext")
                                theme: Appearance.syntaxHighlightingTheme
                            }
                        }
                    }
                    Loader {
                        active: root.isCommandRequest && root.messageData.functionPending
                        visible: active
                        Layout.fillWidth: true
                        Layout.margins: 6
                        Layout.topMargin: 0
                        sourceComponent: RowLayout {
                            Item { Layout.fillWidth: true }
                            ButtonGroup {
                                GroupButton {
                                    contentItem: StyledText {
                                        text: Translation.tr("Reject")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    onClicked: Ai.rejectCommand(root.messageData)
                                }
                                GroupButton {
                                    toggled: true
                                    contentItem: StyledText {
                                        text: Translation.tr("Approve")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    onClicked: Ai.approveCommand(root.messageData)
                                }
                            }
                        }
                    }
                }

                // MouseArea to block scrolling
                // MouseArea {
                //     id: codeBlockMouseArea
                //     anchors.fill: parent
                //     acceptedButtons: editing ? Qt.NoButton : Qt.LeftButton
                //     cursorShape: (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
                //     onWheel: (event) => {
                //         event.accepted = false
                //     }
                // }
            }
        }
    }
}