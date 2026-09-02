# Omapaque

Omapaque adds an exact window-opacity slider to the Omarchy bar. It reads the
current theme's focused-window opacity and shows that value when the theme is
applied.

Moving the slider sets that exact opacity for active, inactive, and fullscreen
windows. Setting it to 100% makes windows fully opaque, even when the theme has
an opacity multiplier. Switching themes removes the live override and reads the
new theme's value.

## Install

The Omarchy plugin command clones a Git repository. From inside this checkout,
run:

```bash
omarchy plugin install . --enable --yes
```

For a published copy, replace the path with its Git URL:

```bash
omarchy plugin install https://github.com/tomrplummer/omapaque.git --enable
```

Omarchy places the widget in the right section by default. If needed, move it
with:

```bash
omarchy bar move tomrplummer.omapaque --section right
```

## Use

- Left-click opens the slider.
- Scroll over the icon to change opacity in 2.5% steps.
- Right-click resets to the theme value.
- In the panel, Left and Right adjust the slider. Enter resets it.

The 50% lower limit prevents accidental near-invisible windows. Omapaque applies
the chosen value to open windows and new windows. It only changes Hyprland's
live state. It does not edit theme files or files under `~/.config/hypr`.

## Remove

```bash
omarchy plugin remove tomrplummer.omapaque --yes
hyprctl reload
```

Reloading Hyprland restores the current theme's opacity after removal.

## Requirements

- Omarchy 4.x
- Hyprland using Omarchy's Lua configuration
- Omarchy shell with bar-widget plugin support

## License

MIT
