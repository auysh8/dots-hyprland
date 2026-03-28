import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Slider {
    id: root

    property color highlightColor: Appearance.colors.colPrimary
    property color trackColor: Appearance.colors.colSecondaryContainer
    property color handleColor: Appearance.colors.colPrimary
    property bool wavy: false
    property bool animateWave: true
    property real trackWidth: wavy ? 4 : 6
    property real handleHeight: 24
    property real handleDefaultWidth: 3
    property real handlePressedWidth: 1.5
    property real handleMargins: 4
    property real waveAmplitudeMultiplier: wavy ? 0.5 : 0
    property real waveFrequency: 6
    property real stopDotSize: 3

    leftPadding: handleMargins
    rightPadding: handleMargins

    readonly property real effectiveDraggingWidth: width - leftPadding - rightPadding
    readonly property real handleWidth: pressed ? handlePressedWidth : handleDefaultWidth
    readonly property real handleCenterX: leftPadding + visualPosition * effectiveDraggingWidth
    readonly property real handleGap: handleMargins + handleWidth / 2
    readonly property real leftFillWidth: Math.max(0, leftPadding + visualPosition * effectiveDraggingWidth - handleGap)
    readonly property real rightFillX: handleCenterX + handleGap
    readonly property real rightFillWidth: Math.max(0, (1 - visualPosition) * effectiveDraggingWidth - handleGap + rightPadding)

    Layout.fillWidth: true
    from: 0
    to: 1

    Behavior on trackWidth {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    Behavior on waveAmplitudeMultiplier {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => mouse.accepted = false
        cursorShape: root.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    }

    background: Item {
        anchors.fill: parent

        Item {
            id: leftFill
            x: 0
            width: root.leftFillWidth
            height: parent.height
            clip: true

            Rectangle {
                visible: root.waveAmplitudeMultiplier <= 0.01
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: root.trackWidth
                radius: height / 2
                color: root.highlightColor
            }

            WavyLine {
                id: wavyFill
                visible: root.wavy || root.waveAmplitudeMultiplier > 0.01
                anchors.fill: parent
                amplitudeMultiplier: root.waveAmplitudeMultiplier
                frequency: root.waveFrequency
                color: root.highlightColor
                lineWidth: root.trackWidth
                fullLength: Math.max(root.width, 1)

                FrameAnimation {
                    running: root.animateWave && (root.wavy || root.waveAmplitudeMultiplier > 0.01)
                    onTriggered: wavyFill.requestPaint()
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.rightFillX
            width: root.rightFillWidth
            height: root.trackWidth
            radius: height / 2
            color: root.trackColor
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.width - root.rightPadding - width
            width: root.stopDotSize
            height: root.stopDotSize
            radius: height / 2
            color: root.highlightColor
        }
    }

    handle: Rectangle {
        implicitWidth: root.handleWidth
        implicitHeight: root.handleHeight
        x: root.handleCenterX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        radius: Appearance.rounding.full
        color: root.handleColor

        Behavior on implicitWidth {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }
}
