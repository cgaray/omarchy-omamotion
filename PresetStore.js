.pragma library

// Custom presets are user data, not executable configuration. Keep the file
// small and reject malformed state before it reaches the editor or Lua writer.
var MAX_FILE_CHARS = 65536
var MAX_PRESETS = 32
var MAX_NAME_CHARS = 48
var LEAF_FAMILIES = {
    global: "global", border: "fade", windows: "windows", windowsIn: "windows",
    windowsOut: "windows", fadeIn: "fade", fadeOut: "fade", fade: "fade",
    fadeSwitch: "fadeSwitch", layers: "windows", layersIn: "layers",
    layersOut: "layers", fadeLayersIn: "fade", fadeLayersOut: "fade",
    workspaces: "workspaces"
}
var STYLES = {
    global: [""], fade: [""], fadeSwitch: [""],
    windows: ["", "fade", "slide", "slide left", "slide right", "slide top", "slide bottom",
              "slide next", "slide prev", "slide center", "slidevert", "popin 60%", "popin 70%",
              "popin 80%", "popin 87%", "popin 95%", "slide fade", "popin 80% fade"],
    layers: ["", "fade", "slide", "slide fade", "popin 80%", "popin 80% fade"],
    workspaces: ["", "fade", "slide", "slidevert", "swipe"]
}

// Preset names are user-authored strings that reach QML text properties.
// Anywhere we own the Text item we set textFormat: Text.PlainText; this is
// for the places we do not own it (bar tooltips, Button labels), where Qt
// would otherwise sniff the string and render it as rich text.
function plainName(name) {
    return String(name === undefined || name === null ? "" : name)
        .replace(/[<>&]/g, " ")
        .replace(/[\u0000-\u001f\u007f]/g, " ")
}

function isFiniteNumber(value) {
    return typeof value === "number" && isFinite(value)
}

function validPoint(point) {
    return Array.isArray(point) && point.length === 2
        && isFiniteNumber(point[0]) && isFiniteNumber(point[1])
        && point[0] >= 0 && point[0] <= 1 && point[1] >= -0.5 && point[1] <= 1.5
}

// Keys that reach a plain object as an index. "__proto__" matches the token
// charset, and assigning it swaps the object's prototype instead of storing
// a value; "constructor" and "prototype" resolve to inherited members that
// read as truthy in an existence check.
// Compared directly rather than looked up in a table: writing "__proto__"
// as an object-literal key sets that object's prototype instead of adding
// the key, so the table would silently not contain the one name that
// matters most.
function isReservedKey(key) {
    var k = String(key)
    return k === "__proto__" || k === "constructor" || k === "prototype"
}

function has(obj, key) {
    return Object.prototype.hasOwnProperty.call(obj, key)
}

function validToken(value) {
    return typeof value === "string"
        && /^[A-Za-z0-9_-]+$/.test(value)
        && !isReservedKey(value)
}

function validState(state) {
    if (!state || typeof state !== "object"
        || !state.curves || typeof state.curves !== "object"
        || !state.animations || typeof state.animations !== "object") return false

    var curveNames = Object.keys(state.curves)
    if (curveNames.length === 0 || curveNames.length > 64) return false
    for (var i = 0; i < curveNames.length; i++) {
        if (!validToken(curveNames[i])) return false
        var curve = state.curves[curveNames[i]]
        if (!curve || !validPoint(curve.p1) || !validPoint(curve.p2)) return false
    }

    var leaves = Object.keys(state.animations)
    if (leaves.length === 0 || leaves.length > 64) return false
    for (var j = 0; j < leaves.length; j++) {
        // has(), not truthiness: LEAF_FAMILIES["constructor"] is inherited
        // and truthy, which let an unknown leaf through this check.
        if (!has(LEAF_FAMILIES, leaves[j])) return false
        var entry = state.animations[leaves[j]]
        if (!entry || typeof entry.enabled !== "boolean") return false
        if (entry.speed !== undefined
            && (!isFiniteNumber(entry.speed) || entry.speed < 0.2 || entry.speed > 12)) return false
        if (entry.bezier !== undefined
            && (typeof entry.bezier !== "string"
                || (entry.bezier !== "default" && !has(state.curves, entry.bezier)))) return false
        if (entry.style !== undefined) {
            var family = LEAF_FAMILIES[leaves[j]]
            var styles = has(STYLES, family) ? STYLES[family] : [""]
            if (typeof entry.style !== "string" || styles.indexOf(entry.style) === -1) return false
        }
    }
    return true
}

function parse(text) {
    var source = String(text || "")
    if (source.length === 0) return { ok: true, presets: [] }
    if (source.length > MAX_FILE_CHARS) return { ok: false, presets: [], error: "Preset file exceeds 64 KiB" }

    var parsed
    try { parsed = JSON.parse(source) } catch (e) {
        return { ok: false, presets: [], error: "Preset file is not valid JSON" }
    }
    if (!Array.isArray(parsed)) return { ok: false, presets: [], error: "Preset file must contain an array" }
    if (parsed.length > MAX_PRESETS) return { ok: false, presets: [], error: "Preset file contains too many presets" }

    var names = Object.create(null)
    for (var i = 0; i < parsed.length; i++) {
        var preset = parsed[i]
        if (!preset || typeof preset.name !== "string"
            || preset.name.trim() === "" || preset.name.length > MAX_NAME_CHARS
            || !preset.state || !validState(preset.state))
            return { ok: false, presets: [], error: "Preset " + (i + 1) + " is invalid" }
        var name = preset.name.trim()
        if (names[name]) return { ok: false, presets: [], error: "Preset names must be unique" }
        if (isReservedKey(name)) return { ok: false, presets: [], error: "Preset " + (i + 1) + " is invalid" }
        names[name] = true
        preset.name = name
    }
    return { ok: true, presets: parsed }
}

function upsert(presets, name, state) {
    var cleanName = String(name || "").trim()
    if (cleanName === "" || cleanName.length > MAX_NAME_CHARS || isReservedKey(cleanName))
        return { ok: false, error: "Preset names must be 1-48 characters" }
    if (!validState(state)) return { ok: false, error: "Current motion state is invalid" }

    var next = JSON.parse(JSON.stringify(presets || []))
    var snapshot = JSON.parse(JSON.stringify(state))
    var replaced = false
    for (var i = 0; i < next.length; i++) {
        if (next[i].name === cleanName) {
            next[i] = { name: cleanName, state: snapshot }
            replaced = true
            break
        }
    }
    if (!replaced) {
        if (next.length >= MAX_PRESETS) return { ok: false, error: "At most 32 custom presets are supported" }
        next.push({ name: cleanName, state: snapshot })
    }
    var text = JSON.stringify(next, null, 2)
    if (text.length > MAX_FILE_CHARS) return { ok: false, error: "Preset file would exceed 64 KiB" }
    return { ok: true, presets: next, text: text }
}
