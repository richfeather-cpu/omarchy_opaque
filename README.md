# Omapaque

Omapaque adds an exact window-opacity slider to the Omarchy bar. It reads the
current theme's Hyprland settings and shows the theme's default active-window
opacity. Personal and app-specific rules, such as a rule that keeps one terminal
opaque, do not replace the theme value shown by the slider.

Moving the slider sets that exact opacity for active, inactive, and fullscreen
windows. Setting it to 100% makes windows fully opaque, even when the theme has
an opacity multiplier. By default, switching themes removes the live override
and reads the new theme's value. An optional panel setting can reapply the custom
value after Omapaque records the new theme default. The compositor-side behavior
is implemented as a named Hyprland Lua window rule, so removing it reveals the
theme's rule again.

## Install

The Omarchy plugin command clones a Git repository. From inside this checkout,
run:

```bash
omarchy plugin add . --enable --yes
```

For a published copy, replace the path with its Git URL:

```bash
omarchy plugin add https://github.com/tomrplummer/omapaque.git --enable
```

Omarchy places the widget in the right section by default. If needed, move it
with:

```bash
omarchy bar move tomrplummer.omapaque --section right
```

## Update

```bash
omarchy plugin update tomrplummer.omapaque --yes
```

The update command rescans installed plugins. If an update does not appear,
force another scan with `omarchy-shell shell rescanPlugins`. Restart the shell
only if the rescan does not work.

## Use

- Left-click opens the slider.
- Scroll over the icon to change opacity in 2.5% steps (1% steps at or below
  10%, where small changes are visible).
- Presets under the slider jump to 1/4, 1/2, or Full opacity.
- Right-click resets to the theme value.
- In the panel, Left and Right adjust the slider. Up and Down move between the
  slider and persistence toggle. Enter activates the selected control.
- Enable **Keep custom opacity across themes** to reapply your chosen value after
  a theme change.

Choosing a value always keeps that exact compositor override, even when the
number matches the current theme value. Use reset when you want the theme to
control opacity again. Reset keeps the cross-theme preference enabled, so the
next custom value will also persist.

The lower limit is 1%. Very low values make windows nearly invisible; right-click
the icon or use the Full preset to recover. Omapaque applies
the chosen value to open windows and new windows. It only changes Hyprland's
live state. It does not edit theme files or files under `~/.config/hypr`.

The override applies to every regular window, including browsers, media apps,
and other applications that Omarchy normally excludes from its default opacity
rule. This is what lets 100% make every window fully opaque. Values below 100%
can make those excluded applications transparent too. Reset restores Omarchy's
normal per-application rules.

## Remove

```bash
omarchy plugin remove tomrplummer.omapaque --yes
hyprctl reload
```

Omapaque restores the theme opacity when it is disabled or removed. The explicit
Hyprland reload is a fallback in case removal interrupts the shell cleanup.

## Requirements

- Omarchy 4.x
- Hyprland using Omarchy's Lua configuration
- Omarchy shell with bar-widget plugin support
- Bash, `jq`, and `flock`, which are included with Omarchy

Omapaque runs `hyprctl eval` to manage its temporary Lua window rule and
`hyprctl reload` when restoring theme control. It does not use `sudo`, edit
Hyprland configuration, start services, or access the network.

## Development

Validate the plugin and run its tests with:

```bash
omarchy plugin validate .
node test/run.js
lua test/lua_test.lua
```

Node.js and Lua are only needed to run the development tests.

## License

MIT
