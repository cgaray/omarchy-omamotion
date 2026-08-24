import QtQuick
import qs.Commons
import qs.Ui
import "Bezier.js" as BezierLib

// Preview the selected animation leaf with approximate QML transforms.
Item {
    id: root

    // MotionPanel supplies the selected entry and curve table.
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

    // Style mapping --------------------------------------------------------
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

    // Desktop preview ------------------------------------------------------
    Canvas {
        id: stage
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            // Preview background
            ctx.fillStyle = Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
            roundedRect(ctx, 0, 0, width, height, 10)
            ctx.fill()
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
            ctx.lineWidth = 1
            roundedRect(ctx, 0.5, 0.5, width - 1, height - 1, 10)
            ctx.stroke()

            if (!root.solver) return

            var t = eased()
            var appear = root.mode === "close" ? 1 - t : t
            var w = width, h = height

            // Two workspace panes make a workspace switch legible. Vertical
            // slide styles stack the panes so the preview follows the actual
            // direction instead of always implying a horizontal move.
            var vertical = slideDir === "top" || slideDir === "bottom"
            var gap = 14
            var paneW = vertical ? w * 0.72 : (w - gap) / 2
            var paneH = vertical ? (h - gap) / 2 : h * 0.72
            var firstX = vertical ? (w - paneW) / 2 : 0
            var firstY = vertical ? 0 : (h - paneH) / 2
            var secondX = vertical ? firstX : firstX + paneW + gap
            var secondY = vertical ? firstY + paneH + gap : firstY

            function pane(x, y, label) {
                ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.035)
                ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.20)
                ctx.lineWidth = 1
                roundedRect(ctx, x, y, paneW, paneH, 8)
                ctx.fill()
                roundedRect(ctx, x + 0.5, y + 0.5, paneW - 1, paneH - 1, 8)
                ctx.stroke()
                ctx.fillStyle = Color.muted
                ctx.font = "12px sans-serif"
                ctx.fillText(label, x + 10, y + 18)
            }

            pane(firstX, firstY, "Workspace 1")
            pane(secondX, secondY, "Workspace 2")

            var switchT = root.mode === "close" ? 1 - appear : appear
            if (slideDir === "top") switchT = 1 - switchT
            var centerX = lerp(firstX + paneW / 2, secondX + paneW / 2, switchT)
            var centerY = lerp(firstY + paneH / 2, secondY + paneH / 2, switchT)
            var ww = paneW * 0.54 * lerp(root.popinFrom, 1, appear)
            var wh = paneH * 0.50 * lerp(root.popinFrom, 1, appear)
            var wx = centerX - ww / 2
            var wy = centerY - wh / 2

            ctx.globalAlpha = root.doFade ? clamp01(appear) : 1
            ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
            roundedRect(ctx, wx, wy, ww, wh, 8)
            ctx.fill()
            ctx.strokeStyle = Color.accent
            ctx.lineWidth = 1.5
            roundedRect(ctx, wx, wy, ww, wh, 8)
            ctx.stroke()
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.20)
            ctx.lineWidth = 1
            roundedRect(ctx, wx + ww * 0.08, wy + wh * 0.16, ww * 0.84, 2, 1)
            ctx.stroke()

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
