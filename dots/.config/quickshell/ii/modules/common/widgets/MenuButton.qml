import qs.modules.common
import QtQuick

RippleButton {
    id: root

    property string iconText: "" // Optional MaterialSymbol glyph rendered before the label

    buttonRadius: 0
    implicitHeight: 36
    property bool hasIcon: root.iconText !== ""
    // Fixed-width icon slot: MaterialSymbol glyphs have differing intrinsic
    // widths, so without a fixed slot the label x-offset shifts per glyph.
    // A constant slot keeps every row aligned (icons centered, labels at the
    // same x) regardless of which icon is used.
    readonly property real iconSlotWidth: 20
    implicitWidth: (root.hasIcon ? root.iconSlotWidth + 12 : 0) + buttonTextWidget.implicitWidth + 14 * 2

    contentItem: Item {
        anchors.fill: parent

        // Fixed-size icon slot; glyph is centered inside it
        Item {
            id: iconSlot
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasIcon
            width: root.iconSlotWidth
            height: root.iconSlotWidth
            // Bound the glyph: Material Symbols ligatures (e.g. push_pin,
            // delete) can paint outside their advance box, which bleeds out of
            // the slot into the label/neighboring rows. An explicit box +
            // center alignment (same pattern as the save button) plus clip
            // keeps every menu row visually identical.
            clip: true

            MaterialSymbol {
                id: iconTextWidget
                anchors.centerIn: parent
                width: root.iconSlotWidth
                height: root.iconSlotWidth
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.iconText
                iconSize: 18
                color: root.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
            }
        }
        StyledText {
            id: buttonTextWidget
            anchors.left: root.hasIcon ? iconSlot.right : parent.left
            anchors.leftMargin: root.hasIcon ? 12 : 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.buttonText
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

}
