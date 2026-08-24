# OmaMotion

OmaMotion is an Omarchy shell plugin for editing Hyprland animation settings.
It provides a preset picker, a simple editor, an advanced editor, a curve
editor, and a live preview.

## Install

```bash
omarchy plugin add https://github.com/cgaray/omamotion.git --enable --yes
```

Open OmaMotion from the application menu or bind it directly:

```lua
o.bind("SUPER + SHIFT + M", "OmaMotion", "omarchy-shell shell toggle io.github.cgaray.omamotion")
```

Remove it with:

```bash
omarchy plugin remove io.github.cgaray.omamotion --yes
```

The plugin does not change Hyprland configuration during removal. Use **Reset
all** first to remove OmaMotion's managed animation block.

## Bar Picker

The bar widget provides the Instant, Snappy, Balanced, Smooth, and Playful
presets. Click a preset to apply it. Right-click the widget to open the studio.
Saved custom presets are also available in this menu.

For a manual installation, enable the widget with:

```bash
omarchy plugin enable io.github.cgaray.omamotion right
```

## Editors

Simple mode uses labels such as Window opens, Panel fades out, Fast, and Slide.
Advanced mode exposes every animation leaf, curve selection, raw style tokens,
and custom curves.

The preview supports window and layer open, close, move, and layer modes. It
also shows two workspace panes and uses stacked panes for vertical workspace
styles. The preview is an approximation of the compositor.

## Custom Presets

Use **Save current preset** in the studio. A preset contains the current
animation state and curve library. The bar picker previews and applies saved
presets.

Presets are stored as validated JSON in:

```text
~/.config/omarchy/plugins/io.github.cgaray.omamotion/presets.json
```

The file is limited to 32 presets and 64 KiB. Presets contain data only; they
cannot contain commands or executable hooks.

## Configuration

OmaMotion owns one fenced block at the end of:

```text
~/.config/hypr/looknfeel.lua
```

Only the content between these markers is rewritten:

```lua
-- >>> omamotion managed block >>>
-- <<< omamotion managed block <<<
```

Content outside the block is preserved. Reset removes the block. State reading
uses a literal parser and does not evaluate the user's Lua configuration.

Hyprland watches `looknfeel.lua`, so saved changes apply live. The QML preview
is separate from the compositor and is intended for visual comparison.

## Managed Settings

| Section | Leaves |
| --- | --- |
| Global | `global` |
| Windows | `windows`, `windowsIn`, `windowsOut` |
| Layers | `layers`, `layersIn`, `layersOut`, `fadeLayersIn`, `fadeLayersOut` |
| Fades | `fadeIn`, `fadeOut`, `fade`, `fadeSwitch` |
| Workspaces | `workspaces` |
| Chrome | `border` |

Theme colors are not edited. Omarchy's theme system owns them.

## Launcher Integration

The service installs a desktop entry at:

```text
~/.local/share/applications/omamotion.desktop
```

The entry contains an `X-OmaMotion-Managed=true` marker. The service only
updates or removes an entry carrying that marker.

## Requirements

- Omarchy 4 with `omarchy-shell`
- Hyprland 0.56 or newer with Lua configuration support
- No external runtime dependencies

## License

MIT. See [LICENSE](LICENSE).
