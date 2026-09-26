import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property bool show: false
    property var sourceCurve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0]
    property var workingCurve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0]
    property real renderX1: 0.43
    property real renderY1: 1.19
    property real renderX2: 1.0
    property real renderY2: 0.4
    property int activePoint: -1
    property bool panning: false
    property bool playing: false
    property int playbackDirection: 1
    property real playhead: 0
    property int playDurationMs: 1000
    property real pixelsPerUnit: 220
    property real panX: 0
    property real panY: 0
    property real lastMouseX: 0
    property real lastMouseY: 0
    property real animTargetPpu: 220
    property real animTargetPanX: 0
    property real animTargetPanY: 0

    readonly property var presetCurves: [
        { name: "Overshoot", icon: "trending_up", curve: [0.43, 1.19, 1.0, 0.4, 1.0, 1.0] },
        { name: "Standard", icon: "show_chart", curve: [0.25, 0.1, 0.25, 1.0, 1.0, 1.0] },
        { name: "Ease In-Out", icon: "timeline", curve: [0.42, 0.0, 0.58, 1.0, 1.0, 1.0] },
        { name: "Decelerate", icon: "speed", curve: [0.0, 0.0, 0.2, 1.0, 1.0, 1.0] },
        { name: "Accelerate", icon: "bolt", curve: [0.4, 0.0, 1.0, 1.0, 1.0, 1.0] },
        { name: "Linear", icon: "linear_scale", curve: [0.0, 0.0, 1.0, 1.0, 1.0, 1.0] }
    ]

    function isPresetActive(preset) {
        const eps = 0.03;
        return Math.abs(renderX1 - preset.curve[0]) < eps &&
               Math.abs(renderY1 - preset.curve[1]) < eps &&
               Math.abs(renderX2 - preset.curve[2]) < eps &&
               Math.abs(renderY2 - preset.curve[3]) < eps;
    }

    signal curveEdited(var nextCurve)
    signal closed()

    function fitToView(animate) {
        const minX = Math.min(0, renderX1, renderX2);
        const maxX = Math.max(1, renderX1, renderX2);
        const minY = Math.min(0, renderY1, renderY2);
        const maxY = Math.max(1, renderY1, renderY2);

        const spanX = Math.max(0.1, maxX - minX);
        const spanY = Math.max(0.1, maxY - minY);

        const marginX = 140;
        const marginY = 110;
        const usableW = Math.max(80, canvas.width - marginX);
        const usableH = Math.max(80, canvas.height - marginY);

        const ppuX = usableW / spanX;
        const ppuY = usableH / spanY;
        const optimalPpu = clamp(Math.min(ppuX, ppuY), 120, 450);

        const centerWorldX = (minX + maxX) / 2;
        const centerWorldY = (minY + maxY) / 2;

        const targetPanX = optimalPpu * (0.5 - centerWorldX);
        const targetPanY = optimalPpu * (centerWorldY - 0.5);

        panAnimation.stop();
        if (animate !== false) {
            animTargetPpu = optimalPpu;
            animTargetPanX = targetPanX;
            animTargetPanY = targetPanY;
            panAnimation.start();
        } else {
            pixelsPerUnit = optimalPpu;
            panX = targetPanX;
            panY = targetPanY;
            canvas.requestPaint();
        }
    }

    function zoomBy(factor) {
        panAnimation.stop();
        animTargetPpu = clamp(pixelsPerUnit * factor, 80, 550);
        animTargetPanX = panX;
        animTargetPanY = panY;
        panAnimation.start();
    }

    function openWithCurve(inputCurve, durationMs) {
        sourceCurve = normalizeCurve(inputCurve);
        workingCurve = sourceCurve.slice();
        if (durationMs && durationMs > 0) playDurationMs = durationMs;
        setRenderCurve(workingCurve);
        playhead = 0;
        playing = false;
        show = true;
        if (canvas.width > 0 && canvas.height > 0) {
            fitToView(false);
        } else {
            panX = 0;
            panY = 0;
            pixelsPerUnit = 220;
        }
    }

    function dismiss() {
        show = false;
        playing = false;
        playbackAnimation.stop();
        closed();
    }

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function clamp01(value) {
        return clamp(value, 0, 1);
    }

    function defaultCurve() {
        return [0.43, 1.19, 1.0, 0.4, 1.0, 1.0];
    }

    function normalizeCurve(source) {
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

    function cubicCoord(t, a, b) {
        const u = 1 - t;
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
    }

    function valueAtX(x) {
        let lo = 0, hi = 1;
        for (let i = 0; i < 16; i++) {
            const mid = (lo + hi) / 2;
            const cx = cubicCoord(mid, renderX1, renderX2);
            if (cx < x) lo = mid;
            else hi = mid;
        }
        const t = (lo + hi) / 2;
        return cubicCoord(t, renderY1, renderY2);
    }

    function setRenderCurve(nextCurve) {
        const next = normalizeCurve(nextCurve);
        renderX1 = next[0];
        renderY1 = next[1];
        renderX2 = next[2];
        renderY2 = next[3];
        x1Input.text = formatNumber(renderX1);
        y1Input.text = formatNumber(renderY1);
        x2Input.text = formatNumber(renderX2);
        y2Input.text = formatNumber(renderY2);
        canvas.requestPaint();
    }

    function originX() {
        return canvas.width / 2 - pixelsPerUnit / 2 + panX;
    }

    function originY() {
        return canvas.height / 2 + pixelsPerUnit / 2 + panY;
    }

    function screenX(x) {
        return originX() + x * pixelsPerUnit;
    }

    function screenY(y) {
        return originY() - y * pixelsPerUnit;
    }

    function worldX(sx) {
        return (sx - originX()) / pixelsPerUnit;
    }

    function worldY(sy) {
        return (originY() - sy) / pixelsPerUnit;
    }

    function formatNumber(value) {
        const rounded = Math.round(value * 100) / 100;
        return rounded.toFixed(2).replace(/\.?0+$/, "");
    }

    function coordinateListText() {
        return `${formatNumber(renderX1)}, ${formatNumber(renderY1)}, ${formatNumber(renderX2)}, ${formatNumber(renderY2)}`;
    }

    function copyCoordinateList() {
        Quickshell.execDetached(["wl-copy", coordinateListText()]);
    }

    function applyPreset(preset) {
        workingCurve = normalizeCurve(preset.curve);
        setRenderCurve(workingCurve);
        fitToView(true);
        triggerPreviewPulse();
    }

    function flipCurve() {
        const next = [1 - renderX2, 1 - renderY2, 1 - renderX1, 1 - renderY1, 1, 1];
        workingCurve = normalizeCurve(next);
        setRenderCurve(workingCurve);
        fitToView(true);
        triggerPreviewPulse();
    }

    function resetToDefault() {
        workingCurve = defaultCurve();
        setRenderCurve(workingCurve);
        fitToView(true);
        triggerPreviewPulse();
    }

    function applyManualInputs() {
        const x1 = parseFloat(x1Input.text);
        const y1 = parseFloat(y1Input.text);
        const x2 = parseFloat(x2Input.text);
        const y2 = parseFloat(y2Input.text);
        if (isFinite(x1) && isFinite(y1) && isFinite(x2) && isFinite(y2)) {
            workingCurve = [clamp01(x1), clamp(y1, -2, 3), clamp01(x2), clamp(y2, -2, 3), 1, 1];
            setRenderCurve(workingCurve);
            triggerPreviewPulse();
        }
    }

    function saveAndClose() {
        root.curveEdited(workingCurve);
        root.dismiss();
    }

    function togglePlayback() {
        if (playing) {
            playbackAnimation.stop();
            playing = false;
            return;
        }
        if (playhead >= 1) playhead = 0;
        playbackDirection = 1;
        playing = true;
        playbackAnimation.from = playhead;
        playbackAnimation.to = 1;
        playbackAnimation.duration = Math.max(200, Math.round(playDurationMs * (1 - playhead)));
        playbackAnimation.start();
    }

    function reversePlayback() {
        playbackAnimation.stop();
        playing = false;
        if (playhead <= 0) playhead = 1;
        playbackDirection = -1;
        playing = true;
        playbackAnimation.from = playhead;
        playbackAnimation.to = 0;
        playbackAnimation.duration = Math.max(200, Math.round(playDurationMs * playhead));
        playbackAnimation.start();
    }

    function triggerPreviewPulse() {
        previewPulseAnimation.restart();
    }

    function hitTest(mx, my) {
        const p1x = screenX(renderX1);
        const p1y = screenY(renderY1);
        const p2x = screenX(renderX2);
        const p2y = screenY(renderY2);
        const d1 = Math.hypot(mx - p1x, my - p1y);
        const d2 = Math.hypot(mx - p2x, my - p2y);
        if (d1 < 22 || d2 < 22) return d1 <= d2 ? 0 : 1;

        // Tangent guide grab
        const s0x = screenX(0), s0y = screenY(0);
        const s1x = screenX(1), s1y = screenY(1);
        function distToSeg(px, py, x1, y1, x2, y2) {
            const dx = x2 - x1, dy = y2 - y1;
            const l2 = dx * dx + dy * dy;
            if (l2 === 0) return Math.hypot(px - x1, py - y1);
            let t = Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / l2));
            return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
        }
        if (distToSeg(mx, my, s0x, s0y, p1x, p1y) < 14) return 0;
        if (distToSeg(mx, my, s1x, s1y, p2x, p2y) < 14) return 1;
        return -1;
    }

    Component.onCompleted: {
        if (Window.window && Window.window.contentItem) {
            for (let i = Window.window.contentItem.children.length - 1; i >= 0; i--) {
                const child = Window.window.contentItem.children[i];
                if (child && child !== root && child.objectName === "bezierCurveWorkbenchOverlay") {
                    child.destroy();
                }
            }
            objectName = "bezierCurveWorkbenchOverlay";
            parent = Window.window.contentItem;
            anchors.fill = parent;
            if (root.show) {
                GlobalStates.settingsModalOpen = true;
            }
        }
    }

    Component.onDestruction: {
        GlobalStates.settingsModalOpen = false;
    }

    onShowChanged: {
        GlobalStates.settingsModalOpen = root.show;
    }

    visible: opacity > 0
    opacity: show ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Scrim backdrop
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colScrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
        }
    }

    // Main Modal Card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 920)
        height: Math.min(parent.height - 64, 620)
        radius: Appearance.rounding.large ?? 16
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        StyledRectangularShadow {
            target: card
            opacity: card.opacity
        }

        scale: root.show ? 1 : 0.95
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                WindowDialogTitle {
                    text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Bézier Curve") : "Bézier Curve"
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.copyCoordinateList()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "content_copy"
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnLayer2
                    }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.dismiss()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        fill: 1
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }

            // Presets row (clean, no heavy wrapper container)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: root.presetCurves

                    delegate: RippleButton {
                        required property var modelData
                        readonly property bool active: root.isPresetActive(modelData)
                        implicitHeight: 30
                        implicitWidth: presetRow.implicitWidth + 20
                        buttonRadius: Appearance.rounding.small
                        colBackground: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                        onClicked: root.applyPreset(modelData)

                        contentItem: Row {
                            id: presetRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -1.5
                                text: modelData.icon
                                iconSize: 14
                                fill: 1
                                color: active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: active ? Font.Bold : Font.Normal
                                color: active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }
            }

            // Main Canvas Area
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
                clip: true

                Canvas {
                    id: canvas
                    anchors.fill: parent

                    onWidthChanged: {
                        if (root.show && root.panX === 0 && root.panY === 0 && root.pixelsPerUnit === 220) {
                            root.fitToView(false);
                        }
                    }
                    onHeightChanged: {
                        if (root.show && root.panX === 0 && root.panY === 0 && root.pixelsPerUnit === 220) {
                            root.fitToView(false);
                        }
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        if (!ctx) return;
                        ctx.clearRect(0, 0, width, height);

                        const ox = root.originX();
                        const oy = root.originY();
                        const ppu = root.pixelsPerUnit;

                        // 1. Grid Lines
                        ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.05);
                        ctx.lineWidth = 1;

                        const startGridX = Math.floor(-ox / (ppu * 0.25)) * 0.25;
                        const endGridX = Math.ceil((width - ox) / (ppu * 0.25)) * 0.25;
                        for (let gx = startGridX; gx <= endGridX; gx += 0.25) {
                            const sx = root.screenX(gx);
                            ctx.beginPath();
                            ctx.moveTo(sx, 0);
                            ctx.lineTo(sx, height);
                            ctx.stroke();
                        }

                        const startGridY = Math.floor((oy - height) / (ppu * 0.25)) * 0.25;
                        const endGridY = Math.ceil(oy / (ppu * 0.25)) * 0.25;
                        for (let gy = startGridY; gy <= endGridY; gy += 0.25) {
                            const sy = root.screenY(gy);
                            ctx.beginPath();
                            ctx.moveTo(0, sy);
                            ctx.lineTo(width, sy);
                            ctx.stroke();
                        }

                        // 2. Unit Box [0, 1] x [0, 1]
                        const uLeft = root.screenX(0);
                        const uTop = root.screenY(1);
                        const uRight = root.screenX(1);
                        const uBottom = root.screenY(0);

                        ctx.fillStyle = ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.04);
                        ctx.fillRect(uLeft, uTop, uRight - uLeft, uBottom - uTop);

                        ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.22);
                        ctx.lineWidth = 1.4;
                        ctx.strokeRect(uLeft, uTop, uRight - uLeft, uBottom - uTop);

                        // 3. Diagonal reference line (0,0) -> (1,1)
                        ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.18);
                        ctx.lineWidth = 1.2;
                        if (typeof ctx.setLineDash === "function") ctx.setLineDash([4, 4]);
                        ctx.beginPath();
                        ctx.moveTo(uLeft, uBottom);
                        ctx.lineTo(uRight, uTop);
                        ctx.stroke();
                        if (typeof ctx.setLineDash === "function") ctx.setLineDash([]);

                        // 4. Tangent Guide Lines
                        const p1x = root.screenX(root.renderX1);
                        const p1y = root.screenY(root.renderY1);
                        const p2x = root.screenX(root.renderX2);
                        const p2y = root.screenY(root.renderY2);

                        ctx.lineWidth = 1.6;
                        if (typeof ctx.setLineDash === "function") ctx.setLineDash([5, 5]);

                        ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.75);
                        ctx.beginPath();
                        ctx.moveTo(uLeft, uBottom);
                        ctx.lineTo(p1x, p1y);
                        ctx.stroke();

                        ctx.strokeStyle = ColorUtils.applyAlpha(Appearance.colors.colSecondary, 0.75);
                        ctx.beginPath();
                        ctx.moveTo(uRight, uTop);
                        ctx.lineTo(p2x, p2y);
                        ctx.stroke();
                        if (typeof ctx.setLineDash === "function") ctx.setLineDash([]);

                        // 5. Main Bézier Curve
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        ctx.strokeStyle = Appearance.colors.colPrimary;
                        ctx.lineWidth = 3.6;
                        ctx.beginPath();
                        for (let i = 0; i <= 150; i++) {
                            const t = i / 150;
                            const cx = root.cubicCoord(t, root.renderX1, root.renderX2);
                            const cy = root.cubicCoord(t, root.renderY1, root.renderY2);
                            const sx = root.screenX(cx);
                            const sy = root.screenY(cy);
                            if (i === 0) ctx.moveTo(sx, sy);
                            else ctx.lineTo(sx, sy);
                        }
                        ctx.stroke();

                        // 6. Playhead Trail
                        if (root.playhead > 0) {
                            const trailSteps = Math.max(1, Math.round(root.playhead * 150));
                            ctx.strokeStyle = Appearance.colors.colTertiary || Appearance.colors.colPrimary;
                            ctx.lineWidth = 3.6;
                            ctx.beginPath();
                            for (let i = 0; i <= trailSteps; i++) {
                                const t = (i / trailSteps) * root.playhead;
                                const cx = root.cubicCoord(t, root.renderX1, root.renderX2);
                                const cy = root.cubicCoord(t, root.renderY1, root.renderY2);
                                const sx = root.screenX(cx);
                                const sy = root.screenY(cy);
                                if (i === 0) ctx.moveTo(sx, sy);
                                else ctx.lineTo(sx, sy);
                            }
                            ctx.stroke();
                        }

                        // 7. Anchors: (0,0) and (1,1)
                        function drawAnchor(ax, ay) {
                            ctx.fillStyle = Appearance.colors.colSurface || "#ffffff";
                            ctx.strokeStyle = Appearance.colors.colOnSurfaceVariant || "#888888";
                            ctx.lineWidth = 1.8;
                            ctx.beginPath();
                            ctx.arc(ax, ay, 4, 0, Math.PI * 2);
                            ctx.fill();
                            ctx.stroke();
                        }
                        drawAnchor(uLeft, uBottom);
                        drawAnchor(uRight, uTop);

                        // 8. Control Handles P1 and P2
                        function drawHandle(px, py, isP1, active) {
                            const accentCol = isP1 ? Appearance.colors.colPrimary : Appearance.colors.colSecondary;
                            ctx.fillStyle = ColorUtils.applyAlpha(accentCol, active ? 0.35 : 0.15);
                            ctx.beginPath();
                            ctx.arc(px, py, active ? 16 : 12, 0, Math.PI * 2);
                            ctx.fill();

                            ctx.fillStyle = accentCol;
                            ctx.strokeStyle = Appearance.colors.colSurface || "#ffffff";
                            ctx.lineWidth = 2.2;
                            ctx.beginPath();
                            ctx.arc(px, py, active ? 8 : 7, 0, Math.PI * 2);
                            ctx.fill();
                            ctx.stroke();
                        }

                        drawHandle(p1x, p1y, true, root.activePoint === 0);
                        drawHandle(p2x, p2y, false, root.activePoint === 1);

                        // 9. Animated Playhead Ball
                        const ballX = root.screenX(root.cubicCoord(root.playhead, root.renderX1, root.renderX2));
                        const ballY = root.screenY(root.cubicCoord(root.playhead, root.renderY1, root.renderY2));

                        ctx.fillStyle = ColorUtils.applyAlpha(Appearance.colors.colTertiary || Appearance.colors.colPrimary, 0.35);
                        ctx.beginPath();
                        ctx.arc(ballX, ballY, 13, 0, Math.PI * 2);
                        ctx.fill();

                        ctx.fillStyle = Appearance.colors.colTertiary || Appearance.colors.colPrimary;
                        ctx.strokeStyle = "#ffffff";
                        ctx.lineWidth = 2.0;
                        ctx.beginPath();
                        ctx.arc(ballX, ballY, 6.5, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.stroke();
                    }
                }

                MouseArea {
                    id: canvasMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: root.panning ? Qt.ClosedHandCursor
                                 : (root.activePoint >= 0 || root.hitTest(mouseX, mouseY) >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor)

                    onPressed: mouse => {
                        panAnimation.stop();
                        if (mouse.button === Qt.MiddleButton) {
                            root.panning = true;
                            root.lastMouseX = mouse.x;
                            root.lastMouseY = mouse.y;
                            mouse.accepted = true;
                            return;
                        }
                        if (mouse.button === Qt.LeftButton) {
                            const hit = root.hitTest(mouse.x, mouse.y);
                            if (hit >= 0) {
                                root.activePoint = hit;
                                mouse.accepted = true;
                                canvas.requestPaint();
                                return;
                            }
                            root.panning = true;
                            root.lastMouseX = mouse.x;
                            root.lastMouseY = mouse.y;
                            mouse.accepted = true;
                        }
                    }

                    onPositionChanged: mouse => {
                        if (root.panning) {
                            root.panX += (mouse.x - root.lastMouseX);
                            root.panY += (mouse.y - root.lastMouseY);
                            root.lastMouseX = mouse.x;
                            root.lastMouseY = mouse.y;
                            canvas.requestPaint();
                            return;
                        }
                        if (root.activePoint >= 0) {
                            const wx = root.clamp01(root.worldX(mouse.x));
                            const wy = root.clamp(root.worldY(mouse.y), -2.0, 3.0);
                            const next = root.workingCurve.slice();
                            if (root.activePoint === 0) {
                                next[0] = Math.round(wx * 100) / 100;
                                next[1] = Math.round(wy * 100) / 100;
                            } else {
                                next[2] = Math.round(wx * 100) / 100;
                                next[3] = Math.round(wy * 100) / 100;
                            }
                            root.workingCurve = next;
                            root.setRenderCurve(next);
                            canvas.requestPaint();
                        }
                    }

                    onReleased: {
                        root.panning = false;
                        root.activePoint = -1;
                        canvas.requestPaint();
                    }

                    onWheel: wheel => {
                        panAnimation.stop();
                        const zoomFactor = wheel.angleDelta.y > 0 ? 1.15 : 0.87;
                        root.pixelsPerUnit = root.clamp(root.pixelsPerUnit * zoomFactor, 80, 550);
                        canvas.requestPaint();
                        wheel.accepted = true;
                    }
                }

                // Floating Zoom & Viewport Controls (Material 3 GroupButtons as in KDEDrawer & MediaPage)
                ButtonGroup {
                    id: zoomControls
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 6
                    padding: 0
                    color: "transparent"
                    z: 10

                    GroupButton {
                        id: zoomInBtn
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

                        onClicked: root.zoomBy(1.25)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "zoom_in"
                            iconSize: 18
                            fill: 1
                            color: zoomInBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Zoom In") : "Zoom In"
                        }
                    }

                    GroupButton {
                        id: zoomOutBtn
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

                        onClicked: root.zoomBy(1 / 1.25)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "zoom_out"
                            iconSize: 18
                            fill: 1
                            color: zoomOutBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Zoom Out") : "Zoom Out"
                        }
                    }

                    GroupButton {
                        id: fitScreenBtn
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

                        onClicked: root.fitToView(true)

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "fit_screen"
                            iconSize: 18
                            fill: 1
                            color: fitScreenBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Fit Curve to View") : "Fit Curve to View"
                        }
                    }
                }
            }

            // Single Unified Bottom Footer Row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Playback & Edit Controls Group
                ButtonGroup {
                    id: playbackButtonGroup
                    spacing: 6
                    padding: 0
                    color: "transparent"

                    // Play / Pause Button
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

                    // Invert / Flip Curve
                    GroupButton {
                        id: flipBtn
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
                        onClicked: root.flipCurve()

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "swap_horiz"
                            iconSize: 18
                            fill: 1
                            color: flipBtn.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Flip Curve") : "Flip Curve"
                        }
                    }

                    // Reset to default curve
                    GroupButton {
                        id: resetBtn
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
                        onClicked: root.resetToDefault()

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
                }

                // Compact Live Motion Swatch Track
                Rectangle {
                    implicitWidth: 140
                    implicitHeight: 32
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    clip: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        height: 2
                        color: Appearance.colors.colOutlineVariant
                    }

                    Rectangle {
                        id: previewThumb
                        readonly property real evalProgress: root.clamp(root.valueAtX(root.playhead), 0, 1)
                        x: 6 + evalProgress * (parent.width - width - 12)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 20
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colPrimary

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "motion_photos_on"
                            iconSize: 14
                            fill: 1
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            root.playhead = root.clamp01((mouse.x - 6) / Math.max(1, width - 12));
                            canvas.requestPaint();
                        }
                    }
                }

                // Coordinate Inputs: P1 (X, Y) and P2 (X, Y)
                RowLayout {
                    spacing: 6

                    StyledText {
                        text: "P1"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }

                    TextField {
                        id: x1Input
                        implicitWidth: 44
                        implicitHeight: 30
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnLayer2
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }
                        onEditingFinished: root.applyManualInputs()
                    }

                    TextField {
                        id: y1Input
                        implicitWidth: 44
                        implicitHeight: 30
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnLayer2
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }
                        onEditingFinished: root.applyManualInputs()
                    }

                    StyledText {
                        text: "P2"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colSecondary
                    }

                    TextField {
                        id: x2Input
                        implicitWidth: 44
                        implicitHeight: 30
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnLayer2
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }
                        onEditingFinished: root.applyManualInputs()
                    }

                    TextField {
                        id: y2Input
                        implicitWidth: 44
                        implicitHeight: 30
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "Monospace"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colOnLayer2
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }
                        onEditingFinished: root.applyManualInputs()
                    }
                }

                Item { Layout.fillWidth: true }

                // Dialog Action Buttons: Cancel and Apply using DialogButton from widgetrules.md
                WindowDialogButtonRow {
                    DialogButton {
                        buttonText: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Cancel") : "Cancel"
                        onClicked: root.dismiss()
                    }

                    DialogButton {
                        buttonText: (typeof Translation !== "undefined" && Translation.tr) ? Translation.tr("Apply") : "Apply"
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colText: Appearance.colors.colOnPrimary
                        onClicked: root.saveAndClose()
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: playbackAnimation
        target: root
        property: "playhead"
        onFinished: {
            root.playing = false;
            canvas.requestPaint();
        }
    }

    SequentialAnimation {
        id: previewPulseAnimation
        running: false
        NumberAnimation {
            target: root
            property: "playhead"
            from: 0
            to: 1
            duration: Math.max(300, root.playDurationMs)
            easing.type: Easing.Linear
        }
        ScriptAction {
            script: {
                canvas.requestPaint();
            }
        }
    }

    ParallelAnimation {
        id: panAnimation
        NumberAnimation {
            target: root
            property: "pixelsPerUnit"
            to: root.animTargetPpu
            duration: Appearance.animationCurves.expressiveFastSpatialDuration ?? 350
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: root
            property: "panX"
            to: root.animTargetPanX
            duration: Appearance.animationCurves.expressiveFastSpatialDuration ?? 350
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: root
            property: "panY"
            to: root.animTargetPanY
            duration: Appearance.animationCurves.expressiveFastSpatialDuration ?? 350
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    onPixelsPerUnitChanged: canvas.requestPaint()
    onPanXChanged: canvas.requestPaint()
    onPanYChanged: canvas.requestPaint()
    onPlayheadChanged: canvas.requestPaint()
}
