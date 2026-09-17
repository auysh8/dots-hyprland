import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

Item {
    id: root

    property vector2d mainCenter: Qt.vector2d(0, 0)
    property vector2d mainSize: Qt.vector2d(0, 0)
    property real mainRadius: 0
    property vector2d satelliteCenter: Qt.vector2d(0, 0)
    property vector2d satelliteSize: Qt.vector2d(0, 0)
    property real satelliteRadius: 0
    property real blendRadius: 0

    property color surfaceColor: Appearance.colors.colLayer0
    property real edgeSoftness: 0.8
    property bool shadowEnabled: true

    component MorphShader: ShaderEffect {
        anchors.fill: parent

        property vector2d resolution: Qt.vector2d(width, height)
        property color fillColor: root.surfaceColor
        property vector2d mainCenter: root.mainCenter
        property vector2d mainSize: root.mainSize
        property real mainRadius: root.mainRadius
        property vector2d satelliteCenter: root.satelliteCenter
        property vector2d satelliteSize: root.satelliteSize
        property real satelliteRadius: root.satelliteRadius
        property real blendRadius: root.blendRadius
        property real edgeSoftness: root.edgeSoftness

        fragmentShader: Qt.resolvedUrl("../shaders/pill_morph.frag.qsb")
    }

    MorphShader {}
}
