import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property var device
    property bool expanded: false
    pointingHandCursor: !expanded

    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded
    
    component ActionButton: DialogButton {
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryHover
        colText: Appearance.colors.colOnPrimary
    }

    buttonRadius: 18
    horizontalPadding: 14
    verticalPadding: root.expanded ? 14 : 10

    colBackground: (root.device?.connected ?? false) 
        ? Appearance.colors.colPrimaryContainer 
        : Appearance.colors.colLayer1
    colBackgroundHover: (root.device?.connected ?? false) 
        ? Appearance.colors.colPrimaryContainerHover 
        : Appearance.colors.colLayer1Hover
    colRipple: (root.device?.connected ?? false) 
        ? Appearance.colors.colPrimaryContainerActive 
        : Appearance.colors.colLayer1Active

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // Left Icon Badge Container
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 36
                height: 36
                radius: 12
                color: (root.device?.connected ?? false) 
                    ? Appearance.colors.colPrimary 
                    : Appearance.colors.colLayer2

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    fill: 1
                    text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                    color: (root.device?.connected ?? false) 
                        ? Appearance.colors.colOnPrimary 
                        : Appearance.colors.colOnSurface
                }
            }

            // Middle Name & Status Subtitle
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    color: (root.device?.connected ?? false) 
                        ? Appearance.colors.colOnPrimaryContainer 
                        : Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                    renderType: Text.QtRendering
                    font.pixelSize: 14
                    font.weight: (root.device?.connected ?? false) ? Font.Bold : Font.Medium
                    text: root.device?.name || Translation.tr("Unknown device")
                    textFormat: Text.PlainText
                }

                StyledText {
                    visible: (root.device?.connected || root.device?.paired) ?? false
                    Layout.fillWidth: true
                    font.pixelSize: 12
                    color: (root.device?.connected ?? false) 
                        ? Appearance.colors.colOnPrimaryContainer 
                        : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    renderType: Text.QtRendering
                    text: {
                        if (!root.device?.paired) return "";
                        let statusText = root.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                        if (!root.device?.batteryAvailable) return statusText;
                        statusText += ` • ${Math.round(root.device?.battery * 100)}%`;
                        return statusText;
                    }
                    textFormat: Text.PlainText
                }
            }

            // Right Dropdown Expand Arrow
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "keyboard_arrow_down"
                iconSize: 20
                color: (root.device?.connected ?? false) 
                    ? Appearance.colors.colOnPrimaryContainer 
                    : Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.topMargin: 8
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                readonly property bool p: root.device?.paired ?? false
                buttonText: p ? Translation.tr("Forget") : Translation.tr("Always connect")
                onClicked: {
                    if (root.device?.paired) {
                        root.device?.forget();
                    } else {
                        root.device?.pair();
                    }
                }
            }
            ActionButton {
                buttonText: root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: {
                    if (root.device?.connected) {
                        root.device.disconnect();
                    } else {
                        root.device.connect();
                    }
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
