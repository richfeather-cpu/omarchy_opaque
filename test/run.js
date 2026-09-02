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

equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":1}\n' +
    '{"opacity":0.985}\n' +
    '{"opacity_override":false}\n'
  ),
  98.5,
  "multiplied theme opacity"
)
equal(
  context.parseThemeOpacity(
    '{"option":"decoration:active_opacity","float":0.8}\n' +
    '{"opacity":0.92}\n' +
    '{"opacity_override":true}\n'
  ),
  92,
  "overridden theme opacity"
)
equal(context.parseThemeOpacity("not json"), null, "invalid option output")

const opaque = context.renderAbsoluteOpacity(100)
if (!opaque.includes("_G.omapaque_opacity = 1")) throw new Error("100% must set exact opacity 1")
if (!opaque.includes('prop = "opacity_override", value = "true"'))
  throw new Error("absolute opacity must enable the active override")
if (!opaque.includes('prop = "opacity_inactive_override", value = "true"'))
  throw new Error("absolute opacity must enable the inactive override")
if (!opaque.includes("hl.get_windows()")) throw new Error("opacity must apply to every window")
if (!opaque.includes('hl.on("window.open"')) throw new Error("new windows must inherit the opacity")

const cleanup = context.renderCleanup()
if (!cleanup.includes("omapaque_subscription:remove()")) throw new Error("cleanup must remove the window listener")

console.log("Logic tests passed")
