.pragma library

function clampPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return 100
  return Math.max(50, Math.min(100, Math.round(number)))
}

function optionValue(entry) {
  if (entry.float !== undefined) return Number(entry.float)
  if (entry.int !== undefined) return Number(entry.int)
  return undefined
}

function parseOpacityOptions(raw) {
  var values = {}
  var objects = String(raw || "").match(/\{[^{}]*\}/g) || []

  for (var i = 0; i < objects.length; i++) {
    try {
      var entry = JSON.parse(objects[i])
      var value = optionValue(entry)
      if (entry.option && value !== undefined && isFinite(value))
        values[String(entry.option)] = value
    } catch (error) {
    }
  }

  var active = values["decoration:active_opacity"]
  var inactive = values["decoration:inactive_opacity"]
  if (!isFinite(active) || !isFinite(inactive)) return null

  return { active: active, inactive: inactive }
}

function scaledOpacity(base, percent) {
  var value = Number(base) * clampPercent(percent) / 100
  return Math.max(0.05, Math.min(1, value))
}

function luaNumber(value) {
  return String(parseFloat(Number(value).toFixed(4)))
}

function renderOpacityConfig(activeBase, inactiveBase, percent) {
  var active = scaledOpacity(activeBase, percent)
  var inactive = scaledOpacity(inactiveBase, percent)
  return "hl.config({ decoration = { active_opacity = " + luaNumber(active)
    + ", inactive_opacity = " + luaNumber(inactive) + ", }, })"
}
