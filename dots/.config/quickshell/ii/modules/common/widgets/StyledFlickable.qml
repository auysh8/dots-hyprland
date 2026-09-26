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

    WheelHandler {
        id: wheelHandler
        enabled: root.interactive && ((Config && Config.options && Config.options.interactions && Config.options.interactions.scrolling && Config.options.interactions.scrolling.fasterTouchpadScroll !== undefined) ? Config.options.interactions.scrolling.fasterTouchpadScroll : true)
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (wheelEvent) => {
            if (root.isHorizontal) {
                const hasHorizontalDelta = Math.abs(wheelEvent.angleDelta.x) > 0;
                const isShiftWheel = (wheelEvent.modifiers & Qt.ShiftModifier) && Math.abs(wheelEvent.angleDelta.y) > 0;
                const shouldScrollHorizontal = hasHorizontalDelta || isShiftWheel || root.invertWheelToHorizontal;

                if (shouldScrollHorizontal) {
                    const rawDelta = hasHorizontalDelta ? wheelEvent.angleDelta.x : wheelEvent.angleDelta.y;
                    const delta = rawDelta / root.mouseScrollDeltaThreshold;
                    var scrollFactor = Math.abs(rawDelta) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;

                    const minX = -root.leftMargin;
                    const maxX = Math.max(minX, root.contentWidth + root.rightMargin - root.width);
                    const base = scrollAnimX.running ? root.scrollTargetX : root.contentX;
                    var targetX = Math.max(minX, Math.min(base - delta * scrollFactor, maxX));

                    root.scrollTargetX = targetX;
                    root.contentX = targetX;
                    wheelEvent.accepted = true;
                } else {
                    wheelEvent.accepted = false;
                }
            } else {
                const delta = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
                var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;

                const minY = -root.topMargin;
                const maxY = Math.max(minY, root.contentHeight + root.bottomMargin - root.height);
                const base = scrollAnim.running ? root.scrollTargetY : root.contentY;
                var targetY = Math.max(minY, Math.min(base - delta * scrollFactor, maxY));

                root.scrollTargetY = targetY;
                root.contentY = targetY;
                wheelEvent.accepted = true;
            }
        }
    }

    onMovementStarted: {
        scrollAnim.stop();
        scrollAnimX.stop();
        root.scrollTargetY = root.contentY;
        root.scrollTargetX = root.contentX;
    }

    Behavior on contentY {
        enabled: !root.isHorizontal && !root.moving && !root.flicking
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    Behavior on contentX {
        enabled: root.isHorizontal && !root.moving && !root.flicking
        NumberAnimation {
            id: scrollAnimX
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    onContentYChanged: {
        if (!scrollAnim.running) {
            root.scrollTargetY = root.contentY;
        }
    }

    onContentXChanged: {
        if (!scrollAnimX.running) {
            root.scrollTargetX = root.contentX;
        }
    }
}
