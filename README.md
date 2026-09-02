# Omapaque

Omapaque adds a window-opacity slider to the Omarchy bar. It treats each
theme's opacity as the baseline instead of writing a permanent Hyprland
override.

At 100%, windows use the current theme's focused and unfocused opacity. Lower
values scale both settings together, which keeps the theme's active-window
contrast and any window-specific opacity rules. Switching themes resets the
slider to the new theme's values.

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
- Scroll over the icon to change opacity in 5% steps.
- Right-click resets to the theme value.
- In the panel, Left and Right adjust the slider. Enter resets it.

The 50% lower limit prevents accidental near-invisible windows. Omapaque only
changes Hyprland's live state. It does not edit theme files or files under
`~/.config/hypr`.

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
