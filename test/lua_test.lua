local created = {}

hl = {
  window_rule = function(spec)
    local rule = {
      enabled = true,
      spec = spec,
    }
    function rule:set_enabled(enabled)
      self.enabled = enabled
    end
    table.insert(created, rule)
    return rule
  end,
}

local plugin = dofile("Omapaque.lua")

local function group() return _G.omapaque_rule end
local function all_enabled(entry, enabled)
  for _, rule in ipairs(entry.rules) do
    if rule.enabled ~= enabled then return false end
  end
  return true
end

-- Unfocused-only: one rule per Omarchy opacity target.
plugin.apply(0.25, 0.985, 1)
local first = group()
assert(#created == 3, "apply should create one rule per target")
assert(first.rules[1].spec.match.tag == "default-opacity", "first rule targets default-opacity windows")
assert(first.rules[1].spec.opacity == "0.985 override 0.25 override 1 override",
  "focused keeps theme active, unfocused gets the slider value")
assert(first.rules[2].spec.match.tag == "chromium-based-browser", "chromium browsers are targeted")
assert(first.rules[2].spec.opacity == "1 override 0.25 override 1 override", "browsers stay solid when focused")
assert(first.rules[3].spec.match.tag == "firefox-based-browser", "firefox browsers are targeted")
for _, rule in ipairs(created) do
  assert(rule.spec.match.class == nil, "no catch-all class rule (media/PiP stay untouched)")
  assert(not rule.spec.name:find("[|]"), "rule names must not contain '|'")
end

plugin.apply(0.5, 0.985, 1)
assert(all_enabled(first, false), "changing opacity disables the old group")
assert(#created == 6, "a new value creates a new group")

plugin.apply(0.25, 0.985, 1)
assert(#created == 6, "a previous value reuses its group")
assert(all_enabled(first, true), "the reused group is enabled")

plugin.apply(0.01, 0.985, 1)
assert(group().rules[1].spec.opacity == "0.985 override 0.01 override 1 override", "1% floor is exact")
plugin.apply(0, 0.985, 1)
assert(group().rules[1].spec.opacity == "0.985 override 0.01 override 1 override", "below 1% clamps to 1%")

plugin.apply(1)
assert(group().rules[1].spec.opacity == "0.985 override 1 override 1 override",
  "missing theme values fall back to Omarchy defaults")

plugin.cleanup()
assert(_G.omapaque_rule == nil, "cleanup should clear the active group")
assert(_G.omapaque_rules == nil, "cleanup should discard cached rule handles")
for _, rule in ipairs(created) do
  assert(rule.enabled == false, "cleanup leaves no rule enabled")
end

-- Focused slider + browser values (5-argument form).
plugin.apply(0.25, 0.7, 1, 0.7, 0.25)
assert(group().rules[1].spec.opacity == "0.7 override 0.25 override 1 override", "focused slider sets focused opacity")
assert(group().rules[2].spec.opacity == "0.7 override 0.25 override 1 override", "browsers follow a moved focused slider")
plugin.apply(0.96, 0.7, 1, 0.7, 0.985)
assert(group().rules[1].spec.opacity == "0.7 override 0.96 override 1 override", "unfocused at theme default")
assert(group().rules[2].spec.opacity == "0.7 override 0.985 override 1 override", "browsers keep Omarchy's unfocused 98.5%")
plugin.apply(0.25, 0.985, 1, 1, 0.25)
assert(group().rules[2].spec.opacity == "1 override 0.25 override 1 override", "browsers keep 100% focused at theme default")
plugin.cleanup()

local before = #created
plugin.apply(0.25, 0.985, 1)
assert(#created == before + 3, "apply after cleanup creates fresh rules")
assert(created[before + 1].spec.name ~= created[1].spec.name, "fresh rules have unique names")

print("Lua lifecycle tests passed")
