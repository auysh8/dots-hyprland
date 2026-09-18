import QtQuick
import QtQuick.Effects
import qs.modules.common

Item {
    id: root

    property real railProgress: 0.0
    property real mainLeft: 0
    property real collapsedMainWidth: 420
    property real expandedMainWidth: 324
    property real shapeCenterY: height / 2
    property real shapeHeight: 48
    property real buttonDiameter: 40
    property real buttonGap: 8

    property color surfaceColor: Appearance.colors.colBackgroundSurfaceContainer
    property color shadowColor: Appearance.colors.colShadow
    property real shadowBlur: 0.5
    property real shadowVerticalOffset: 3

    readonly property real mainWidth: interpolate(collapsedMainWidth, expandedMainWidth, response(0, 6.2, 7.5, 0.4))
    readonly property real mainCenterX: mainLeft + mainWidth / 2
    readonly property real mainRight: mainLeft + mainWidth
    readonly property real expandedMainRight: mainLeft + expandedMainWidth
    readonly property vector4d mainShape: Qt.vector4d(mainCenterX, shapeCenterY, mainWidth, shapeHeight)

    function smoothstep(value) {
        const progress = Math.max(0, Math.min(1, value));
        return progress * progress * (3 - 2 * progress);
    }

    function stage(start, end) {
        if (end <= start) return root.railProgress >= end ? 1 : 0;
        return smoothstep((root.railProgress - start) / (end - start));
    }

    function interpolate(from, to, progress) {
        return from + (to - from) * progress;
    }

    function response(delay, decay, frequency, phase) {
        if (root.railProgress <= delay) return 0;
        const time = Math.max(0, Math.min(1, root.railProgress) - delay);
        const end = 1 - delay;
        const denom = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency * end));
        if (Math.abs(denom) < 0.0001) return 1;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency * time));
        return value / denom;
    }

    readonly property var travelDelays: [0.06, 0.036]
    readonly property var travelDecays: [7.2, 5.4]
    readonly property var travelFrequencies: [8.9, 6.2]
    readonly property var growthRates: [3.8, 3.1]

    function buttonGrowth(index) {
        if (index === 0)
            return response(0.01, 10.5, 10.5, 1);
        const rate = root.growthRates[index - 1];
        return response(0, rate, rate, 0);
    }

    function buttonCenterX(index) {
        const diameter = root.buttonDiameter;
        const emergence = diameter * 0.3 * (buttonGrowth(0) - 1);
        const firstCenter = root.expandedMainRight + root.buttonGap + diameter / 2 + emergence;
        if (index === 0)
            return firstCenter;
        const decay = root.travelDecays[index - 1];
        const frequency = root.travelFrequencies[index - 1];
        const travel = response(root.travelDelays[index - 1], decay, frequency, decay / frequency);
        return firstCenter + index * (diameter + root.buttonGap) * travel;
    }

    function buttonShape(index) {
        const diameter = root.buttonDiameter * buttonGrowth(index);
        return Qt.vector4d(buttonCenterX(index), root.shapeCenterY, Math.max(0.001, diameter), Math.max(0.001, diameter));
    }

    readonly property vector4d droplet0Shape: buttonShape(0)
    readonly property vector4d droplet1Shape: buttonShape(1)
    readonly property vector4d droplet2Shape: buttonShape(2)

    function buttonBlend(index) {
        const shape = index === 0 ? root.droplet0Shape : (index === 1 ? root.droplet1Shape : root.droplet2Shape);
        const previousCenter = index === 0 ? root.mainRight - root.shapeHeight / 2 : (index === 1 ? root.droplet0Shape.x : root.droplet1Shape.x);
        const radii = (root.shapeHeight / 2 + shape.z / 2);
        const separation = radii > 0 ? Math.abs(shape.x - previousCenter) / radii : 0;
        const exposed = smoothstep((separation - 0.25) / 0.55);
        const release = stage(0.27 + index * 0.063, 0.47 + index * 0.063);
        return Math.min(shape.z, shape.w, root.buttonDiameter) * 0.78 * exposed * (1 - release);
    }

    function iconProgress(index) {
        return stage(0.36 + index * 0.03, 0.55 + index * 0.03);
    }

    ShaderEffect {
        id: surfaceSource
        anchors.fill: parent
        visible: false

        property vector2d resolution: Qt.vector2d(width, height)
        property color fillColor: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 1)
        property vector4d mainShape: root.mainShape
        property vector4d droplet0Shape: root.droplet0Shape
        property vector4d droplet1Shape: root.droplet1Shape
        property vector4d droplet2Shape: root.droplet2Shape
        property vector4d blends: Qt.vector4d(root.buttonBlend(0), root.buttonBlend(1), root.buttonBlend(2), 0)

        fragmentShader: Qt.resolvedUrl("shaders/search_droplets_field.frag.qsb")
    }

    MultiEffect {
        anchors.fill: surfaceSource
        source: surfaceSource
        opacity: root.surfaceColor.a
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: root.shadowColor
        shadowBlur: root.shadowBlur
        shadowVerticalOffset: root.shadowVerticalOffset
        shadowHorizontalOffset: 0
    }
}
