import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool expanded: chatModel.count > 0
    property bool isLoading: false
    readonly property real compactHeight: 72
    readonly property real expandedHeight: 580
    implicitHeight: expanded ? expandedHeight : compactHeight
    implicitWidth: 800
    // Clip so content is masked by the shrinking container during collapse animation
    clip: true

    // showContent lags behind `expanded` on collapse: it stays true until
    // the height animation finishes so content doesn't vanish instantly.
    property bool showContent: false
    onExpandedChanged: {
        if (expanded) {
            showContent = true;
        } else {
            collapseContentTimer.restart();
        }
    }
    Timer {
        id: collapseContentTimer
        // Match the implicitHeight Behavior duration so content hides
        // only after the container has fully collapsed.
        interval: Appearance.animation.elementMove.duration
        onTriggered: root.showContent = false
    }

    // ─── Glow bar ──────────────────────────────────────────────────────
    Rectangle {
        id: assistantGlow
        // Anchored to inputToolbar after it's created — positioned via y binding
        height: 3; width: 0; radius: 2; opacity: 0; z: 10
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#4285F4" }
            GradientStop { position: 0.5; color: "#9B72CB" }
            GradientStop { position: 1.0; color: "#D96570" }
        }
        SequentialAnimation {
            id: wakeAnim; running: false
            ParallelAnimation {
                NumberAnimation { target: assistantGlow; property: "width"; from: 0; to: root.implicitWidth - 100; duration: 700; easing.type: Easing.OutExpo }
                NumberAnimation { target: assistantGlow; property: "opacity"; from: 0; to: 1; duration: 350 }
            }
            SequentialAnimation {
                loops: root.isLoading ? Animation.Infinite : 3
                NumberAnimation { target: assistantGlow; property: "opacity"; from: 1; to: 0.3; duration: 750; easing.type: Easing.InOutSine }
                NumberAnimation { target: assistantGlow; property: "opacity"; from: 0.3; to: 1; duration: 750; easing.type: Easing.InOutSine }
            }
            NumberAnimation { target: assistantGlow; property: "opacity"; to: 0; duration: 600 }
            NumberAnimation { target: assistantGlow; property: "width"; to: 0; duration: 1 }
        }
    }

    onVisibleChanged: {
        if (visible) wakeAnim.restart();
        else { wakeAnim.stop(); assistantGlow.opacity = 0; assistantGlow.width = 0; }
    }

    // ─── Data ──────────────────────────────────────────────────────────
    ListModel { id: chatModel }

    function parseMarkdown(text) {
        if (!text) return "";
        let html = text;
        html = html.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        html = html.replace(/```([\s\S]*?)```/g, (_, code) =>
            `<pre style='background:${Appearance.colors.colLayer1Base};padding:10px;border-radius:8px;font-family:monospace;'><code>${code}</code></pre>`);
        html = html.replace(/`([^`]+)`/g,
            `<code style='background:${Appearance.colors.colLayer1};padding:2px 6px;border-radius:4px;font-family:monospace;'>$1</code>`);
        html = html.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
        html = html.replace(/\*([^*]+)\*/g, "<i>$1</i>");
        html = html.replace(/^### (.+)$/mg, "<h3>$1</h3>");
        html = html.replace(/^## (.+)$/mg, "<h2>$1</h2>");
        html = html.replace(/^# (.+)$/mg, "<h1>$1</h1>");
        html = html.replace(/\n/g, "<br>");
        return html;
    }

    // ─── Network Request Process ───────────────────────────────────────
    Process {
        id: curlProcess
        property int loadingIndex: -1
        property string currentResponseText: ""
        stdout: SplitParser {
            onRead: data => {
                if (curlProcess.loadingIndex === -1) return;
                const trimmedData = data.trim();
                if (!trimmedData) return;
                
                // Parse SSE data
                if (trimmedData.startsWith("data: ")) {
                    try {
                        const jsonStr = trimmedData.substring(6);
                        const parsed = JSON.parse(jsonStr);
                        
                        if (parsed.text) {
                            // Turn off thinking state on first chunk
                            if (root.isLoading) {
                                root.isLoading = false;
                                curlProcess.currentResponseText = "";
                            }
                            
                            curlProcess.currentResponseText += parsed.text;
                            chatModel.setProperty(curlProcess.loadingIndex, "text", curlProcess.currentResponseText);
                        } else if (parsed.error) {
                            root.isLoading = false;
                            chatModel.setProperty(curlProcess.loadingIndex, "text", `⚠️ Error: ${parsed.error}`);
                        }
                    } catch (e) {
                        console.log("[Gemini Overlay] Error parsing SSE chunk:", e, data);
                    }
                }
            }
        }
        onExited: {
            root.isLoading = false;
            wakeAnim.restart();
            // If it exited but was still "loading", it means we got no chunks
            if (chatModel.get(curlProcess.loadingIndex).text === "...") {
                chatModel.setProperty(curlProcess.loadingIndex, "text", `⚠️ Connection closed unexpectedly`);
            }
            curlProcess.loadingIndex = -1;
        }
    }

    function sendMessage() {
        const prompt = inputField.text.trim();
        if (!prompt || root.isLoading) return;
        chatModel.append({ role: "user", text: prompt });
        inputField.clear();
        chatModel.append({ role: "bot", text: "..." });
        
        curlProcess.loadingIndex = chatModel.count - 1;
        curlProcess.currentResponseText = "...";
        root.isLoading = true;
        wakeAnim.restart();
        
        const payload = JSON.stringify({ prompt: prompt });
        // Use bash to construct the curl command properly
        curlProcess.command = [
            "bash", 
            "-c", 
            `curl -N -s -X POST http://127.0.0.1:8000/chat -H "Content-Type: application/json" -d '${payload.replace(/'/g, "'\\''")}'`
        ];
        curlProcess.running = true;
    }

    // ─── Height animation ──────────────────────────────────────────────
    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    // ─── Layout ────────────────────────────────────────────────────────
    // inputToolbar is anchored directly to root's bottom so it is ALWAYS
    // visible at the correct position. The ColumnLayout (topBar + chatList)
    // fills the space above it and gets clipped cleanly during collapse.
    ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputToolbar.top
        spacing: 0

        // ── Top App Bar ─────────────────────────────────────────────────
        Item {
            id: topBar
            Layout.fillWidth: true
            implicitHeight: 64
            visible: root.showContent

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 8
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                spacing: 12

                // Icon: spinner while loading, sparkle when idle
                Loader {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    sourceComponent: root.isLoading ? loadingComp : iconComp
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration }
                    }
                    Component {
                        id: loadingComp
                        MaterialLoadingIndicator {
                            implicitSize: 32; loading: true
                            shapeColor: Appearance.colors.colPrimary
                            color: "transparent"
                        }
                    }
                    Component {
                        id: iconComp
                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: Qt.rgba(Appearance.colors.colPrimary.r,
                                           Appearance.colors.colPrimary.g,
                                           Appearance.colors.colPrimary.b, 0.15)
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "auto_awesome"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colPrimary
                                fill: 1
                            }
                        }
                    }
                }

                // Title
                StyledText {
                    Layout.fillWidth: true
                    text: root.isLoading ? "Generating…" : "Gemini"
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.title
                }

                // Clear chat icon button
                RippleButton {
                    implicitWidth: 40; implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete_sweep"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                        fill: 0
                    }
                    StyledToolTip { text: "Clear chat" }
                    onClicked: chatModel.clear()
                }
            }

            // M3 divider
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.4
            }
        }

        // ── Chat list ───────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showContent
            clip: true

            StyledListView {
                id: chatList
                anchors.fill: parent
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                model: chatModel
                spacing: 8
                animateAppearance: true
                popin: true
                remove: Transition {}
                removeDisplaced: Transition {}
                onCountChanged: Qt.callLater(() => chatList.positionViewAtEnd())

                delegate: Item {
                    id: delegateRoot
                    width: ListView.view.width
                    height: bubbleLoader.implicitHeight + 12
                    readonly property bool isUser: model.role === "user"
                    readonly property bool isThinking: model.text === "..."

                    Loader {
                        id: bubbleLoader
                        width: parent.width
                        sourceComponent: delegateRoot.isUser ? userBubble : botBubble

                        // ── User bubble ─────────────────────────────────
                        Component {
                            id: userBubble
                            Item {
                                implicitHeight: userMsg.implicitHeight + 24
                                anchors.right: parent?.right

                                Rectangle {
                                    anchors.right: parent.right
                                    width: Math.min(userMsg.implicitWidth + 32, delegateRoot.width * 0.75)
                                    height: parent.implicitHeight
                                    radius: Appearance.rounding.large
                                    color: Appearance.colors.colSecondaryContainer

                                    StyledText {
                                        id: userMsg
                                        anchors {
                                            left: parent.left; leftMargin: 16
                                            right: parent.right; rightMargin: 16
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: model.text
                                        wrapMode: Text.WordWrap
                                        color: Appearance.colors.colOnSecondaryContainer
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                            }
                        }

                        // ── Bot bubble ──────────────────────────────────
                        Component {
                            id: botBubble
                            ColumnLayout {
                                spacing: 8
                                width: parent?.width ?? 0

                                // Thinking state
                                RowLayout {
                                    visible: delegateRoot.isThinking
                                    spacing: 12
                                    Layout.leftMargin: 8

                                    MaterialLoadingIndicator {
                                        implicitSize: 24; loading: true
                                        shapeColor: Appearance.colors.colPrimary
                                        color: "transparent"
                                    }
                                    StyledText {
                                        text: "Thinking…"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                // Bot Card
                                Rectangle {
                                    visible: !delegateRoot.isThinking
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: delegateRoot.width * 0.85
                                    implicitHeight: botContent.implicitHeight + 24
                                    radius: Appearance.rounding.large
                                    color: Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: botContent
                                        anchors {
                                            left: parent.left; leftMargin: 16
                                            right: parent.right; rightMargin: 16
                                            top: parent.top; topMargin: 12
                                        }
                                        spacing: 12

                                        // Response text
                                        Text {
                                            Layout.fillWidth: true
                                            text: parseMarkdown(model.text)
                                            textFormat: Text.RichText
                                            color: Appearance.colors.colOnLayer2
                                            font.family: Appearance.font.family.main
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            wrapMode: Text.WordWrap
                                            lineHeight: 1.5
                                            renderType: Text.NativeRendering
                                        }

                                        // Action Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 4
                                            spacing: 8

                                            // Copy chip — M3 assist chip style
                                            RippleButton {
                                                implicitWidth: copyRow.implicitWidth + 24
                                                implicitHeight: 32
                                                buttonRadius: Appearance.rounding.full
                                                colBackground: Appearance.colors.colLayer3
                                                
                                                property bool justCopied: false
                                                Timer {
                                                    id: resetCopy
                                                    interval: 1500
                                                    onTriggered: parent.justCopied = false
                                                }

                                                contentItem: RowLayout {
                                                    id: copyRow
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    MaterialSymbol {
                                                        text: parent.parent.justCopied ? "check" : "content_copy"
                                                        iconSize: Appearance.font.pixelSize.smaller
                                                        color: parent.parent.justCopied
                                                            ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colOnLayer2
                                                    }
                                                    StyledText {
                                                        text: parent.parent.justCopied ? "Copied" : "Copy"
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: parent.parent.justCopied
                                                            ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colOnLayer2
                                                    }
                                                }
                                                onClicked: {
                                                    Quickshell.clipboardText = model.text;
                                                    justCopied = true;
                                                    resetCopy.restart();
                                                }
                                            }

                                            Item { Layout.fillWidth: true } // Spacer
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Input area (M3 Search Bar) — anchored to root bottom ──────────────
    // Lives outside the ColumnLayout so topBar/chatList collapsing above it
    // can never squeeze it out of position.
    Rectangle {
        id: inputToolbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 8
        height: 56
        radius: Appearance.rounding.full

        // M3 Search Bar: surfaceContainerHighest
        color: Appearance.colors.colLayer3

        // Glow bar — bottom edge of the input pill
        Binding { target: assistantGlow; property: "x"
            value: inputToolbar.x + (inputToolbar.width - assistantGlow.width) / 2 }
        Binding { target: assistantGlow; property: "y"
            value: inputToolbar.y + inputToolbar.height - 2 }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 8

            // Leading AI sparkle icon
            MaterialSymbol {
                visible: !root.expanded
                Layout.alignment: Qt.AlignVCenter
                text: "auto_awesome"
                iconSize: Appearance.font.pixelSize.larger
                color: (inputField.text.trim().length > 0 || root.isLoading || inputField.activeFocus)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                fill: (root.isLoading || inputField.activeFocus) ? 1 : 0
                verticalAlignment: Text.AlignVCenter
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            // Text input
            ScrollView {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Math.min(inputField.implicitHeight, 100)
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                StyledTextArea {
                    id: inputField
                    placeholderText: "Ask Gemini…"
                    wrapMode: TextArea.Wrap
                    background: Item {}
                    topPadding: 0; bottomPadding: 0
                    verticalAlignment: TextArea.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.normal

                    Keys.onPressed: (event) => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && !(event.modifiers & Qt.ShiftModifier)) {
                            event.accepted = true;
                            sendMessage();
                        }
                    }
                }
            }

            // Send button — M3 Filled Tonal Icon Button (36px)
            RippleButton {
                id: sendButton
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: (inputField.text.trim().length > 0 || root.isLoading)
                    ? Appearance.colors.colPrimaryContainer
                    : "transparent"
                colRipple: Appearance.colors.colPrimaryContainer
                Behavior on colBackground {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isLoading ? "stop_circle" : "arrow_upward"
                    iconSize: Appearance.font.pixelSize.large
                    color: (inputField.text.trim().length > 0 || root.isLoading)
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colSubtext
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
                onClicked: { if (!root.isLoading) sendMessage(); }
            }
        }
    }
}




