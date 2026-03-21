import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

Flickable {
    id: root

    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds
    flickableDirection: Flickable.HorizontalFlick

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    property real scrollTargetX: 0

    MouseArea {
        visible: Config?.options?.interactions?.scrolling?.fasterTouchpadScroll ?? true
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        propagateComposedEvents: true

        onPressed: mouse => mouse.accepted = false
        onReleased: mouse => mouse.accepted = false
        onClicked: mouse => mouse.accepted = false
        onDoubleClicked: mouse => mouse.accepted = false
        onPressAndHold: mouse => mouse.accepted = false

        onWheel: function(wheelEvent) {
            const absX = Math.abs(wheelEvent.angleDelta.x);
            const absY = Math.abs(wheelEvent.angleDelta.y);
            // Relax the angle to allow slight vertical deviation (e.g. up to 1.5x) when scrolling horizontally
            if (absY > absX * 1.5) {
                wheelEvent.accepted = false;
                return;
            }

            const rawDelta = absX > 0 ? wheelEvent.angleDelta.x : wheelEvent.angleDelta.y;
            const delta = rawDelta / root.mouseScrollDeltaThreshold;
            const scrollFactor = Math.abs(rawDelta) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;

            const maxX = Math.max(0, root.contentWidth - root.width);
            const base = scrollAnim.running ? root.scrollTargetX : root.contentX;
            const targetX = Math.max(0, Math.min(base - delta * scrollFactor, maxX));

            root.scrollTargetX = targetX;
            scrollAnim.stop();
            scrollAnim.to = targetX;
            scrollAnim.start();
            wheelEvent.accepted = true;
        }
    }

    onMovementStarted: {
        scrollAnim.stop()
        root.scrollTargetX = root.contentX
    }

    NumberAnimation {
        id: scrollAnim
        target: root
        property: "contentX"
        duration: Appearance.animation.scroll.duration
        easing.type: Appearance.animation.scroll.type
        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
    }

    onContentXChanged: {
        if (!scrollAnim.running) {
            root.scrollTargetX = root.contentX;
        }
    }
}
