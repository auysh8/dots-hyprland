import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects

Canvas { // Visualizer
    id: root
    property list<var> points
    property list<var> smoothPoints
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property bool live: true
    property color color: Appearance.m3colors.m3primary
    property string style: "bars" // "waves", "bars", "dots", "symmetric-bars", "line"

    onPointsChanged: () => {
        root.requestPaint()
    }
    
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        var points = root.points;
        var maxVal = root.maxVisualizerValue || 1;
        var h = height;
        var w = width;
        var n = points.length;
        if (n < 2) return;

        // Smoothing: simple moving average (optional)
        var smoothWindow = root.smoothing; // adjust for more/less smoothing
        root.smoothPoints = [];
        for (var i = 0; i < n; ++i) {
            var sum = 0, count = 0;
            for (var j = -smoothWindow; j <= smoothWindow; ++j) {
                var idx = Math.max(0, Math.min(n - 1, i + j));
                sum += points[idx];
                count++;
            }
            root.smoothPoints.push(sum / count);
        }
        if (!root.live) root.smoothPoints.fill(0); // If not playing, show no points

        if (root.style === "waves") {
            ctx.beginPath();
            ctx.moveTo(0, h);
            for (var i = 0; i < n; ++i) {
                var x = i * w / (n - 1);
                var y = h - (root.smoothPoints[i] / maxVal) * h;
                ctx.lineTo(x, y);
            }
            ctx.lineTo(w, h);
            ctx.closePath();

            ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.15);
            ctx.fill();
            
            // Draw a slightly brighter line on top
            ctx.beginPath();
            for (var i = 0; i < n; ++i) {
                var x = i * w / (n - 1);
                var y = h - (root.smoothPoints[i] / maxVal) * h;
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 0.8);
            ctx.lineWidth = 1;
            ctx.stroke();

        } else if (root.style === "bars") {
            var barWidth = w / n;
            var spacing = 1; // 1px space between bars
            ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 1.0);
            
            for (var i = 0; i < n; ++i) {
                var barHeight = (root.smoothPoints[i] / maxVal) * h;
                if (root.live && barHeight < 2) barHeight = 2; // minimum height
                var x = i * barWidth;
                var y = h - barHeight;
                ctx.fillRect(x + (spacing/2), y, barWidth - spacing, barHeight);
            }
            
        } else if (root.style === "dots") {
            ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 1.0);
            for (var i = 0; i < n; ++i) {
                var x = i * w / (n - 1);
                var y = h - (root.smoothPoints[i] / maxVal) * h;
                if (root.live && y > h - 2) y = h - 2;
                
                ctx.beginPath();
                ctx.arc(x, y, 1.5, 0, 2 * Math.PI);
                ctx.fill();
            }
        } else if (root.style === "symmetric-bars") {
            var barWidth = w / n;
            var spacing = 1;
            ctx.fillStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 1.0);
            
            var centerY = h / 2;
            for (var i = 0; i < n; ++i) {
                var barHeight = (root.smoothPoints[i] / maxVal) * h;
                if (root.live && barHeight < 2) barHeight = 2;
                // Cut height in half since we are drawing it in both directions from center
                var halfHeight = barHeight / 2; 
                var x = i * barWidth;
                
                // Draw from center outwards
                ctx.fillRect(x + (spacing/2), centerY - halfHeight, barWidth - spacing, barHeight);
            }
        } else if (root.style === "pills") {
            var barWidth = w / n;
            var spacing = root.live ? Math.max(1, barWidth * 0.3) : 1;
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 1.0);
            var actualLineWidth = barWidth - spacing;
            ctx.lineWidth = actualLineWidth;
            var halfRadius = actualLineWidth / 2;
            
            var centerY = h / 2;
            
            ctx.beginPath();
            for (var i = 0; i < n; ++i) {
                // Return to a small but visible pill shape when silent
                var minPillHeight = Math.max(actualLineWidth * 1.3, h * 0.1); 
                var barHeight = (root.smoothPoints[i] / maxVal) * h;
                if (barHeight < minPillHeight) barHeight = minPillHeight;
                
                var halfHeight = barHeight / 2;
                var x = i * barWidth + (barWidth / 2);
                
                var yBottom = centerY + halfHeight - halfRadius;
                var yTop = centerY - halfHeight + halfRadius;
                
                if (yTop > yBottom) yTop = yBottom;
                
                ctx.moveTo(x, yBottom);
                ctx.lineTo(x, yTop);
            }
            ctx.stroke();
        } else if (root.style === "line") {
            ctx.beginPath();
            for (var i = 0; i < n; ++i) {
                var x = i * w / (n - 1);
                var y = h - (root.smoothPoints[i] / maxVal) * h;
                // Add a minimum bounce so it's not a perfectly flat line
                if (root.live && y > h - 1) y = h - 1; 
                
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            
            ctx.strokeStyle = Qt.rgba(root.color.r, root.color.g, root.color.b, 1.0);
            ctx.lineWidth = 2;
            ctx.stroke();
        }
    }

    layer.enabled: true
    layer.effect: MultiEffect { // Blur a bit to obscure away the points
        source: root
        saturation: 0.2
        blurEnabled: root.style !== "pills"
        blurMax: 7
        blur: 1
    }
}