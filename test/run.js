const fs = require("fs")
const vm = require("vm")

const path = require("path")

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
equal(context.clampPercent(87.6), 88, "whole-percent rounding")

const parsed = context.parseOpacityOptions(
  '{"option":"decoration:active_opacity","float":0.98}\n' +
  '{"option":"decoration:inactive_opacity","float":0.91}\n'
)
equal(parsed.active, 0.98, "active opacity")
equal(parsed.inactive, 0.91, "inactive opacity")
equal(context.parseOpacityOptions("not json"), null, "invalid option output")

equal(context.scaledOpacity(0.98, 80), 0.784, "theme-relative active opacity")
equal(context.scaledOpacity(0.91, 80), 0.728, "theme-relative inactive opacity")
equal(
  context.renderOpacityConfig(0.98, 0.91, 80),
  "hl.config({ decoration = { active_opacity = 0.784, inactive_opacity = 0.728, }, })",
  "Hyprland Lua"
)

console.log("Logic tests passed")
