const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Logic.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
const context = { JSON, Math, Number, String, isFinite, parseFloat }
vm.createContext(context)
vm.runInContext(source, context)

function panel_src() {
  return fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
}

function equal(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`)
  }
}

equal(context.clampPercent(20), 20, "20% is allowed")
equal(context.clampPercent(0), 1, "lower clamp")
equal(context.clampPercent(0.2), 1, "sub-1% clamps to 1%")
equal(context.wheelStep(10, -1), 1, "fine step at the low end")
equal(context.wheelStep(50, -1), 2.5, "coarse step above 10%")
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

// Unfocused-only theme parsing and Lua call args.
const unfocused = context.parseThemeUnfocusedSettings(
  "",
  'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
  ""
)
equal(unfocused.active, 98.5, "theme focused opacity")
equal(unfocused.inactive, 96, "theme unfocused opacity")
equal(unfocused.fullscreen, 100, "two-value rule leaves fullscreen solid")
const themed = context.parseThemeUnfocusedSettings(
  "hl.config({ decoration = { inactive_opacity = 0.5 } })",
  'o.window({ tag = "default-opacity" }, { opacity = "0.985 0.96" })',
  'hl.window_rule({ match = { tag = "default-opacity" }, opacity = "0.9 override 0.8 0.95 override" })'
)
equal(themed.active, 90, "theme override active is absolute")
equal(themed.inactive, 40, "non-override inactive is multiplied by inactive_opacity")
equal(themed.fullscreen, 95, "theme fullscreen value is read")
equal(context.parseThemeUnfocusedSettings("", "", ""), null, "missing rule is reported")
const unfocusedCall = context.renderLuaCall("/tmp/Omapaque.lua", "apply", 25, 98.5, 100)
if (!unfocusedCall.includes("plugin.apply(0.25, 0.985, 1)"))
  throw new Error("apply must pass unfocused, focused and fullscreen values: " + unfocusedCall)

// Focused slider argument building.
const defaults = context.applyValues(false, 96, 96, false, 98.5, 98.5, 100)
equal(defaults.join(","), "96,98.5,100,100,98.5", "untouched sliders keep theme and browser defaults")
const both = context.applyValues(true, 25, 96, true, 70, 98.5, 100)
equal(both.join(","), "25,70,100,70,25", "moved sliders apply to normal windows and browsers")
const focusedOnly = context.applyValues(false, 96, 96, true, 70, 98.5, 100)
equal(focusedOnly.join(","), "96,70,100,70,98.5", "focused slider alone leaves unfocused at theme values")
const applyCall = context.renderLuaApply("/tmp/Omapaque.lua", both)
if (!applyCall.includes("plugin.apply(0.25, 0.7, 1, 0.7, 0.25)"))
  throw new Error("renderLuaApply must pass all five values: " + applyCall)
if (!panel_src().includes("function setFocusedOpacity(")) throw new Error("panel must expose the focused slider")
if (!panel_src().includes("root.themeReadPending = true"))
  throw new Error("startup must wait for host settings before reading saved state")
if (!panel_src().includes('focusSection === "focused"')) throw new Error("focused slider must be keyboard reachable")

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
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
const pluginId = "io.github.richfeather-cpu.omarchy-opaque"
equal(manifest.id, pluginId, "manifest plugin id")
equal(manifest.name, "Omarchy Opaque", "manifest display name")
equal(manifest.barWidget.displayName, "Omarchy Opaque", "bar widget display name")
if (!panel.includes(`moduleName: "${pluginId}"`)) throw new Error("panel moduleName must match the plugin id")
if (!panel.includes(`ipcTarget: "${pluginId}"`)) throw new Error("panel ipc target must match the plugin id")
if (panel.includes("tomrplummer.omapaque") || manifest.id === "tomrplummer.omapaque")
  throw new Error("plugin must not keep the original plugin id")
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
