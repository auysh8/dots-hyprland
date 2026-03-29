import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    property bool toggled
    property string buttonText
    property bool pointingHandCursor: true
    property real buttonRadius: Appearance?.rounding?.small ?? 4
    property real buttonRadiusPressed: buttonRadius
    property real buttonEffectiveRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property int rippleDuration: 800
    property bool rippleEnabled: true
    property var downAction // When left clicking (down)
    property var releaseAction // When left clicking (release)
    property var altAction // When right clicking
    property var middleClickAction // When middle clicking

    property color colBackground: ColorUtils.transparentize(Appearance?.colors.colLayer1Hover, 1) || "transparent"
    property color colBackgroundHover: colBackground
    property color colBackgroundToggled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colBackgroundToggledHover: colBackgroundToggled
    property color colRipple: ColorUtils.transparentize(Appearance?.colors.colOnSurface ?? "#FFFFFF", 0.85)
    property color colRippleToggled: ColorUtils.transparentize(Appearance?.colors.colOnPrimary ?? "#FFFFFF", 0.85)

    opacity: root.enabled ? 1 : 0.4
    property color buttonColor: ColorUtils.transparentize(root.toggled ? 
        (root.hovered ? colBackgroundToggledHover : 
            colBackgroundToggled) :
        (root.hovered ? colBackgroundHover : 
            colBackground), root.enabled ? 0 : 1)
    property color rippleColor: root.toggled ? colRippleToggled : colRipple

    function cancelRipple() { rippleFadeAnim.restart(); }

    function startRipple(x, y) {
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;

        const dist = (ox,oy) => ox*ox + oy*oy
        const stateEndY = stateY + buttonBackground.height
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)))

        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        scrollGestureEnabled: false
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (event) => { 
            if(event.button === Qt.RightButton) {
                if (root.altAction) root.altAction(event);
                return;
            }
            if(event.button === Qt.MiddleButton) {
                if (root.middleClickAction) root.middleClickAction();
                return;
            }
            root.down = true
            if (root.downAction) root.downAction();
            if (!root.rippleEnabled) return;
            const {x,y} = event
            startRipple(x, y)
        }
        onReleased: (event) => {
            root.down = false
            if (event.button != Qt.LeftButton) return;
            if (root.releaseAction) root.releaseAction();
            root.click() // Because the MouseArea already consumed the event
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
        onCanceled: (event) => {
            root.down = false
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim

        property real x
        property real y
        property real radius

        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1.0
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Item {
        id: buttonBackground
        implicitHeight: 30

        Rectangle {
            id: bgRect
            anchors.fill: parent
            radius: root.buttonEffectiveRadius
            color: root.buttonColor
            Behavior on color {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        
        // M3 State Layer Overlay
        Rectangle {
            id: stateLayer
            anchors.fill: parent
            radius: root.buttonEffectiveRadius
            color: root.rippleColor
            opacity: root.down ? 0.1 : (root.hovered ? 0.04 : 0)
            
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
            }
        }

        Item {
            id: rippleMaskTarget
            anchors.fill: parent
            visible: false
            
            Rectangle {
                anchors.fill: parent
                radius: root.buttonEffectiveRadius
            }
        }

        Item {
            id: rippleContainer
            anchors.fill: parent
            visible: ripple.opacity > 0
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: rippleMaskTarget
            }

            Rectangle {
                id: ripple
                width: ripple.implicitWidth
                height: ripple.implicitHeight
                radius: width / 2
                color: ColorUtils.applyAlpha(root.rippleColor, 0.25)
                opacity: 0
                visible: width > 0 && height > 0

                property real implicitWidth: 0
                property real implicitHeight: 0

                Behavior on opacity {
                    animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                transform: Translate {
                    x: -ripple.width / 2
                    y: -ripple.height / 2
                }
            }
        }
    }

    contentItem: StyledText {
        text: root.buttonText
    }
}
