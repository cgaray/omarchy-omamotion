# OmaMotion

**A motion studio for Hyprland — draw your easing curves, tune every animation
leaf, feel the result live, then save it as plain Lua.**

An Omarchy shell plugin. Omaland gave Hyprland's geometry a GUI and Aether gave
color one; OmaMotion completes the trio for **motion**: every animation leaf
Omarchy ships, a hand-draggable bezier editor, an approximate live preview,
and one-click presets.

No network access. No sudo. No background service.

<p align="center"><img src="preview.png" alt="The OmaMotion panel: leaf list on the left, bezier curve editor and animated preview on the right" width="880"></p>

## Install

```bash
omarchy plugin add https://github.com/cgaray/omamotion.git --enable --yes
```

Open it from **SUPER+SPACE › OmaMotion**, or bind it:

```lua
o.bind("SUPER + SHIFT + M", "OmaMotion", "omarchy-shell shell toggle io.github.cgaray.omamotion")
```

To remove it:

```bash
omarchy plugin remove io.github.cgaray.omamotion --yes
```

**Reset all** (or removing the plugin) takes the managed block with it and
restores your `looknfeel.lua` byte for byte.

## What it edits

Every animation leaf Omarchy defines in `~/.config/hypr/looknfeel.lua`, plus
the curves they reference:

| Section | Leaves |
|---|---|
| **Global** | master enable, speed multiplier curve |
| **Windows** | `windows`, `windowsIn`, `windowsOut` — speed, curve, style (`popin 87%`, `slide top`, `fade`, …) |
| **Layers** | `layers`, `layersIn`, `layersOut`, `fadeLayersIn/Out` |
| **Fades** | `fadeIn`, `fadeOut`, `fade`, `fadeSwitch` |
| **Workspaces** | `workspaces` enable/style/speed |
| **Chrome** | `border` |

Colors are absent on purpose: Omarchy themes own them, and touching them here
would fight `omarchy theme set`.

## The curve editor

- Drag **P1/P2** handles; click empty space to snap a handle there
- A tracer dot sweeps the curve continuously so easing is *felt*, not guessed
- The five stock Omarchy curves are editable; **Add as new** clones the
  current shape under a custom name, and any leaf can switch to it from its
  dropdown
- Editing a curve updates every leaf that uses it — usage is counted above
  the editor

## Preview

The stage replays the selected leaf with Open / Close / Move / Layer buttons,
mapping Hyprland style tokens (`popin %`, slide directions, fades) to
approximate QML transforms. It is deliberately labelled approximate: the real
compositor is always one save away, and writes apply live because Hyprland
watches the file.

## Presets

**Omarchy stock · Butter · Snappy · Dramatic · Instant** — presets replace the
animation table wholesale and keep your curve library intact.

## How it works

**Where it writes.** One fenced block at the end of
`~/.config/hypr/looknfeel.lua` between two marker comments. Nothing outside
the fences is touched. Clearing every override (Reset all) removes the block
and restores the file byte for byte. The block is plain Lua in exactly the
shape Omarchy itself writes — readable, diffable, hand-editable:

```lua
-- >>> omamotion managed block >>>
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
-- <<< omamotion managed block <<<
```

**Reading state back** never evaluates Lua: the block is parsed with balanced
scans over string/number/table literals only. If a hand-edit breaks the
syntax, OmaMotion says so instead of guessing, and saving rewrites the block
cleanly. External changes to the file are watched and merged while you work.

**Live preview** of the real thing comes for free: Hyprland reloads
`looknfeel.lua` on change, so each debounced save applies instantly. The QML
stage is for feel; the compositor is for truth.

## Keys

| | |
|---|---|
| `Esc` | close |

Everything else is mouse-first by design; sliders, toggles and dropdowns come
from Omarchy's own UI kit and follow your theme.

## Requirements

- Omarchy 4 with the Quattro shell (`omarchy-shell`)
- Hyprland ≥ 0.56 with Lua config support
- No external dependencies — no `lua` interpreter, no network tools

## Security posture

- Writes only inside its fenced block in `~/.config/hypr/looknfeel.lua`
- Never executes plugin-side or user-side code to read state back
- No network access, no sudo/pkexec, no daemons, no shell-out
- All state lives in the block itself; remove it and nothing remains

## License

[MIT](LICENSE)
