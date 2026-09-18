import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property bool draggable: false
    readonly property bool hovered: pointerArea.containsMouse
    readonly property bool dragging: pointerArea.dragging

    signal dragPositionChanged(real localX, real localY)
    signal nudgeRequested(real horizontalPixels, real verticalPixels)

    implicitWidth: 48
    implicitHeight: 48
    activeFocusOnTab: root.draggable

    Keys.onPressed: event => {
        if (!root.draggable)
            return;

        const step = (event.modifiers & Qt.ShiftModifier) !== 0 ? 20 : 4;
        if (event.key === Qt.Key_Left)
            root.nudgeRequested(-step, 0);
        else if (event.key === Qt.Key_Right)
            root.nudgeRequested(step, 0);
        else if (event.key === Qt.Key_Up)
            root.nudgeRequested(0, -step);
        else if (event.key === Qt.Key_Down)
            root.nudgeRequested(0, step);
        else
            return;
        event.accepted = true;
    }

    // Outer ripple ring on hover/drag
    Rectangle {
        anchors.centerIn: parent
        width: root.dragging ? 44 : (root.hovered || root.activeFocus ? 40 : 34)
        height: width
        radius: width / 2
        color: ColorUtils.transparentize(
            Appearance.colors.colPrimary,
            root.dragging ? 0.65 : (root.hovered || root.activeFocus ? 0.78 : 0.88)
        )

        Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    // Outer pin badge
    Rectangle {
        id: pinBadge
        anchors.centerIn: parent
        width: 26
        height: 26
        radius: width / 2
        color: Appearance.colors.colLayer0
        border.width: 2
        border.color: Appearance.colors.colPrimary

        // Inner center dot
        Rectangle {
            anchors.centerIn: parent
            width: 14
            height: 14
            radius: width / 2
            color: Appearance.colors.colPrimary
        }
    }

    MouseArea {
        id: pointerArea

        property bool dragging: false
        property real pressOffsetX: 0
        property real pressOffsetY: 0

        anchors.fill: parent
        enabled: root.draggable
        hoverEnabled: true
        preventStealing: true
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        onPressed: mouse => {
            root.forceActiveFocus();
            dragging = true;
            pressOffsetX = mouse.x - width / 2;
            pressOffsetY = mouse.y - height / 2;
        }

        onPositionChanged: mouse => {
            if (pressed)
                root.dragPositionChanged(mouse.x - pressOffsetX, mouse.y - pressOffsetY);
        }

        onReleased: dragging = false
        onCanceled: dragging = false
    }
}
