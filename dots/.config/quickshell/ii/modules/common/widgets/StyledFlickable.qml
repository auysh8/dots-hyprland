import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    property real touchpadScrollFactor: (Config && Config.options && Config.options.interactions && Config.options.interactions.scrolling) ? Config.options.interactions.scrolling.touchpadScrollFactor : 100
    property real mouseScrollFactor: (Config && Config.options && Config.options.interactions && Config.options.interactions.scrolling) ? Config.options.interactions.scrolling.mouseScrollFactor : 50
    property real mouseScrollDeltaThreshold: (Config && Config.options && Config.options.interactions && Config.options.interactions.scrolling) ? Config.options.interactions.scrolling.mouseScrollDeltaThreshold : 120
    
    property real scrollTargetY: 0
    property real scrollTargetX: 0
    property bool showHorizontalScrollBar: false
    property bool invertWheelToHorizontal: false
    readonly property bool isHorizontal: root.flickableDirection === Flickable.HorizontalFlick || (root.contentWidth > root.width && root.contentHeight <= root.height)

    ScrollBar.vertical: StyledScrollBar {
        visible: !root.isHorizontal
    }
    ScrollBar.horizontal: StyledScrollBar {
        orientation: Qt.Horizontal
        visible: root.isHorizontal && root.showHorizontalScrollBar
    }

    MouseArea {
        visible: (Config && Config.options && Config.options.interactions && Config.options.interactions.scrolling && Config.options.interactions.scrolling.fasterTouchpadScroll !== undefined) ? Config.options.interactions.scrolling.fasterTouchpadScroll : true
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        propagateComposedEvents: true

        onPressed: mouse => mouse.accepted = false
        onReleased: mouse => mouse.accepted = false
        onClicked: mouse => mouse.accepted = false
        onDoubleClicked: mouse => mouse.accepted = false
        onPressAndHold: mouse => mouse.accepted = false
        onWheel: function(wheelEvent) {
            if (root.isHorizontal) {
                const hasHorizontalDelta = Math.abs(wheelEvent.angleDelta.x) > 0;
                const isShiftWheel = (wheelEvent.modifiers & Qt.ShiftModifier) && Math.abs(wheelEvent.angleDelta.y) > 0;
                const shouldScrollHorizontal = hasHorizontalDelta || isShiftWheel || root.invertWheelToHorizontal;

                if (shouldScrollHorizontal) {
                    const rawDelta = hasHorizontalDelta ? wheelEvent.angleDelta.x : wheelEvent.angleDelta.y;
                    const delta = rawDelta / root.mouseScrollDeltaThreshold;
                    var scrollFactor = Math.abs(rawDelta) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;

                    const maxX = Math.max(0, root.contentWidth - root.width);
                    const base = root.contentX;
                    var targetX = Math.max(0, Math.min(base - delta * scrollFactor, maxX));

                    root.scrollTargetX = targetX;
                    root.contentX = targetX;
                    wheelEvent.accepted = true;
                } else {
                    wheelEvent.accepted = false;
                }
            } else {
                const delta = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
                var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;

                const maxY = Math.max(0, root.contentHeight - root.height);
                const base = root.contentY;
                var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

                root.scrollTargetY = targetY;
                root.contentY = targetY;
                wheelEvent.accepted = true;
            }
        }
    }

    onMovementStarted: {
        root.scrollTargetY = root.contentY;
        root.scrollTargetX = root.contentX;
    }

    Behavior on contentY {
        enabled: !root.isHorizontal
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    Behavior on contentX {
        enabled: root.isHorizontal
        NumberAnimation {
            id: scrollAnimX
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    onContentYChanged: {
        root.scrollTargetY = root.contentY;
    }

    onContentXChanged: {
        root.scrollTargetX = root.contentX;
    }
}
