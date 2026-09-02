// Exercises the shell helper embedded in SafeFile.qml against real files.
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

const helper = extractHelper(path.join(__dirname, "..", "SafeFile.qml"))
const work = fs.mkdtempSync(path.join(os.tmpdir(), "omamotion-writer-"))

function run(mode, target, want, stdin, keepbak) {
  // maxBuffer covers the bounded oversized read; timeout catches a hang on a
  // fifo, which is exactly what the non-blocking open exists to prevent.
  return spawnSync("sh", ["-c", helper, "omamotion-file", mode, target, String(want),
                          keepbak === undefined ? "1" : String(keepbak)],
                   { input: stdin === undefined ? "" : stdin,
                     maxBuffer: 8 * 1024 * 1024, timeout: 15000 })
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

// A managed file whose parent directory does not exist yet gets one created
// for it (e.g. presets.json living outside the plugin tree, with nothing
// else responsible for creating its directory on a fresh install).
const freshDir = path.join(work, "fresh-subdir")
assert.strictEqual(fs.existsSync(freshDir), false)
assert.strictEqual(
  run("install", path.join(freshDir, "presets.json"), bytes("[]\n"), "[]\n").status, 0)
assert.strictEqual(fs.readFileSync(path.join(freshDir, "presets.json"), "utf8"), "[]\n")

// A stage that is shorter than promised — the sender died mid-write — is
// dropped before the rename, so the live file is untouched, and the backup
// still holds the state before the last SUCCESSFUL write: an aborted save
// must not destroy the recovery point.
fs.writeFileSync(file("cfg2.lua"), "keepme\n")
assert.strictEqual(run("install", file("cfg2.lua"), bytes("v2\n"), "v2\n").status, 0)
assert.strictEqual(run("install", file("cfg2.lua"), 999, "trunc\n").status, 21)
assert.strictEqual(fs.readFileSync(file("cfg2.lua"), "utf8"), "v2\n")
assert.strictEqual(fs.readFileSync(file("cfg2.lua.omamotion.bak"), "utf8"), "keepme\n")

// The backup path is predictable, so it is plantable. Writing it by shell
// redirection followed a symlink there and gave an arbitrary write outside
// the config directory; it is now staged and renamed like the install.
fs.writeFileSync(file("live.lua"), "original\n")
fs.writeFileSync(file("outside"), "PRIVATE\n")
fs.symlinkSync(file("outside"), file("live.lua.omamotion.bak"))
assert.strictEqual(run("install", file("live.lua"), bytes("new\n"), "new\n").status, 0)
assert.strictEqual(fs.readFileSync(file("outside"), "utf8"), "PRIVATE\n")
assert.strictEqual(fs.lstatSync(file("live.lua.omamotion.bak")).isSymbolicLink(), false)
assert.strictEqual(fs.readFileSync(file("live.lua.omamotion.bak"), "utf8"), "original\n")

// Restoring from a symlinked backup is refused rather than followed.
fs.unlinkSync(file("live.lua.omamotion.bak"))
fs.symlinkSync(file("outside"), file("live.lua.omamotion.bak"))
assert.strictEqual(run("restore", file("live.lua"), 0).status, 16)
assert.strictEqual(fs.readFileSync(file("live.lua"), "utf8"), "new\n")
fs.unlinkSync(file("live.lua.omamotion.bak"))

// --- guarded reads --------------------------------------------------------
// The config is read through the helper, never through FileView, so the open
// is O_NOFOLLOW|O_NONBLOCK and the read is bounded before anything is parsed.

assert.strictEqual(run("read", file("live.lua"), 0).stdout.toString(), "new\n")
assert.strictEqual(run("read", file("absent.lua"), 0).status, 24)

// A symlinked config is refused by the open itself.
fs.symlinkSync(file("outside"), file("readlink.lua"))
assert.strictEqual(run("read", file("readlink.lua"), 0).status, 11)

// A fifo returns promptly instead of blocking the shell forever.
execFileSync("mkfifo", [file("readfifo.lua")])
const fifoRead = run("read", file("readfifo.lua"), 0)
assert.notStrictEqual(fifoRead.status, 0)
assert.strictEqual(fifoRead.signal, null, "fifo read must not have been killed by a timeout")

// An oversized file is read back bounded, and over the 1 MiB limit so the
// QML side rejects it rather than seeing a silently truncated file.
fs.writeFileSync(file("big.lua"), "x".repeat(3_000_000))
const big = run("read", file("big.lua"), 0)
assert.strictEqual(big.status, 0)
assert.ok(big.stdout.length > 1048576, "oversized read must exceed the limit")
assert.ok(big.stdout.length <= 1114112, "oversized read must stay bounded")

// probe reports a usable backup, and refuses a planted symlink at that path.
assert.strictEqual(run("probe", file("cfg2.lua"), 0).status, 0)
assert.strictEqual(run("probe", file("absent.lua"), 0).status, 14)
fs.symlinkSync(file("outside"), file("probe.lua.omamotion.bak"))
fs.writeFileSync(file("probe.lua"), "x\n")
assert.strictEqual(run("probe", file("probe.lua"), 0).status, 25)
fs.unlinkSync(file("probe.lua.omamotion.bak"))

// Multibyte content round-trips: the byte count QML computes is the count the
// helper checks against.
const utf8 = '-- héllo →\nhl.animation({ leaf = "windowsIn" })\n'
assert.strictEqual(run("install", file("utf8.lua"), bytes(utf8), utf8).status, 0)
assert.strictEqual(fs.readFileSync(file("utf8.lua"), "utf8"), utf8)

// No staging files are left behind by any of the above.
assert.deepStrictEqual(fs.readdirSync(work).filter((n) => n.startsWith(".omamotion.")), [])

// keepbak=0 regenerated files (the launcher entry) leave no stray .bak.
fs.writeFileSync(file("entry.desktop"), "old\n")
assert.strictEqual(run("install", file("entry.desktop"), bytes("new\n"), "new\n", 0).status, 0)
assert.strictEqual(fs.readFileSync(file("entry.desktop"), "utf8"), "new\n")
assert.strictEqual(fs.existsSync(file("entry.desktop.omamotion.bak")), false)

// The helper resolves its tools from a fixed PATH, so a hostile PATH entry
// cannot stand in for dd, mktemp or mv.
const evil = path.join(work, "evilbin")
fs.mkdirSync(evil)
for (const tool of ["dd", "mktemp", "mv", "stat", "cat", "rm", "sync"]) {
  fs.writeFileSync(path.join(evil, tool), "#!/bin/sh\nexit 42\n")
  fs.chmodSync(path.join(evil, tool), 0o755)
}
fs.writeFileSync(file("path.lua"), "before\n")
const hijack = spawnSync("sh",
  ["-c", helper, "omamotion-file", "install", file("path.lua"), String(bytes("after\n")), "1"],
  { input: "after\n", env: { ...process.env, PATH: evil + ":" + process.env.PATH } })
assert.strictEqual(hijack.status, 0, "helper must ignore a hostile PATH")
assert.strictEqual(fs.readFileSync(file("path.lua"), "utf8"), "after\n")

fs.rmSync(work, { recursive: true, force: true })
console.log("config-writer tests passed")
