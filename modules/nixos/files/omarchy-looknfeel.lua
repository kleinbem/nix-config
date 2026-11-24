-- Managed declaratively by nix-config (modules/nixos/desktop.nix).
-- Prevents floating windows from losing their titlebars above the top bar
-- (e.g. when moving from a taller logical monitor to a scaled monitor, or
-- when dragging a window too far up).
-- tracking: omacom/omarchy#20029

-- Magnetically snap dragged floating windows to monitor edges and the top bar.
hl.config({
  general = {
    snap = {
      enabled = true,
      window_gap = 10,
      monitor_gap = 10,
      respect_gaps = true,
    },
  },
})

local WORKSPACE_TAG = "omarchy-floating-workspace"

local function has_tag(window, name)
  for _, tag in ipairs(window.tags or {}) do
    if tag == name or tag == name .. "*" then
      return true
    end
  end
  return false
end

local function titlebar_height_for(window)
  if not has_tag(window, WORKSPACE_TAG) then
    return 0
  end
  return tonumber(hl.get_config("plugin.hyprbars.bar_height")) or 30
end

local function clamp_window(window)
  if not window or not window.mapped or window.hidden or not window.floating then
    return
  end
  if (window.fullscreen or 0) ~= 0 then
    return
  end

  local ws_id = window.workspace and tonumber(window.workspace.id)
  if not ws_id or ws_id < 1 then
    return
  end

  local monitor = window.monitor
  if not monitor or not monitor.width or not monitor.scale or monitor.scale <= 0 then
    return
  end

  local mon_w, mon_h = monitor.width, monitor.height
  if (monitor.transform or 0) % 2 == 1 then
    mon_w, mon_h = mon_h, mon_w
  end
  mon_w = math.floor(mon_w / monitor.scale)
  mon_h = math.floor(mon_h / monitor.scale)

  local mon_x = monitor.x or 0
  local mon_y = monitor.y or 0
  local reserved = monitor.reserved or {}
  local res_left = reserved.left or 0
  local res_right = reserved.right or 0
  local res_top = reserved.top or 0
  local res_bottom = reserved.bottom or 0

  local bar_h = titlebar_height_for(window)
  local min_x = mon_x + res_left
  local min_y = mon_y + res_top + bar_h
  local max_w = math.max(200, mon_w - res_left - res_right)
  local max_h = math.max(150, mon_h - res_top - res_bottom - bar_h)

  local at = window.at
  local sz = window.size
  if not at or not sz then
    return
  end

  local wx = at.x or at[1]
  local wy = at.y or at[2]
  local ww = sz.x or sz.w or sz[1]
  local wh = sz.y or sz.h or sz[2]
  if not wx or not wy or not ww or not wh then
    return
  end

  local new_w = math.min(ww, max_w)
  local new_h = math.min(wh, max_h)
  if new_w ~= ww or new_h ~= wh then
    hl.dispatch(hl.dsp.window.resize({
      x = new_w,
      y = new_h,
      relative = false,
      window = window,
    }))
  end

  local max_y = mon_y + mon_h - res_bottom - 32
  local new_y = math.max(min_y, math.min(wy, max_y))
  local new_x = math.max(min_x - new_w + 64, math.min(wx, mon_x + mon_w - res_right - 64))
  if new_x ~= wx or new_y ~= wy then
    hl.dispatch(hl.dsp.window.move({
      x = new_x,
      y = new_y,
      relative = false,
      window = window,
    }))
  end
end

local function clamp_by_address(address)
  if not address then
    return
  end
  for _, win in ipairs(hl.get_windows()) do
    if win.address == address then
      clamp_window(win)
      return
    end
  end
end

local function clamp_all()
  for _, win in ipairs(hl.get_windows()) do
    clamp_window(win)
  end
end

local function schedule_window(window, delay_ms)
  local addr = window and window.address
  if not addr then
    return
  end
  hl.timer(function()
    clamp_by_address(addr)
  end, { type = "oneshot", timeout = delay_ms or 50 })
end

local function schedule_all(delay_ms)
  hl.timer(clamp_all, { type = "oneshot", timeout = delay_ms or 100 })
end

hl.on("window.open", function(window)
  schedule_window(window, 50)
end)

hl.on("window.move_to_workspace", function(window)
  schedule_window(window, 50)
end)

hl.on("window.fullscreen", function(window)
  schedule_window(window, 50)
end)

-- Raise maximized/fullscreen windows above sibling floating windows on focus,
-- and raise floating overlays cleanly when focusing them over fullscreen.
-- tracking: omacom/omarchy#16404
local restacking = false
local function restack_fullscreen_siblings(window)
  if restacking or not window or not window.workspace then
    return
  end
  if not has_tag(window, WORKSPACE_TAG) then
    return
  end

  local ws_id = tonumber(window.workspace.id)
  if not ws_id or ws_id < 1 then
    return
  end

  local windows = hl.get_workspace_windows(tostring(ws_id))
  restacking = true
  if (window.fullscreen or 0) > 0 then
    for i = #windows, 1, -1 do
      local other = windows[i]
      if other.address ~= window.address then
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = other }))
      end
    end
  elseif window.floating and not window.pinned then
    for _, other in ipairs(windows) do
      if (other.fullscreen or 0) > 0 then
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
        break
      end
    end
  end

  -- Restacking replays the pointer, which can focus a sibling underneath it.
  local active = hl.get_active_window()
  if not active or active.address ~= window.address then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
  end
  restacking = false
end

hl.on("window.active", function(window)
  restack_fullscreen_siblings(window)
  schedule_window(window, 50)
end)

hl.on("workspace.move_to_monitor", function()
  schedule_all(100)
end)

hl.on("monitor.layout_changed", function()
  schedule_all(100)
end)

hl.on("monitor.added", function()
  schedule_all(100)
end)

hl.on("monitor.removed", function()
  schedule_all(100)
end)

hl.on("config.reloaded", function()
  schedule_all(100)
end)
