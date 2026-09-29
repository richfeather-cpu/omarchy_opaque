.pragma library

function clampPercent(value) {
  var number = Number(value)
  if (!isFinite(number)) return 100
  return Math.max(1, Math.min(100, Math.round(number * 2) / 2))
}

function formatPercent(value) {
  var number = clampPercent(value)
  return (Math.round(number) === number ? String(number) : number.toFixed(1)) + "%"
}

// Scroll/keyboard step: 2.5% normally, 1% at or below 10% where small
// changes are visible.
function wheelStep(current, direction) {
  return Number(current) + (direction < 0 ? -0.0001 : 0) <= 10 ? 1 : 2.5
}

function nextRetryDelay(value) {
  var delay = Number(value)
  if (!isFinite(delay) || delay < 1500) delay = 1500
  return Math.min(Math.round(delay * 2), 10000)
}

function shouldCarryAcrossTheme(persist, customized, pending) {
  return persist === true && (customized === true || pending === true)
}

function shouldRefreshTheme(changed, savedTheme, nextTheme, fileChanged) {
  return fileChanged === true || changed === true || String(savedTheme) !== String(nextTheme)
}

function canSetOpacity(awaitingThemeBaseline) {
  return awaitingThemeBaseline !== true
}

function finiteNumber(value) {
  if (value === undefined || value === null || value === "") return null
  var number = Number(value)
  return isFinite(number) ? number : null
}

function stripLuaComments(raw) {
  var source = String(raw || "")
  var result = ""
  var quote = ""
  var index = 0

  while (index < source.length) {
    var current = source.charAt(index)
    var next = source.charAt(index + 1)

    if (quote !== "") {
      result += current
      if (current === "\\" && index + 1 < source.length) {
        result += next
        index += 2
        continue
      }
      if (current === quote) quote = ""
      index += 1
      continue
    }

    if (current === '"' || current === "'") {
      quote = current
      result += current
      index += 1
      continue
    }

    if (current === "-" && next === "-") {
      if (source.substr(index + 2, 2) === "[[") {
        index += 4
        while (index < source.length && source.substr(index, 2) !== "]]") {
          if (source.charAt(index) === "\n") result += "\n"
          index += 1
        }
        index = Math.min(source.length, index + 2)
      } else {
        index += 2
        while (index < source.length && source.charAt(index) !== "\n") index += 1
      }
      continue
    }

    result += current
    index += 1
  }

  return result
}

function luaCallBodies(raw) {
  var source = stripLuaComments(raw)
  var pattern = /(?:^|[^A-Za-z0-9_])(?:o\.window|hl\.window_rule)\s*\(/g
  var bodies = []
  var match

  while ((match = pattern.exec(source)) !== null) {
    var open = pattern.lastIndex - 1
    var depth = 1
    var quote = ""
    var index = open + 1

    while (index < source.length && depth > 0) {
      var current = source.charAt(index)
      if (quote !== "") {
        if (current === "\\") {
          index += 2
          continue
        }
        if (current === quote) quote = ""
      } else if (current === '"' || current === "'") {
        quote = current
      } else if (current === "(") {
        depth += 1
      } else if (current === ")") {
        depth -= 1
      }
      index += 1
    }

    if (depth === 0) bodies.push(source.substring(open + 1, index - 1))
    pattern.lastIndex = Math.max(pattern.lastIndex, index)
  }

  return bodies
}

function parseOpacitySpec(raw) {
  var tokens = String(raw || "").trim().split(/\s+/)
  var opacity = finiteNumber(tokens[0])
  if (opacity === null) return null
  return {
    opacity: opacity,
    override: String(tokens[1] || "").toLowerCase() === "override"
  }
}

function defaultOpacityRule(raw) {
  var bodies = luaCallBodies(raw)
  var result = null

  for (var i = 0; i < bodies.length; i++) {
    var body = bodies[i]
    if (!/\btag\s*=\s*["']default-opacity["']/.test(body)) continue
    var opacity = body.match(/\bopacity\s*=\s*["']([^"']+)["']/)
    if (!opacity) continue
    var parsed = parseOpacitySpec(opacity[1])
    if (parsed !== null) result = parsed
  }

  return result
}

function lastNumericSetting(raw, name) {
  var source = stripLuaComments(raw)
  var pattern = new RegExp("\\b" + String(name) + "\\s*=\\s*([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?)", "g")
  var result = null
  var match
  while ((match = pattern.exec(source)) !== null) result = finiteNumber(match[1])
  return result
}

function parseThemeOpacitySettings(defaultLookRaw, defaultRulesRaw, themeRaw) {
  var activeOpacity = lastNumericSetting(defaultLookRaw, "active_opacity")
  if (activeOpacity === null) activeOpacity = 1

  var themeActiveOpacity = lastNumericSetting(themeRaw, "active_opacity")
  if (themeActiveOpacity !== null) activeOpacity = themeActiveOpacity

  var rule = defaultOpacityRule(defaultRulesRaw)
  var themeRule = defaultOpacityRule(themeRaw)
  if (themeRule !== null) rule = themeRule
  if (rule === null) return null

  var actual = rule.override ? rule.opacity : activeOpacity * rule.opacity
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
