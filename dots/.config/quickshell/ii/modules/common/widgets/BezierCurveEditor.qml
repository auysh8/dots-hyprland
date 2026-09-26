import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var curve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0]
    property var workingCurve: curve
    property string easingMode: "customBezier"
    readonly property bool editable: easingMode === "customBezier"
    property real chartSize: 280
    property real chartWidth: chartSize
    property real chartHeight: 330
    property int activePoint: -1
    property bool playing: false
    property int playbackDirection: 1
    property real playhead: 0
    property int playDurationMs: 1200
    property int editingCoordinate: -1
    property string coordinateDraft: ""
    property bool coordinateInvalid: false
    property real renderX1: 0.43
    property real renderY1: 1.19
    property real renderX2: 1.0
    property real renderY2: 0.4
    property var animationTargetCurve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0]
    property bool curveAnimationActive: false
    property bool curveAnimationCommit: false

    property color chartSurfaceColor: Appearance.colors.colLayer1
    property color chartAxisColor: ColorUtils.applyAlpha(Appearance.colors.colOnSurfaceVariant, 0.3)
    property color chartPrimaryColor: Appearance.colors.colPrimary
    property color chartSecondaryColor: Appearance.colors.colSecondary
    property color chartTertiaryColor: Appearance.colors.colTertiary

    signal controlsEdited(var nextCurve)
    signal editRequested()

    implicitWidth: chartWidth
    implicitHeight: chartColumn.implicitHeight

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function clamp01(value) {
        return clamp(value, 0, 1);
    }

    function defaultCurve() {
        return [0.43, 1.19, 1.0, 0.4, 1.0, 1.0];
    }

    function normalizedCurve(source) {
        const defaults = defaultCurve();
        const next = [];
        for (let i = 0; i < 6; i += 1) {
            const value = source && source.length > i ? Number(source[i]) : defaults[i];
            next.push(isFinite(value) ? value : defaults[i]);
        }
        next[4] = 1;
        next[5] = 1;
        return next;
    }

    function dimensionWithinUnit(p1, p2) {
        if (!isFinite(p1) || !isFinite(p2)) return false;
        const epsilon = 0.0001;
        const values = [0, 1];
        const a = 3 * p1 - 3 * p2 + 1;
        const b = -4 * p1 + 2 * p2;
        const c = p1;

        function addRoot(t) {
            if (isFinite(t) && t > epsilon && t < 1 - epsilon)
                values.push(cubicCoord(t, p1, p2));
        }

        if (Math.abs(a) < 0.000001) {
            if (Math.abs(b) >= 0.000001) addRoot(-c / b);
        } else {
            const discriminant = b * b - 4 * a * c;
            if (discriminant >= -epsilon) {
                const rootVal = Math.sqrt(Math.max(0, discriminant));
                addRoot((-b + rootVal) / (2 * a));
                addRoot((-b - rootVal) / (2 * a));
            }
        }

        for (let i = 0; i < values.length; i += 1) {
            if (values[i] < -epsilon || values[i] > 1 + epsilon) return false;
        }
        return true;
    }

    function dimensionMonotonicIncreasing(p1, p2) {
        if (!isFinite(p1) || !isFinite(p2)) return false;
        const epsilon = 0.0001;
        const a = 3 * p1 - 3 * p2 + 1;
        const b = -4 * p1 + 2 * p2;
        const c = p1;
        const values = [c, a + b + c];

        if (Math.abs(a) >= 0.000001) {
            const t = -b / (2 * a);
            if (t > epsilon && t < 1 - epsilon)
                values.push(a * t * t + b * t + c);
        }

        for (let i = 0; i < values.length; i += 1) {
            if (values[i] < -epsilon) return false;
        }
        return true;
    }

    function curveWithinUnit(crv) {
        const next = normalizedCurve(crv);
        const xValid = isFinite(next[0]) && isFinite(next[2]) && next[0] >= 0 && next[0] <= 1 && next[2] >= 0 && next[2] <= 1;
        const yValid = isFinite(next[1]) && isFinite(next[3]) && next[1] >= -2.0 && next[1] <= 3.0 && next[3] >= -2.0 && next[3] <= 3.0;
        return xValid && yValid;
    }

    function safeCurve(source) {
        const next = normalizedCurve(source);
        return curveWithinUnit(next) ? next : defaultCurve();
    }

    function setRenderCurve(nextCurve) {
        const next = normalizedCurve(nextCurve);
        renderX1 = next[0];
        renderY1 = next[1];
        renderX2 = next[2];
        renderY2 = next[3];
        chart.requestPaint();
    }

    function rawP1() { return [renderX1, renderY1]; }
    function rawP2() { return [renderX2, renderY2]; }
    function displayPoint(point) { return [clamp01(point[0]), point[1]]; }

    function formatNumber(value) {
        const rounded = Math.round(value * 100) / 100;
        return rounded.toFixed(2).replace(/\.?0+$/, "");
    }

    function cubicCoord(t, a, b) {
        const u = 1 - t;
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
    }

    function presetValueAt(t) {
        const mode = easingMode;
        if (mode === "linear") return t;
        if (mode === "quad") return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
        if (mode === "cubic") return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
        if (mode === "quart") return t < 0.5 ? 8 * Math.pow(t, 4) : 1 - Math.pow(-2 * t + 2, 4) / 2;
        if (mode === "quint") return t < 0.5 ? 16 * Math.pow(t, 5) : 1 - Math.pow(-2 * t + 2, 5) / 2;
        if (mode === "sine") return -(Math.cos(Math.PI * t) - 1) / 2;
        if (mode === "expo") {
            if (t === 0 || t === 1) return t;
            return t < 0.5 ? Math.pow(2, 20 * t - 10) / 2 : (2 - Math.pow(2, -20 * t + 10)) / 2;
        }
        if (mode === "circ") {
            return t < 0.5 ? (1 - Math.sqrt(1 - Math.pow(2 * t, 2))) / 2 : (Math.sqrt(1 - Math.pow(-2 * t + 2, 2)) + 1) / 2;
        }
        return t;
    }

    function customBezierValueAt(x) {
        const p1 = rawP1();
        const p2 = rawP2();
        let lo = 0;
        let hi = 1;
        let s = x;
        for (let i = 0; i < 18; i += 1) {
            s = (lo + hi) / 2;
            if (cubicCoord(s, p1[0], p2[0]) < x) lo = s;
            else hi = s;
        }
        return cubicCoord(s, p1[1], p2[1]);
    }

    function valueAt(t) {
        if (easingMode === "customBezier") return customBezierValueAt(t);
        return presetValueAt(t);
    }

    function curvePathPoint(t) {
        return [t, valueAt(t)];
    }

    function plotX(x) { return chart.plotLeft + clamp01(x) * chart.plotSize; }
    function plotY(y) { return chart.plotTop + (1.0 - y) * chart.plotSize; }

    function visualPoint(p) {
        const px = clamp(plotX(p[0]), 16, chart.width - 16);
        const py = clamp(plotY(p[1]), 16, chart.height - 16);
        return [px, py];
    }

    function pointFromMouse(mx, my) {
        const clampedX = clamp((mx - chart.plotLeft) / chart.plotSize, 0, 1);
        const clampedPixelY = clamp(my, 16, chart.height - 16);
        const calcY = 1.0 - (clampedPixelY - chart.plotTop) / chart.plotSize;
        return [
            Math.round(clampedX * 100) / 100,
            Math.round(calcY * 100) / 100
        ];
    }

    function distToSegment(px, py, x1, y1, x2, y2) {
        const dx = x2 - x1;
        const dy = y2 - y1;
        const l2 = dx * dx + dy * dy;
        if (l2 === 0) return Math.hypot(px - x1, py - y1);
        let t = ((px - x1) * dx + (py - y1) * dy) / l2;
        t = Math.max(0, Math.min(1, t));
        return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
    }

    function hitTest(mx, my) {
        if (!editable) return -1;
        const v1 = visualPoint(rawP1());
        const v2 = visualPoint(rawP2());
        const d1 = Math.hypot(mx - v1[0], my - v1[1]);
        const d2 = Math.hypot(mx - v2[0], my - v2[1]);
        if (d1 < 24 || d2 < 24) return d1 <= d2 ? 0 : 1;

        // Tangent arm grab tolerance: allow grabbing by clicking anywhere along the arm
        const startX = plotX(0);
        const startY = plotY(0);
        const endX = plotX(1);
        const endY = plotY(1);
        const lineD1 = distToSegment(mx, my, startX, startY, v1[0], v1[1]);
        const lineD2 = distToSegment(mx, my, endX, endY, v2[0], v2[1]);
        if (lineD1 < 14) return 0;
        if (lineD2 < 14) return 1;

        return -1;
    }

    function coordinateListText() {
        const p1 = rawP1();
        const p2 = rawP2();
        return formatNumber(p1[0]) + ", " + formatNumber(p1[1]) + ", " + formatNumber(p2[0]) + ", " + formatNumber(p2[1]);
    }

    function copyCoordinateList() {
        Quickshell.execDetached(["wl-copy", coordinateListText()]);
    }

    function coordinateFallback(index) {
        const defaults = [0.43, 1.19, 1.0, 0.4];
        return defaults[index] || 0;
    }

    function coordinateValue(index) {
        const values = [renderX1, renderY1, renderX2, renderY2];
        const value = Number(values[index]);
        return isFinite(value) ? value : coordinateFallback(index);
    }

    function coordinateText(index) {
        return formatNumber(coordinateValue(index));
    }

    function openCoordinateField(index) {
        if (!editable) return;
        editingCoordinate = index;
        coordinateDraft = coordinateText(index);
        coordinateInvalid = false;
    }

    function applyCoordinateField() {
        if (editingCoordinate < 0) return;
        const value = Number(coordinateDraft.trim());
        if (!isFinite(value)) {
            coordinateInvalid = true;
            return;
        }

        const next = workingCurve.slice();
        while (next.length < 6) next.push(1);
        next[editingCoordinate] = value;
        next[4] = 1;
        next[5] = 1;
        if (!curveWithinUnit(next)) {
            coordinateInvalid = true;
            return;
        }

        workingCurve = next;
        setRenderCurve(next);
        controlsEdited(next);
        editingCoordinate = -1;
        coordinateInvalid = false;
        chart.requestPaint();
    }

    function cancelCoordinateField() {
        editingCoordinate = -1;
        coordinateInvalid = false;
    }

    function startPlayback() {
        if (playhead >= 1) playhead = 0;
        playbackDirection = 1;
        playing = true;
        playbackAnimation.from = playhead;
        playbackAnimation.to = 1;
        playbackAnimation.duration = Math.max(160, Math.round(playDurationMs * (1 - playhead)));
        playbackAnimation.start();
    }

    function togglePlayback() {
        if (playing) {
            playbackAnimation.stop();
            playing = false;
            return;
        }
        startPlayback();
    }

    function reversePlayback() {
        playbackAnimation.stop();
        playing = false;
        if (playhead <= 0) playhead = 1;
        playbackDirection = -1;
        playing = true;
        playbackAnimation.from = playhead;
        playbackAnimation.to = 0;
        playbackAnimation.duration = Math.max(160, Math.round(playDurationMs * playhead));
        playbackAnimation.start();
    }

    function flipCurve() {
        if (!editable) return;
        const p1 = rawP1();
        const p2 = rawP2();
        const next = [1 - p2[0], 1 - p2[1], 1 - p1[0], 1 - p1[1], 1, 1];
        animateCurveTo(next, true);
    }

    function resetCurve() {
        if (!editable) return;
        animateCurveTo(defaultCurve(), true);
    }

    function animateCurveTo(nextCurve, commit) {
        const next = normalizedCurve(nextCurve);
        if (!curveWithinUnit(next)) return;
        curveAnimationCommit = false;
        controlPointAnimation.stop();
        animationTargetCurve = next;
        curveAnimationCommit = !!commit;
        curveAnimationActive = true;
        controlPointAnimation.start();
    }

    function animationReachedTarget() {
        const next = animationTargetCurve;
        return Math.abs(renderX1 - next[0]) < 0.0001 && Math.abs(renderY1 - next[1]) < 0.0001 &&
               Math.abs(renderX2 - next[2]) < 0.0001 && Math.abs(renderY2 - next[3]) < 0.0001;
    }

    function repaintChart() {
        if (chart) chart.requestPaint();
    }

    onCurveChanged: {
        if (activePoint < 0 && !curveAnimationActive) {
            workingCurve = safeCurve(curve);
            setRenderCurve(workingCurve);
        }
        chart.requestPaint();
    }
    onWorkingCurveChanged: {
        if (!curveAnimationActive) setRenderCurve(workingCurve);
        chart.requestPaint();
    }
    onEasingModeChanged: chart.requestPaint()
    onPlayheadChanged: chart.requestPaint()
    onWidthChanged: chart.requestPaint()
    onHeightChanged: chart.requestPaint()
    onRenderX1Changed: repaintChart()
    onRenderY1Changed: repaintChart()
    onRenderX2Changed: repaintChart()
    onRenderY2Changed: repaintChart()

    NumberAnimation {
        id: playbackAnimation
        target: root
        property: "playhead"
        to: 1
        easing.type: Easing.Linear
        onStopped: {
            if ((root.playbackDirection > 0 && root.playhead >= 1) || (root.playbackDirection < 0 && root.playhead <= 0))
                root.playing = false;
        }
    }

    ParallelAnimation {
        id: controlPointAnimation

        NumberAnimation {
            target: root
            property: "renderX1"
            to: root.animationTargetCurve[0]
            duration: 250
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "renderY1"
            to: root.animationTargetCurve[1]
            duration: 250
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "renderX2"
            to: root.animationTargetCurve[2]
            duration: 250
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "renderY2"
            to: root.animationTargetCurve[3]
            duration: 250
            easing.type: Easing.OutCubic
        }

        onStopped: {
            if (!root.curveAnimationActive) return;
            const shouldCommit = root.curveAnimationCommit && root.animationReachedTarget();
            root.curveAnimationActive = false;
            root.curveAnimationCommit = false;
            if (shouldCommit) {
                root.workingCurve = root.animationTargetCurve;
                root.controlsEdited(root.animationTargetCurve);
            }
            chart.requestPaint();
        }
    }

    Component.onCompleted: {
        workingCurve = safeCurve(curve);
        setRenderCurve(workingCurve);
    }

    ColumnLayout {
        id: chartColumn
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width > 0 ? parent.width : root.chartWidth, root.chartWidth)
        spacing: 10

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.chartWidth
            Layout.preferredHeight: root.chartHeight
            implicitWidth: root.chartWidth
            implicitHeight: root.chartHeight
            width: root.chartWidth
            height: root.chartHeight

            Canvas {
                id: chart
                anchors.fill: parent
                readonly property real plotLeft: 45
                readonly property real plotTop: 64
                readonly property real plotSize: 190

                onPaint: {
                    const ctx = getContext("2d");
                    if (!ctx) return;
                    ctx.clearRect(0, 0, width, height);

                    const left = plotLeft;
                    const top = plotTop;
                    const size = plotSize;
                    const right = left + size;
                    const bottom = top + size;
                    const p1 = root.rawP1();
                    const p2 = root.rawP2();
                    const startX = root.plotX(0);
                    const startY = root.plotY(0);
                    const endX = root.plotX(1);
                    const endY = root.plotY(1);

                    function drawRoundedBox(x, y, w, h, r) {
                        ctx.beginPath();
                        if (typeof ctx.roundRect === "function") {
                            ctx.roundRect(x, y, w, h, r);
                        } else {
                            ctx.moveTo(x + r, y);
                            ctx.arcTo(x + w, y, x + w, y + h, r);
                            ctx.arcTo(x + w, y + h, x, y + h, r);
                            ctx.arcTo(x, y + h, x, y, r);
                            ctx.arcTo(x, y, x + w, y, r);
                            ctx.closePath();
                        }
                    }

                    // 1. Outer background card
                    ctx.fillStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.05);
                    drawRoundedBox(2, 2, width - 4, height - 4, 16);
                    ctx.fill();
                    ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.10);
                    ctx.lineWidth = 1.0;
                    drawRoundedBox(2, 2, width - 4, height - 4, 16);
                    ctx.stroke();

                    // 2. Unit grid box [0, 1] x [0, 1]
                    ctx.fillStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.04);
                    drawRoundedBox(left, top, size, size, 8);
                    ctx.fill();

                    // Grid lines (25%, 50%, 75%)
                    ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.07);
                    ctx.lineWidth = 1.0;
                    for (let step = 1; step <= 3; step++) {
                        const gx = left + (size * step) / 4;
                        const gy = top + (size * step) / 4;
                        ctx.beginPath();
                        ctx.moveTo(gx, top);
                        ctx.lineTo(gx, bottom);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(left, gy);
                        ctx.lineTo(right, gy);
                        ctx.stroke();
                    }

                    // Unit box border
                    ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.22);
                    ctx.lineWidth = 1.4;
                    drawRoundedBox(left, top, size, size, 8);
                    ctx.stroke();

                    // 3. Diagonal reference line (0,0) to (1,1)
                    ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.25);
                    ctx.lineWidth = 1.2;
                    if (typeof ctx.setLineDash === "function") ctx.setLineDash([4, 4]);
                    ctx.beginPath();
                    ctx.moveTo(startX, startY);
                    ctx.lineTo(endX, endY);
                    ctx.stroke();
                    if (typeof ctx.setLineDash === "function") ctx.setLineDash([]);

                    // 4. Tangent guide lines
                    if (root.editable) {
                        const v1 = root.visualPoint(p1);
                        const v2 = root.visualPoint(p2);
                        ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.75);
                        ctx.lineWidth = 1.5;
                        if (typeof ctx.setLineDash === "function") ctx.setLineDash([4, 4]);
                        ctx.beginPath();
                        ctx.moveTo(startX, startY);
                        ctx.lineTo(v1[0], v1[1]);
                        ctx.moveTo(endX, endY);
                        ctx.lineTo(v2[0], v2[1]);
                        ctx.stroke();
                        if (typeof ctx.setLineDash === "function") ctx.setLineDash([]);
                    }

                    // 5. Main Bézier Curve
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.strokeStyle = Appearance.colors.colPrimary;
                    ctx.lineWidth = 3.4;
                    ctx.beginPath();
                    for (let i = 0; i <= 100; i += 1) {
                        const point = root.curvePathPoint(i / 100);
                        const px = root.plotX(point[0]);
                        const py = root.plotY(point[1]);
                        if (i === 0) ctx.moveTo(px, py);
                        else ctx.lineTo(px, py);
                    }
                    ctx.stroke();

                    // 6. Playhead trail
                    if (root.playhead > 0) {
                        const trailSteps = Math.max(1, Math.round(root.playhead * 100));
                        ctx.strokeStyle = Appearance.colors.colTertiary || Appearance.colors.colPrimary;
                        ctx.lineWidth = 3.4;
                        ctx.beginPath();
                        for (let i = 0; i <= trailSteps; i += 1) {
                            const point = root.curvePathPoint((i / trailSteps) * root.playhead);
                            const px = root.plotX(point[0]);
                            const py = root.plotY(point[1]);
                            if (i === 0) ctx.moveTo(px, py);
                            else ctx.lineTo(px, py);
                        }
                        ctx.stroke();
                    }

                    // 7. Control Points handles (P1 and P2)
                    function drawControlPoint(px, py, selected) {
                        // Outer halo
                        ctx.fillStyle = ColorUtils.applyAlpha(Appearance.colors.colPrimary, selected ? 0.35 : 0.15);
                        ctx.beginPath();
                        ctx.arc(px, py, selected ? 14 : 11, 0, Math.PI * 2);
                        ctx.fill();

                        // Inner dot
                        ctx.fillStyle = selected ? (Appearance.colors.colTertiary || Appearance.colors.colPrimary) : Appearance.colors.colSecondary;
                        ctx.strokeStyle = Appearance.colors.colSurface || "#ffffff";
                        ctx.lineWidth = 2.0;
                        ctx.beginPath();
                        ctx.arc(px, py, selected ? 7 : 6, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.stroke();
                    }

                    if (root.editable) {
                        const v1 = root.visualPoint(p1);
                        const v2 = root.visualPoint(p2);
                        drawControlPoint(v1[0], v1[1], root.activePoint === 0);
                        drawControlPoint(v2[0], v2[1], root.activePoint === 1);
                    }

                    // 8. Animated Playhead Ball
                    const playPoint = root.curvePathPoint(root.playhead);
                    const bX = root.plotX(playPoint[0]);
                    const bY = root.plotY(playPoint[1]);

                    // Glow aura
                    ctx.fillStyle = ColorUtils.applyAlpha(Appearance.colors.colTertiary || Appearance.colors.colPrimary, 0.35);
                    ctx.beginPath();
                    ctx.arc(bX, bY, 13, 0, Math.PI * 2);
                    ctx.fill();

                    // Solid core
                    ctx.fillStyle = Appearance.colors.colTertiary || Appearance.colors.colPrimary;
                    ctx.strokeStyle = "#ffffff";
                    ctx.lineWidth = 2.0;
                    ctx.beginPath();
                    ctx.arc(bX, bY, 7, 0, Math.PI * 2);
                    ctx.fill();
                    ctx.stroke();
                }
            }

            MouseArea {
                anchors.fill: chart
                acceptedButtons: Qt.LeftButton
                enabled: root.editable
                hoverEnabled: true
                preventStealing: true
                cursorShape: root.activePoint >= 0 || root.hitTest(mouseX, mouseY) >= 0
                             ? Qt.PointingHandCursor : Qt.ArrowCursor

                onPressed: mouse => {
                    if (mouse.button !== Qt.LeftButton) {
                        mouse.accepted = false;
                        return;
                    }
                    const hit = root.hitTest(mouse.x, mouse.y);
                    if (hit < 0) {
                        mouse.accepted = false;
                        return;
                    }
                    root.activePoint = hit;
                    mouse.accepted = true;
                    chart.requestPaint();
                }

                onDoubleClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        root.editRequested();
                    }
                }

                onPositionChanged: mouse => {
                    if (root.activePoint < 0) return;
                    const point = root.pointFromMouse(mouse.x, mouse.y);
                    const next = root.workingCurve.slice();
                    if (root.activePoint === 0) {
                        next[0] = point[0];
                        next[1] = point[1];
                    } else {
                        next[2] = point[0];
                        next[3] = point[1];
                    }
                    next[4] = 1;
                    next[5] = 1;
                    if (!root.curveWithinUnit(next)) return;
                    root.workingCurve = next;
                    chart.requestPaint();
                }

                onReleased: {
                    if (root.activePoint >= 0)
                        root.controlsEdited(root.workingCurve);
                    root.activePoint = -1;
                    chart.requestPaint();
                }

                onCanceled: {
                    root.workingCurve = root.safeCurve(root.curve);
                    root.activePoint = -1;
                    chart.requestPaint();
                }
            }
        }

        // Action Toolbar: Play/Pause, Replay, Flip, Reset, Expand, Copy
        ButtonGroup {
            id: actionButtonGroup
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            padding: 0
            color: "transparent"

            GroupButton {
                id: playBtn
                Layout.fillWidth: true
                baseWidth: 34
                baseHeight: 34
                clickedWidth: baseWidth + (isAtSide ? 8 : 14)
                buttonRadius: 17
                buttonRadiusPressed: 12
                bounce: true
                toggled: root.playing

                colBackground: root.playing ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colBackgroundHover: root.playing ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                colBackgroundActive: root.playing ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Hover
                onClicked: root.togglePlayback()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.playing ? "pause" : "play_arrow"
                    iconSize: 18
                    fill: 1
                    color: root.playing ? Appearance.colors.colOnPrimary : (playBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2)
                }

                StyledToolTip {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Play / Pause") : "Play / Pause"
                }
            }

            GroupButton {
                id: replayBtn
                Layout.fillWidth: true
                baseWidth: 34
                baseHeight: 34
                clickedWidth: baseWidth + (isAtSide ? 8 : 14)
                buttonRadius: 17
                buttonRadiusPressed: 12
                bounce: true

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Hover
                onClicked: root.reversePlayback()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "replay"
                    iconSize: 18
                    fill: 1
                    color: replayBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Replay") : "Replay"
                }
            }

            GroupButton {
                id: flipBtn
                Layout.fillWidth: true
                baseWidth: 34
                baseHeight: 34
                clickedWidth: baseWidth + (isAtSide ? 8 : 14)
                buttonRadius: 17
                buttonRadiusPressed: 12
                bounce: true
                enabled: root.editable
                opacity: enabled ? 1 : 0.4

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Hover
                onClicked: root.flipCurve()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "swap_vert"
                    iconSize: 18
                    fill: 1
                    color: flipBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Invert Curve") : "Invert Curve"
                }
            }

            GroupButton {
                id: resetBtn
                Layout.fillWidth: true
                baseWidth: 34
                baseHeight: 34
                clickedWidth: baseWidth + (isAtSide ? 8 : 14)
                buttonRadius: 17
                buttonRadiusPressed: 12
                bounce: true
                enabled: root.editable
                opacity: enabled ? 1 : 0.4

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Hover
                onClicked: root.resetCurve()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "restart_alt"
                    iconSize: 18
                    fill: 1
                    color: resetBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Reset to Default") : "Reset to Default"
                }
            }

            GroupButton {
                id: expandBtn
                Layout.fillWidth: true
                baseWidth: 34
                baseHeight: 34
                clickedWidth: baseWidth + (isAtSide ? 8 : 14)
                buttonRadius: 17
                buttonRadiusPressed: 12
                bounce: true
                enabled: root.editable
                opacity: enabled ? 1 : 0.4

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Hover
                onClicked: root.editRequested()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "open_in_full"
                    iconSize: 18
                    fill: 1
                    color: expandBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Open in Full Editor") : "Open in Full Editor"
                }
            }

            GroupButton {
                id: copyBtn
                Layout.fillWidth: true
                baseWidth: 34
                baseHeight: 34
                clickedWidth: baseWidth + (isAtSide ? 8 : 14)
                buttonRadius: 17
                buttonRadiusPressed: 12
                bounce: true

                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundActive: Appearance.colors.colLayer2Hover
                onClicked: root.copyCoordinateList()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "content_copy"
                    iconSize: 18
                    fill: 1
                    color: copyBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                }

                StyledToolTip {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Copy Coordinates") : "Copy Coordinates"
                }
            }
        }

        // Coordinate chips row
        Item {
            id: coordContainer
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.chartWidth
            Layout.preferredHeight: coordRow.implicitHeight
            visible: root.editable

            RowLayout {
                id: coordRow
                anchors.centerIn: parent
                spacing: 8

                Repeater {
                    model: [0, 1, 2, 3]

                    delegate: Item {
                        id: coordItem
                        required property int modelData
                        readonly property bool editing: root.editingCoordinate === modelData

                        implicitWidth: 52
                        implicitHeight: 28

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: coordItem.editing ? Appearance.colors.colLayer2 : ColorUtils.applyAlpha(Appearance.colors.colSurfaceContainerHigh, 0.5)
                            border.width: coordItem.editing ? 1 : 0
                            border.color: root.coordinateInvalid ? Appearance.colors.colError : Appearance.colors.colPrimary
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: !coordItem.editing
                            text: root.coordinateText(coordItem.modelData)
                            color: coordMouse.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }

                        TextField {
                            id: coordInput
                            anchors.fill: parent
                            visible: coordItem.editing
                            text: root.coordinateDraft
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 12
                            background: Item {}

                            onTextChanged: {
                                if (coordItem.editing) {
                                    root.coordinateDraft = text;
                                    root.coordinateInvalid = false;
                                }
                            }
                            onVisibleChanged: {
                                if (visible) {
                                    Qt.callLater(() => {
                                        coordInput.forceActiveFocus();
                                        coordInput.selectAll();
                                    });
                                }
                            }
                            onEditingFinished: root.applyCoordinateField()
                            Keys.onReturnPressed: root.applyCoordinateField()
                            Keys.onEnterPressed: root.applyCoordinateField()
                            Keys.onEscapePressed: event => {
                                root.cancelCoordinateField();
                                event.accepted = true;
                            }
                        }

                        MouseArea {
                            id: coordMouse
                            anchors.fill: parent
                            enabled: !coordItem.editing
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openCoordinateField(coordItem.modelData)
                        }
                    }
                }
            }
        }
    }
}
