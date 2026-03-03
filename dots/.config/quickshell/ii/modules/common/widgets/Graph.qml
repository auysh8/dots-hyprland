import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: 60 // Default to the 60 seconds history length to prevent shrinking
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left

    onValuesChanged: root.requestPaint()
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2)
            return

        var n = root.points
        var dx = width / (n - 1)
        
        // Build the points array including padded 0s
        var pts = []
        for (var i = 0; i < n; ++i) {
            var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - n + i : i
            var norm = 0.0;
            if (valueIndex >= 0 && valueIndex < root.values.length) {
                norm = root.values[valueIndex];
            }
            pts.push({ x: i * dx, y: height - norm * height * 0.9 }) // 0.9 to prevent hitting the absolute top edge
        }

        // Draw the smooth curve
        ctx.beginPath()
        ctx.moveTo(pts[0].x, height) // Start bottom left for fill
        ctx.lineTo(pts[0].x, pts[0].y)

        // Calculate control points for smooth splines
        for (var i = 0; i < n - 1; i++) {
            var xc = (pts[i].x + pts[i + 1].x) / 2;
            var yc = (pts[i].y + pts[i + 1].y) / 2;
            ctx.quadraticCurveTo(pts[i].x, pts[i].y, xc, yc);
        }
        // curve through the last two points
        ctx.quadraticCurveTo(pts[n - 2].x, pts[n - 2].y, pts[n - 1].x, pts[n - 1].y);
        
        // Finish path for the fill
        ctx.lineTo(width, height)
        ctx.closePath()

        // Create a vertical gradient fill
        var gradient = ctx.createLinearGradient(0, 0, 0, height);
        gradient.addColorStop(0, ColorUtils.transparentize(root.color, 1 - root.fillOpacity));
        gradient.addColorStop(1, ColorUtils.transparentize(root.color, 0.95)); // Fade out to bottom
        
        ctx.fillStyle = gradient
        ctx.fill()

        // Now draw just the line on top (smoothly)
        ctx.beginPath()
        ctx.moveTo(pts[0].x, pts[0].y)
        for (var i = 0; i < n - 1; i++) {
            var xc = (pts[i].x + pts[i + 1].x) / 2;
            var yc = (pts[i].y + pts[i + 1].y) / 2;
            ctx.quadraticCurveTo(pts[i].x, pts[i].y, xc, yc);
        }
        ctx.quadraticCurveTo(pts[n - 2].x, pts[n - 2].y, pts[n - 1].x, pts[n - 1].y);
        
        ctx.strokeStyle = root.color
        ctx.lineWidth = 2
        ctx.stroke()
    }
}
