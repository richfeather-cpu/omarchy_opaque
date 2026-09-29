local M = {}

-- apply() sets separate values for focused and unfocused windows. Hyprland
-- evaluates active vs inactive per window, so this follows focus. Fullscreen
-- windows, and any slider that has not been moved, keep the theme's values,
-- which the panel reads from windows.lua / the theme and passes in.
--
-- Only windows that Omarchy itself makes translucent are touched: the
-- `default-opacity` tag plus the browser tags (browsers opt out of
-- default-opacity but still use "1.0 0.985"). Apps Omarchy keeps solid
-- (video, PiP, games, VMs, webcam overlay, ...) are left alone.
--
-- Browsers get separate values, so they keep Omarchy's "1.0 0.985" until the
-- matching slider is moved (the panel computes those and passes them in).
local TARGETS = {
  { tag = "default-opacity", browser = false },
  { tag = "chromium-based-browser", browser = true },
  { tag = "firefox-based-browser", browser = true },
}

local function clamp(value, low, fallback)
  return math.max(low, math.min(1, tonumber(value) or fallback))
end

local function set_enabled(entry, enabled)
  if not entry then return end
  local rules = entry.omapaque_group and entry.rules or { entry }
  for _, rule in ipairs(rules) do
    pcall(function()
      rule:set_enabled(enabled)
    end)
  end
end

local function disable_rule(entry)
  set_enabled(entry, false)
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

function M.spec(active, inactive, fullscreen)
  return opacity_key(active) .. " override " .. opacity_key(inactive) .. " override "
    .. opacity_key(fullscreen) .. " override"
end

-- apply(inactive [, active [, fullscreen [, browser_active [, browser_inactive]]]])
function M.apply(value, active, fullscreen, browser_active, browser_inactive)
  local inactive = clamp(value, 0.01, 1)
  local theme_active = clamp(active, 0.01, 0.985)
  local theme_fullscreen = clamp(fullscreen, 0.01, 1)
  local b_active = clamp(browser_active, 0.01, 1)
  local b_inactive = clamp(browser_inactive, 0.01, inactive)
  local key = opacity_key(inactive) .. "_" .. opacity_key(theme_active) .. "_" .. opacity_key(theme_fullscreen)
    .. "_" .. opacity_key(b_active) .. "_" .. opacity_key(b_inactive)

  clear_legacy_state()
  disable_rule(_G.omapaque_rule)

  _G.omapaque_rules = _G.omapaque_rules or {}
  local entry = _G.omapaque_rules[key]
  if entry then
    set_enabled(entry, true)
  else
    _G.omapaque_rule_serial = (_G.omapaque_rule_serial or 0) + 1
    entry = { omapaque_group = true, rules = {} }
    for _, target in ipairs(TARGETS) do
      local focused = target.browser and b_active or theme_active
      local unfocused = target.browser and b_inactive or inactive
      table.insert(entry.rules, hl.window_rule({
        name = "omapaque-unfocused-" .. target.tag .. "-" .. key .. "-" .. _G.omapaque_rule_serial,
        match = { tag = target.tag },
        opacity = M.spec(focused, unfocused, theme_fullscreen),
      }))
    end
    _G.omapaque_rules[key] = entry
  end

  _G.omapaque_rule = entry
end

function M.cleanup()
  disable_rule(_G.omapaque_rule)
  _G.omapaque_rule = nil
  _G.omapaque_rules = nil
  clear_legacy_state()
end

return M
