import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Popup {
    id: root

    property Item anchorItem
    property var options: []
    property int selectedValue: -1
    property bool openAbove: false
    signal valueSelected(int value)

    parent: anchorItem ? anchorItem : undefined
    x: anchorItem ? (anchorItem.width - width) : 0
    y: openAbove ? (-height - 6) : (anchorItem ? (anchorItem.height + 6) : 0)
    width: 240
    padding: 6
    modal: false
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    transformOrigin: openAbove ? Item.BottomRight : Item.TopRight

    property real _lastClosedAt: 0
    onClosed: _lastClosedAt = Date.now()

    function toggle() {
        if (opened) {
            close();
        } else {
            if (Date.now() - _lastClosedAt < 200) return;
            open();
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        NumberAnimation {
            property: "scale"
            from: 0.88
            to: 1.0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            property: "scale"
            from: 1.0
            to: 0.88
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    background: Item {
        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.m3colors.m3surfaceContainerHigh ?? (Appearance.m3colors.darkmode ? "#2b2a2a" : "#f3edf7")
            border.width: 1
            border.color: Appearance.colors.colLayer0Border ?? Appearance.m3colors.m3outlineVariant
        }
    }

    contentItem: Column {
        spacing: 2
        width: parent.width

        Repeater {
            model: root.options

            delegate: RippleButton {
                id: itemBtn
                required property var modelData
                width: parent.width
                implicitHeight: 38
                buttonRadius: Appearance.rounding.verysmall
                colBackground: itemBtn.modelData.value === root.selectedValue ? 
                    (Appearance.colors.colSecondaryContainer ?? "#3a383f") : "transparent"
                colBackgroundHover: itemBtn.modelData.value === root.selectedValue ? 
                    (Appearance.colors.colSecondaryContainerHover ?? "#45434a") :
                    ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.07)

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    MaterialSymbol {
                        text: itemBtn.modelData.icon || ""
                        iconSize: 18
                        color: itemBtn.modelData.value === root.selectedValue ? 
                            (Appearance.colors.colOnSecondaryContainer ?? Appearance.colors.colPrimary) : 
                            Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: itemBtn.modelData.label
                        color: itemBtn.modelData.value === root.selectedValue ? 
                            (Appearance.colors.colOnSecondaryContainer ?? Appearance.colors.colOnSurface) : 
                            Appearance.colors.colOnSurface
                        font.pixelSize: 13
                        font.bold: itemBtn.modelData.value === root.selectedValue
                        elide: Text.ElideRight
                    }

                    MaterialSymbol {
                        visible: itemBtn.modelData.value === root.selectedValue
                        text: "check"
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer ?? Appearance.colors.colPrimary
                    }
                }

                onClicked: {
                    root.valueSelected(Number(itemBtn.modelData.value));
                    root.close();
                }
            }
        }
    }
}
