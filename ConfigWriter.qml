import QtQuick
import Quickshell.Io
import "LuaConfig.js" as LuaConfig

// Replaces a user-owned config file without ever leaving it half-written.
//
// FileView.setText() rewrites the live file in place, so an interrupted save
// can truncate ~/.config/hypr/looknfeel.lua and take the user's Hyprland
// configuration with it. Every write here instead goes through a helper that
//
//   1. refuses a target that is a symlink or not a regular file,
//   2. stages the new bytes in a sibling temp file,
//   3. copies the live file's permission bits onto the staged file,
//   4. keeps the previous contents in <file>.omamotion.bak,
//   5. checks the staged byte count against what we meant to write,
//   6. and only then rename(2)s the staged file into place.
//
// rename(2) replaces a symlink rather than writing through it, so the
// symlink check cannot be raced into a write outside the config directory.
// Nothing after step 2 can leave a partial file: either the rename happens
// and the file is complete, or it does not and the file is untouched.
QtObject {
    id: writer

    // Absolute path of the file to manage.
    property string path: ""

    // True while a helper run is in flight.
    property bool busy: false

    // ok means the file on disk now holds exactly the bytes handed to
    // write(). A write() issued while another is in flight is coalesced into
    // the queued one, so these fire once per helper run, not once per call.
    signal written(bool ok, string message)
    signal restored(bool ok, string message)

    // Internal run bookkeeping.
    property string pendingText: ""
    property string queuedText: ""
    property bool hasQueued: false
    property string mode: "install"

    readonly property string helper: [
        "set -u",
        "mode=$1",
        "target=$2",
        "want=$3",
        "dir=${target%/*}",
        "[ \"$dir\" = \"$target\" ] && dir=.",
        "backup=$target.omamotion.bak",
        "",
        "# Never follow a symlink and never write over a non-regular file.",
        "if [ -L \"$target\" ]; then exit 11; fi",
        "if [ -e \"$target\" ] && [ ! -f \"$target\" ]; then exit 12; fi",
        "if [ ! -d \"$dir\" ]; then exit 13; fi",
        "",
        "if [ \"$mode\" = restore ]; then",
        "  [ -f \"$backup\" ] || exit 14",
        "  rtmp=$(mktemp -- \"$dir/.omamotion.XXXXXX\") || exit 15",
        "  if ! cat -- \"$backup\" > \"$rtmp\"; then rm -f -- \"$rtmp\"; exit 16; fi",
        "  rbits=$(stat -c %a -- \"$backup\" 2>/dev/null) && chmod \"$rbits\" -- \"$rtmp\" 2>/dev/null",
        "  sync -- \"$rtmp\" 2>/dev/null || sync",
        "  if ! mv -f -- \"$rtmp\" \"$target\"; then rm -f -- \"$rtmp\"; exit 17; fi",
        "  exit 0",
        "fi",
        "",
        "tmp=$(mktemp -- \"$dir/.omamotion.XXXXXX\") || exit 18",
        "bits=",
        "if [ -f \"$target\" ]; then",
        "  bits=$(stat -c %a -- \"$target\" 2>/dev/null) || bits=",
        "  if ! cat -- \"$target\" > \"$backup\"; then rm -f -- \"$tmp\"; exit 19; fi",
        "  [ -n \"$bits\" ] && chmod \"$bits\" -- \"$backup\" 2>/dev/null",
        "fi",
        "# Inherit the live file's mode; a file we are creating gets 0644.",
        "if [ -n \"$bits\" ]; then chmod \"$bits\" -- \"$tmp\" 2>/dev/null; else chmod 644 -- \"$tmp\" 2>/dev/null; fi",
        "",
        "if ! cat > \"$tmp\"; then rm -f -- \"$tmp\"; exit 20; fi",
        "sync -- \"$tmp\" 2>/dev/null || sync",
        "# A short stage means the sender died mid-write. Drop it; the live",
        "# file has not been touched yet, so there is nothing to recover.",
        "got=$(stat -c %s -- \"$tmp\" 2>/dev/null) || got=",
        "if [ -n \"$got\" ] && [ \"$got\" != \"$want\" ]; then rm -f -- \"$tmp\"; exit 21; fi",
        "if ! mv -f -- \"$tmp\" \"$target\"; then rm -f -- \"$tmp\"; exit 22; fi",
        "sync -- \"$dir\" 2>/dev/null",
        "exit 0"
    ].join("\n")

    function describe(code) {
        if (code === 11) return "target is a symlink — refusing to write through it"
        if (code === 12) return "target is not a regular file"
        if (code === 13) return "config directory is missing"
        if (code === 14) return "no backup to restore from"
        if (code === 15 || code === 18) return "could not stage a temporary file"
        if (code === 19) return "could not back up the current file"
        if (code === 20) return "writing the staged file failed"
        if (code === 21) return "staged file was incomplete — original left untouched"
        if (code === 16 || code === 17 || code === 22) return "could not install the new file"
        return "write helper failed (" + code + ")"
    }

    // Replace the managed file with text. Fires written() when done.
    function write(text) {
        if (path === "") {
            writer.written(false, "no config path")
            return
        }
        if (LuaConfig.exceedsLimit(text)) {
            writer.written(false, "refusing to write more than 1 MiB to the config")
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
        proc.command = ["sh", "-c", helper, "omamotion-config", "install", path,
                        String(LuaConfig.utf8Length(pendingText))]
        // onStarted clears this to signal EOF, which also drops the binding,
        // so every run re-arms stdin before it launches.
        proc.stdinEnabled = true
        proc.running = true
    }

    // Put the pre-write contents back. Fires restored() when done.
    function restore() {
        if (path === "" || busy) {
            writer.restored(false, "cannot restore right now")
            return
        }
        pendingText = ""
        mode = "restore"
        busy = true
        proc.command = ["sh", "-c", helper, "omamotion-config", "restore", path, "0"]
        proc.stdinEnabled = true
        proc.running = true
    }

    function finish(code) {
        var wasRestore = mode === "restore"
        var ok = code === 0
        busy = false
        pendingText = ""
        if (wasRestore) writer.restored(ok, ok ? "" : describe(code))
        else writer.written(ok, ok ? "" : describe(code))
        if (!hasQueued) return
        hasQueued = false
        var next = queuedText
        queuedText = ""
        write(next)
    }

    property Process proc: Process {
        id: proc
        stdinEnabled: false     // re-armed per run by write()/restore()
        onStarted: {
            // proc.write() is Process's stdin, not writer.write() above.
            if (writer.mode === "install") proc.write(writer.pendingText)
            proc.stdinEnabled = false      // EOF: the helper's `cat` returns
        }
        onExited: function (exitCode, exitStatus) {
            writer.finish(exitStatus === 0 ? exitCode : 99)
        }
    }
}
