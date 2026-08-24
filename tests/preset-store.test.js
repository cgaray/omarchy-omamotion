const assert = require("assert")
const fs = require("fs")
const vm = require("vm")

function load(file, imports = {}) {
  let source = fs.readFileSync(file, "utf8")
    .replace(/^\.pragma library\s*$/gm, "")
    .replace(/^import .*$/gm, "")
  const context = { ...imports, console, isFinite, JSON, Object, Array, String, Number, Math }
  vm.createContext(context)
  vm.runInContext(source, context, { filename: file })
  return context
}

const motion = load("MotionState.js")
const store = load("PresetStore.js", { MotionState: motion })
const state = motion.defaultState()

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

console.log("preset-store tests passed")
