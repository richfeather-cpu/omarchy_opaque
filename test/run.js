const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Logic.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
const context = { JSON, Math, Number, String, isFinite, parseFloat }
vm.createContext(context)
vm.runInContext(source, context)

function equal(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`)
  }
}

equal(context.clampPercent(20), 50, "lower clamp")
equal(context.clampPercent(104), 100, "upper clamp")
equal(context.clampPercent(87.6), 87.5, "half-percent rounding")
equal(context.formatPercent(98.5), "98.5%", "decimal percentage")
equal(context.formatPercent(100), "100%", "whole percentage")
equal(context.nextRetryDelay(1500), 3000, "first retry backoff")
equal(context.nextRetryDelay(6000), 10000, "retry backoff cap")
equal(context.nextRetryDelay(10000), 10000, "capped retry backoff")
equal(context.nextRetryDelay("invalid"), 3000, "invalid retry delay fallback")
equal(context.shouldCarryAcrossTheme(false, true, false), false, "theme persistence defaults off")
equal(context.shouldCarryAcrossTheme(true, true, false), true, "custom opacity carries across themes")
equal(context.shouldCarryAcrossTheme(true, false, true), true, "repeated theme event keeps pending opacity")
equal(context.shouldCarryAcrossTheme(true, false, false), false, "theme default does not become custom")

equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":1}\n' +
    '{"opacity":0.985,"opacity_override":false}\n'
  ),
  98.5,
  "multiplied theme opacity"
)
equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":0.8}\n' +
    '{"opacity":0.92,"opacity_override":true}\n'
  ),
  92,
  "overridden theme opacity"
)
equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":0.8}\n'
  ),
  null,
  "missing live window opacity"
)
equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":0.8}\n' +
    '{"opacity":null,"opacity_override":false}\n'
  ),
  null,
  "null live window opacity"
)
equal(context.parseThemeOpacity("not json"), null, "invalid option output")
equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":1}\n' +
    '{"opacity":1,"opacity_override":true}\n' +
    '{"opacity":0.985,"opacity_override":false}\n' +
    '{"opacity":1,"opacity_override":true}\n'
  ),
  98.5,
  "app-specific opaque windows do not replace the theme value"
)
equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":1}\n' +
    '{"opacity":0.94,"opacity_override":true}\n' +
    '{"opacity":1,"opacity_override":true}\n'
  ),
  94,
  "override-only themes use the lowest matching value"
)

const themeProbe = context.themeOpacityProbe()
if (!themeProbe.includes("hyprctl clients -j"))
  throw new Error("theme probe must inspect all live clients")
if (!themeProbe.includes("^default-opacity\\\\*?$"))
  throw new Error("theme probe must match Hyprland's dynamic tag suffix")
if (!themeProbe.includes("^0x[0-9A-Fa-f]+$"))
  throw new Error("theme probe must validate client addresses")

const opaque = context.renderLuaCall("/tmp/Omapaque.lua", "apply", 100)
if (!opaque.includes('loadfile("/tmp/Omapaque.lua")')) throw new Error("Lua module path must be quoted")
if (!opaque.includes("plugin.apply(1)")) throw new Error("100% must call Lua with opacity 1")

const cleanup = context.renderLuaCall("/tmp/Omapaque.lua", "cleanup")
if (!cleanup.includes("plugin.cleanup()")) throw new Error("cleanup must call the Lua module")

const unloadCleanup = context.renderUnloadCleanup()
if (!unloadCleanup.includes("listPlugins")) throw new Error("unload cleanup must check plugin state")
if (!unloadCleanup.includes(".enabled == true")) throw new Error("enabled plugins must keep their override")
if (!unloadCleanup.includes("flock -n")) throw new Error("parallel unloads must share one cleanup")
if (!unloadCleanup.includes("hyprctl reload")) throw new Error("disabled plugins must restore theme opacity")

console.log("Logic tests passed")
