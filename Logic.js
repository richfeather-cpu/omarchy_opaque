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

  var globalActive = Number(values["decoration:active_opacity"])
  if (!isFinite(globalActive)) return null

  // Omarchy's normal window rule is 0.985 when no matching window exists for
  // getprop to inspect. A live matching window supplies the theme's real value.
  var ruleActive = Number(values.opacity)
  if (!isFinite(ruleActive)) ruleActive = 0.985

  var actual = values.opacity_override === true
    ? ruleActive
    : globalActive * ruleActive
  return clampPercent(actual * 100)
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
