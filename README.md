# OmaMotion

**A motion studio for Hyprland — pick a vibe, feel it live, done.**

An Omarchy shell plugin. Omaland gave Hyprland's geometry a GUI and Aether gave
color one; OmaMotion completes the trio for **motion**.

Most people need exactly one thing: a *vibe*. The panel opens on five big
cards — Instant, Snappy, Balanced, Smooth, Playful. Click one, Hyprland
changes immediately, done. Beneath them a **Simple** tab speaks plain English
("Window opens", "Panel fades out", speeds as *Fast* / *Balanced* / *Relaxed*,
styles as *Pop* / *Slide & fade*). The **Advanced** tab holds the full
studio: every animation leaf Omarchy ships, a hand-draggable bezier editor
with a live tracer, custom curves, and raw style tokens.

No network access. No sudo. The optional launcher/bar integration is a tiny
local service; it has no daemon of its own.

<p align="center"><img src="preview.png" alt="The OmaMotion panel: leaf list on the left, bezier curve editor and animated preview on the right" width="880"></p>

## Install

```bash
omarchy plugin add https://github.com/cgaray/omamotion.git --enable --yes
```

Open it from **SUPER+SPACE › Apps › OmaMotion** (the service half of the
plugin installs a launcher entry automatically), or bind it:

```lua
o.bind("SUPER + SHIFT + M", "OmaMotion", "omarchy-shell shell toggle io.github.cgaray.omamotion")
```

To remove it:

```bash
omarchy plugin remove io.github.cgaray.omamotion --yes
```

## Status bar presets

OmaMotion adds a small `≈` button to the right side of the Omarchy bar. Click
it to choose Instant, Snappy, Balanced, Smooth, or Playful without opening the
studio. Right-click the button to open the full studio.

If you installed the repository manually, enable the bar widget with:

```bash
omarchy plugin enable io.github.cgaray.omamotion right
```

The bar picker is intentionally simple: each choice applies immediately and
closes the popup. The studio is there when you want to understand or tune the
details.

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

## Vibes (presets)

The five cards map to full-animation presets: **Balanced** = Omarchy stock,
**Smooth** = Butter, **Playful** = Dramatic. Applying a vibe saves instantly
and keeps your custom curve library intact. The active vibe highlights
itself; the moment you hand-tune anything, no card is highlighted — honest
state, no pretending.

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
- The service kind installs one launcher entry,
  `~/.local/share/applications/omamotion.desktop`, guarded by an
  `X-OmaMotion-Managed` marker: pre-existing files are never touched, and
  removal deletes only what we wrote
- Never executes plugin-side or user-side code to read state back
- No network access, no sudo/pkexec, no daemons, no shell-out
- All state lives in the block itself; remove it and nothing remains

## License

[MIT](LICENSE)
