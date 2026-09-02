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
    // speed and bezier are both required here even though Omarchy's own
    // stock looknfeel.lua omits both (line 88, "workspaces", currently
    // enabled = false) — on this Hyprland version hl.animation("workspaces")
    // rejects the whole config on reload without them, one error at a time
    // ("missing required field speed", then once that's fixed, "bezier or
    // spring is required"), unlike fadeSwitch just above, which genuinely
    // needs neither (confirmed: it has produced zero reload errors across
    // many saves). Values match this plugin's own seeded "Default" preset.
    { leaf: "workspaces",    family: "workspaces",  group: "Workspaces",  enabled: false, speed: 2, bezier: "easeOutQuint" }
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

// --------------------------------------------------------- preset labels

// One-click vibes. preset refers to a presetNames() entry.
var VIBES = [
    { id: "Instant",  name: "Instant",  desc: "No animation; windows appear immediately." },
    { id: "Snappy",   name: "Snappy",   desc: "Quick and minimal. For getting things done." },
    { id: "Balanced", name: "Balanced", desc: "The Omarchy default. Gentle and clear." },
    { id: "Smooth",   name: "Smooth",   desc: "Slower and softer, almost cinematic." },
    { id: "Playful",  name: "Playful",  desc: "Bouncy slides and big pops. Shows off." }
]

var VIBE_PRESET = {
    "Instant": "Instant", "Snappy": "Snappy", "Balanced": "Omarchy stock",
    "Smooth": "Butter", "Playful": "Dramatic"
}

// Simple-mode sections: plain names, curated leaves (global and fadeSwitch
// stay advanced-only. A master multiplier and niche toggle confuse more
// than they help).
var SIMPLE_GROUPS = [
    { name: "Windows",        leaves: ["windows", "windowsIn", "windowsOut"] },
    { name: "Menus & panels", leaves: ["layers", "layersIn", "layersOut", "fadeLayersIn", "fadeLayersOut"] },
    { name: "Fades",          leaves: ["fadeIn", "fadeOut", "fade"] },
    { name: "Desktops",       leaves: ["workspaces"] },
    { name: "Borders",        leaves: ["border"] }
]

var LEAF_LABELS = {
    "windows": "Move & resize", "windowsIn": "Window opens", "windowsOut": "Window closes",
    "layers": "Panel move", "layersIn": "Panel opens", "layersOut": "Panel closes",
    "fadeLayersIn": "Panel fades in", "fadeLayersOut": "Panel fades out",
    "fadeIn": "Fade in", "fadeOut": "Fade out", "fade": "Dim & overlay fade",
    "workspaces": "Desktop switch", "border": "Border draw", "global": "Master speed",
    "fadeSwitch": "Workspace fade"
}

// Curated style choices for Simple mode: [token, label] pairs.
var SIMPLE_STYLES = {
    "windows": [
        ["", "Plain"], ["fade", "Fade"], ["slide", "Slide"], ["popin 87%", "Pop"],
        ["slide fade", "Slide & fade"], ["popin 87% fade", "Pop & fade"]
    ],
    "layers": [
        ["", "Plain"], ["fade", "Fade"], ["slide", "Slide"]
    ],
    "workspaces": [
        ["", "Plain"], ["fade", "Fade"], ["slide", "Slide"],
        ["slidevert", "Slide vertically"], ["swipe", "Swipe"]
    ]
}

function simpleGroupNames() {
    return SIMPLE_GROUPS.map(function (g) { return g.name })
}

function simpleGroupLeaves(groupName) {
    for (var i = 0; i < SIMPLE_GROUPS.length; i++)
        if (SIMPLE_GROUPS[i].name === groupName) return SIMPLE_GROUPS[i].leaves
    return []
}

function leafLabel(leaf) {
    return Object.prototype.hasOwnProperty.call(LEAF_LABELS, leaf) ? LEAF_LABELS[leaf] : leaf
}

function simpleStylesFor(family) {
    return Object.prototype.hasOwnProperty.call(SIMPLE_STYLES, family) ? SIMPLE_STYLES[family] : null
}

function simpleStyleLabels(family) {
    var pairs = simpleStylesFor(family)
    return pairs ? pairs.map(function (p) { return p[1] }) : []
}

function simpleStyleToken(family, label) {
    var pairs = simpleStylesFor(family)
    if (pairs) for (var i = 0; i < pairs.length; i++)
        if (pairs[i][1] === label) return pairs[i][0]
    return ""
}

function simpleStyleLabel(family, token) {
    var pairs = simpleStylesFor(family)
    if (pairs) for (var i = 0; i < pairs.length; i++)
        if (pairs[i][0] === token) return pairs[i][1]
    return token === "" ? "Plain" : token
}

// Hyprland speeds are durations: higher = slower.
function speedWord(v) {
    if (v <= 1.5) return "Very fast"
    if (v <= 3) return "Fast"
    if (v <= 5) return "Balanced"
    if (v <= 7.5) return "Relaxed"
    return "Slow"
}

// Which vibe (if any) the current animations match. rev is a change
// counter passed in so QML bindings re-evaluate after in-place mutations.
function currentVibe(state, rev) {
    void rev
    var cur = JSON.stringify(state.animations)
    for (var i = 0; i < VIBES.length; i++) {
        var probe = applyPreset(cloneState(state), VIBE_PRESET[VIBES[i].id])
        if (JSON.stringify(probe.animations) === cur) return VIBES[i].id
    }
    return ""
}
