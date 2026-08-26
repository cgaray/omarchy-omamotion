import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MotionState.js" as MotionState
import "LuaConfig.js" as LuaConfig
import "PresetStore.js" as PresetStore

// OmaMotion visual motion studio for Hyprland animations.
// Edits a single managed block in ~/.config/hypr/looknfeel.lua.
Item {
    id: root

    // ---- plugin lifecycle ---------------------------------------------------
    property bool closingFromHost: false
    property var shell: null

    function open(payloadJson) {
        closingFromHost = false
        window.visible = true
        configWriter.read()
        configWriter.probe()
        focusScope.forceActiveFocus()
    }

    function close() {
        closingFromHost = true
        window.visible = false
        closingFromHost = false
    }

    function requestClose() {
        window.visible = false
        if (shell && typeof shell.hide === "function") shell.hide(root.pluginId)
    }

    readonly property string pluginId: "io.github.cgaray.omamotion"

    // ---- state --------------------------------------------------------------
    property var state: MotionState.defaultState()
    property string selectedLeaf: "windowsIn"
    property string activeCurve: "easeOutQuint"
    property bool blockOnDisk: false
    property string statusText: ""
    property string fileText: ""
    property bool advancedMode: false
    property string customPresetName: ""
    property var customPresets: []
    property string pendingPresetText: ""
    property string pendingConfigText: ""
    property bool pendingRemoval: false
    property bool configLocked: false      // oversized/unsafe file: never rewrite it
    property string lockReason: ""
    property bool backupAvailable: false
    property string hoveredVibe: ""
    property int stateRev: 0            // bumped on in-place mutations so
                                        // vibe-highlight bindings re-evaluate

    readonly property var previewState: hoveredVibe === ""
        ? state
        : MotionState.applyPreset(MotionState.defaultState(), MotionState.VIBE_PRESET[hoveredVibe])

    function leafOrder() {
        return MotionState.LEAVES.map(function (m) { return m.leaf })
    }

    // ---- persistence --------------------------------------------------------
    // No FileView is pointed at looknfeel.lua or at its backup: FileView
    // opens and loads before QML can check anything, so a planted symlink,
    // fifo or oversized file would already have been followed or slurped.
    // Every read and write of both paths goes through ConfigWriter's helper.
    readonly property string configPath:
        Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"

    ConfigWriter {
        id: configWriter
        path: root.configPath
        onLoaded: function (ok, text, message) { root.ingestDisk(ok, text, message) }
        onWritten: function (ok, message) { root.onConfigWritten(ok, message) }
        onRestored: function (ok, message) { root.onConfigRestored(ok, message) }
        onProbed: function (available) { root.backupAvailable = available }
    }

    FileView {
        id: presetFile
        path: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.cgaray.omamotion/presets.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: { root.loadCustomPresets(); root.verifyPresetWrite(); root.migrateLegacyPresets() }
        onFileChanged: { root.loadCustomPresets(); root.verifyPresetWrite() }
        onLoadFailed: root.customPresets = []
    }

    FileView {
        id: legacyPresetFile
        path: Quickshell.env("HOME") + "/.config/omamotion/presets.json"
        watchChanges: false
        printErrors: false
        onLoaded: root.migrateLegacyPresets()
    }

    function loadCustomPresets() {
        var result = PresetStore.parse(presetFile.text())
        root.customPresets = result.ok ? result.presets : []
        if (!result.ok) root.statusText = result.error
    }

    function migrateLegacyPresets() {
        if (presetFile.text().trim() !== "" || legacyPresetFile.text().trim() === "") return
        var result = PresetStore.parse(legacyPresetFile.text())
        if (!result.ok) return
        presetFile.setText(JSON.stringify(result.presets, null, 2))
        root.customPresets = result.presets
        root.statusText = "Migrated saved presets"
    }

    function verifyPresetWrite() {
        if (pendingPresetText === "") return
        var expected = pendingPresetText
        pendingPresetText = ""
        if (presetFile.text().trim() !== expected.trim()) {
            statusText = "Preset could not be written"
            return
        }
        statusText = "Preset saved"
    }

    function saveCustomPreset() {
        var name = customPresetName.trim()
        if (name === "") {
            statusText = "Enter a name for this preset"
            return
        }
        var result = PresetStore.upsert(customPresets, name, root.state)
        if (!result.ok) {
            statusText = result.error
            return
        }
        pendingPresetText = result.text
        presetFile.setText(result.text)
        customPresets = result.presets
        customPresetName = ""
        statusText = "Saving preset..."
    }

    function markChanged(label) {
        statusText = label ? label + " — unsaved" : "Unsaved"
        stateRev++
        saveTimer.restart()
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.saveNow()
    }

    // The editor's view of the file only advances once ConfigWriter reports
    // the bytes are down, so a refused or failed write leaves fileText
    // matching what is actually on disk.
    function saveNow() {
        if (root.configLocked) {
            root.statusText = root.lockReason
            return
        }
        var body = LuaConfig.generateBody(root.state, root.leafOrder())
        root.pendingConfigText = LuaConfig.applyToText(root.fileText, body)
        root.pendingRemoval = false
        root.statusText = "Saving..."
        configWriter.write(root.pendingConfigText)
    }

    function onConfigWritten(ok, message) {
        if (!ok) {
            root.statusText = "Could not save — " + message
            configWriter.read()
            return
        }
        root.fileText = root.pendingConfigText
        root.blockOnDisk = !root.pendingRemoval
        root.statusText = root.pendingRemoval
            ? "Managed block removed — stock Omarchy motion restored"
            : "Saved — Hyprland applies live"
        root.backupAvailable = true      // the write just snapshotted one
    }

    function onConfigRestored(ok, message) {
        root.statusText = ok
            ? "Restored looknfeel.lua from OmaMotion's backup"
            : "Could not restore — " + message
        if (ok) configWriter.read()
    }

    function restoreBackup() {
        saveTimer.stop()
        root.statusText = "Restoring backup..."
        configWriter.restore()
    }

    function ingestDisk(ok, text, message) {
        if (!ok) {
            root.configLocked = true
            root.lockReason = "~/.config/hypr/looknfeel.lua — " + message
            root.fileText = ""
            root.blockOnDisk = false
            root.state = MotionState.defaultState()
            root.statusText = root.lockReason
            refreshEditor()
            return
        }
        var res = LuaConfig.readState(text)
        // Refuse to parse — or later rewrite — a file that is far larger than
        // any real looknfeel.lua. Editing stays disabled until it shrinks.
        if (res.oversize) {
            root.fileText = ""
            root.configLocked = true
            root.lockReason = "~/.config/hypr/looknfeel.lua is over 1 MiB — OmaMotion will not modify it"
            root.blockOnDisk = false
            root.state = MotionState.defaultState()
            root.statusText = root.lockReason
            refreshEditor()
            return
        }
        root.configLocked = false
        root.lockReason = ""
        root.fileText = text
        root.blockOnDisk = res.found
        if (!res.found) {
            root.state = MotionState.defaultState()
            root.statusText = "Stock Omarchy motion — no OmaMotion block yet"
        } else if (res.error !== "") {
            root.statusText = "Managed block unreadable — saving will rewrite it"
            root.state = MotionState.defaultState()
        } else {
            root.state = normalizeParsed(res.state)
            root.statusText = "Editing the OmaMotion block"
        }
        refreshEditor()
    }

    function normalizeParsed(parsed) {
        var s = MotionState.defaultState()
        var name
        // Curve names read from looknfeel.lua are shown as Button labels and
        // written back into the Lua block. Keep them to the token charset so
        // neither path has to deal with markup or quotes.
        for (name in parsed.curves)
            if (PresetStore.validToken(name)) s.curves[name] = parsed.curves[name]
        for (var leaf in parsed.animations) {
            var t = parsed.animations[leaf]
            var entry = { enabled: !!t.enabled }
            if (typeof t.speed === "number") entry.speed = t.speed
            if (typeof t.bezier === "string"
                && (t.bezier === "default" || s.curves[t.bezier])) entry.bezier = t.bezier
            entry.style = typeof t.style === "string" ? t.style : ""
            s.animations[leaf] = entry
        }
        return s
    }

    // ---- curve editor sync --------------------------------------------------
    function refreshEditor() {
        var cv = root.state.curves[root.activeCurve]
        if (!cv) return
        curveEditor.p1x = cv.p1[0]; curveEditor.p1y = cv.p1[1]
        curveEditor.p2x = cv.p2[0]; curveEditor.p2y = cv.p2[1]
        curveChips.rebuild()
    }

    function round2(v) { return Math.round(v * 100) / 100 }

    function commitCurve() {
        var cv = root.state.curves[root.activeCurve]
        if (!cv) return
        cv.p1 = [round2(curveEditor.p1x), round2(curveEditor.p1y)]
        cv.p2 = [round2(curveEditor.p2x), round2(curveEditor.p2y)]
        markChanged("Curve updated")
    }

    function selectCurve(name) {
        root.activeCurve = name
        refreshEditor()
    }

    function addCustomCurve() {
        var base = root.state.curves[root.activeCurve] || { p1: [0.23, 1], p2: [0.32, 1] }
        var wanted = newCurveName.text.trim().replace(/[^A-Za-z0-9_-]/g, "")
        if (wanted === "") wanted = "custom"
        var name = wanted, n = 2
        while (root.state.curves[name]) { name = wanted + n; n++ }
        root.state.curves[name] = { p1: base.p1.slice(), p2: base.p2.slice() }
        root.selectCurve(name)
        markChanged("Curve added")
    }

    function removeCustomCurve() {
        if (MotionState.isEditableCurve(root.activeCurve)) return
        delete root.state.curves[root.activeCurve]
        root.selectCurve("easeOutQuint")
        markChanged("Curve removed")
    }

    function curveOptions() {
        var opts = MotionState.CURVE_KINDS.slice()
        for (var name in root.state.curves)
            if (!MotionState.isEditableCurve(name) && opts.indexOf(name) === -1) opts.push(name)
        return opts
    }

    function curveUsage(name) {
        var n = 0
        for (var leaf in root.state.animations)
            if (root.state.animations[leaf].bezier === name) n++
        return n
    }

    // ---- leaf mutations -------------------------------------------------------
    function setEnabled(leaf, v) { state.animations[leaf].enabled = v; markChanged(leaf) }
    function setSpeed(leaf, v)   { state.animations[leaf].speed = MotionState.clampSpeed(v); markChanged(leaf) }
    function setBezier(leaf, nm) { state.animations[leaf].bezier = nm; markChanged(leaf) }
    function setStyle(leaf, s)   { state.animations[leaf].style = s; markChanged(leaf) }

    function entryVal(leaf, key, dflt) {
        var e = state.animations[leaf]
        if (!e || e[key] === undefined) return dflt
        return e[key]
    }

    function previewDurationHint() {
        var e = state.animations[selectedLeaf]
        if (!e || e.speed === undefined) return 300
        return Math.max(120, e.speed * 100)
    }

    function leavesInGroup(group) {
        return MotionState.LEAVES
            .filter(function (m) { return m.group === group })
            .map(function (m) { return m.leaf })
    }

    // ---- presets / reset --------------------------------------------------------
    function applyPreset(name) {
        root.state = MotionState.applyPreset(root.state, name)
        refreshEditor()
        saveNow()
        statusText = "Preset applied — " + name
    }

    property bool confirmReset: false
    Timer { id: resetArm; interval: 3000; onTriggered: root.confirmReset = false }

    function resetAll() {
        if (root.configLocked) {
            statusText = root.lockReason
            return
        }
        if (!confirmReset) {
            confirmReset = true
            resetArm.restart()
            return
        }
        confirmReset = false
        saveTimer.stop()          // a pending save must not resurrect the block
        root.pendingConfigText = LuaConfig.applyToText(fileText, null)
        root.pendingRemoval = true
        state = MotionState.defaultState()
        selectCurve("easeOutQuint")
        selectedLeaf = "windowsIn"
        statusText = "Removing managed block..."
        configWriter.write(root.pendingConfigText)
    }

    // ---- inline row component ----------------------------------------------------
    component LeafRow: Rectangle {
        id: leafRow

        property string leafName: ""
        property bool simple: false
        readonly property var meta: MotionState.leafMeta(leafName) || {}
        readonly property bool hasSpeed: meta.speed !== undefined
            || (root.entryVal(leafName, "speed", null) !== null)
        readonly property bool hasBezier: meta.bezier !== undefined
        readonly property bool hasStyles: simple
            ? MotionState.simpleStylesFor(meta.family || "") !== null
            : MotionState.stylesFor(meta.family || "").length > 1
        readonly property bool previewing: root.selectedLeaf === leafName

        width: leafList.width
        height: rowInner.height + Style.space(3)
        radius: 6
        color: mouse.containsMouse || previewing
               ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.selectedLeaf = leafRow.leafName
        }

        Column {
            id: rowInner
            x: Style.space(2)
            spacing: Style.space(2)

            Item {
                width: leafRow.width - Style.space(4)
                height: Math.max(sw.implicitHeight, Style.space(6))

                ToggleSwitch {
                    id: sw
                    width: implicitWidth
                    height: implicitHeight
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    checked: !!root.entryVal(leafRow.leafName, "enabled", false)
                    onToggled: root.setEnabled(leafRow.leafName, checked)
                }

                Text {
                    anchors.left: sw.right
                    anchors.leftMargin: Style.space(3)
                    anchors.right: speedRow.visible ? speedRow.left : parent.right
                    anchors.rightMargin: Style.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: {
                        var label = leafRow.simple
                            ? MotionState.leafLabel(leafRow.leafName)
                            : leafRow.leafName
                        return leafRow.previewing ? label + "  ◀" : label
                    }
                    elide: Text.ElideRight
                    color: leafRow.previewing ? Color.accent : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

                Row {
                    id: speedRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: leafRow.hasSpeed
                    spacing: Style.space(2)

                    Text {
                        text: leafRow.simple
                              ? MotionState.speedWord(root.entryVal(leafRow.leafName, "speed", 0))
                              : Number(root.entryVal(leafRow.leafName, "speed", 0)).toFixed(2)
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        width: leafRow.simple ? 70 : 32
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    PanelSlider {
                        id: speedSlider
                        width: 130
                        anchors.verticalCenter: parent.verticalCenter
                        minimum: MotionState.SPEED_MIN
                        maximum: MotionState.SPEED_MAX
                        step: 0.01
                        value: root.entryVal(leafRow.leafName, "speed", 1)
                        // Commit only while dragging. The value binding also
                        // changes this property during initialization.
                        onValueChanged: {
                            var cur = root.entryVal(leafRow.leafName, "speed", -1)
                            if (dragging && Math.abs(value - cur) > 0.001)
                                root.setSpeed(leafRow.leafName, value)
                        }
                    }
                }
            }

            Row {
                visible: (leafRow.hasBezier && !leafRow.simple) || leafRow.hasStyles
                spacing: Style.space(2)

                Dropdown {
                    visible: leafRow.hasBezier && !leafRow.simple
                    width: 150
                    value: String(root.entryVal(leafRow.leafName, "bezier", ""))
                    options: root.curveOptions()
                    onChanged: function(v) { root.setBezier(leafRow.leafName, v) }
                }
                Dropdown {
                    visible: leafRow.hasStyles
                    width: 170
                    showLabel: false
                    value: leafRow.simple
                        ? MotionState.simpleStyleLabel(leafRow.meta.family || "",
                                                       String(root.entryVal(leafRow.leafName, "style", "")))
                        : String(root.entryVal(leafRow.leafName, "style", ""))
                    options: leafRow.simple
                        ? MotionState.simpleStyleLabels(leafRow.meta.family || "")
                        : MotionState.stylesFor(leafRow.meta.family || "")
                    onChanged: function(v) {
                        if (leafRow.simple)
                            root.setStyle(leafRow.leafName,
                                          MotionState.simpleStyleToken(leafRow.meta.family || "", v))
                        else
                            root.setStyle(leafRow.leafName, v)
                    }
                }
            }
        }
    }

    // ---- window -----------------------------------------------------------------
    FloatingWindow {
        id: window
        title: "OmaMotion — Hyprland motion studio"
        color: Color.background
        implicitWidth: 960
        implicitHeight: 620
        minimumSize: Qt.size(840, 500)

        onVisibleChanged: {
            if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
                root.shell.hide(root.pluginId)
        }

        FocusScope {
            id: focusScope
            anchors.fill: parent
            focus: true

            Keys.priority: Keys.AfterItem
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.requestClose()
                    event.accepted = true
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                spacing: Style.space(3)

                // Header -----------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(3)

                    Text {
                        text: "OmaMotion"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.heading
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: "motion studio"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "Simple"
                        selected: !root.advancedMode
                        onClicked: root.advancedMode = false
                    }
                    Button {
                        text: "Advanced"
                        selected: root.advancedMode
                        onClicked: root.advancedMode = true
                    }
                    Button {
                        text: root.confirmReset ? "Really reset?" : "Reset all"
                        onClicked: root.resetAll()
                    }
                    // Recovery hatch: every write leaves the previous file in
                    // looknfeel.lua.omamotion.bak, so a bad edit is undoable.
                    Button {
                        text: "Restore backup"
                        visible: root.backupAvailable
                        enabled: !configWriter.busy
                        onClicked: root.restoreBackup()
                    }
                }

                // Vibe cards ---------------------------------------------------
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                        text: "How should your desktop feel?"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.advancedMode
                            ? "Choose a starting point, then tune every detail below."
                            : "Choose one. You can change it any time from the bar."
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Repeater {
                        model: MotionState.VIBES

                        delegate: Rectangle {
                            id: vibeCard

                            required property var modelData
                            readonly property bool active: MotionState.currentVibe(root.state, root.stateRev) === modelData.id

                            Layout.fillWidth: true
                            Layout.preferredHeight: vibeColumn.implicitHeight + Style.space(4)
                            radius: 8
                            color: mouse.containsMouse
                                   ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
                                   : "transparent"
                            border.width: active ? 2 : 1
                            border.color: active ? Color.accent
                                                 : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.25)
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.hoveredVibe = vibeCard.modelData.id
                                    root.selectedLeaf = "windowsIn"
                                    Qt.callLater(function() { previewStage.trigger("open") })
                                }
                                onExited: {
                                    if (root.hoveredVibe !== vibeCard.modelData.id) return
                                    root.hoveredVibe = ""
                                    Qt.callLater(function() { previewStage.trigger("open") })
                                }
                                onClicked: {
                                    root.selectedLeaf = "windowsIn"
                                    root.applyPreset(MotionState.VIBE_PRESET[vibeCard.modelData.id])
                                }
                            }

                            Column {
                                id: vibeColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Style.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(1)

                                Text {
                                    text: vibeCard.modelData.name
                                    textFormat: Text.PlainText
                                    color: vibeCard.active ? Color.accent : Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.body
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: vibeCard.modelData.desc
                                    textFormat: Text.PlainText
                                    color: Color.muted
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    TextField {
                        id: customPresetField
                        Layout.preferredWidth: 220
                        placeholderText: "name this setup"
                        text: root.customPresetName
                        onTextChanged: root.customPresetName = text
                        onAccepted: root.saveCustomPreset()
                    }
                    Button {
                        text: "Save current preset"
                        onClicked: root.saveCustomPreset()
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: root.customPresets.length > 0
                            ? root.customPresets.length + " saved"
                            : "Saved presets appear in the bar"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                PanelSeparator { Layout.fillWidth: true }

                // Body ---------------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    spacing: Style.space(4)

                    Flickable {
                        id: leafList
                        Layout.preferredWidth: 400
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        contentWidth: width
                        contentHeight: leafColumn.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        Column {
                            id: leafColumn
                            width: leafList.width
                            spacing: Style.space(1)

                            Repeater {
                                model: root.advancedMode
                                       ? MotionState.GROUP_ORDER
                                       : MotionState.simpleGroupNames()

                                delegate: Column {
                                    required property string modelData
                                    width: leafColumn.width
                                    spacing: Style.space(1)

                                    PanelSectionHeader {
                                        width: parent.width
                                        text: modelData.toUpperCase()
                                        topPadding: Style.space(3)
                                        bottomPadding: Style.space(1)
                                    }

                                    Repeater {
                                        model: root.advancedMode
                                            ? root.leavesInGroup(modelData)
                                            : MotionState.simpleGroupLeaves(modelData)

                                        delegate: LeafRow {
                                            leafName: modelData
                                            simple: !root.advancedMode
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        spacing: Style.space(2)

                        // Advanced-only: curve chips, editor, custom curves.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.advancedMode
                            spacing: Style.space(2)

                            Flow {
                                id: curveChips
                                Layout.fillWidth: true
                                spacing: Style.space(2)

                                property var model: []
                                function rebuild() {
                                    model = Object.keys(root.state.curves)
                                }
                                Component.onCompleted: rebuild()

                                Repeater {
                                    model: curveChips.model

                                    delegate: Button {
                                        required property string modelData
                                        text: modelData
                                        selected: root.activeCurve === modelData
                                        onClicked: root.selectCurve(modelData)
                                    }
                                }
                            }

                            CurveEditor {
                                id: curveEditor
                                Layout.fillWidth: true
                                Layout.preferredHeight: 230
                                sweepMs: root.previewDurationHint()
                                onEdited: root.commitCurve()
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(2)

                                TextField {
                                    id: newCurveName
                                    Layout.preferredWidth: 200
                                    placeholderText: "new curve name"
                                    onAccepted: root.addCustomCurve()
                                }
                                Button { text: "Add as new"; onClicked: root.addCustomCurve() }
                                Button {
                                    text: "Delete"
                                    enabled: !MotionState.isEditableCurve(root.activeCurve)
                                    onClicked: root.removeCustomCurve()
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    textFormat: Text.PlainText
                                    text: root.activeCurve + " drives "
                                          + root.curveUsage(root.activeCurve)
                                          + (root.curveUsage(root.activeCurve) === 1 ? " leaf ·" : " leaves ·")
                                          + " sweep ≈ " + Math.round(curveEditor.sweepMs) + " ms"
                                    color: Color.muted
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }

                        PanelSeparator {
                            Layout.fillWidth: true
                            visible: root.advancedMode
                        }

                        PreviewStage {
                            id: previewStage
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spec: ({
                                entry: root.previewState.animations[root.hoveredVibe === ""
                                    ? root.selectedLeaf : "windowsIn"],
                                curves: root.previewState.curves
                            })
                        }
                    }
                }

                // Footer ----------------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(3)

                    Text {
                        Layout.preferredWidth: 520
                        text: root.statusText
                        // Parser and preset errors quote text from the files
                        // they failed on, so never let Qt sniff this as HTML.
                        textFormat: Text.PlainText
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.advancedMode
                            ? "Esc closes · writes a fenced block in ~/.config/hypr/looknfeel.lua"
                            : "Pick a vibe, or fine-tune below. Switch to Advanced for curves."
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }
            }
        }
    }
}
