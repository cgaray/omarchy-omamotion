// Managed-block reader/writer for ~/.config/hypr/looknfeel.lua.
//
// Contract: OmaMotion owns exactly one fenced block between two marker
// lines. Content outside the fences is preserved verbatim. Clearing every
// override removes the whole fence and restores the file byte for byte.
//
// The block is pure Lua in the same shape Omarchy itself writes:
//
//   -- >>> omamotion managed block >>>
//   hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
//   hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
//   -- <<< omamotion managed block <<<
.pragma library
.import "MotionState.js" as MotionState

var BEGIN = "-- >>> omamotion managed block >>>"
var END = "-- <<< omamotion managed block <<<"

// ------------------------------------------------------------ reading

function findBlock(text) {
    var b = text.indexOf(BEGIN)
    if (b === -1) return null
    var e = text.indexOf(END, b)
    if (e === -1) return { unclosed: true }
    return { begin: b, bodyStart: b + BEGIN.length, bodyEnd: e, end: e + END.length }
}

function readState(text) {
    var block = findBlock(text)
    if (!block) return { found: false, state: null, error: "" }
    if (block.unclosed) return { found: true, state: null, error: "managed block is missing its closing fence" }
    var body = text.substring(block.bodyStart, block.bodyEnd)
    try {
        return { found: true, state: parseBody(body), error: "" }
    } catch (err) {
        return { found: true, state: null, error: String(err) }
    }
}

// Parse hl.curve(...) and hl.animation(...) calls from a fenced body.
// The scanner handles Lua literals and never evaluates the file.
function parseBody(body) {
    var curves = {}
    var animations = {}
    var i = 0
    while (i < body.length) {
        var atCurve = body.indexOf("hl.curve(", i)
        var atAnim = body.indexOf("hl.animation(", i)
        if (atCurve === -1 && atAnim === -1) break
        var isCurve = atAnim === -1 || (atCurve !== -1 && atCurve < atAnim)
        var callAt = isCurve ? atCurve : atAnim
        var openParen = body.indexOf("(", callAt)
        var closeParen = matchParen(body, openParen)
        if (closeParen === -1) throw new Error("unbalanced parentheses in managed block")
        var argsText = body.substring(openParen + 1, closeParen)
        var args = splitTopLevel(argsText)
        if (isCurve) {
            if (args.length !== 2) throw new Error("hl.curve expects 2 arguments")
            var name = stripQuotes(args[0].trim())
            var def = parseLuaValue(args[1].trim())
            if (!def || def.type !== "bezier" || !def.points || def.points.length !== 2)
                throw new Error("unsupported curve definition for '" + name + "'")
            curves[name] = {
                p1: [Number(def.points[0][0]), Number(def.points[0][1])],
                p2: [Number(def.points[1][0]), Number(def.points[1][1])]
            }
        } else {
            if (args.length !== 1) throw new Error("hl.animation expects 1 argument")
            var t = parseLuaValue(args[0].trim())
            if (!t || !t.leaf) throw new Error("hl.animation missing leaf")
            animations[t.leaf] = t
        }
        i = closeParen + 1
    }
    return { curves: curves, animations: animations }
}

function matchParen(text, openAt) {
    var depth = 0, inStr = false, quote = ""
    for (var i = openAt; i < text.length; i++) {
        var ch = text[i]
        if (inStr) {
            if (ch === "\\") { i++; continue }
            if (ch === quote) inStr = false
            continue
        }
        if (ch === "\"" || ch === "'") { inStr = true; quote = ch; continue }
        if (ch === "(" || ch === "{" || ch === "[") depth++
        else if (ch === ")" || ch === "}" || ch === "]") {
            depth--
            if (depth === 0) return i
        }
    }
    return -1
}

function splitTopLevel(text) {
    var parts = [], depth = 0, inStr = false, quote = "", cur = ""
    for (var i = 0; i < text.length; i++) {
        var ch = text[i]
        if (inStr) {
            cur += ch
            if (ch === "\\") { cur += text[i + 1] || ""; i++; continue }
            if (ch === quote) inStr = false
            continue
        }
        if (ch === "\"" || ch === "'") { inStr = true; quote = ch; cur += ch; continue }
        if (ch === "(" || ch === "{" || ch === "[") depth++
        else if (ch === ")" || ch === "}" || ch === "]") depth--
        if (ch === "," && depth === 0) { parts.push(cur); cur = "" }
        else cur += ch
    }
    if (cur.trim() !== "") parts.push(cur)
    return parts
}

function stripQuotes(s) {
    if (s.length >= 2 && ((s[0] === "\"" && s[s.length - 1] === "\"") || (s[0] === "'" && s[s.length - 1] === "'")))
        return s.substring(1, s.length - 1)
    return s
}

// Tiny recursive-descent parser for Lua literal tables/values.
// Positional items land in the result array; keyed items on the object.
function parseLuaValue(s) {
    s = s.trim()
    if (s[0] === "{") return parseTable(s, { i: 1 }).value
    if (s === "true") return true
    if (s === "false") return false
    var n = Number(s)
    if (!isNaN(n)) return n
    return stripQuotes(s)
}

function parseTable(s, pos) {
    var obj = []
    for (;;) {
        skipWs(s, pos)
        if (s[pos.i] === "}") { pos.i++; return { value: obj } }
        var value
        var key = tryParseKey(s, pos)
        if (key !== null) {
            skipWs(s, pos)
            value = parseLuaValueFromPos(s, pos)
            // Keyed entries become named properties on the result array;
            // JSON serialization still shows only positional items.
            obj[key] = value
        } else {
            value = parseLuaValueFromPos(s, pos)
            obj.push(value)
        }
        skipWs(s, pos)
        if (s[pos.i] === ",") { pos.i++; continue }
        if (s[pos.i] === "}") { pos.i++; return { value: obj } }
        throw new Error("unexpected token '" + s[pos.i] + "' in table")
    }
}

function parseLuaValueFromPos(s, pos) {
    skipWs(s, pos)
    var ch = s[pos.i]
    if (ch === "{") {
        pos.i++
        return parseTable(s, pos).value
    }
    if (ch === "\"" || ch === "'") {
        var quote = ch, out = ""
        pos.i++
        while (pos.i < s.length && s[pos.i] !== quote) {
            if (s[pos.i] === "\\") { out += s[pos.i + 1] || ""; pos.i += 2 }
            else { out += s[pos.i]; pos.i++ }
        }
        pos.i++
        return out
    }
    var start = pos.i
    while (pos.i < s.length && !",}".includes(s[pos.i])) pos.i++
    var raw = s.substring(start, pos.i).trim()
    if (raw === "true") return true
    if (raw === "false") return false
    var n = Number(raw)
    if (!isNaN(n) && raw !== "") return n
    throw new Error("cannot parse literal '" + raw + "'")
}

function tryParseKey(s, pos) {
    // A key is a bare identifier followed by '='. Returns null (and
    // restores the position) when this isn't a keyed entry.
    var save = pos.i
    skipWs(s, pos)
    var start = pos.i
    while (pos.i < s.length && /[A-Za-z0-9_]/.test(s[pos.i])) pos.i++
    var end = pos.i
    if (end > start) {
        skipWs(s, pos)
        if (s[pos.i] === "=") {
            pos.i++
            return s.substring(start, end)
        }
    }
    pos.i = save
    return null
}

function skipWs(s, pos) {
    while (pos.i < s.length && /\s/.test(s[pos.i])) pos.i++
}

// ------------------------------------------------------------- writing

function fmtNum(v) {
    var r = Math.round(v * 100) / 100
    return String(r)
}

function fmtPoints(p1, p2) {
    return "{ { " + fmtNum(p1[0]) + ", " + fmtNum(p1[1]) + " }, { " + fmtNum(p2[0]) + ", " + fmtNum(p2[1]) + " } }"
}

function luaTable(entries) {
    var parts = []
    for (var i = 0; i < entries.length; i++)
        parts.push(entries[i][0] + " = " + entries[i][1])
    return "{ " + parts.join(", ") + " }"
}

// Deterministic generator: stock curve order first, then custom curves
// alphabetically, then leaves in MotionState.LEAVES order.
function generateBody(state, leafOrder) {
    var lines = []
    var names = Object.keys(state.curves)
    var stock = [], custom = []
    for (var i = 0; i < names.length; i++)
        (MotionState.isEditableCurve(names[i]) ? stock : custom).push(names[i])
    stock.sort(function (a, b) {
        return MotionState.CURVE_KINDS.indexOf(a) - MotionState.CURVE_KINDS.indexOf(b)
    })
    custom.sort()
    var ordered = stock.concat(custom)
    for (var c = 0; c < ordered.length; c++) {
        var nm = ordered[c], cv = state.curves[nm]
        lines.push('hl.curve("' + nm + '", { type = "bezier", points = '
                   + fmtPoints(cv.p1, cv.p2) + ' })')
    }
    for (var l = 0; l < leafOrder.length; l++) {
        var leaf = leafOrder[l]
        var a = state.animations[leaf]
        if (!a) continue
        var entries = [["leaf", '"' + leaf + '"'], ["enabled", a.enabled ? "true" : "false"]]
        if (a.speed !== undefined) entries.push(["speed", fmtNum(a.speed)])
        if (a.bezier) entries.push(["bezier", '"' + a.bezier + '"'])
        if (a.style && a.style !== "") entries.push(["style", '"' + a.style + '"'])
        lines.push("hl.animation(" + luaTable(entries) + ")")
    }
    return lines.join("\n")
}

// Returns the full new file text. body === null removes an existing block.
//
// Insertion appends the fence at EOF with exactly one separating blank
// line and NO trailing newline, so removal can restore prior bytes
// exactly: strip one blank line before BEGIN and everything from BEGIN on.
function applyToText(fileText, body) {
    var block = findBlock(fileText)
    if (body === null) {
        if (!block || block.unclosed) {
            // Unclosed fence: fall back to a tolerant cut from BEGIN to EOF.
            var b = fileText.indexOf(BEGIN)
            if (b === -1) return fileText
            var head = fileText.substring(0, b)
            return head.endsWith("\n") ? head.slice(0, -1) : head
        }
        var head2 = fileText.substring(0, block.begin)
        if (head2.endsWith("\n\n")) head2 = head2.slice(0, -1)
        return head2
    }
    var fenced = BEGIN + "\n" + body + "\n" + END
    if (block && !block.unclosed) {
        return fileText.substring(0, block.begin) + fenced + fileText.substring(block.end)
    }
    var base = fileText
    if (base === "") return fenced
    if (!base.endsWith("\n")) base += "\n"
    if (base.length === 0 || base.endsWith("\n\n")) return base + fenced
    return base + "\n" + fenced
}
