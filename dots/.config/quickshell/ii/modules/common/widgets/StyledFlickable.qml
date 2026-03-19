import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    
    property real scrollTargetY: contentY

    ScrollBar.vertical: StyledScrollBar {}

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: Config?.options?.interactions?.scrolling?.fasterTouchpadScroll ?? true
        
        onWheel: (event) => {
            const delta = event.angleDelta.y / root.mouseScrollDeltaThreshold;
            const scrollFactor = Math.abs(event.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;
            const maxY = Math.max(0, root.contentHeight - root.height);
            
            var newTargetY = Math.max(0, Math.min(root.scrollTargetY - (delta * scrollFactor), maxY));
            root.scrollTargetY = newTargetY;
            
            wheelAnim.to = newTargetY;
            wheelAnim.restart();
            
            event.accepted = true;
        }
    }

    NumberAnimation {
        id: wheelAnim
        target: root
        property: "contentY"
        duration: Appearance.animation.scroll.duration
        easing.type: Appearance.animation.scroll.type
        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
    }

    onMovementStarted: {
        wheelAnim.stop();
        scrollTargetY = contentY;
    }
    
    onFlickStarted: {
        wheelAnim.stop();
        scrollTargetY = contentY;
    }
    
    onContentHeightChanged: {
        if (!wheelAnim.running) scrollTargetY = contentY;
    }
    
    onVisibleChanged: {
        if (visible) {
            wheelAnim.stop();
            scrollTargetY = contentY;
        }
    }
}
