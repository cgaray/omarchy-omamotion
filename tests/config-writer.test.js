// Exercises the shell helper embedded in ConfigWriter.qml against real files.
// The script lives inside a QML string, so it is easy to break silently; these
// cases pin down the properties the writer exists to guarantee.
const assert = require("assert")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { execFileSync, spawnSync } = require("child_process")

// Pull the helper out of the `readonly property string helper: [...]` literal.
function extractHelper(file) {
  const src = fs.readFileSync(file, "utf8")
  const open = src.indexOf("[", src.indexOf("readonly property string helper:"))
  let depth = 0, end = -1
  for (let i = open; i < src.length; i++) {
    if (src[i] === "[") depth++
    else if (src[i] === "]" && --depth === 0) { end = i; break }
  }
  assert.notStrictEqual(end, -1, "could not find the helper array in " + file)
  // The array is a plain list of string literals joined with newlines.
  return JSON.parse("[" + src.slice(open + 1, end).replace(/,\s*$/, "") + "]").join("\n")
}

const helper = extractHelper(path.join(__dirname, "..", "ConfigWriter.qml"))
const work = fs.mkdtempSync(path.join(os.tmpdir(), "omamotion-writer-"))

function run(mode, target, want, stdin) {
  return spawnSync("sh", ["-c", helper, "omamotion-config", mode, target, String(want)],
                   { input: stdin === undefined ? "" : stdin })
}
const bytes = (s) => Buffer.byteLength(s, "utf8")
const mode = (p) => (fs.statSync(p).mode & 0o777).toString(8)
const file = (name) => path.join(work, name)

// An existing file is replaced with its permission bits intact, and the
// previous contents survive in the backup.
fs.writeFileSync(file("cfg.lua"), "original\n")
fs.chmodSync(file("cfg.lua"), 0o640)
assert.strictEqual(run("install", file("cfg.lua"), bytes("new body\n"), "new body\n").status, 0)
assert.strictEqual(fs.readFileSync(file("cfg.lua"), "utf8"), "new body\n")
assert.strictEqual(mode(file("cfg.lua")), "640")
assert.strictEqual(fs.readFileSync(file("cfg.lua.omamotion.bak"), "utf8"), "original\n")
assert.strictEqual(mode(file("cfg.lua.omamotion.bak")), "640")

// Restore puts the pre-write contents back.
assert.strictEqual(run("restore", file("cfg.lua"), 0).status, 0)
assert.strictEqual(fs.readFileSync(file("cfg.lua"), "utf8"), "original\n")
assert.strictEqual(mode(file("cfg.lua")), "640")

// Restoring with no backup fails instead of clobbering the file.
assert.strictEqual(run("restore", file("absent.lua"), 0).status, 14)

// A file we create ourselves gets ordinary config permissions.
assert.strictEqual(run("install", file("new.lua"), bytes("fresh\n"), "fresh\n").status, 0)
assert.strictEqual(mode(file("new.lua")), "644")

// A symlinked target is refused, never written through.
fs.writeFileSync(file("secret"), "target\n")
fs.symlinkSync(file("secret"), file("link.lua"))
assert.strictEqual(run("install", file("link.lua"), bytes("pwned\n"), "pwned\n").status, 11)
assert.strictEqual(fs.readFileSync(file("secret"), "utf8"), "target\n")

// So is anything that is not a regular file.
execFileSync("mkfifo", [file("fifo.lua")])
assert.strictEqual(run("install", file("fifo.lua"), 2, "x\n").status, 12)

// A stage that is shorter than promised — the sender died mid-write — is
// dropped before the rename, so the live file is untouched.
fs.writeFileSync(file("cfg2.lua"), "keepme\n")
assert.strictEqual(run("install", file("cfg2.lua"), 999, "trunc\n").status, 21)
assert.strictEqual(fs.readFileSync(file("cfg2.lua"), "utf8"), "keepme\n")

// Multibyte content round-trips: the byte count QML computes is the count the
// helper checks against.
const utf8 = '-- héllo →\nhl.animation({ leaf = "windowsIn" })\n'
assert.strictEqual(run("install", file("utf8.lua"), bytes(utf8), utf8).status, 0)
assert.strictEqual(fs.readFileSync(file("utf8.lua"), "utf8"), utf8)

// No staging files are left behind by any of the above.
assert.deepStrictEqual(fs.readdirSync(work).filter((n) => n.startsWith(".omamotion.")), [])

fs.rmSync(work, { recursive: true, force: true })
console.log("config-writer tests passed")
