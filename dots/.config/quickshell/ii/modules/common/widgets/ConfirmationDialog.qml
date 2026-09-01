import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    property bool show: false
    property string title: Translation.tr("Confirm")
    property string text: ""
    property string cancelText: Translation.tr("Cancel")
    property string confirmText: Translation.tr("OK")
    property bool isDestructive: false
    property real dialogWidth: 380

    signal confirmed()
    signal canceled()

    anchors.fill: parent
    z: 99
    visible: root.show || bgScrim.opacity > 0

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.canceled();
            event.accepted = true;
        }
    }

    // Scrim backdrop
    Rectangle {
        id: bgScrim
        anchors.fill: parent
        radius: Appearance.rounding.screenRounding
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
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: root.canceled()
        }
    }

    // Centered Dialog Card
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, root.dialogWidth)
        height: dialogColumn.implicitHeight + 48
        radius: Appearance.rounding.verylarge
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true

        StyledRectangularShadow {
            target: dialogCard
            opacity: dialogCard.opacity
        }

        property real animProgress: root.show ? 1 : 0
        opacity: animProgress
        scale: 0.92 + animProgress * 0.08
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
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onPressed: {} // Prevent dismissing when clicking inside card
        }

        ColumnLayout {
            id: dialogColumn
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12

            StyledText {
                Layout.fillWidth: true
                text: root.title
                color: Appearance.m3colors.m3onSurface
                wrapMode: Text.Wrap
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.larger
                    weight: Font.DemiBold
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.text.length > 0
                text: root.text
                color: Appearance.m3colors.m3onSurfaceVariant
                wrapMode: Text.WordWrap
                font {
                    family: Appearance.font.family.main
                    pixelSize: Appearance.font.pixelSize.small
                }
                lineHeight: 1.4
            }

            Item {
                implicitHeight: 12
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                DialogButton {
                    buttonText: root.cancelText
                    onClicked: root.canceled()
                }

                DialogButton {
                    buttonText: root.confirmText
                    colEnabled: root.isDestructive ? Appearance.colors.colError : Appearance.colors.colPrimary
                    colBackground: root.isDestructive ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                    colBackgroundHover: root.isDestructive ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryContainerHover
                    colRipple: root.isDestructive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    colText: root.isDestructive ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    onClicked: root.confirmed()
                }
            }
        }
    }
}
