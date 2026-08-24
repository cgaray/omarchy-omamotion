// OmaMotion data model: Omarchy's stock curves and animation leaves,
// Hyprland style options per leaf family, and built-in presets.
//
// Everything here mirrors /usr/share/omarchy/default/hypr/looknfeel.lua
// (the stock Omarchy 4 look and feel) plus the animation style matrix from
// https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
.pragma library

// Stock Omarchy bezier curves. points = [[x1,y1],[x2,y2]].
var STOCK_CURVES = {
    "easeOutQuint": { p1: [0.23, 1], p2: [0.32, 1] },
    "easeInOutCubic": { p1: [0.65, 0.05], p2: [0.36, 1] },
    "linear": { p1: [0.0, 0], p2: [1.0, 1] },
    "almostLinear": { p1: [0.5, 0.5], p2: [0.75, 1.0] },
    "quick": { p1: [0.15, 0], p2: [0.1, 1] }
}

var CURVE_KINDS = ["default", "linear"].concat(Object.keys(STOCK_CURVES))

function isEditableCurve(name) {
    return Object.prototype.hasOwnProperty.call(STOCK_CURVES, name)
}

// Animation leaves exactly as Omarchy ships them (leaf -> stock values).
// family drives which styles are legal; group drives UI sectioning.
var LEAVES = [
    { leaf: "global",        family: "global",      group: "Global",      enabled: true,  speed: 10,   bezier: "default" },
    { leaf: "border",        family: "fade",        group: "Chrome",      enabled: true,  speed: 5.39, bezier: "easeOutQuint" },
    { leaf: "windows",       family: "windows",     group: "Windows",     enabled: true,  speed: 3.79, bezier: "easeOutQuint", style: "" },
    { leaf: "windowsIn",     family: "windows",     group: "Windows",     enabled: true,  speed: 4.1,  bezier: "easeOutQuint", style: "popin 87%" },
    { leaf: "windowsOut",    family: "windows",     group: "Windows",     enabled: true,  speed: 1.49, bezier: "linear",       style: "popin 87%" },
    { leaf: "fadeIn",        family: "fade",        group: "Fades",       enabled: true,  speed: 1.73, bezier: "almostLinear" },
    { leaf: "fadeOut",       family: "fade",        group: "Fades",       enabled: true,  speed: 1.46, bezier: "almostLinear" },
    { leaf: "fade",          family: "fade",        group: "Fades",       enabled: true,  speed: 3.03, bezier: "quick" },
    { leaf: "fadeSwitch",    family: "fadeSwitch",  group: "Fades",       enabled: false },
    { leaf: "layers",        family: "windows",     group: "Layers",      enabled: true,  speed: 3.81, bezier: "easeOutQuint", style: "" },
    { leaf: "layersIn",      family: "layers",      group: "Layers",      enabled: true,  speed: 4,    bezier: "easeOutQuint", style: "fade" },
    { leaf: "layersOut",     family: "layers",      group: "Layers",      enabled: true,  speed: 1.5,  bezier: "linear",       style: "fade" },
    { leaf: "fadeLayersIn",  family: "fade",        group: "Layers",      enabled: true,  speed: 1.79, bezier: "almostLinear" },
    { leaf: "fadeLayersOut", family: "fade",        group: "Layers",      enabled: true,  speed: 1.39, bezier: "almostLinear" },
    { leaf: "workspaces",    family: "workspaces",  group: "Workspaces",  enabled: false }
]

var GROUP_ORDER = ["Global", "Windows", "Layers", "Fades", "Workspaces", "Chrome"]

// Curated style matrices per family. "" means: write no style key.
var STYLES = {
    "windows":    ["", "fade", "slide", "slide left", "slide right", "slide top", "slide bottom",
                   "slide next", "slide prev", "slide center", "slidevert",
                   "popin 60%", "popin 70%", "popin 80%", "popin 87%", "popin 95%",
                   "slide fade", "popin 80% fade"],
    "layers":     ["", "fade", "slide", "slide fade", "popin 80%", "popin 80% fade"],
    "workspaces": ["", "fade", "slide", "slidevert", "swipe"],
    "fade":       [""],
    "fadeSwitch": [""],
    "global":     [""]
}

var SPEED_MIN = 0.2
var SPEED_MAX = 12

function leafMeta(leaf) {
    for (var i = 0; i < LEAVES.length; i++)
        if (LEAVES[i].leaf === leaf) return LEAVES[i]
    return null
}

function stylesFor(family) {
    return Object.prototype.hasOwnProperty.call(STYLES, family) ? STYLES[family] : [""]
}

function defaultState() {
    var animations = {}
    for (var i = 0; i < LEAVES.length; i++) {
        var m = LEAVES[i]
        var entry = { enabled: m.enabled }
        if (m.speed !== undefined) entry.speed = m.speed
        entry.bezier = m.bezier
        if (m.style !== undefined && m.style !== "") entry.style = m.style
        animations[m.leaf] = entry
    }
    return { curves: cloneCurves(STOCK_CURVES), animations: animations }
}

function cloneCurves(src) {
    var out = {}
    for (var name in src)
        out[name] = { p1: src[name].p1.slice(), p2: src[name].p2.slice() }
    return out
}

function cloneState(s) {
    return JSON.parse(JSON.stringify(s))
}

function statesEqual(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
}

// ---------------------------------------------------------------- presets

function presetNames() {
    return ["Omarchy stock", "Butter", "Snappy", "Dramatic", "Instant"]
}

// Presets replace the animations table wholesale and keep the curve library.
function applyPreset(state, name) {
    var s = cloneState(state)
    var base = defaultState()
    if (name === "Omarchy stock") {
        s.animations = base.animations
    } else if (name === "Butter") {
        s.animations = scaled(base.animations, 1.7)
        s.animations.windowsIn.style = "popin 92%"
        s.animations.windows.bezier = "easeInOutCubic"
        s.animations.layersIn.speed = round2(base.animations.layersIn.speed * 1.5)
        s.animations.workspaces.enabled = true
        s.animations.workspaces.style = "slide"
        s.animations.workspaces.speed = 4.5
        s.animations.workspaces.bezier = "easeInOutCubic"
    } else if (name === "Snappy") {
        s.animations = scaled(base.animations, 0.5)
        s.animations.windowsIn.style = "popin 94%"
        s.animations.fade.bezier = "quick"
    } else if (name === "Dramatic") {
        s.animations = scaled(base.animations, 1.35)
        s.animations.windows.bezier = "easeInOutCubic"
        s.animations.windowsIn.style = "slide top"
        s.animations.windowsOut.style = "slide bottom"
        s.animations.windowsOut.bezier = "easeInOutCubic"
        s.animations.workspaces.enabled = true
        s.animations.workspaces.style = "slidevert"
        s.animations.workspaces.speed = 6
        s.animations.workspaces.bezier = "easeInOutCubic"
    } else if (name === "Instant") {
        for (var leaf in base.animations) base.animations[leaf].enabled = false
        s.animations = base.animations
    }
    return s
}

function scaled(anims, factor) {
    var out = JSON.parse(JSON.stringify(anims))
    for (var leaf in out) {
        if (out[leaf].speed !== undefined)
            out[leaf].speed = clampSpeed(round2(out[leaf].speed * factor))
    }
    return out
}

function round2(v) { return Math.round(v * 100) / 100 }

function clampSpeed(v) { return Math.min(SPEED_MAX, Math.max(SPEED_MIN, v)) }
