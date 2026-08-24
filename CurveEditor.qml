import QtQuick
import qs.Commons
import "Bezier.js" as BezierLib

// Interactive cubic-bezier editor. Normalized space: x in [0,1],
// y in [-0.5, 1.5]. P0=(0,0) and P3=(1,1) are fixed; P1/P2 drag.
// A tracer dot sweeps the curve while it is being edited.
Canvas {
    id: root

    property real p1x: 0.23
    property real p1y: 1.0
    property real p2x: 0.32
    property real p2y: 1.0

    // Approximate duration for the tracer sweep, milliseconds.
    property real sweepMs: 380

    signal edited()

    readonly property var solver: BezierLib.fromPoints([p1x, p1y], [p2x, p2y])

    onP1xChanged: requestPaint()
    onP1yChanged: requestPaint()
    onP2xChanged: requestPaint()
    onP2yChanged: requestPaint()

    // Plot geometry -------------------------------------------------------
    readonly property real padL: 34
    readonly property real padR: 18
    readonly property real padT: 18
    readonly property real padB: 26
    readonly property real plotW: width - padL - padR
    readonly property real plotH: height - padT - padB

    // y range shown: -0.25 .. 1.25
    function px(nx) { return padL + nx * plotW }
    function py(ny) { return padT + (1.25 - ny) / 1.5 * plotH }
    function nx(pxVal) { return Math.min(1, Math.max(0, (pxVal - padL) / plotW)) }
    function ny(pyVal) {
        var v = 1.25 - (pyVal - padT) / plotH * 1.5
        return Math.min(1.5, Math.max(-0.5, v))
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        // Frame + grid
        ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
        ctx.lineWidth = 1
        for (var g = 0; g <= 4; g++) {
            var gx = px(g / 4)
            var gy = py(g / 4)
            ctx.beginPath(); ctx.moveTo(gx, py(-0.25)); ctx.lineTo(gx, py(1.25)); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(px(0), gy); ctx.lineTo(px(1), gy); ctx.stroke()
        }

        // Control arms
        ctx.strokeStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)
        ctx.lineWidth = 1.5
        ctx.beginPath(); ctx.moveTo(px(0), py(0)); ctx.lineTo(px(p1x), py(p1y)); ctx.stroke()
        ctx.beginPath(); ctx.moveTo(px(1), py(1)); ctx.lineTo(px(p2x), py(p2y)); ctx.stroke()

        // The curve
        ctx.strokeStyle = Color.accent
        ctx.lineWidth = 2.5
        ctx.beginPath()
        for (var s = 0; s <= 64; s++) {
            var pt = solver.sample(s / 64)
            var X = px(pt.x), Y = py(pt.y)
            if (s === 0) ctx.moveTo(X, Y); else ctx.lineTo(X, Y)
        }
        ctx.stroke()

        // Tracer dot at current sweep progress
        var ty = solver.at(tracer.t)
        ctx.fillStyle = Color.urgent
        ctx.beginPath()
        ctx.arc(px(tracer.t), py(ty), 5, 0, Math.PI * 2)
        ctx.fill()

        // Handles
        drawHandle(ctx, p1x, p1y)
        drawHandle(ctx, p2x, p2y)

        // Axis labels
        ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.55)
        ctx.font = "600 11px " + Style.font.family
        ctx.fillText("0", px(0) - 3, py(0) + 14)
        ctx.fillText("t", px(1) - 4, py(0) + 14)
        ctx.fillText("1", px(0) - 12, py(1) + 4)
    }

    function drawHandle(ctx, hx, hy) {
        ctx.fillStyle = Color.background
        ctx.strokeStyle = Color.accent
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(px(hx), py(hy), 7, 0, Math.PI * 2)
        ctx.fill()
        ctx.stroke()
    }

    Timer {
        id: tracer
        property real t: 0
        interval: 16
        repeat: true
        running: root.visible && root.enabled
        onTriggered: {
            t += interval / Math.max(120, root.sweepMs)
            if (t >= 1) { t = 0; pauseRestart.restart() }
            else root.requestPaint()
        }
    }

    Timer { id: pauseRestart; interval: sweepMs * 0.45; onTriggered: root.requestPaint() }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: activeDrag !== 0 ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property int activeDrag: 0   // 1 = P1, 2 = P2

        function hit(mx, my) {
            var d1 = Math.hypot(mx - root.px(root.p1x), my - root.py(root.p1y))
            var d2 = Math.hypot(mx - root.px(root.p2x), my - root.py(root.p2y))
            var r = 16
            if (d1 < r && d1 <= d2) return 1
            if (d2 < r) return 2
            return 0
        }

        onPressed: function(m) {
            activeDrag = hit(m.x, m.y)
            if (activeDrag === 0) {
                // Click empty space: snap nearest handle to the click.
                var nxx = root.nx(m.x), nyy = root.ny(m.y)
                if (Math.abs(m.x - root.px(root.p1x)) < Math.abs(m.x - root.px(root.p2x)))
                    { root.p1x = nxx; root.p1y = nyy; activeDrag = 1 }
                else
                    { root.p2x = nxx; root.p2y = nyy; activeDrag = 2 }
                root.edited()
            }
        }

        onPositionChanged: function(m) {
            if (activeDrag === 0) return
            var nxx = root.nx(m.x), nyy = root.ny(m.y)
            if (activeDrag === 1) { root.p1x = nxx; root.p1y = nyy }
            else { root.p2x = nxx; root.p2y = nyy }
            root.edited()
        }

        onReleased: activeDrag = 0
    }
}
