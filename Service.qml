import QtQuick
import Quickshell
import Quickshell.Io

// Install the launcher entry used by the application menu.
// Only entries carrying the X-OmaMotion-Managed marker are changed.
QtObject {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property string sourceDir: ""

  readonly property string dest: Quickshell.env("HOME") + "/.local/share/applications/omamotion.desktop"
  readonly property string marker: "X-OmaMotion-Managed=true"

  property bool installed: false

  // Both files go through the same guarded reader/writer as everything else:
  // dest sits on a predictable path a symlink could be planted at, and the
  // template is read rather than trusted. The entry is regenerated, not
  // edited, so it keeps no backup.
  property string templateText: ""
  property string existingText: ""
  property bool templateIn: false
  property bool existingIn: false

  property SafeFile templateFile: SafeFile {
    id: templateFile
    path: root.sourceDir === "" ? "" : root.sourceDir + "/omamotion.desktop"
    keepBackup: false
    onLoaded: function (ok, text, message) {
      root.templateText = ok ? text : ""
      root.templateIn = true
      root.installDesktopEntry()
    }
  }

  property SafeFile desktopFile: SafeFile {
    id: desktopFile
    path: root.dest
    keepBackup: false
    onLoaded: function (ok, text, message) {
      root.existingText = ok ? text : ""
      root.existingIn = true
      root.installDesktopEntry()
    }
  }

  // A .desktop file is line-oriented, so a newline reaching a value would
  // start a new key -- Exec= among them. sourceDir comes from the host, but
  // this entry ends up in the application menu, so it is not taken on trust.
  function safeIconPath() {
    var dir = String(sourceDir)
    if (dir === "" || /[\r\n]/.test(dir)) return ""
    return dir + "/icon.png"
  }

  function installDesktopEntry() {
    if (!installed || sourceDir === "" || !templateIn || !existingIn) return
    if (templateText.trim() === "") return
    var icon = safeIconPath()
    if (icon === "") return
    if (existingText !== "" && existingText.indexOf(marker) === -1) return
    var rendered = templateText.replace(/@ICON@/g, icon)
    if (existingText === rendered) return
    desktopFile.write(rendered)
  }

  // The shell assigns manifest after createObject() has already run
  // Component.onCompleted, and a binding on it has not re-evaluated by the
  // time this fires, so the paths are built here rather than bound.
  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (installed || !dir) return
    installed = true
    sourceDir = String(dir)
    templateFile.read()
    desktopFile.read()
  }

  // Reached on disable and on remove alike. rm -f unlinks the path itself,
  // so a symlink planted at dest is removed rather than followed.
  Component.onDestruction: {
    if (!installed) return
    if (existingText.indexOf(marker) !== -1)
      Quickshell.execDetached(["rm", "-f", "--", dest])
  }
}
