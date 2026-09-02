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

function nextRetryDelay(value) {
  var delay = Number(value)
  if (!isFinite(delay) || delay < 1500) delay = 1500
  return Math.min(Math.round(delay * 2), 10000)
}

function shouldCarryAcrossTheme(persist, customized, pending) {
  return persist === true && (customized === true || pending === true)
}

function finiteNumber(value) {
  if (value === undefined || value === null || value === "") return null
  var number = Number(value)
  return isFinite(number) ? number : null
}

function parseThemeOpacity(raw) {
  var globalActive = null
  var candidates = []
  var objects = String(raw || "").match(/\{[^{}]*\}/g) || []

  for (var i = 0; i < objects.length; i++) {
    try {
      var entry = JSON.parse(objects[i])
      if (entry.option) {
        if (String(entry.option) !== "decoration:active_opacity") continue
        if (entry.float !== undefined) globalActive = finiteNumber(entry.float)
        else if (entry.int !== undefined) globalActive = finiteNumber(entry.int)
        continue
      }
      var opacity = finiteNumber(entry.opacity)
      if (opacity !== null) {
        candidates.push({
          opacity: opacity,
          override: entry.opacity_override === true
        })
      }
    } catch (error) {
    }
  }

  if (globalActive === null) return null
  if (candidates.length === 0) return null

  // App rules commonly force media apps and terminals opaque. Prefer windows
  // still using the theme's multiplying rule, then take the lowest matching
  // value so a later app-specific opaque rule cannot masquerade as the theme.
  var themeCandidates = []
  for (var j = 0; j < candidates.length; j++) {
    if (!candidates[j].override) themeCandidates.push(candidates[j])
  }
  if (themeCandidates.length === 0) themeCandidates = candidates

  var actual = null
  for (var k = 0; k < themeCandidates.length; k++) {
    var candidate = themeCandidates[k]
    var value = candidate.override
      ? candidate.opacity
      : globalActive * candidate.opacity
    if (actual === null || value < actual) actual = value
  }
  return clampPercent(actual * 100)
}

function themeOpacityProbe() {
  return [
    "set -o pipefail",
    "hyprctl -j getoption decoration:active_opacity",
    "hyprctl clients -j | jq -r '.[] | select(any(.tags[]?; test(\"^default-opacity\\\\*?$\"))) | .address' | while IFS= read -r address; do",
    "  [[ \"$address\" =~ ^0x[0-9A-Fa-f]+$ ]] || continue",
    "  hyprctl -j --batch \"getprop address:$address opacity ; getprop address:$address opacity_override\" | jq -sc 'map(select(type == \"object\")) | {opacity: (map(select(has(\"opacity\")))[0].opacity // null), opacity_override: (map(select(has(\"opacity_override\")))[0].opacity_override // false)}'",
    "done"
  ].join("\n")
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

function luaString(value) {
  return '"' + String(value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n") + '"'
}

function renderLuaCall(path, method, percent) {
  var argument = percent === undefined ? "" : luaNumber(clampPercent(percent) / 100)
  return "local plugin = assert(loadfile(" + luaString(path) + "))(); plugin."
    + String(method) + "(" + argument + ")"
}
