import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MotionState.js" as MotionState
import "LuaConfig.js" as LuaConfig
import "Bezier.js" as BezierLib
import "PresetStore.js" as PresetStore

// Preset picker for the bar. The final row opens the full studio.
Panel {
    id: root

    moduleName: "io.github.cgaray.omamotion"
    ipcTarget: "io.github.cgaray.omamotion.bar"
    manageIpc: true

    property string fileText: ""
    property string activeVibe: ""
    property string hoveredVibe: ""
    property var hoveredPreset: null
    property real previewProgress: 0
    property var customPresets: []
    property int customPresetRev: 0
    property string pendingConfigText: ""
    property string pendingVibe: ""
    property bool configLocked: false      // oversized/unsafe file: never rewrite it

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

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

    function reloadState(ok, text) {
        // Anything the guarded reader refused — symlink, fifo, unreadable —
        // leaves presets disabled rather than acted on.
        if (!ok) {
            fileText = ""
            configLocked = true
            activeVibe = ""
            return
        }
        var result = LuaConfig.readState(text)
        // A file this large is not a looknfeel.lua we should be parsing, let
        // alone rewriting. Applying presets stays disabled until it shrinks.
        if (result.oversize) {
            fileText = ""
            configLocked = true
            activeVibe = ""
            return
        }
        configLocked = false
        fileText = text
        if (!result.found || result.error) {
            activeVibe = "Balanced"
            return
        }
        var current = normalizeParsed(result.state)
        activeVibe = MotionState.currentVibe(current, 0)
        if (activeVibe !== "") return
        for (var i = 0; i < customPresets.length; i++) {
            if (customPresets[i].state
                && JSON.stringify(customPresets[i].state.animations) === JSON.stringify(current.animations)) {
                activeVibe = customPresets[i].name
                return
            }
        }
    }

    // The bar only reads presets; migration of the legacy path is the
    // studio's job, so a stale legacy file is not acted on from here.
    function loadCustomPresets(ok, text) {
        var result = ok ? PresetStore.parse(text) : { ok: false, presets: [] }
        customPresets = result.ok ? result.presets : []
        customPresetRev++
    }

    function presetItems() {
        var items = []
        for (var i = 0; i < MotionState.VIBES.length; i++) {
            var vibe = MotionState.VIBES[i]
            items.push({ id: vibe.id, name: vibe.name, desc: vibe.desc, builtin: true })
        }
        for (var j = 0; j < customPresets.length; j++) {
            var custom = customPresets[j]
            if (custom && custom.name && custom.state)
                items.push({ id: "custom-" + j, name: custom.name, desc: "Saved custom setup", builtin: false, state: custom.state })
        }
        return items
    }

    function previewState() {
        if (!hoveredPreset) return null
        return hoveredPreset.builtin
            ? MotionState.applyPreset(MotionState.defaultState(), MotionState.VIBE_PRESET[hoveredPreset.id])
            : hoveredPreset.state
    }

    function previewEntry() {
        var s = previewState()
        if (!s || !s.animations) return null
        return s.animations.workspaces && s.animations.workspaces.enabled
            ? s.animations.workspaces : s.animations.windowsIn
    }

    // Both apply paths hand the new file to SafeFile, which stages it and
    // renames it into place; fileText only advances once that succeeds.
    function commitConfig(nextText, nextVibe) {
        pendingConfigText = nextText
        pendingVibe = nextVibe
        configWriter.write(nextText)
        root.close()
    }

    function onConfigWritten(ok) {
        if (!ok) {
            configWriter.read()
            return
        }
        fileText = pendingConfigText
        activeVibe = pendingVibe
    }

    function applyVibe(id) {
        if (configLocked) return
        var result = LuaConfig.readState(fileText)
        var state = result.found && !result.error
            ? normalizeParsed(result.state)
            : MotionState.defaultState()
        var nextState = MotionState.applyPreset(state, MotionState.VIBE_PRESET[id])
        commitConfig(LuaConfig.applyToText(
            fileText,
            LuaConfig.generateBody(nextState, MotionState.LEAVES.map(function (m) { return m.leaf }))
        ), id)
    }

    function applyCustomPreset(item) {
        if (configLocked) return
        var result = LuaConfig.readState(fileText)
        var state = result.found && !result.error
            ? normalizeParsed(result.state) : MotionState.defaultState()
        if (!item.state || !item.state.animations) return
        state.animations = JSON.parse(JSON.stringify(item.state.animations))
        if (item.state.curves) state.curves = JSON.parse(JSON.stringify(item.state.curves))
        commitConfig(LuaConfig.applyToText(
            fileText,
            LuaConfig.generateBody(state, MotionState.LEAVES.map(function (m) { return m.leaf }))
        ), item.name)
    }

    function applyItem(item) {
        if (item.builtin) applyVibe(item.id)
        else applyCustomPreset(item)
    }

    function openStudio() {
        if (bar) bar.run("omarchy-shell shell toggle io.github.cgaray.omamotion")
        root.close()
    }

    function previewDuration() {
        var entry = previewEntry()
        return entry && entry.speed !== undefined ? Math.max(140, entry.speed * 100) : 480
    }

    function previewEasing() {
        var s = previewState()
        var entry = previewEntry()
        var curves = s && s.curves ? s.curves : {}
        var curve = entry && curves[entry.bezier]
            ? curves[entry.bezier] : { p1: [0.23, 1], p2: [0.32, 1] }
        return BezierLib.fromPoints(curve.p1, curve.p2)
    }

    Timer {
        id: previewTimer
        interval: 16
        repeat: true
        running: root.opened && root.hoveredVibe !== ""
        onTriggered: {
            root.previewProgress += interval / root.previewDuration()
            if (root.previewProgress >= 1) root.previewProgress = 0
            previewCanvas.requestPaint()
        }
    }

    // No FileView on looknfeel.lua: it would open and load the file before
    // any check could run. The config is read only through the guarded
    // helper, on startup, when the picker opens, and after a failed write.
    SafeFile {
        id: configWriter
        path: Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"
        onLoaded: function (ok, text, message) { root.reloadState(ok, text) }
        onWritten: function (ok, message) { root.onConfigWritten(ok) }
    }

    Component.onCompleted: { configWriter.read(); presetFile.read() }
    onOpenedChanged: {
        if (!root.opened) return
        configWriter.read()
        presetFile.read()
    }

    // Same guarded treatment as the config: presets.json sits on a
    // predictable path and is user data, so no FileView is pointed at it.
    SafeFile {
        id: presetFile
        path: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.cgaray.omamotion/presets.json"
        onLoaded: function (ok, text, message) { root.loadCustomPresets(ok, text) }
    }

    Component {
        id: motionIcon

        Item {
            implicitWidth: Style.bar.iconCanvas
            implicitHeight: Style.bar.iconCanvas

            Canvas {
                anchors.fill: parent

                onPaint: {
                    var ctx = getContext("2d")
                    var w = width
                    var h = height
                    var stroke = button.foreground
                    var accent = Color.accent

                    ctx.clearRect(0, 0, w, h)
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"

                    // Draw the easing curve and its control handles.
                    ctx.strokeStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, 0.38)
                    ctx.lineWidth = Math.max(1, w * 0.07)
                    ctx.beginPath()
                    ctx.moveTo(w * 0.14, h * 0.82)
                    ctx.lineTo(w * 0.34, h * 0.22)
                    ctx.moveTo(w * 0.86, h * 0.82)
                    ctx.lineTo(w * 0.66, h * 0.66)
                    ctx.stroke()

                    ctx.strokeStyle = stroke
                    ctx.lineWidth = Math.max(1.5, w * 0.11)
                    ctx.beginPath()
                    ctx.moveTo(w * 0.14, h * 0.82)
                    ctx.bezierCurveTo(w * 0.34, h * 0.22, w * 0.66, h * 0.66, w * 0.86, h * 0.82)
                    ctx.stroke()

                    ctx.fillStyle = accent
                    ctx.beginPath()
                    ctx.arc(w * 0.62, h * 0.61, Math.max(1.5, w * 0.12), 0, Math.PI * 2)
                    ctx.fill()
                }
            }
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: motionIcon
        active: root.activeVibe !== ""
        // BarIconButton renders this; we cannot set its textFormat, so the
        // user-authored preset name is stripped of markup instead.
        tooltipText: root.activeVibe === ""
            ? "Motion presets"
            : "Motion: " + PresetStore.plainName(root.activeVibe)
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.RightButton) root.openStudio()
            else root.toggle()
        }
    }

    KeyboardPanel {
        id: popup
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        contentWidth: Style.space(380)
        // Reserve space for KeyboardPanel's surface insets.
        contentHeight: contentColumn.implicitHeight + Style.space(28)

        Column {
            id: contentColumn
            width: parent.width
            spacing: Style.space(2)

            Text {
                text: "Motion feel"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.configLocked
                    ? "looknfeel.lua is over 1 MiB — presets are disabled."
                    : "Choose how your desktop moves."
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }

            Row {
                id: pickerRow
                width: parent.width
                spacing: Style.space(3)

                Flickable {
                    id: presetList
                    width: (parent.width - pickerRow.spacing) * 0.60
                    height: Math.min(presetColumn.implicitHeight, Style.space(300))
                    contentWidth: width
                    contentHeight: presetColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    Column {
                        id: presetColumn
                        width: presetList.width
                        spacing: Style.space(2)

                        Repeater {
                            model: { var rev = root.customPresetRev; return root.presetItems() }

                            delegate: Rectangle {
                                required property var modelData
                                width: presetColumn.width
                            height: presetText.implicitHeight + Style.space(4)
                            radius: 6
                            color: hover.containsMouse
                                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
                                : "transparent"
                            border.width: root.activeVibe === modelData.name ? 2 : 1
                            border.color: root.activeVibe === modelData.name
                                ? Color.accent
                                : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.22)

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.hoveredVibe = modelData.id
                                    root.hoveredPreset = modelData
                                    root.previewProgress = 0
                                    previewTimer.restart()
                                    previewCanvas.requestPaint()
                                }
                                onExited: {
                                    if (root.hoveredVibe !== modelData.id) return
                                    previewTimer.stop()
                                    root.hoveredVibe = ""
                                    root.hoveredPreset = null
                                    previewCanvas.requestPaint()
                                }
                        onClicked: root.applyItem(modelData)
                            }

                            Column {
                                id: presetText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Style.space(3)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(1)

                                Text {
                                    text: modelData.name
                                    // Saved preset names come from presets.json;
                                    // AutoText would sniff them as rich text.
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    width: parent.width
                                    color: root.activeVibe === modelData.name ? Color.accent : Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.body
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.desc
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
                }

                Item {
                    width: parent.width - presetList.width - pickerRow.spacing
                    height: presetList.height

                    Canvas {
                        id: previewCanvas
                        anchors.fill: parent

                        onPaint: {
                            var ctx = getContext("2d")
                            var w = width
                            var h = height
                            var gap = Style.space(3)
                            var previewStyle = root.previewEntry() && root.previewEntry().style
                                ? root.previewEntry().style : ""
                            var vertical = previewStyle.indexOf("slidevert") !== -1
                            var workspaceWidth = vertical ? w : (w - gap) / 2
                            var workspaceHeight = vertical ? (h - gap) / 2 : h - Style.space(4)
                            var eased = root.hoveredVibe === ""
                                ? 0.5
                                : (root.hoveredVibe === "Instant" ? 1 : root.previewEasing().at(root.previewProgress))

                            ctx.clearRect(0, 0, w, h)
                            ctx.lineWidth = 1
                            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                            ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                            ctx.fillRect(0, 0, workspaceWidth, workspaceHeight)
                            ctx.strokeRect(0.5, 0.5, workspaceWidth - 1, workspaceHeight - 1)
                            if (vertical) {
                                ctx.fillRect(0, workspaceHeight + gap, workspaceWidth, workspaceHeight)
                                ctx.strokeRect(0.5, workspaceHeight + gap + 0.5, workspaceWidth - 1, workspaceHeight - 1)
                            } else {
                                ctx.fillRect(workspaceWidth + gap, 0, workspaceWidth, workspaceHeight)
                                ctx.strokeRect(workspaceWidth + gap + 0.5, 0.5, workspaceWidth - 1, workspaceHeight - 1)
                            }

                            ctx.fillStyle = Color.muted
                            ctx.font = Math.max(9, Style.font.caption) + "px sans-serif"
                            ctx.fillText("1", 5, 13)
                            if (vertical) ctx.fillText("2", 5, workspaceHeight + gap + 13)
                            else ctx.fillText("2", workspaceWidth + gap + 5, 13)

                            var windowWidth = vertical ? workspaceWidth * 0.52 : workspaceWidth * 0.58
                            var windowHeight = workspaceHeight * 0.5
                            var x = vertical ? (workspaceWidth - windowWidth) / 2 : workspaceWidth * 0.18
                            var y = (workspaceHeight - windowHeight) / 2 + 2
                            if (vertical) {
                                y += (workspaceHeight + gap) * eased
                            } else {
                                x += (workspaceWidth + gap) * eased
                            }
                            ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.24)
                            ctx.strokeStyle = Color.accent
                            ctx.fillRect(x, y, windowWidth, windowHeight)
                            ctx.strokeRect(x + 0.5, y + 0.5, windowWidth - 1, windowHeight - 1)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "Hover a preset"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        visible: root.hoveredVibe === ""
                    }
                }
            }

            PanelSeparator { width: parent.width }

            Button {
                width: parent.width
                text: "Open full motion studio"
                onClicked: root.openStudio()
            }
        }
    }
}
