-- omarchy-workspaces: zone-aware, monitor-pinned workspaces.
-- Workspace id = (slot-1)*20 + (monitor index, left-to-right, 0-based)*10 + local (1-10).
-- Defines functions only -- call ws.pin_zones({"DP-1","HDMI-A-1"}, 10) from monitors.lua and ws.bind_relative_workspace_keys() from bindings.lua, via dofile(".../workspaces.lua").

local M = {}

function M.sorted_monitors()
  local monitors = hl.get_monitors()
  table.sort(monitors, function(a, b) return a.x < b.x end)
  return monitors
end

function M.zone_base(workspace_id)
  return math.floor((workspace_id - 1) / 20) * 20
end

function M.focused_monitor_offset()
  local active = hl.get_active_monitor()
  if not active then return 0 end
  for i, m in ipairs(M.sorted_monitors()) do
    if m.name == active.name then return (i - 1) * 10 end
  end
  return 0
end

function M.focused_zone_base()
  local active = hl.get_active_monitor()
  if not active or not active.active_workspace then return 0 end
  return M.zone_base(active.active_workspace.id)
end

-- 1-10 position of the focused monitor's active workspace within its own block.
function M.focused_local_workspace()
  local active = hl.get_active_monitor()
  if not active or not active.active_workspace then return 1 end
  return ((active.active_workspace.id - 1) % 10) + 1
end

-- Pins workspaces 1..(cap*20) across monitor_names (left-to-right); call once at config load with your own monitor names.
function M.pin_zones(monitor_names, cap)
  cap = cap or 10
  for slot = 1, cap do
    for m_index, name in ipairs(monitor_names) do
      for l = 1, 10 do
        local id = (slot - 1) * 20 + (m_index - 1) * 10 + l
        hl.workspace_rule({ workspace = tostring(id), monitor = name, persistent = true })
      end
    end
  end
end

-- Binds SUPER+N (+SHIFT, +SHIFT+ALT) so N means "workspace N in the current zone, on the monitor you're on", resolved at press time.
function M.bind_relative_workspace_keys()
  for workspace = 1, 10 do
    local key = "code:" .. tostring(workspace + 9)

    hl.unbind("SUPER + " .. key)
    hl.unbind("SUPER + SHIFT + " .. key)
    hl.unbind("SUPER + SHIFT + ALT + " .. key)

    local function target()
      return tostring(workspace + M.focused_zone_base() + M.focused_monitor_offset())
    end

    o.bind("SUPER + " .. key, "Switch to workspace " .. workspace .. " on this monitor", function()
      hl.dispatch(hl.dsp.focus({ workspace = target() }))
    end)
    o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace .. " on this monitor", function()
      hl.dispatch(hl.dsp.window.move({ workspace = target() }))
    end)
    o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace .. " on this monitor", function()
      hl.dispatch(hl.dsp.window.move({ workspace = target(), follow = false }))
    end)
  end
end

-- Stock SUPER+TAB/SHIFT+TAB cycle "e+1"/"e-1", the next/previous EXISTING workspace globally -- with every zone block persistent, that now spans all monitors and all zones. Rebind to wrap within the current zone's block on the current monitor only.
function M.bind_relative_tab_keys()
  hl.unbind("SUPER + TAB")
  hl.unbind("SUPER + SHIFT + TAB")

  local function base()
    return M.focused_zone_base() + M.focused_monitor_offset()
  end

  o.bind("SUPER + TAB", "Next workspace on this monitor", function()
    local next_local = (M.focused_local_workspace() % 10) + 1
    hl.dispatch(hl.dsp.focus({ workspace = tostring(base() + next_local) }))
  end)
  o.bind("SUPER + SHIFT + TAB", "Previous workspace on this monitor", function()
    local prev_local = ((M.focused_local_workspace() - 2 + 10) % 10) + 1
    hl.dispatch(hl.dsp.focus({ workspace = tostring(base() + prev_local) }))
  end)
end

return M
