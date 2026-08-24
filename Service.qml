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

  property FileView templateFile: FileView {
    id: templateFile
    path: root.sourceDir === "" ? "" : root.sourceDir + "/omamotion.desktop"
    watchChanges: false
    printErrors: false
    onLoaded: root.installDesktopEntry()
  }

  property FileView desktopFile: FileView {
    id: desktopFile
    path: root.dest
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.installDesktopEntry()
    onLoadFailed: root.installDesktopEntry()
  }

  function installDesktopEntry() {
    if (!installed || sourceDir === "" || templateFile.text().trim() === "") return
    var existing = desktopFile.text()
    if (existing !== "" && existing.indexOf(marker) === -1) return
    var rendered = templateFile.text().replace(/@ICON@/g, sourceDir + "/icon.png")
    if (existing === rendered) return
    desktopFile.setText(rendered)
  }

  // The shell assigns manifest after createObject() has already run
  // Component.onCompleted, and a binding on it has not re-evaluated by the
  // time this fires, so the paths are built here rather than bound.
  onManifestChanged: {
    var dir = manifest && manifest.__sourceDir
    if (installed || !dir) return
    installed = true
    sourceDir = String(dir)
    templateFile.reload()
    desktopFile.reload()
  }

  // Reached on disable and on remove alike: omarchy-plugin-remove disables
  // first, so the service is torn down while the entry is still ours.
  Component.onDestruction: {
    if (!installed) return
    if (desktopFile.text().indexOf(marker) !== -1)
      Quickshell.execDetached(["rm", "-f", dest])
  }
}
