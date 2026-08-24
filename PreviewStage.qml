import QtQuick
import qs.Commons
import qs.Ui
import "Bezier.js" as BezierLib

// A mock desktop that replays the leaf currently being edited. The
// mapping from Hyprland semantics to QML transforms is deliberately
// approximate (labelled as such) — its job is to make speed, curve and
// style choices felt before they touch the real config.
Item {
    id: root

    // Injected by MotionPanel: { entry: <leaf state>, curves: <state.curves>,
    // sweepMs: number } — updated on every relevant change.
    property var spec: null
    property string mode: "open"   // open | close | move | layer

    readonly property var solver: {
        if (!spec) return null
        var name = spec.entry && spec.entry.bezier ? spec.entry.bezier : "default"
        if (!spec.curves[name]) name = Object.keys(spec.curves)[0]
        if (!spec.curves[name]) return null
        var c = spec.curves[name]
        return BezierLib.fromPoints(c.p1, c.p2)
    }

    readonly property real durationMs: {
        if (!spec || !spec.entry || spec.entry.speed === undefined) return 300
        return Math.max(120, spec.entry.speed * 100)
    }

    // Style heuristics -----------------------------------------------------
    readonly property bool doFade: !spec || !spec.entry.style
        ? mode !== "move"
        : spec.entry.style.indexOf("fade") !== -1 || spec.modeHint === "fade"
    readonly property real popinFrom: {
        var s = spec && spec.entry && spec.entry.style ? spec.entry.style : ""
        var m = s.match(/popin\s+(\d+)/)
        return m ? Number(m[1]) / 100 : (s && s.indexOf("slide") === -1 ? 0.86 : 1.0)
    }
    readonly property string slideDir: {
        var s = spec && spec.entry && spec.entry.style ? spec.entry.style : ""
        if (mode === "move") return "right"
        if (s.indexOf("slidevert") !== -1) return "bottom"
        if (s.indexOf("slide top") !== -1) return "top"
        if (s.indexOf("slide bottom") !== -1) return "bottom"
        if (s.indexOf("slide left") !== -1) return "left"
        if (s.indexOf("slide right") !== -1) return "right"
        if (s.indexOf("slide") !== -1) return "bottom"
        return ""
    }

    function trigger(m) {
        mode = m
        progress = 0
        playing = true
    }

    // Animation driver -----------------------------------------------------
    property real progress: 0     // 0..1 through the motion
    property bool playing: false
    property bool phaseOut: false

    Timer {
        id: ticker
        interval: 16
        repeat: true
        running: root.playing && root.visible
        onTriggered: {
            root.progress += interval / root.durationMs
            if (root.progress >= 1) {
                root.progress = 1
                root.playing = false
                if (!root.holdTimer.running) root.holdTimer.restart()
            }
            stage.requestPaint()
        }
    }

    Timer {
        id: holdTimer
        interval: Math.max(350, root.durationMs)
        onTriggered: root.trigger(root.mode === "close" ? "open" : root.mode === "open" ? "close" : root.mode)
    }

    // Desktop mock ---------------------------------------------------------
    Canvas {
        id: stage
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            // Wallpaper-ish backdrop
            ctx.fillStyle = Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
            roundedRect(ctx, 0, 0, width, height, 10)
            ctx.fill()
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
            ctx.lineWidth = 1
            roundedRect(ctx, 0.5, 0.5, width - 1, height - 1, 10)
            ctx.stroke()

            // Ghost tile hinting where the window lands
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
            roundedRect(ctx, width * 0.30, height * 0.22, width * 0.40, height * 0.56, 8)
            ctx.stroke()

            if (!root.solver) return

            var t = eased()
            var appear = root.mode === "close" ? 1 - t : t
            var slideOff = slideOffset(appear)
            var w = width, h = height

            var ww = w * 0.40 * lerp(root.popinFrom, 1, appear)
            var wh = h * 0.56 * lerp(root.popinFrom, 1, appear)
            var wx = w * 0.30 + (w * 0.40 - ww) / 2 + slideOff.x
            var wy = h * 0.22 + (h * 0.56 - wh) / 2 + slideOff.y

            ctx.globalAlpha = root.doFade ? clamp01(appear) : 1

            // Window card with titlebar dots
            ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.13)
            roundedRect(ctx, wx, wy, ww, wh, 8)
            ctx.fill()
            ctx.strokeStyle = Color.accent
            ctx.lineWidth = 1.5
            roundedRect(ctx, wx, wy, ww, wh, 8)
            ctx.stroke()
            for (var d = 0; d < 3; d++) {
                ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.35)
                ctx.beginPath()
                ctx.arc(wx + 12 + d * 11, wy + 11, 2.6, 0, Math.PI * 2)
                ctx.fill()
            }

            // Layer mode: a second sheet sliding over
            if (root.mode === "layer") {
                var lt = eased() * w * 0.34
                ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.28)
                roundedRect(ctx, w - lt, h * 0.18, lt, h * 0.64, 6)
                ctx.fill()
            }

            ctx.globalAlpha = 1
        }
    }

    function eased() {
        if (!solver) return progress
        var x = mode === "close" ? 1 - progress : progress
        return solver.at(clamp01(x))
    }

    function slideOffset(k) {
        var dist = (1 - k)
        var m = 46
        switch (slideDir) {
        case "left":   return { x: -dist * m, y: 0 }
        case "right":  return { x: dist * m, y: 0 }
        case "top":    return { x: 0, y: -dist * m }
        case "bottom": return { x: 0, y: dist * m }
        default:       return { x: 0, y: 0 }
        }
    }

    function roundedRect(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + w, y, x + w, y + h, r)
        ctx.arcTo(x + w, y + h, x, y + h, r)
        ctx.arcTo(x, y + h, x, y, r)
        ctx.arcTo(x, y, x + w, y, r)
        ctx.closePath()
    }

    function lerp(a, b, k) { return a + (b - a) * k }
    function clamp01(v) { return Math.min(1, Math.max(0, v)) }

    onSpecChanged: { progress = 0; playing = false; stage.requestPaint() }
    onModeChanged: stage.requestPaint()

    // Controls -------------------------------------------------------------
    Row {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        spacing: Style.space(3)

        Button { text: "Open";  onClicked: root.trigger("open") }
        Button { text: "Close"; onClicked: root.trigger("close") }
        Button { text: "Move";  onClicked: root.trigger("move") }
        Button { text: "Layer"; onClicked: root.trigger("layer") }
    }
}
