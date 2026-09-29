local M = {}

local function disable_rule(rule)
  if rule then
    pcall(function()
      rule:set_enabled(false)
    end)
  end
end

local function clear_legacy_state()
  if _G.omapaque_subscription then
    pcall(function()
      _G.omapaque_subscription:remove()
    end)
  end
  _G.omapaque_subscription = nil
  _G.omapaque_apply_window = nil
  _G.omapaque_opacity = nil
end

local function opacity_key(value)
  return string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
end

function M.apply(value)
  local opacity = math.max(0.01, math.min(1, tonumber(value) or 1))
  local key = opacity_key(opacity)

  clear_legacy_state()
  disable_rule(_G.omapaque_rule)

  _G.omapaque_rules = _G.omapaque_rules or {}
  local rule = _G.omapaque_rules[key]
  if rule then
    rule:set_enabled(true)
  else
    _G.omapaque_rule_serial = (_G.omapaque_rule_serial or 0) + 1
    local exact = key .. " override " .. key .. " override " .. key .. " override"
    rule = hl.window_rule({
      name = "omapaque-opacity-" .. key .. "-" .. _G.omapaque_rule_serial,
      match = { class = ".*" },
      opacity = exact,
    })
    _G.omapaque_rules[key] = rule
  end

  _G.omapaque_rule = rule
end

function M.cleanup()
  disable_rule(_G.omapaque_rule)
  _G.omapaque_rule = nil
  _G.omapaque_rules = nil
  clear_legacy_state()
end

return M
