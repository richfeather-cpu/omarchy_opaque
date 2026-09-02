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
equal(context.shouldRefreshTheme(true, "old", "new", false), true, "changed theme refreshes")
equal(context.shouldRefreshTheme(false, "same", "same", true), true, "reapplied theme refreshes")
equal(context.shouldRefreshTheme(false, "old", "new", false), true, "stale saved theme refreshes")
equal(context.shouldRefreshTheme(false, "same", "same", false), false, "unchanged theme stays idle")
equal(context.canSetOpacity(false), true, "input is enabled after reading the theme")
equal(context.canSetOpacity(true), false, "input is disabled while reading the theme")

equal(
  context.parseThemeOpacitySettings(
    "",
    'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
    ""
  ),
  98.5,
  "default Omarchy opacity"
)
equal(
  context.parseThemeOpacitySettings(
    "hl.config({ decoration = { active_opacity = 0.8 } })",
    'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
    ""
  ),
  79,
  "default active opacity multiplies the default rule"
)
equal(
  context.parseThemeOpacitySettings(
    "hl.config({ decoration = { active_opacity = 0.8 } })",
    'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
    "hl.config({ decoration = { active_opacity = 0.94 } })"
  ),
  92.5,
  "theme active opacity replaces the Omarchy default"
)
equal(
  context.parseThemeOpacitySettings(
    "hl.config({ decoration = { active_opacity = 0.8 } })",
    'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
    'hl.window_rule({ match = { tag = "default-opacity" }, opacity = "0.9 override 0.84 override" })'
  ),
  90,
  "theme override rule is an absolute opacity"
)
equal(
  context.parseThemeOpacitySettings(
    "",
    'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
    'o.window("com.mitchellh.ghostty", { opacity = "0.72 override" })'
  ),
  98.5,
  "app-specific theme rules do not replace the default rule"
)
equal(
  context.parseThemeOpacitySettings(
    "-- active_opacity = 0.5\nactive_opacity = 1",
    '-- o.window({ tag = "default-opacity" }, { opacity = "0.5 override" })\n' +
      "o.window({ tag = 'default-opacity' }, { opacity = '0.985 0.96' })",
    "--[[\nactive_opacity = 0.6\n]]"
  ),
  98.5,
  "commented settings are ignored"
)
equal(
  context.parseThemeOpacitySettings(
    "",
    'o.window({ tag = "default-opacity" }, { opacity = "0.985" })',
    'o.window({ tag = "default-opacity" }, { opacity = "0.8" })'
  ),
  80,
  "the last theme-owned default rule wins"
)
equal(
  context.parseThemeOpacitySettings("active_opacity = 0.8", "", ""),
  null,
  "missing default-opacity rule is reported"
)

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

const panel = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
if (!panel.includes("root.cancelPendingApply()"))
  throw new Error("theme reads must cancel stale opacity applies")
if (!panel.includes("if (evalProc.running) evalProc.running = false"))
  throw new Error("canceling an apply must stop the running process")
if (panel.includes("hyprctl clients"))
  throw new Error("theme opacity must not depend on live windows")
if (!panel.includes("root.readThemeName(changed)"))
  throw new Error("same-theme file changes must force a baseline refresh")
if (!panel.includes("if (!Logic.canSetOpacity(root.awaitingThemeBaseline)) return"))
  throw new Error("opacity input must wait for the theme baseline")

const systemLook = "/usr/share/omarchy/default/hypr/looknfeel.lua"
const systemRules = "/usr/share/omarchy/default/hypr/windows.lua"
const currentTheme = path.join(process.env.HOME || "", ".local/state/omarchy/current/theme/hyprland.lua")
if (fs.existsSync(systemLook) && fs.existsSync(systemRules)) {
  const actual = context.parseThemeOpacitySettings(
    fs.readFileSync(systemLook, "utf8"),
    fs.readFileSync(systemRules, "utf8"),
    fs.existsSync(currentTheme) ? fs.readFileSync(currentTheme, "utf8") : ""
  )
  if (actual === null) throw new Error("installed Omarchy settings must produce a theme opacity")
}

console.log("Logic tests passed")
