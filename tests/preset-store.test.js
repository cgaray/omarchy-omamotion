const assert = require("assert")
const fs = require("fs")
const vm = require("vm")

function load(file, imports = {}) {
  let source = fs.readFileSync(file, "utf8")
    .replace(/^\.pragma library\s*$/gm, "")
    .replace(/^\.?import .*$/gm, "")
  const context = { ...imports, console, isFinite, isNaN, JSON, Object, Array, String, Number, Math, Error, RegExp }
  vm.createContext(context)
  vm.runInContext(source, context, { filename: file })
  return context
}

const motion = load("MotionState.js")
const store = load("PresetStore.js", { MotionState: motion })
const lua = load("LuaConfig.js", { MotionState: motion })
const state = motion.defaultState()
const leafOrder = motion.LEAVES.map((m) => m.leaf)

let result = store.upsert([], "Overshoot", state)
assert.strictEqual(result.ok, true)
assert.strictEqual(store.parse(result.text).ok, true)

const overshoot = JSON.parse(JSON.stringify(state))
overshoot.curves.custom = { p1: [0.2, 1.4], p2: [0.8, -0.2] }
result = store.upsert([], "Overshoot", overshoot)
assert.strictEqual(result.ok, true)

const injected = JSON.parse(JSON.stringify(state))
injected.animations.windows.style = 'fade", hacked = true, style = "'
assert.strictEqual(store.upsert([], "Injected", injected).ok, false)

const invalidCurve = JSON.parse(JSON.stringify(state))
invalidCurve.animations.windows.bezier = "missing"
assert.strictEqual(store.upsert([], "Invalid", invalidCurve).ok, false)

const tooMany = Array.from({ length: 33 }, (_, i) => ({ name: String(i), state }))
assert.strictEqual(store.parse(JSON.stringify(tooMany)).ok, false)

// --- untrusted display strings -------------------------------------------

assert.strictEqual(store.plainName("<b>bold</b>"), " b bold /b ")
assert.strictEqual(store.plainName("Snappy"), "Snappy")
assert.strictEqual(store.plainName(undefined), "")

// --- builtin vibe presets -------------------------------------------------

// scaled() only rewrites .speed, so any preset relying purely on scaled()
// silently inherits workspaces.enabled = false from the stock base state.
// Snappy should still transition on workspace switch, just quickly —
// "quick and minimal" isn't "no transition at all", and Butter/Dramatic
// both explicitly enable it for the same reason.
const snappy = motion.applyPreset(motion.defaultState(), "Snappy")
assert.strictEqual(snappy.animations.workspaces.enabled, true)

// --- config size bound ----------------------------------------------------

assert.strictEqual(lua.utf8Length("abc"), 3)
assert.strictEqual(lua.utf8Length("é"), 2)
assert.strictEqual(lua.utf8Length("→"), 3)
assert.strictEqual(lua.utf8Length("\u{1F600}"), 4)

assert.strictEqual(lua.exceedsLimit("-- small file"), false)
const oversized = "-".repeat(1048577)
assert.strictEqual(lua.exceedsLimit(oversized), true)

const refused = lua.readState(oversized)
assert.strictEqual(refused.oversize, true)
assert.strictEqual(refused.found, false)
assert.strictEqual(refused.state, null)

// A file just under the cap is still parsed normally.
const padded = "-- pad\n".repeat(1000) + lua.applyToText("", lua.generateBody(state, leafOrder))
assert.strictEqual(lua.exceedsLimit(padded), false)
assert.strictEqual(lua.readState(padded).found, true)

// --- generated Lua never breaks out of its string literals ----------------

const hostile = JSON.parse(JSON.stringify(state))
hostile.curves['bad", hacked = true, x = "'] = { p1: [0.2, 0.2], p2: [0.8, 0.8] }
hostile.animations.windows.style = 'fade", hacked = true, style = "'
const body = lua.generateBody(hostile, leafOrder)
assert.strictEqual(body.includes("hacked"), false)
assert.strictEqual(lua.readState(lua.applyToText("", body)).error, "")

// Legitimate stock styles and curve names survive the filter.
const styled = JSON.parse(JSON.stringify(state))
styled.animations.windowsIn.style = "popin 87%"
assert.ok(lua.generateBody(styled, leafOrder).includes('style = "popin 87%"'))

// --- keys that are not data ------------------------------------------------
// "__proto__" matches the token charset and, assigned to a plain object,
// replaces its prototype instead of storing a value. "constructor" and
// "prototype" resolve to inherited members that read as truthy, which let an
// unknown leaf past a bare truthiness check.

for (const key of ["__proto__", "constructor", "prototype"]) {
  assert.strictEqual(store.validToken(key), false, key + " must not be a valid token")
  assert.strictEqual(store.parse(JSON.stringify([{ name: key, state }])).ok, false,
                     key + " must not be a valid preset name")
  assert.strictEqual(store.upsert([], key, state).ok, false,
                     key + " must not be upsertable")

  const leafKey = JSON.parse(JSON.stringify(state))
  leafKey.animations = { [key]: { enabled: true } }
  assert.strictEqual(store.validState(leafKey), false, key + " must not pass as a leaf")
}
assert.strictEqual(store.parse(JSON.stringify([{ name: "Real", state }])).ok, true)

// A curve named __proto__ must not become the curves map's prototype.
const proto = lua.readState(
  lua.BEGIN + '\nhl.curve("__proto__", { type = "bezier", points = { { 0.1, 0.2 }, { 0.3, 0.4 } } })\n' + lua.END)
assert.strictEqual(proto.state.curves.p1, undefined, "curves must not inherit from parsed input")
assert.strictEqual(lua.generateBody({ curves: { __proto__: { p1: [0, 0], p2: [1, 1] } }, animations: {} },
                                    leafOrder).includes("__proto__"), false)

console.log("preset-store tests passed")
