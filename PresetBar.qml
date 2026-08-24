import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MotionState.js" as MotionState
import "LuaConfig.js" as LuaConfig
import "Bezier.js" as BezierLib

// A compact, beginner-friendly preset picker. The full studio remains
// available from the final row; the common path is one click on a vibe.
Panel {
    id: root

    moduleName: "io.github.cgaray.omamotion"
    ipcTarget: "io.github.cgaray.omamotion"
    manageIpc: false

    property string fileText: ""
    property string activeVibe: ""
    property bool suppressEcho: false
    property string hoveredVibe: ""
    property real previewProgress: 0

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function normalizeParsed(parsed) {
        var s = MotionState.defaultState()
        var name
        for (name in parsed.curves) s.curves[name] = parsed.curves[name]
        for (var leaf in parsed.animations) {
            var t = parsed.animations[leaf]
            var entry = { enabled: !!t.enabled }
            if (typeof t.speed === "number") entry.speed = t.speed
            if (typeof t.bezier === "string") entry.bezier = t.bezier
            entry.style = typeof t.style === "string" ? t.style : ""
            s.animations[leaf] = entry
        }
        return s
    }

    function reloadState() {
        fileText = configFile.text()
        var result = LuaConfig.readState(fileText)
        activeVibe = result.found && !result.error
            ? MotionState.currentVibe(normalizeParsed(result.state), 0)
            : "Balanced"
    }

    function applyVibe(id) {
        var result = LuaConfig.readState(fileText)
        var state = result.found && !result.error
            ? normalizeParsed(result.state)
            : MotionState.defaultState()
        var nextState = MotionState.applyPreset(state, MotionState.VIBE_PRESET[id])
        var nextText = LuaConfig.applyToText(
            fileText,
            LuaConfig.generateBody(nextState, MotionState.LEAVES.map(function (m) { return m.leaf }))
        )
        suppressEcho = true
        configFile.setText(nextText)
        fileText = nextText
        activeVibe = id
        root.close()
    }

    function openStudio() {
        if (bar) bar.run("omarchy-shell shell toggle io.github.cgaray.omamotion")
        root.close()
    }

    function previewDuration() {
        if (hoveredVibe === "Instant") return 140
        if (hoveredVibe === "Snappy") return 280
        if (hoveredVibe === "Smooth") return 900
        if (hoveredVibe === "Playful") return 560
        return 480
    }

    function previewEasing() {
        if (hoveredVibe === "Snappy") return BezierLib.fromPoints([0.15, 0], [0.1, 1])
        if (hoveredVibe === "Smooth") return BezierLib.fromPoints([0.65, 0.05], [0.36, 1])
        return BezierLib.fromPoints([0.23, 1], [0.32, 1])
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

    FileView {
        id: configFile
        path: Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"
        watchChanges: true
        printErrors: false
        onLoaded: root.reloadState()
        onFileChanged: {
            if (root.suppressEcho) {
                root.suppressEcho = false
                return
            }
            reload()
        }
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

                    // A compact easing curve: two control handles and a
                    // highlighted point make the widget readable at bar size.
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
        tooltipText: root.activeVibe === ""
            ? "Motion presets"
            : "Motion: " + root.activeVibe
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
        contentWidth: Style.space(330)
        // KeyboardPanel adds its own surface insets around the content.
        // Leave a generous bottom reserve so the studio action never lands
        // underneath the card edge on compact themes or font scales.
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
                text: "Choose how your desktop moves."
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }

            Row {
                id: pickerRow
                width: parent.width
                spacing: Style.space(3)

                Column {
                    id: presetList
                    width: (parent.width - pickerRow.spacing) * 0.58
                    spacing: Style.space(2)

                    Repeater {
                        model: MotionState.VIBES

                        delegate: Rectangle {
                            required property var modelData
                            width: presetList.width
                            height: presetText.implicitHeight + Style.space(4)
                            radius: 6
                            color: hover.containsMouse
                                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
                                : "transparent"
                            border.width: root.activeVibe === modelData.id ? 2 : 1
                            border.color: root.activeVibe === modelData.id
                                ? Color.accent
                                : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.22)

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.hoveredVibe = modelData.id
                                    root.previewProgress = 0
                                    previewCanvas.requestPaint()
                                }
                                onExited: {
                                    root.hoveredVibe = ""
                                    previewCanvas.requestPaint()
                                }
                                onClicked: root.applyVibe(modelData.id)
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
                                    color: root.activeVibe === modelData.id ? Color.accent : Color.foreground
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.body
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.desc
                                    color: Color.muted
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
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
                            var workspaceWidth = (w - gap) / 2
                            var workspaceHeight = h - Style.space(4)
                            var eased = root.hoveredVibe === ""
                                ? 0.5
                                : (root.hoveredVibe === "Instant" ? 1 : root.previewEasing().at(root.previewProgress))

                            ctx.clearRect(0, 0, w, h)
                            ctx.lineWidth = 1
                            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                            ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                            ctx.fillRect(0, 0, workspaceWidth, workspaceHeight)
                            ctx.strokeRect(0.5, 0.5, workspaceWidth - 1, workspaceHeight - 1)
                            ctx.fillRect(workspaceWidth + gap, 0, workspaceWidth, workspaceHeight)
                            ctx.strokeRect(workspaceWidth + gap + 0.5, 0.5, workspaceWidth - 1, workspaceHeight - 1)

                            ctx.fillStyle = Color.muted
                            ctx.font = Math.max(9, Style.font.caption) + "px sans-serif"
                            ctx.fillText("1", 5, 13)
                            ctx.fillText("2", workspaceWidth + gap + 5, 13)

                            var windowWidth = workspaceWidth * 0.58
                            var windowHeight = workspaceHeight * 0.5
                            var fromX = workspaceWidth * 0.18
                            var toX = workspaceWidth + gap + workspaceWidth * 0.18
                            var x = fromX + (toX - fromX) * eased
                            var y = (workspaceHeight - windowHeight) / 2 + 2
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
