.pragma library

function clampPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return 100
  return Math.max(50, Math.min(100, Math.round(number * 2) / 2))
}

function formatPercent(value) {
  var number = clampPercent(value)
  return (Math.round(number) === number ? String(number) : number.toFixed(1)) + "%"
}

function finiteNumber(value) {
  if (value === undefined || value === null || value === "") return null
  var number = Number(value)
  return isFinite(number) ? number : null
}

function parseThemeOpacity(raw) {
  var values = {}
  var objects = String(raw || "").match(/\{[^{}]*\}/g) || []

  for (var i = 0; i < objects.length; i++) {
    try {
      var entry = JSON.parse(objects[i])
      if (entry.option) {
        if (entry.float !== undefined) values[String(entry.option)] = Number(entry.float)
        else if (entry.int !== undefined) values[String(entry.option)] = Number(entry.int)
        continue
      }
      for (var key in entry) values[key] = entry[key]
    } catch (error) {
    }
  }

  var globalActive = finiteNumber(values["decoration:active_opacity"])
  if (globalActive === null) return null

  // getprop needs a live matching window. Returning null lets the panel retry
  // instead of presenting a guessed Omarchy default as the theme's value.
  var ruleActive = finiteNumber(values.opacity)
  if (ruleActive === null) return null

  var actual = values.opacity_override === true
    ? ruleActive
    : globalActive * ruleActive
  return clampPercent(actual * 100)
}

function renderUnloadCleanup() {
  return [
    "exec 9>\"${XDG_RUNTIME_DIR:-/tmp}/omapaque-cleanup.lock\"",
    "flock -n 9 || exit 0",
    "sleep 0.25",
    "plugins=$(omarchy-shell shell listPlugins 2>/dev/null) || exit 0",
    "[[ -n \"$plugins\" ]] || exit 0",
    "if printf '%s' \"$plugins\" | jq -e --arg id \"$1\" 'any(.[]; .id == $id and .enabled == true)' >/dev/null; then exit 0; fi",
    "hyprctl eval \"$2\" >/dev/null 2>&1",
    "hyprctl reload >/dev/null 2>&1"
  ].join("\n")
}

function luaNumber(value) {
  return String(parseFloat(Number(value).toFixed(4)))
}

function renderAbsoluteOpacity(percent) {
  var opacity = luaNumber(clampPercent(percent) / 100)
  return [
    "_G.omapaque_opacity = " + opacity,
    "_G.omapaque_apply_window = function(window)",
    "  if not window then return end",
    "  local value = tostring(_G.omapaque_opacity or 1)",
    "  hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = \"opacity_override\", value = \"true\" }))",
    "  hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = \"opacity_inactive_override\", value = \"true\" }))",
    "  hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = \"opacity_fullscreen_override\", value = \"true\" }))",
    "  hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = \"opacity\", value = value }))",
    "  hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = \"opacity_inactive\", value = value }))",
    "  hl.dispatch(hl.dsp.window.set_prop({ window = window, prop = \"opacity_fullscreen\", value = value }))",
    "end",
    "local subscription_active = false",
    "if _G.omapaque_subscription then",
    "  local ok, active = pcall(function() return _G.omapaque_subscription:is_active() end)",
    "  subscription_active = ok and active",
    "end",
    "if not subscription_active then",
    "  _G.omapaque_subscription = hl.on(\"window.open\", function(window)",
    "    if _G.omapaque_apply_window then _G.omapaque_apply_window(window) end",
    "  end)",
    "end",
    "for _, window in ipairs(hl.get_windows()) do _G.omapaque_apply_window(window) end"
  ].join("\n")
}

function renderCleanup() {
  return [
    "if _G.omapaque_subscription then",
    "  pcall(function() _G.omapaque_subscription:remove() end)",
    "end",
    "_G.omapaque_subscription = nil",
    "_G.omapaque_apply_window = nil",
    "_G.omapaque_opacity = nil"
  ].join("\n")
}
