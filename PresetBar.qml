import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "MotionState.js" as MotionState
import "LuaConfig.js" as LuaConfig

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
        contentHeight: contentColumn.implicitHeight + Style.space(8)

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

            Repeater {
                model: MotionState.VIBES

                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
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

            PanelSeparator { width: parent.width }

            Button {
                width: parent.width
                text: "Open full motion studio"
                onClicked: root.openStudio()
            }
        }
    }
}
