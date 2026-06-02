-- @description FX Randomizer - Multi-parameter randomization tool
-- @version 1.0.0
-- @author VibeCoding Team
-- @about
--   Randomize multiple FX parameters across tracks with various algorithms,
--   snapshots, history, and presets. Requires ReaImGui extension.
-- @changelog
--   Initial release

--------------------------------------------------------------------------------
-- 0. DEPENDENCY CHECK
--------------------------------------------------------------------------------
local app_vrs = tonumber(reaper.GetAppVersion():match('[%d%.]+'))
if not app_vrs or app_vrs < 6 then
  return reaper.MB('This script requires REAPER 6.0+', 'FX Randomizer', 0)
end

if not reaper.ImGui_GetBuiltinPath then
  return reaper.MB('This script requires the ReaImGui extension.\nPlease install it via ReaPack or the REAPER extension manager.', 'FX Randomizer', 0)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

--------------------------------------------------------------------------------
-- 1. CONFIGURATION & STATE
--------------------------------------------------------------------------------
local SCRIPT_NAME = 'FX Randomizer'
local SCRIPT_VERSION = '1.0.0'
local EXT_STATE_KEY = 'VibeCoding_FXRandomizer'

local CONFIG = {
  -- Window
  win_x = 100,
  win_y = 100,
  win_w = 900,
  win_h = 600,
  
  -- Randomization
  default_algo = 'uniform',
  default_min = 0.0,
  default_max = 1.0,
  smooth_ms = 50,        -- parameter change interval to prevent pops
  
  -- UI
  show_filtered_only = false,
  filter_keywords = '',
  
  -- Behavior
  auto_seed = true,
  seed = 0,
}

local STATE = {
  -- Scan cache
  tracks = {},           -- {track_idx, track_name, ptr, fxs: {fx_idx, fx_name, params: {param_idx, param_name, current_val, min_val, max_val, is_toggle}}}
  
  -- Selection / Mapping
  mapped_params = {},    -- {uid, track_idx, fx_idx, param_idx, track_name, fx_name, param_name, algo, rand_min, rand_max, weight, exclude_ranges: {{min,max}}}
  
  -- Snapshots
  snapshots = {},        -- {id, name, values: {uid -> value}}
  current_snapshot = 0,  -- 0 = none, 1 = A, 2 = B
  
  -- History
  history = {},          -- stack of {uid -> prev_value}
  history_idx = 0,       -- current position in history
  
  -- Presets
  presets = {},          -- {name, mapped_params_config}
  
  -- UI State
  selected_track = 1,
  selected_fx = 1,
  rand_amount = 1.0,     -- global randomization amount (0-1)
  need_rescan = true,
  last_rand_time = 0,
  preset_input_name = '',
}

--------------------------------------------------------------------------------
-- 2. UTILITY FUNCTIONS
--------------------------------------------------------------------------------
local function msg(s)
  if not s then return end
  if type(s) == 'boolean' then s = s and 'true' or 'false' end
  if type(s) == 'table' then s = require('reaper').stringFromNative(s) or tostring(s) end
  reaper.ShowConsoleMsg(tostring(s) .. '\n')
end

local function clamp(val, min, max)
  if not min or not max then min, max = 0, 1 end
  return math.max(min, math.min(val, max))
end

local function deep_copy(orig)
  local copy
  if type(orig) == 'table' then
    copy = {}
    for k, v in next, orig, nil do
      copy[deep_copy(k)] = deep_copy(v)
    end
    setmetatable(copy, deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

local function uid(track_idx, fx_idx, param_idx)
  return string.format('%d:%d:%d', track_idx, fx_idx, param_idx)
end

local function parse_uid(uid_str)
  local t, f, p = uid_str:match('(%d+):(%d+):(%d+)')
  return tonumber(t), tonumber(f), tonumber(p)
end

--------------------------------------------------------------------------------
-- 3. EXT STATE PERSISTENCE
--------------------------------------------------------------------------------
local function ext_save()
  -- Save CONFIG
  for k, v in pairs(CONFIG) do
    if type(v) == 'number' or type(v) == 'string' or type(v) == 'boolean' then
      reaper.SetExtState(EXT_STATE_KEY, 'cfg_' .. k, tostring(v), true)
    end
  end
  
  -- Save snapshots
  local snap_count = #STATE.snapshots
  reaper.SetExtState(EXT_STATE_KEY, 'snap_count', tostring(snap_count), true)
  for i, snap in ipairs(STATE.snapshots) do
    reaper.SetExtState(EXT_STATE_KEY, 'snap_'..i..'_name', snap.name, true)
    local vals = {}
    for uid_str, val in pairs(snap.values) do
      vals[#vals+1] = uid_str .. '=' .. string.format('%.6f', val)
    end
    reaper.SetExtState(EXT_STATE_KEY, 'snap_'..i..'_vals', table.concat(vals, '|'), true)
  end
  
  -- Save presets
  local preset_count = #STATE.presets
  reaper.SetExtState(EXT_STATE_KEY, 'preset_count', tostring(preset_count), true)
  for i, preset in ipairs(STATE.presets) do
    reaper.SetExtState(EXT_STATE_KEY, 'preset_'..i..'_name', preset.name, true)
    -- Simplified: save just param uids and their configs
    local configs = {}
    for _, mp in ipairs(preset.mapped_params) do
      configs[#configs+1] = string.format('%s;%s;%.4f;%.4f', mp.uid, mp.algo or 'uniform', mp.rand_min or 0, mp.rand_max or 1)
    end
    reaper.SetExtState(EXT_STATE_KEY, 'preset_'..i..'_cfg', table.concat(configs, '|'), true)
  end
end

local function ext_load()
  -- Load CONFIG
  for k, v in pairs(CONFIG) do
    local key = 'cfg_' .. k
    if reaper.HasExtState(EXT_STATE_KEY, key) then
      local str = reaper.GetExtState(EXT_STATE_KEY, key)
      if type(v) == 'number' then
        CONFIG[k] = tonumber(str) or v
      elseif type(v) == 'boolean' then
        CONFIG[k] = str == 'true'
      else
        CONFIG[k] = str
      end
    end
  end
  
  -- Load snapshots
  local snap_count = tonumber(reaper.GetExtState(EXT_STATE_KEY, 'snap_count')) or 0
  for i = 1, snap_count do
    local name = reaper.GetExtState(EXT_STATE_KEY, 'snap_'..i..'_name')
    local vals_str = reaper.GetExtState(EXT_STATE_KEY, 'snap_'..i..'_vals')
    local values = {}
    if vals_str and vals_str ~= '' then
      for pair in vals_str:gmatch('([^|]+)') do
        local uid_str, val = pair:match('([^=]+)=(.+)')
        if uid_str and val then values[uid_str] = tonumber(val) end
      end
    end
    STATE.snapshots[i] = {id = i, name = name, values = values}
  end
  
  -- Load presets
  local preset_count = tonumber(reaper.GetExtState(EXT_STATE_KEY, 'preset_count')) or 0
  for i = 1, preset_count do
    local name = reaper.GetExtState(EXT_STATE_KEY, 'preset_'..i..'_name')
    local cfg_str = reaper.GetExtState(EXT_STATE_KEY, 'preset_'..i..'_cfg')
    local mapped_params = {}
    if cfg_str and cfg_str ~= '' then
      for item in cfg_str:gmatch('([^|]+)') do
        local uid_str, algo, rmin, rmax = item:match('([^;]+);([^;]+);([^;]+);([^;]+)')
        if uid_str then
          mapped_params[#mapped_params+1] = {
            uid = uid_str,
            algo = algo or 'uniform',
            rand_min = tonumber(rmin) or 0,
            rand_max = tonumber(rmax) or 1,
          }
        end
      end
    end
    STATE.presets[i] = {name = name, mapped_params = mapped_params}
  end
end

--------------------------------------------------------------------------------
-- 4. PARAMETER SCANNING
--------------------------------------------------------------------------------
local function scan_project()
  STATE.tracks = {}
  local track_count = reaper.CountTracks(0)
  
  -- Include Master Track as track 0
  local master = reaper.GetMasterTrack(0)
  if master then
    local _, name = reaper.GetTrackName(master)
    local track_data = {
      track_idx = 0,
      track_name = name or 'Master',
      ptr = master,
      fxs = {}
    }
    local fx_count = reaper.TrackFX_GetCount(master)
    for fx_idx = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(master, fx_idx)
      local param_count = reaper.TrackFX_GetNumParams(master, fx_idx)
      local fx_data = {
        fx_idx = fx_idx,
        fx_name = fx_name or ('FX ' .. fx_idx),
        params = {}
      }
      for param_idx = 0, param_count - 1 do
        local _, param_name = reaper.TrackFX_GetParamName(master, fx_idx, param_idx)
        local current_val = reaper.TrackFX_GetParamNormalized(master, fx_idx, param_idx)
        local _, min_val, max_val = reaper.TrackFX_GetParam(master, fx_idx, param_idx)
        local _, _, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(master, fx_idx, param_idx)
        fx_data.params[#fx_data.params+1] = {
          param_idx = param_idx,
          param_name = param_name or ('Param ' .. param_idx),
          current_val = current_val,
          min_val = min_val or 0,
          max_val = max_val or 1,
          is_toggle = istoggle or false,
        }
      end
      track_data.fxs[#track_data.fxs+1] = fx_data
    end
    STATE.tracks[#STATE.tracks+1] = track_data
  end
  
  -- Regular tracks
  for track_idx = 1, track_count do
    local tr = reaper.GetTrack(0, track_idx - 1)
    if not tr then goto next_track end
    local _, name = reaper.GetTrackName(tr)
    local track_data = {
      track_idx = track_idx,
      track_name = name or ('Track ' .. track_idx),
      ptr = tr,
      fxs = {}
    }
    
    local fx_count = reaper.TrackFX_GetCount(tr)
    for fx_idx = 0, fx_count - 1 do
      local _, fx_name = reaper.TrackFX_GetFXName(tr, fx_idx)
      local param_count = reaper.TrackFX_GetNumParams(tr, fx_idx)
      local fx_data = {
        fx_idx = fx_idx,
        fx_name = fx_name or ('FX ' .. fx_idx),
        params = {}
      }
      for param_idx = 0, param_count - 1 do
        local _, param_name = reaper.TrackFX_GetParamName(tr, fx_idx, param_idx)
        local current_val = reaper.TrackFX_GetParamNormalized(tr, fx_idx, param_idx)
        local _, min_val, max_val = reaper.TrackFX_GetParam(tr, fx_idx, param_idx)
        local _, _, _, _, istoggle = reaper.TrackFX_GetParameterStepSizes(tr, fx_idx, param_idx)
        fx_data.params[#fx_data.params+1] = {
          param_idx = param_idx,
          param_name = param_name or ('Param ' .. param_idx),
          current_val = current_val,
          min_val = min_val or 0,
          max_val = max_val or 1,
          is_toggle = istoggle or false,
        }
      end
      track_data.fxs[#track_data.fxs+1] = fx_data
    end
    
    STATE.tracks[#STATE.tracks+1] = track_data
    ::next_track::
  end
  
  STATE.need_rescan = false
end

--------------------------------------------------------------------------------
-- 5. RANDOM ALGORITHMS
--------------------------------------------------------------------------------
local ALGORITHMS = {
  uniform = {
    name = 'Uniform',
    func = function(min_val, max_val, _weight)
      return min_val + math.random() * (max_val - min_val)
    end
  },
  
  normal = {
    name = 'Normal',
    func = function(min_val, max_val, _weight)
      -- Box-Muller transform
      local u1 = math.random()
      local u2 = math.random()
      if u1 < 1e-10 then u1 = 1e-10 end
      local z0 = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
      -- Mean at center, stddev = (max-min)/6 (so 99.7% within range)
      local mean = (min_val + max_val) / 2
      local stddev = (max_val - min_val) / 6
      local val = mean + z0 * stddev
      return clamp(val, min_val, max_val)
    end
  },
  
  weighted = {
    name = 'Weighted',
    func = function(min_val, max_val, weight)
      -- weight: 0 = bias toward min, 1 = bias toward max, 0.5 = uniform-like
      weight = weight or 0.5
      local r = math.random()
      -- Power curve: r^power where power depends on weight
      local power
      if weight < 0.5 then
        power = 1 / (1 + (0.5 - weight) * 4)  -- > 1 when weight < 0.5
      else
        power = 1 + (weight - 0.5) * 4        -- < 1 when weight > 0.5
      end
      if weight < 0.5 then
        r = r ^ power
      else
        r = 1 - (1 - r) ^ (1 / power)
      end
      return min_val + r * (max_val - min_val)
    end
  },
  
  stepped = {
    name = 'Stepped',
    func = function(min_val, max_val, _weight)
      -- 10 discrete steps
      local steps = 10
      local step = math.floor(math.random() * steps)
      return min_val + (step / (steps - 1)) * (max_val - min_val)
    end
  },
}

-- Ordered list for UI consistency
local ALGO_KEYS = {'uniform', 'normal', 'weighted', 'stepped'}

--------------------------------------------------------------------------------
-- 6. PARAMETER MAPPING
--------------------------------------------------------------------------------
local function find_mapped_param(uid_str)
  for i, mp in ipairs(STATE.mapped_params) do
    if mp.uid == uid_str then return i, mp end
  end
  return nil, nil
end

local function add_param_to_map(track_idx, fx_idx, param_idx)
  local uid_str = uid(track_idx, fx_idx, param_idx)
  if find_mapped_param(uid_str) then return end  -- already mapped
  
  local track_data = nil
  for _, t in ipairs(STATE.tracks) do
    if t.track_idx == track_idx then track_data = t; break end
  end
  if not track_data then return end
  
  local fx_data = nil
  for _, f in ipairs(track_data.fxs) do
    if f.fx_idx == fx_idx then fx_data = f; break end
  end
  if not fx_data then return end
  
  local param_data = nil
  for _, p in ipairs(fx_data.params) do
    if p.param_idx == param_idx then param_data = p; break end
  end
  if not param_data then return end
  
  local mp = {
    uid = uid_str,
    track_idx = track_idx,
    fx_idx = fx_idx,
    param_idx = param_idx,
    track_name = track_data.track_name,
    fx_name = fx_data.fx_name,
    param_name = param_data.param_name,
    algo = CONFIG.default_algo,
    rand_min = CONFIG.default_min,
    rand_max = CONFIG.default_max,
    weight = 0.5,
    exclude_ranges = {},
    is_toggle = param_data.is_toggle,
  }
  STATE.mapped_params[#STATE.mapped_params+1] = mp
end

local function remove_param_from_map(uid_str)
  for i, mp in ipairs(STATE.mapped_params) do
    if mp.uid == uid_str then
      table.remove(STATE.mapped_params, i)
      return
    end
  end
end

local function clear_all_mapped_params()
  STATE.mapped_params = {}
end

--------------------------------------------------------------------------------
-- 7. RANDOMIZATION ENGINE
--------------------------------------------------------------------------------
local function do_randomize()
  if #STATE.mapped_params == 0 then return end
  
  -- Set seed
  if CONFIG.seed and CONFIG.seed ~= 0 then
    math.randomseed(CONFIG.seed)
  else
    math.randomseed(os.time())
  end
  
  -- Push undo block
  reaper.Undo_BeginBlock()
  
  -- Collect previous values for history
  local prev_values = {}
  
  for _, mp in ipairs(STATE.mapped_params) do
    local tr_idx, fx_idx, param_idx = parse_uid(mp.uid)
    local tr = nil
    if tr_idx == 0 then
      tr = reaper.GetMasterTrack(0)
    else
      tr = reaper.GetTrack(0, tr_idx - 1)
    end
    if not tr then goto next_param end
    
    -- Get current value for history
    prev_values[mp.uid] = reaper.TrackFX_GetParamNormalized(tr, fx_idx, param_idx)
    
    -- Determine new value
    local new_val
    if mp.is_toggle then
      new_val = math.random() < 0.5 and 0 or 1
    else
      local algo = ALGORITHMS[mp.algo] or ALGORITHMS.uniform
      new_val = algo.func(mp.rand_min, mp.rand_max, mp.weight)
      
      -- Apply global amount: blend between current and random
      local current_val = prev_values[mp.uid]
      new_val = current_val + (new_val - current_val) * STATE.rand_amount
      
      -- Check exclude ranges
      for _, range in ipairs(mp.exclude_ranges or {}) do
        if new_val >= range.min and new_val <= range.max then
          -- Push to nearest boundary
          local dist_to_min = math.abs(new_val - range.min)
          local dist_to_max = math.abs(new_val - range.max)
          if dist_to_min < dist_to_max then
            new_val = range.min - 0.001
          else
            new_val = range.max + 0.001
          end
        end
      end
    end
    
    new_val = clamp(new_val, 0, 1)
    reaper.TrackFX_SetParamNormalized(tr, fx_idx, param_idx, new_val)
    
    ::next_param::
  end
  
  reaper.Undo_EndBlock('FX Randomizer: Randomize parameters', -1)
  reaper.UpdateArrange()
  
  -- Push to history
  push_history(prev_values)
  
  -- Rescan to update current values display
  STATE.need_rescan = true
end

--------------------------------------------------------------------------------
-- 8. HISTORY / UNDO
--------------------------------------------------------------------------------
local function push_history(prev_values)
  -- Truncate forward history if we're not at the end
  while #STATE.history > STATE.history_idx do
    table.remove(STATE.history)
  end
  
  STATE.history_idx = STATE.history_idx + 1
  STATE.history[STATE.history_idx] = {
    time = os.time(),
    values = deep_copy(prev_values)
  }
  
  -- Limit history size
  if #STATE.history > 50 then
    table.remove(STATE.history, 1)
    STATE.history_idx = STATE.history_idx - 1
  end
end

local function undo_last()
  if STATE.history_idx <= 0 then return end
  
  local entry = STATE.history[STATE.history_idx]
  if not entry then return end
  
  reaper.Undo_BeginBlock()
  for uid_str, prev_val in pairs(entry.values) do
    local tr_idx, fx_idx, param_idx = parse_uid(uid_str)
    local tr = nil
    if tr_idx == 0 then
      tr = reaper.GetMasterTrack(0)
    else
      tr = reaper.GetTrack(0, tr_idx - 1)
    end
    if tr then
      reaper.TrackFX_SetParamNormalized(tr, fx_idx, param_idx, prev_val)
    end
  end
  reaper.Undo_EndBlock('FX Randomizer: Undo', -1)
  reaper.UpdateArrange()
  
  STATE.history_idx = STATE.history_idx - 1
  STATE.need_rescan = true
end

local function redo_last()
  if STATE.history_idx >= #STATE.history then return end
  -- Note: redo would need storing new values too; simplified: just re-randomize not supported
end

--------------------------------------------------------------------------------
-- 9. SNAPSHOTS
--------------------------------------------------------------------------------
local function take_snapshot(name)
  local values = {}
  for _, mp in ipairs(STATE.mapped_params) do
    local tr_idx, fx_idx, param_idx = parse_uid(mp.uid)
    local tr = nil
    if tr_idx == 0 then
      tr = reaper.GetMasterTrack(0)
    else
      tr = reaper.GetTrack(0, tr_idx - 1)
    end
    if tr then
      values[mp.uid] = reaper.TrackFX_GetParamNormalized(tr, fx_idx, param_idx)
    end
  end
  
  -- Find existing snapshot with this name or create new
  for i, snap in ipairs(STATE.snapshots) do
    if snap.name == name then
      snap.values = values
      ext_save()
      return
    end
  end
  
  STATE.snapshots[#STATE.snapshots+1] = {
    id = #STATE.snapshots + 1,
    name = name,
    values = values
  }
  ext_save()
end

local function restore_snapshot(name)
  for _, snap in ipairs(STATE.snapshots) do
    if snap.name == name then
      reaper.Undo_BeginBlock()
      for uid_str, val in pairs(snap.values) do
        local tr_idx, fx_idx, param_idx = parse_uid(uid_str)
        local tr = nil
        if tr_idx == 0 then
          tr = reaper.GetMasterTrack(0)
        else
          tr = reaper.GetTrack(0, tr_idx - 1)
        end
        if tr then
          reaper.TrackFX_SetParamNormalized(tr, fx_idx, param_idx, val)
        end
      end
      reaper.Undo_EndBlock('FX Randomizer: Restore snapshot ' .. name, -1)
      reaper.UpdateArrange()
      STATE.need_rescan = true
      return
    end
  end
end

--------------------------------------------------------------------------------
-- 10. PRESETS
--------------------------------------------------------------------------------
local function save_preset(name)
  local mapped_copy = {}
  for _, mp in ipairs(STATE.mapped_params) do
    mapped_copy[#mapped_copy+1] = {
      uid = mp.uid,
      algo = mp.algo,
      rand_min = mp.rand_min,
      rand_max = mp.rand_max,
      weight = mp.weight,
    }
  end
  
  -- Update or add
  for i, preset in ipairs(STATE.presets) do
    if preset.name == name then
      preset.mapped_params = mapped_copy
      ext_save()
      return
    end
  end
  
  STATE.presets[#STATE.presets+1] = {
    name = name,
    mapped_params = mapped_copy
  }
  ext_save()
end

local function load_preset(name)
  for _, preset in ipairs(STATE.presets) do
    if preset.name == name then
      clear_all_mapped_params()
      for _, cfg in ipairs(preset.mapped_params) do
        local tr_idx, fx_idx, param_idx = parse_uid(cfg.uid)
        add_param_to_map(tr_idx, fx_idx, param_idx)
        -- Apply config
        local idx, mp = find_mapped_param(cfg.uid)
        if mp then
          mp.algo = cfg.algo or 'uniform'
          mp.rand_min = cfg.rand_min or 0
          mp.rand_max = cfg.rand_max or 1
          mp.weight = cfg.weight or 0.5
        end
      end
      return
    end
  end
end

local function delete_preset(name)
  for i, preset in ipairs(STATE.presets) do
    if preset.name == name then
      table.remove(STATE.presets, i)
      ext_save()
      return
    end
  end
end



--------------------------------------------------------------------------------
-- 11. IMGUI UI
--------------------------------------------------------------------------------
local ctx
local fonts = {}

local function init_imgui()
  ctx = ImGui.CreateContext(SCRIPT_NAME)
  fonts.main = ImGui.CreateFont('Arial', 14)
  fonts.small = ImGui.CreateFont('Arial', 12)
  ImGui.Attach(ctx, fonts.main)
  ImGui.Attach(ctx, fonts.small)
end

local function push_theme()
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 6, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 6)
  
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x1E1E1E << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x252525 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x333333 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x3A3A3A << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x444444 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x2D5A8A << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x3A6FA0 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1E4A70 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x2D5A8A << 8 | 0x80)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x3A6FA0 << 8 | 0x90)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x1E4A70 << 8 | 0xA0)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE0E0E0 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_TextDisabled, 0x888888 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x404040 << 8 | 0x60)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, 0x4A90D9 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, 0x5AA0E9 << 8 | 0xFF)
end

local function pop_theme()
  ImGui.PopStyleVar(ctx, 7)
  ImGui.PopStyleColor(ctx, 16)
end

-- Help marker tooltip
local function help_marker(desc)
  ImGui.TextDisabled(ctx, '(?)')
  if ImGui.BeginItemTooltip(ctx) then
    ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 25)
    ImGui.Text(ctx, desc)
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndTooltip(ctx)
  end
end

-- Draw the parameter browser (left panel)
local function draw_browser()
  local _, avail_h = ImGui.GetContentRegionAvail(ctx)
  ImGui.BeginChild(ctx, 'Browser', 220, avail_h, true)
  
  ImGui.Text(ctx, 'Parameter Browser')
  ImGui.Separator(ctx)
  
  if ImGui.Button(ctx, 'Rescan Project') then
    scan_project()
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Clear Map') then
    clear_all_mapped_params()
  end
  
  ImGui.Separator(ctx)
  
  -- Filter
  local changed, new_filter = ImGui.InputText(ctx, 'Filter', CONFIG.filter_keywords)
  if changed then CONFIG.filter_keywords = new_filter end
  
  ImGui.Separator(ctx)
  
  -- Tree
  for _, track in ipairs(STATE.tracks) do
    local track_label = string.format('%s', track.track_name)
    local track_open = ImGui.TreeNode(ctx, track_label)
    
    if track_open then
      for _, fx in ipairs(track.fxs) do
        local fx_label = string.format('%s (%d params)', fx.fx_name, #fx.params)
        local fx_open = ImGui.TreeNode(ctx, fx_label)
        
        if fx_open then
          for _, param in ipairs(fx.params) do
            local uid_str = uid(track.track_idx, fx.fx_idx, param.param_idx)
            local _, is_mapped = find_mapped_param(uid_str)
            
            -- Check filter
            local show = true
            if CONFIG.filter_keywords and CONFIG.filter_keywords ~= '' then
              local kw = CONFIG.filter_keywords:lower()
              show = param.param_name:lower():find(kw, 1, true) ~= nil
            end
            
            if show then
              local label = param.param_name .. ' = ' .. string.format('%.3f', param.current_val) .. '##' .. uid_str
              local checked = is_mapped ~= nil
              
              if param.is_toggle then
                ImGui.BeginDisabled(ctx, true)
              end
              
              local clicked, new_checked = ImGui.Checkbox(ctx, label, checked)
              if clicked then
                if new_checked then
                  add_param_to_map(track.track_idx, fx.fx_idx, param.param_idx)
                else
                  remove_param_from_map(uid_str)
                end
              end
              
              if param.is_toggle then
                ImGui.EndDisabled(ctx)
                ImGui.SameLine(ctx)
                help_marker('Toggle parameters are handled as binary (0 or 1)')
              end
            end
          end
          ImGui.TreePop(ctx)
        end
      end
      ImGui.TreePop(ctx)
    end
  end
  
  ImGui.EndChild(ctx)
end

-- Draw mapped parameters editor (right top)
local function draw_mapped_params()
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  local table_height = math.min(350, avail_h * 0.6)
  local remove_idx = nil
  
  ImGui.Text(ctx, 'Mapped Parameters (' .. #STATE.mapped_params .. ')')
  ImGui.SameLine(ctx, avail_w - 80)
  if ImGui.Button(ctx, 'Remove All') then
    clear_all_mapped_params()
  end
  
  ImGui.BeginChild(ctx, 'MappedParams', -1, table_height, true)
  
  if #STATE.mapped_params == 0 then
    ImGui.TextDisabled(ctx, 'No parameters mapped. Select parameters from the browser on the left.')
  else
    if ImGui.BeginTable(ctx, 'MappedTable', 6, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
      ImGui.TableSetupColumn(ctx, 'Parameter', ImGui.TableColumnFlags_None, 3.0)
      ImGui.TableSetupColumn(ctx, 'Algorithm', ImGui.TableColumnFlags_None, 1.5)
      ImGui.TableSetupColumn(ctx, 'Min', ImGui.TableColumnFlags_None, 1.0)
      ImGui.TableSetupColumn(ctx, 'Max', ImGui.TableColumnFlags_None, 1.0)
      ImGui.TableSetupColumn(ctx, 'Weight', ImGui.TableColumnFlags_None, 1.0)
      ImGui.TableSetupColumn(ctx, 'Action', ImGui.TableColumnFlags_None, 0.8)
      ImGui.TableHeadersRow(ctx)
      
      for i, mp in ipairs(STATE.mapped_params) do
        ImGui.TableNextRow(ctx)
        
        -- Parameter name
        ImGui.TableSetColumnIndex(ctx, 0)
        ImGui.Text(ctx, mp.track_name .. ' > ' .. mp.fx_name .. ' > ' .. mp.param_name)
        
        -- Algorithm
        ImGui.TableSetColumnIndex(ctx, 1)
        if ImGui.BeginCombo(ctx, '##algo' .. i, ALGORITHMS[mp.algo].name) then
          for _, algo_key in ipairs(ALGO_KEYS) do
            local algo_data = ALGORITHMS[algo_key]
            local is_selected = mp.algo == algo_key
            if ImGui.Selectable(ctx, algo_data.name, is_selected) then
              mp.algo = algo_key
            end
            if is_selected then ImGui.SetItemDefaultFocus(ctx) end
          end
          ImGui.EndCombo(ctx)
        end
        
        -- Min
        ImGui.TableSetColumnIndex(ctx, 2)
        local changed, new_min = ImGui.SliderDouble(ctx, '##min' .. i, mp.rand_min, 0, 1, '%.3f')
        if changed then mp.rand_min = math.min(new_min, mp.rand_max) end
        
        -- Max
        ImGui.TableSetColumnIndex(ctx, 3)
        local changed2, new_max = ImGui.SliderDouble(ctx, '##max' .. i, mp.rand_max, 0, 1, '%.3f')
        if changed2 then mp.rand_max = math.max(new_max, mp.rand_min) end
        
        -- Weight (for weighted algo)
        ImGui.TableSetColumnIndex(ctx, 4)
        if mp.algo == 'weighted' then
          local changed3, new_w = ImGui.SliderDouble(ctx, '##w' .. i, mp.weight, 0, 1, '%.2f')
          if changed3 then mp.weight = new_w end
        else
          ImGui.TextDisabled(ctx, '--')
        end
        
        -- Remove button
        ImGui.TableSetColumnIndex(ctx, 5)
        if ImGui.Button(ctx, 'X##rem' .. i) then
          remove_idx = i
        end
      end
      
      ImGui.EndTable(ctx)
    end
  end
  
  if remove_idx then
    table.remove(STATE.mapped_params, remove_idx)
  end
  
  ImGui.EndChild(ctx)
end

-- Draw control panel (right bottom)
local function table_count(t)
  local c = 0
  for _ in pairs(t) do c = c + 1 end
  return c
end

local function draw_controls()
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  
  ImGui.BeginChild(ctx, 'Controls', -1, -1, true)
  
  -- Randomize section
  ImGui.Text(ctx, 'Randomization Controls')
  ImGui.Separator(ctx)
  
  -- Algorithm quick select
  ImGui.Text(ctx, 'Default Algorithm:')
  ImGui.SameLine(ctx)
  if ImGui.BeginCombo(ctx, '##def_algo', ALGORITHMS[CONFIG.default_algo].name) then
    for _, algo_key in ipairs(ALGO_KEYS) do
      local algo_data = ALGORITHMS[algo_key]
      local is_selected = CONFIG.default_algo == algo_key
      if ImGui.Selectable(ctx, algo_data.name, is_selected) then
        CONFIG.default_algo = algo_key
      end
      if is_selected then ImGui.SetItemDefaultFocus(ctx) end
    end
    ImGui.EndCombo(ctx)
  end
  
  -- Apply default algo to all mapped params
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Apply to All') then
    for _, mp in ipairs(STATE.mapped_params) do
      mp.algo = CONFIG.default_algo
    end
  end
  
  -- Seed
  ImGui.Text(ctx, 'Random Seed:')
  ImGui.SameLine(ctx)
  local changed, new_seed = ImGui.InputInt(ctx, '##seed', CONFIG.seed, 1, 100)
  if changed then CONFIG.seed = new_seed end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Random Seed') then
    CONFIG.seed = math.random(1, 999999)
  end
  ImGui.SameLine(ctx)
  help_marker('Use 0 for random seed each time. Set a fixed seed to reproduce results.')
  
  -- Random amount
  ImGui.Text(ctx, 'Random Amount:')
  ImGui.SameLine(ctx)
  local changed2, new_amount = ImGui.SliderDouble(ctx, '##amount', STATE.rand_amount, 0, 1, '%.0f%%')
  if changed2 then STATE.rand_amount = new_amount end
  ImGui.SameLine(ctx)
  help_marker('0% = no change, 100% = full randomization')
  
  ImGui.Separator(ctx)
  
  -- BIG RANDOMIZE BUTTON
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x228B22 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x32AB32 << 8 | 0xFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x187318 << 8 | 0xFF)
  local btn_w = avail_w - 16
  local btn_h = 45
  if ImGui.Button(ctx, 'RANDOMIZE!##bigbtn', btn_w, btn_h) then
    do_randomize()
  end
  ImGui.PopStyleColor(ctx, 3)
  
  ImGui.Separator(ctx)
  
  -- Snapshots
  ImGui.Text(ctx, 'Snapshots')
  if ImGui.Button(ctx, 'Snap A', 80) then take_snapshot('A') end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Snap B', 80) then take_snapshot('B') end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Restore A', 80) then restore_snapshot('A') end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Restore B', 80) then restore_snapshot('B') end
  
  -- Show snapshots
  if #STATE.snapshots > 0 then
    for _, snap in ipairs(STATE.snapshots) do
      ImGui.Text(ctx, string.format('  %s: %d params', snap.name, table_count(snap.values)))
    end
  end
  
  ImGui.Separator(ctx)
  
  -- History
  ImGui.Text(ctx, 'History')
  if ImGui.Button(ctx, 'Undo Last Randomize') then
    undo_last()
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, string.format('(%d/%d)', STATE.history_idx, #STATE.history))
  
  ImGui.Separator(ctx)
  
  -- Presets
  ImGui.Text(ctx, 'Presets')
  
  -- Preset list
  for _, preset in ipairs(STATE.presets) do
    if ImGui.Button(ctx, 'Load##pl' .. preset.name, 50) then
      load_preset(preset.name)
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, preset.name)
    ImGui.SameLine(ctx, avail_w - 80)
    if ImGui.Button(ctx, 'Del##pd' .. preset.name, 50) then
      delete_preset(preset.name)
    end
  end
  
  -- Save preset
  ImGui.PushItemWidth(ctx, 150)
  local changed3, new_preset_name = ImGui.InputText(ctx, '##preset_name', STATE.preset_input_name, ImGui.InputTextFlags_EnterReturnsTrue)
  if changed3 then STATE.preset_input_name = new_preset_name end
  ImGui.PopItemWidth(ctx)
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Save Preset') or changed3 then
    local name = STATE.preset_input_name ~= '' and STATE.preset_input_name or ('Preset ' .. (#STATE.presets + 1))
    save_preset(name)
    STATE.preset_input_name = ''
  end
  
  ImGui.EndChild(ctx)
end

-- Main draw function
local function draw_ui()
  if STATE.need_rescan then
    scan_project()
  end
  
  local window_flags = ImGui.WindowFlags_MenuBar
  window_flags = window_flags | ImGui.WindowFlags_NoCollapse
  
  ImGui.SetNextWindowSize(ctx, CONFIG.win_w, CONFIG.win_h, ImGui.Cond_FirstUseEver)
  
  local visible, open = ImGui.Begin(ctx, SCRIPT_NAME .. ' v' .. SCRIPT_VERSION .. '##main', true, window_flags)
  
  -- Track window position/size for saving
  if visible then
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    STATE.win_x, STATE.win_y = wx, wy
    STATE.win_w, STATE.win_h = ww, wh
  end
  
  if visible then
    -- Menu bar
    if ImGui.BeginMenuBar(ctx) then
      if ImGui.BeginMenu(ctx, 'File') then
        if ImGui.MenuItem(ctx, 'Rescan Project') then scan_project() end
        if ImGui.MenuItem(ctx, 'Clear All Mappings') then clear_all_mapped_params() end
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx, 'Save Settings') then ext_save() end
        if ImGui.MenuItem(ctx, 'Load Settings') then ext_load() end
        ImGui.EndMenu(ctx)
      end
      
      if ImGui.BeginMenu(ctx, 'Help') then
        if ImGui.MenuItem(ctx, 'About') then
          reaper.MB(SCRIPT_NAME .. ' v' .. SCRIPT_VERSION .. '\n\nA multi-parameter FX randomization tool for REAPER.', 'About', 0)
        end
        ImGui.EndMenu(ctx)
      end
      
      ImGui.EndMenuBar(ctx)
    end
    
    -- Main layout: left browser | right panel
    local _, avail_h = ImGui.GetContentRegionAvail(ctx)
    
    if ImGui.BeginTable(ctx, 'MainLayout', 2, ImGui.TableFlags_Resizable) then
      ImGui.TableSetupColumn(ctx, 'Browser', ImGui.TableColumnFlags_WidthFixed, 240)
      ImGui.TableSetupColumn(ctx, 'Controls', ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableNextRow(ctx)
      
      -- Left column: Browser
      ImGui.TableNextColumn(ctx)
      draw_browser()
      
      -- Right column: Mapped params + Controls
      ImGui.TableNextColumn(ctx)
      draw_mapped_params()
      draw_controls()
      
      ImGui.EndTable(ctx)
    end
    
    ImGui.End(ctx)
  end
  
  return open
end

--------------------------------------------------------------------------------
-- 12. MAIN LOOP
--------------------------------------------------------------------------------
local function loop()
  -- Check for project changes
  local scc = reaper.GetProjectStateChangeCount(0)
  if STATE.last_scc and STATE.last_scc ~= scc then
    STATE.need_rescan = true
  end
  STATE.last_scc = scc
  
  -- Validate context
  if not ctx or not ImGui.ValidatePtr(ctx, 'ImGui_Context*') then
    init_imgui()
  end
  
  push_theme()
  local open = draw_ui()
  pop_theme()
  
  if open then
    reaper.defer(loop)
  else
    -- Save window position/size before closing
    if STATE.win_x then CONFIG.win_x = STATE.win_x end
    if STATE.win_y then CONFIG.win_y = STATE.win_y end
    if STATE.win_w then CONFIG.win_w = STATE.win_w end
    if STATE.win_h then CONFIG.win_h = STATE.win_h end
    ext_save()
  end
end

--------------------------------------------------------------------------------
-- 13. ENTRY POINT
--------------------------------------------------------------------------------
local function main()
  -- Load saved state
  ext_load()
  
  -- Initial scan
  scan_project()
  
  -- Start UI
  init_imgui()
  reaper.defer(loop)
end

main()
