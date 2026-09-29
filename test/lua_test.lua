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

plugin.apply(1)
assert(#created == 1, "apply should create one rule")
assert(created[1].spec.opacity == "1 override 1 override 1 override", "100% should be exact")

plugin.apply(0.75)
assert(created[1].enabled == false, "changing opacity should disable the old rule")
assert(#created == 2, "a new opacity should create another rule")
assert(created[2].spec.opacity == "0.75 override 0.75 override 0.75 override", "75% should be exact")

plugin.apply(1)
assert(#created == 2, "a previous opacity should reuse its rule")
assert(created[1].enabled == true, "the reused rule should be enabled")
assert(created[2].enabled == false, "the replaced rule should be disabled")

plugin.cleanup()
assert(created[1].enabled == false, "cleanup should disable the active rule")
assert(_G.omapaque_rule == nil, "cleanup should clear the active rule")
assert(_G.omapaque_rules == nil, "cleanup should discard cached rule handles")

plugin.apply(1)
assert(#created == 3, "apply after cleanup should create a fresh rule handle")
assert(created[3].spec.name ~= created[1].spec.name, "fresh rules should have unique names")

-- 1% floor
plugin.apply(0.01)
assert(_G.omapaque_rule.spec.opacity == "0.01 override 0.01 override 0.01 override", "1% should be exact")
plugin.apply(0)
assert(_G.omapaque_rule.spec.opacity == "0.01 override 0.01 override 0.01 override", "below 1% clamps to 1%")
plugin.apply(0.25)
assert(_G.omapaque_rule.spec.opacity == "0.25 override 0.25 override 0.25 override", "25% should be exact")
plugin.cleanup()

print("Lua lifecycle tests passed")
