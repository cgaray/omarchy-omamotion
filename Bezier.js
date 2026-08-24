// Cubic bezier solver (CSS easing semantics): P0=(0,0), P3=(1,1),
// control points P1=(x1,y1), P2=(x2,y2). Solves y for a given x by
// first solving the parameter t from x(t) with Newton-Raphson plus a
// bisection fallback, then evaluating y(t).
.pragma library

function cubicBezier(x1, y1, x2, y2) {
    function ax(t) { return ((1 - t) * (1 - t) * (1 - t)) * 0 + 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t }
    function ay(t) { return 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t }
    function dx(t) { return 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2) }

    function solveT(x) {
        if (x <= 0) return 0
        if (x >= 1) return 1
        var t = x
        for (var i = 0; i < 8; i++) {
            var err = ax(t) - x
            if (Math.abs(err) < 1e-6) return t
            var d = dx(t)
            if (Math.abs(d) < 1e-6) break
            t -= err / d
        }
        var lo = 0, hi = 1
        t = x
        for (var j = 0; j < 24; j++) {
            var v = ax(t)
            if (Math.abs(v - x) < 1e-6) return t
            if (v < x) lo = t; else hi = t
            t = (lo + hi) / 2
        }
        return t
    }

    return {
        at: function (x) { return ay(solveT(x)) },
        sample: function (t) { return { x: ax(t), y: ay(t) } }
    }
}

// Convenience: build solver from OmaMotion curve state entries.
function fromPoints(p1, p2) {
    return cubicBezier(p1[0], p1[1], p2[0], p2[1])
}
