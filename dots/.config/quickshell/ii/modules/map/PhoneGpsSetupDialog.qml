import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property bool show: false
    signal testRequested()
    signal closed()

    z: 10000
    visible: root.show || bgScrim.opacity > 0

    Component.onCompleted: {
        if (Window.window && Window.window.contentItem) {
            for (let i = Window.window.contentItem.children.length - 1; i >= 0; i--) {
                const child = Window.window.contentItem.children[i];
                if (child && child !== root && child.objectName === "phoneGpsSetupDialogOverlay") {
                    child.destroy();
                }
            }
            objectName = "phoneGpsSetupDialogOverlay";
            parent = Window.window.contentItem;
            anchors.fill = parent;
        }
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.show = false;
            root.closed();
            event.accepted = true;
        }
    }

    // Scrim backdrop
    Rectangle {
        id: bgScrim
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: root.show ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.show = false;
                root.closed();
            }
        }
    }

    // Modal Card
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.92, 540)
        implicitHeight: dialogLayout.implicitHeight + 40
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer3Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        StyledRectangularShadow {
            target: dialogCard
            opacity: dialogCard.opacity
        }

        property real animProgress: root.show ? 1 : 0
        opacity: animProgress
        scale: 0.94 + animProgress * 0.06
        transformOrigin: Item.Center

        Behavior on animProgress {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {} // Prevent dismissing when clicking inside card
        }

        ColumnLayout {
            id: dialogLayout
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "smartphone"
                    iconSize: 26
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Phone GPS Setup Guide")
                        font.family: Appearance.font.family.title
                        font.pixelSize: 18
                        font.bold: true
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: Translation.tr("Sync pinpoint GPS on-demand over local Wi-Fi with 0% battery drain.")
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.1)
                    onClicked: {
                        root.show = false;
                        root.closed();
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
            }

            // Step 1: Install Termux & Termux:API
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15)
                    StyledText {
                        anchors.centerIn: parent
                        text: "1"
                        font.bold: true
                        font.pixelSize: 12
                        color: Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Install Termux & Termux:API")
                        font.bold: true
                        font.pixelSize: 13
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Download official APKs from F-Droid or GitHub (do not use Google Play).")
                        font.pixelSize: 11
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // Step 2: Location Permission
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15)
                    StyledText {
                        anchors.centerIn: parent
                        text: "2"
                        font.bold: true
                        font.pixelSize: 12
                        color: Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Grant Location Permission")
                        font.bold: true
                        font.pixelSize: 13
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("In phone Settings → Apps → Termux:API → Permissions, enable Location with 'Precise location' ON.")
                        font.pixelSize: 11
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // Step 3: Run the GPS server
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15)
                    StyledText {
                        anchors.centerIn: parent
                        text: "3"
                        font.bold: true
                        font.pixelSize: 12
                        color: Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Run GPS Server in Termux")
                        font.bold: true
                        font.pixelSize: 13
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Paste this command in Termux to start the lightweight LAN server:")
                        font.pixelSize: 11
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Command Snippet Box
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cmdRow.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                RowLayout {
                    id: cmdRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: "termux-wake-lock && python ~/gps_server.py &"
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 11
                        color: Appearance.colors.colPrimary
                        elide: Text.ElideRight
                    }

                    RippleButtonWithIcon {
                        id: copyBtn
                        property bool copied: false
                        mainText: copied ? Translation.tr("Copied!") : Translation.tr("Copy")
                        materialIcon: copied ? "check" : "content_copy"
                        colBackground: Appearance.colors.colLayer2Base
                        iconColor: Appearance.colors.colOnLayer1
                        textColor: Appearance.colors.colOnLayer1
                        onClicked: {
                            Quickshell.execDetached(["wl-copy", "termux-wake-lock && python ~/gps_server.py &"]);
                            copied = true;
                            resetTimer.restart();
                        }

                        Timer {
                            id: resetTimer
                            interval: 2500
                            onTriggered: copyBtn.copied = false
                        }
                    }
                }
            }

            // Step 4: Network note
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15)
                    StyledText {
                        anchors.centerIn: parent
                        text: "4"
                        font.bold: true
                        font.pixelSize: 12
                        color: Appearance.colors.colPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Ensure Same Wi-Fi or Hotspot")
                        font.bold: true
                        font.pixelSize: 13
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Phone and laptop must be connected to the same local network or paired in KDE Connect.")
                        font.pixelSize: 11
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // Action Buttons Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.topMargin: 6

                Item { Layout.fillWidth: true }

                RippleButtonWithIcon {
                    mainText: Translation.tr("Close")
                    materialIcon: "close"
                    colBackground: Appearance.colors.colLayer2Base
                    iconColor: Appearance.colors.colOnSecondaryContainer
                    textColor: Appearance.colors.colOnSecondaryContainer
                    onClicked: {
                        root.show = false;
                        root.closed();
                    }
                }

                RippleButtonWithIcon {
                    mainText: Translation.tr("Test Connection")
                    materialIcon: "wifi_find"
                    colBackground: Appearance.colors.colPrimary
                    iconColor: Appearance.colors.colOnPrimary
                    textColor: Appearance.colors.colOnPrimary
                    onClicked: {
                        root.testRequested();
                    }
                }
            }
        }
    }
}
