import QtQuick
import Quickshell.Io
import "LuaConfig.js" as LuaConfig

// The only path by which OmaMotion touches any file on disk.
//
// Every file this plugin reads or writes -- the live Hyprland config, its
// backup, the preset store, the legacy preset store, the launcher entry --
// goes through one shell helper, so nothing is ever opened by something that
// follows symlinks, blocks, or reads unbounded. FileView is not pointed at
// any of them, because it loads before QML can check anything:
//
//   read     open with O_NOFOLLOW|O_NONBLOCK and read at most 17x64KiB, one
//            block past the 1 MiB limit, so an oversized file reads back
//            visibly over it instead of being silently truncated, a planted
//            symlink is refused by the open, and a planted fifo cannot hang
//            the shell. Nothing else ever opens the config -- FileView is not
//            pointed at it, because FileView loads before QML can check.
//   install  stage the new bytes in a sibling mktemp file, give it the live
//            file's permission bits, verify the staged byte count, snapshot
//            the file being replaced into <file>.omamotion.bak, then rename(2)
//            the stage into place.
//   probe    report whether a usable, non-symlinked backup exists.
//   restore  put that snapshot back, through the same guarded read.
//
// Every read is bound to the descriptor it opened, so a swap between check
// and use cannot redirect it. Every write lands by rename(2), which replaces
// a symlink rather than writing through it -- including the backup, whose
// path is predictable and therefore plantable. Nothing can leave a partial
// file: either the rename happens and the file is complete, or it does not
// and the file is untouched. A failed write leaves the backup alone, so an
// aborted save never destroys the recovery point.
QtObject {
    id: gate

    // Absolute path of the file to manage.
    property string path: ""

    // Whether a write snapshots what it replaces. Off for files that are
    // regenerated rather than edited, so they leave no stray .bak behind.
    property bool keepBackup: true

    // True while a helper run is in flight.
    property bool busy: false

    // ok means the file on disk now holds exactly the bytes handed to
    // write(). A write() issued while another is in flight is coalesced into
    // the queued one, so these fire once per helper run, not once per call.
    signal written(bool ok, string message)
    signal restored(bool ok, string message)
    // text is the config's contents, already bounded by the helper.
    signal loaded(bool ok, string text, string message)
    signal probed(bool available)

    // Internal run bookkeeping.
    property string pendingText: ""
    property string queuedText: ""
    property bool hasQueued: false
    property string mode: "install"

    readonly property string helper: [
        "set -u",
        "IFS=' \t\n'",
        "# Resolve every tool from a fixed PATH. This helper is the security",
        "# boundary; inheriting PATH would let anything earlier on it stand in",
        "# for dd, mktemp or mv.",
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
        "export PATH",
        "mode=$1",
        "target=$2",
        "want=$3",
        "keepbak=${4-1}",
        "dir=${target%/*}",
        "[ \"$dir\" = \"$target\" ] && dir=.",
        "backup=$target.omamotion.bak",
        "",
        "# Path tests are a fast reject only. Every read below re-opens with",
        "# O_NOFOLLOW on the descriptor it actually reads, so a swap between the",
        "# check and the use cannot redirect us.",
        "if [ -L \"$target\" ]; then exit 11; fi",
        "if [ -e \"$target\" ] && [ ! -f \"$target\" ]; then exit 12; fi",
        "if [ ! -d \"$dir\" ]; then exit 13; fi",
        "",
        "# Bounded no-follow non-blocking read. 17 x 64KiB = 1114112 bytes, one block",
        "# past the 1 MiB limit so an oversized file reads back visibly over it rather",
        "# than silently truncated. O_NONBLOCK stops a planted fifo from hanging us.",
        "readguarded() {",
        "  dd if=\"$1\" iflag=nofollow,nonblock,fullblock bs=65536 count=17 status=none",
        "}",
        "",
        "if [ \"$mode\" = read ]; then",
        "  [ -e \"$target\" ] || exit 24",
        "  readguarded \"$target\" || exit 23",
        "  exit 0",
        "fi",
        "",
        "if [ \"$mode\" = probe ]; then",
        "  [ -L \"$backup\" ] && exit 25",
        "  [ -f \"$backup\" ] || exit 14",
        "  exit 0",
        "fi",
        "",
        "if [ \"$mode\" = restore ]; then",
        "  [ -e \"$backup\" ] || exit 14",
        "  rtmp=$(mktemp -- \"$dir/.omamotion.XXXXXX\") || exit 15",
        "  if ! readguarded \"$backup\" > \"$rtmp\"; then rm -f -- \"$rtmp\"; exit 16; fi",
        "  rbits=$(stat -c %a -- \"$backup\" 2>/dev/null) && chmod \"$rbits\" -- \"$rtmp\" 2>/dev/null",
        "  sync -- \"$rtmp\" 2>/dev/null || sync",
        "  if ! mv -f -- \"$rtmp\" \"$target\"; then rm -f -- \"$rtmp\"; exit 17; fi",
        "  exit 0",
        "fi",
        "",
        "tmp=$(mktemp -- \"$dir/.omamotion.XXXXXX\") || exit 18",
        "bits=",
        "[ -f \"$target\" ] && { bits=$(stat -c %a -- \"$target\" 2>/dev/null) || bits=; }",
        "# A target swapped to a symlink between the check and here would give",
        "# stat the link target's mode; only octal digits are ever applied.",
        "case $bits in ''|*[!0-7]*) bits= ;; esac",
        "if [ -n \"$bits\" ]; then chmod \"$bits\" -- \"$tmp\" 2>/dev/null; else chmod 644 -- \"$tmp\" 2>/dev/null; fi",
        "",
        "if ! cat > \"$tmp\"; then rm -f -- \"$tmp\"; exit 20; fi",
        "sync -- \"$tmp\" 2>/dev/null || sync",
        "got=$(stat -c %s -- \"$tmp\" 2>/dev/null) || got=",
        "if [ -n \"$got\" ] && [ \"$got\" != \"$want\" ]; then rm -f -- \"$tmp\"; exit 21; fi",
        "",
        "# Snapshot only once the stage is complete and verified, so an aborted write",
        "# never destroys the recovery point. mktemp is O_EXCL so the snapshot cannot",
        "# be a planted symlink, and mv replaces a symlink at $backup instead of",
        "# writing through it -- redirecting straight to $backup followed one.",
        "if [ \"$keepbak\" = 1 ] && [ -f \"$target\" ]; then",
        "  btmp=$(mktemp -- \"$dir/.omamotion.XXXXXX\") || { rm -f -- \"$tmp\"; exit 18; }",
        "  if ! readguarded \"$target\" > \"$btmp\"; then rm -f -- \"$tmp\" \"$btmp\"; exit 19; fi",
        "  [ -n \"$bits\" ] && chmod \"$bits\" -- \"$btmp\" 2>/dev/null",
        "  if ! mv -f -- \"$btmp\" \"$backup\"; then rm -f -- \"$tmp\" \"$btmp\"; exit 19; fi",
        "fi",
        "if ! mv -f -- \"$tmp\" \"$target\"; then rm -f -- \"$tmp\"; exit 22; fi",
        "sync -- \"$dir\" 2>/dev/null",
        "exit 0"
    ].join("\n")

    function describe(code) {
        if (code === 11) return "target is a symlink — refusing to follow it"
        if (code === 12) return "target is not a regular file"
        if (code === 13) return "config directory is missing"
        if (code === 14) return "no backup to restore from"
        if (code === 15 || code === 18) return "could not stage a temporary file"
        if (code === 19) return "could not snapshot the current file"
        if (code === 20) return "writing the staged file failed"
        if (code === 21) return "staged file was incomplete — original left untouched"
        if (code === 23) return "config could not be read safely"
        if (code === 24) return "config file not found"
        if (code === 25) return "backup path is a symlink — refusing to follow it"
        if (code === 16 || code === 17 || code === 22) return "could not install the new file"
        return "config helper failed (" + code + ")"
    }

    function command(runMode, bytes) {
        return ["sh", "-c", helper, "omamotion-file", runMode, path,
                String(bytes), keepBackup ? "1" : "0"]
    }

    // ---- reading ----------------------------------------------------------

    property int readCode: 0
    property bool readCodeIn: false
    property bool readTextIn: false
    property string readText: ""

    // Load the config through the guarded helper. Fires loaded().
    function read() {
        if (path === "" || readProc.running) return
        readCodeIn = false
        readTextIn = false
        readText = ""
        readProc.command = command("read", 0)
        readProc.running = true
    }

    // Both the exit code and the collected stdout are needed, and they can
    // arrive in either order, so settle only once both are in.
    function settleRead() {
        if (!readCodeIn || !readTextIn) return
        var ok = readCode === 0
        gate.loaded(ok, ok ? readText : "", ok ? "" : describe(readCode))
    }

    function probe() {
        if (path === "" || probeProc.running) return
        probeProc.command = command("probe", 0)
        probeProc.running = true
    }

    // ---- writing ----------------------------------------------------------

    // Replace the managed file with text. Fires written() when done.
    function write(text) {
        if (path === "") {
            gate.written(false, "no config path")
            return
        }
        if (LuaConfig.exceedsLimit(text)) {
            gate.written(false, "refusing to write more than 1 MiB to the config")
            return
        }
        if (busy) {
            queuedText = String(text)
            hasQueued = true
            return
        }
        pendingText = String(text)
        mode = "install"
        busy = true
        proc.command = command("install", LuaConfig.utf8Length(pendingText))
        // onStarted clears this to signal EOF, which also drops the binding,
        // so every run re-arms stdin before it launches.
        proc.stdinEnabled = true
        proc.running = true
    }

    // Put the pre-write snapshot back. Fires restored() when done.
    function restore() {
        if (path === "" || busy) {
            gate.restored(false, "cannot restore right now")
            return
        }
        pendingText = ""
        mode = "restore"
        busy = true
        proc.command = command("restore", 0)
        proc.stdinEnabled = true
        proc.running = true
    }

    function finish(code) {
        var wasRestore = mode === "restore"
        var ok = code === 0
        busy = false
        pendingText = ""
        if (wasRestore) gate.restored(ok, ok ? "" : describe(code))
        else gate.written(ok, ok ? "" : describe(code))
        if (!hasQueued) return
        hasQueued = false
        var next = queuedText
        queuedText = ""
        write(next)
    }

    // ---- processes --------------------------------------------------------

    property Process proc: Process {
        id: proc
        stdinEnabled: false     // re-armed per run by write()/restore()
        onStarted: {
            // proc.write() is Process's stdin, not gate.write() above.
            if (gate.mode === "install") proc.write(gate.pendingText)
            proc.stdinEnabled = false      // EOF: the helper's `cat` returns
        }
        onExited: function (exitCode, exitStatus) {
            gate.finish(exitStatus === 0 ? exitCode : 99)
        }
    }

    property Process readProc: Process {
        id: readProc
        stdout: StdioCollector {
            id: readOut
            onStreamFinished: {
                gate.readText = readOut.text
                gate.readTextIn = true
                gate.settleRead()
            }
        }
        onExited: function (exitCode, exitStatus) {
            gate.readCode = exitStatus === 0 ? exitCode : 99
            gate.readCodeIn = true
            gate.settleRead()
        }
    }

    property Process probeProc: Process {
        id: probeProc
        onExited: function (exitCode, exitStatus) {
            gate.probed(exitStatus === 0 && exitCode === 0)
        }
    }
}
