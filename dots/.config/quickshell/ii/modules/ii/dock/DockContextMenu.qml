import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var appToplevel
    property Item targetButton
    property alias isOpen: menuLoader.active
    readonly property var desktopEntry: appToplevel ? DesktopEntries.heuristicLookup(appToplevel.appId) : null
    readonly property bool hasWindows: Boolean(appToplevel && appToplevel.toplevels && appToplevel.toplevels.length > 0)
    readonly property bool hasDesktopActions: Boolean(desktopEntry && desktopEntry.actions && desktopEntry.actions.length > 0)

    function open(button, appToplevelData) {
        if (menuLoader.item && typeof menuLoader.item.forceClose === "function")
            menuLoader.item.forceClose();
        else if (menuLoader.active)
            menuLoader.active = false;
        targetButton = button;
        appToplevel = appToplevelData;
        menuLoader.active = true;
    }

    function close() {
        if (!menuLoader.active) return;
        if (menuLoader.item && typeof menuLoader.item.close === "function")
            menuLoader.item.close();
        else
            menuLoader.active = false;
    }

    Loader {
        id: menuLoader
        active: false
        sourceComponent: PopupWindow {
            id: contextPopup
            visible: true
            property bool closing: false
            property real revealProgress: 0

            anchor {
                window: root.targetButton?.QsWindow?.window ?? root.QsWindow?.window
                item: root.targetButton
                gravity: Edges.Top
                edges: Edges.Top
                adjustment: PopupAdjustment.SlideX
            }

            HyprlandFocusGrab {
                id: focusGrab
                active: false
                windows: [contextPopup]
                onCleared: root.close()
            }

            Timer {
                id: grabTimer
                interval: Appearance.animation.elementMoveFast.duration + 40
                running: true
                onTriggered: {
                    if (menuLoader.active && !contextPopup.closing) {
                        focusGrab.active = true;
                    }
                }
            }

            Component.onCompleted: openAnim.start();

            function close() {
                if (closing) return;
                closing = true;
                focusGrab.active = false;
                closeAnim.restart();
            }

            function forceClose() {
                closing = false;
                focusGrab.active = false;
                openAnim.stop();
                closeAnim.stop();
                menuLoader.active = false;
            }

            color: "transparent"
            implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            NumberAnimation {
                id: openAnim
                target: contextPopup
                property: "revealProgress"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }

            SequentialAnimation {
                id: closeAnim
                NumberAnimation {
                    target: contextPopup
                    property: "revealProgress"
                    to: 0
                    duration: Math.max(120, Appearance.animation.elementMoveFast.duration - 40)
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                ScriptAction {
                    script: {
                        contextPopup.closing = false;
                        menuLoader.active = false;
                    }
                }
            }

            StyledRectangularShadow {
                target: menuBackground
                opacity: contextPopup.revealProgress
                visible: opacity > 0
            }

            Rectangle {
                id: menuBackground
                property real padding: 4
                opacity: contextPopup.revealProgress
                scale: 0.96 + contextPopup.revealProgress * 0.04
                transformOrigin: Item.Bottom
                transform: Translate {
                    y: (1 - contextPopup.revealProgress) * 10
                }

                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: Appearance.sizes.elevationMargin
                }
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                implicitWidth: menuColumn.implicitWidth + padding * 2
                implicitHeight: menuColumn.implicitHeight + padding * 2

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        fill: parent
                        margins: parent.padding
                    }
                    spacing: 0

                    // Desktop entry actions
                    Repeater {
                        model: root.hasDesktopActions ? root.desktopEntry.actions : []
                        delegate: ContextMenuItem {
                            required property var modelData
                            Layout.fillWidth: true
                            iconName: modelData.icon ?? ""
                            label: modelData.name
                            onClicked: {
                                modelData.execute();
                                root.close();
                            }
                        }
                    }

                    // Separator after desktop actions
                    Loader {
                        active: root.hasDesktopActions
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Open new instance
                    ContextMenuItem {
                        Layout.fillWidth: true
                        iconName: "open_in_new"
                        label: "Open new instance"
                        enabled: root.desktopEntry !== null
                        onClicked: {
                            root.desktopEntry?.execute();
                            root.close();
                        }
                    }

                    // Separator
                    ContextMenuSeparator {
                        Layout.fillWidth: true
                    }

                    // Move to workspace (only when has windows)
                    Loader {
                        active: root.hasWindows
                        Layout.fillWidth: true
                        sourceComponent: ColumnLayout {
                            spacing: 0

                            ContextMenuItem {
                                Layout.fillWidth: true
                                iconName: "move_item"
                                label: "Move to workspace"
                                enabled: false
                                pointingHandCursor: false
                            }

                            RowLayout {
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                Layout.bottomMargin: 4
                                spacing: 2

                                Repeater {
                                    model: 10
                                    delegate: RippleButton {
                                        id: wsButton
                                        required property int index
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.small
                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: String(wsButton.index + 1)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            horizontalAlignment: Text.AlignHCenter
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            const ws = wsButton.index + 1;
                                            for (const toplevel of root.appToplevel.toplevels) {
                                                const addr = `0x${toplevel.HyprlandToplevel?.address}`;
                                                Hyprland.dispatch(`movetoworkspacesilent ${ws},address:${addr}`);
                                            }
                                            root.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Pin / Unpin
                    ContextMenuItem {
                        Layout.fillWidth: true
                        iconName: TaskbarApps.isPinned(root.appToplevel?.appId ?? "") ? "keep_off" : "keep"
                        label: TaskbarApps.isPinned(root.appToplevel?.appId ?? "") ? "Unpin" : "Pin to dock"
                        onClicked: {
                            TaskbarApps.togglePin(root.appToplevel.appId);
                            root.close();
                        }
                    }

                    // Separator before close (only when has windows)
                    Loader {
                        active: root.hasWindows
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Close window(s) (only when has windows)
                    Loader {
                        active: root.hasWindows
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuItem {
                            iconName: "close"
                            label: (root.appToplevel?.toplevels.length ?? 0) > 1 ? "Close all windows" : "Close window"
                            onClicked: {
                                for (const toplevel of root.appToplevel.toplevels) {
                                    toplevel.close();
                                }
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }

    component ContextMenuItem: RippleButton {
        id: menuItemRoot
        property string iconName
        property string label
        implicitHeight: 36
        implicitWidth: Math.max(itemRow.implicitWidth + 20, 180)
        buttonRadius: Appearance.rounding.small

        contentItem: RowLayout {
            id: itemRow
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 14
            }
            spacing: 8

            MaterialSymbol {
                text: menuItemRoot.iconName
                iconSize: Appearance.font.pixelSize.normal
                color: menuItemRoot.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                visible: menuItemRoot.iconName !== ""
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                Layout.fillWidth: true
                text: menuItemRoot.label
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.small
                color: menuItemRoot.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                elide: Text.ElideRight
            }
        }
    }

    component ContextMenuSeparator: Item {
        Layout.fillWidth: true
        implicitHeight: 9

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 10
                rightMargin: 10
            }
            implicitHeight: 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
        }
    }
}
