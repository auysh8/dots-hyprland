import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TabButton {
    id: root

    property bool toggled: TabBar.tabBar.currentIndex === TabBar.index
    property string buttonIcon
    property real buttonIconRotation: 0
    property string buttonText
    property bool expanded: false
    property bool showToggledHighlight: true
    readonly property real visualWidth: root.expanded ? root.baseSize + 20 + itemText.implicitWidth : root.baseSize

    // Optional color overrides — leave unset for default shell colors
    property color overrideActiveColor: "transparent"
    property color overrideActiveHoverColor: "transparent"
    property color overrideIconColor: "transparent"
    property color overrideTextColor: "transparent"
    property bool useOverrideColors: false

    property real baseSize: 54
    property real baseHighlightHeight: 32
    property real highlightCollapsedTopMargin: 2
    padding: 0

    // The navigation item’s target area always spans the full width of the
    // nav rail, even if the item container hugs its contents.
    Layout.fillWidth: true
    // implicitWidth: contentItem.implicitWidth
    implicitHeight: baseSize

    background: null
    PointingHandInteraction {}

    // Real stuff
    contentItem: Item {
        id: buttonContent
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: undefined
        }
        
        implicitWidth: root.visualWidth
        implicitHeight: root.expanded ? itemIconBackground.implicitHeight : itemIconBackground.implicitHeight + itemText.implicitHeight 

        Rectangle {
            id: itemBackground
            anchors.top: itemIconBackground.top
            anchors.left: itemIconBackground.left
            anchors.bottom: itemIconBackground.bottom
            implicitWidth: root.visualWidth
            radius: Appearance.rounding.full
            color: toggled ? 
                root.showToggledHighlight ?
                    (root.useOverrideColors 
                        ? (root.down ? Qt.darker(root.overrideActiveColor, 1.1) : root.hovered ? root.overrideActiveHoverColor : root.overrideActiveColor)
                        : (root.down ? Appearance.colors.colSecondaryContainerActive : root.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer))
                    : (root.useOverrideColors 
                        ? ColorUtils.transparentize(root.overrideActiveColor, 0.5)
                        : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer)) :
                (root.down ? Appearance.colors.colLayer1Active : root.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))

            states: State {
                name: "expanded"
                when: root.expanded
                AnchorChanges {
                    target: itemBackground
                    anchors.top: buttonContent.top
                    anchors.left: buttonContent.left
                    anchors.bottom: buttonContent.bottom
                }
                PropertyChanges {
                    target: itemBackground
                    implicitWidth: root.visualWidth
                }
            }
            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                PropertyAnimation {
                    target: itemBackground
                    property: "implicitWidth"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Item {
            id: itemIconBackground
            implicitWidth: root.baseSize
            implicitHeight: root.baseHighlightHeight
            anchors {
                left: parent.left
                top: root.expanded ? undefined : parent.top
                topMargin: root.expanded ? 0 : 2
                verticalCenter: root.expanded ? parent.verticalCenter : undefined
            }
            MaterialSymbol {
                id: navRailButtonIcon
                rotation: root.buttonIconRotation
                anchors.centerIn: parent
                iconSize: 24
                fill: 1
                font.weight: (toggled || root.hovered) ? Font.DemiBold : Font.Normal
                text: buttonIcon
                color: toggled 
                    ? (root.useOverrideColors ? root.overrideIconColor : Appearance.m3colors.m3onSecondaryContainer) 
                    : (root.useOverrideColors ? root.overrideTextColor : Appearance.colors.colOnLayer1)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledText {
            id: itemText
            anchors {
                top: itemIconBackground.bottom
                topMargin: 2
                horizontalCenter: itemIconBackground.horizontalCenter
            }
            states: State {
                name: "expanded"
                when: root.expanded
                AnchorChanges {
                    target: itemText
                    anchors {
                        top: undefined
                        horizontalCenter: undefined
                        left: itemIconBackground.right
                        verticalCenter: itemIconBackground.verticalCenter
                    }
                }
            }
            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            text: buttonText
            font.pixelSize: 13
            font.weight: toggled ? Font.Bold : Font.Medium
            color: root.useOverrideColors ? root.overrideTextColor : Appearance.colors.colOnLayer1
        }
    }

}
