# FX Randomizer

A powerful multi-parameter randomization tool for REAPER, built with ReaImGui.

> 项目三：效果器 Random Reaper 插件 —— VibeCoding 六项目深度规划

---

## Features

- **Multi-parameter mapping**: Select parameters from any track → FX → parameter tree
- **Multiple random algorithms**:
  - **Uniform**: Classic even distribution
  - **Normal**: Gaussian/Box-Muller distribution (clusters around center)
  - **Weighted**: Bias toward min or max with adjustable weight
  - **Stepped**: Discrete stepped randomization
- **Per-parameter range control**: Set individual min/max for each mapped parameter
- **Random seed**: Reproducible results with fixed seeds
- **Global random amount**: Blend between current values and fully random (0%–100%)
- **Snapshots (A/B)**: Save and restore parameter states for comparison
- **Undo/History**: Step back through randomization actions
- **Presets**: Save and load entire randomization configurations
- **Project persistence**: Settings, snapshots, and presets survive REAPER restarts

---

## Requirements

- **REAPER 6.0+**
- **ReaImGui extension** (install via [ReaPack](https://reapack.com/) or [GitHub](https://github.com/cfillion/reaimgui))

---

## Installation

1. Install the **ReaImGui** extension if you haven't already.
2. Copy `FX Randomizer.lua` to your REAPER Scripts folder:
   - **Windows**: `%APPDATA%\REAPER\Scripts\`
   - **macOS**: `~/Library/Application Support/REAPER/Scripts/`
   - **Linux**: `~/.config/REAPER/Scripts/`
3. In REAPER, open the Actions list (`?` key), click **Load...**, and select `FX Randomizer.lua`.
4. Optionally, assign a toolbar button or keyboard shortcut.

---

## Usage

### 1. Open the Tool
Run the script from the Actions list or via your assigned shortcut.

### 2. Browse Parameters (Left Panel)
- Expand **Tracks** → **FX** → **Parameters**
- Check the checkbox next to any parameter to add it to the randomization map
- Use the **Filter** box to quickly find parameters by name
- Click **Rescan Project** if you add/remove tracks or FX

### 3. Configure Mapped Parameters (Right Top)
For each mapped parameter, you can set:
- **Algorithm**: Choose from Uniform / Normal / Weighted / Stepped
- **Min / Max**: Randomization range (0.0 – 1.0, normalized)
- **Weight**: (Weighted algorithm only) Bias toward low (0) or high (1) values

### 4. Randomize
- Adjust **Random Amount** to control how far from current values the randomization goes
- Set a **Random Seed** (0 = random each time, any other number = reproducible)
- Click the big **RANDOMIZE!** button

### 5. Snapshots
- **Snap A / Snap B**: Save current parameter values to snapshot
- **Restore A / Restore B**: Instantly recall saved values

### 6. Undo
- Click **Undo Last Randomize** to revert the most recent randomization

### 7. Presets
- Type a preset name and click **Save Preset** to store your current mapping
- Click **Load** to recall a preset
- Click **Del** to remove a preset

---

## UI Overview

```
┌─────────────────────────────────────────────────────────────┐
│ FX Randomizer v1.0.0                              [File][Help]
├───────────────────────┬─────────────────────────────────────┤
│ Parameter Browser     │ Mapped Parameters (12)     [Remove All]
│ [Rescan] [Clear Map]  │ ┌─────────────────────────────────┐ │
│                       │ │ Param     Algo    Min  Max  Wgt │ │
│ Filter: [________]    │ │ Master>Reverb>Decay  Normal 0.2 0.8 --│ │
│                       │ │ Track1>Comp>Ratio Uniform 1.0 10.0 --│ │
│ ▼ Master             │ │ ...                             │ │
│   ▼ Reverb (24)      │ └─────────────────────────────────┘ │
│     [✓] Decay = 0.52 │                                     │
│     [ ] Damping=0.30 │ Randomization Controls              │
│     [✓] Wet = 0.80   │ Default Algorithm: [Uniform ▼]      │
│   ▼ Compressor (12)  │ Random Seed: [0] [Random Seed] (?)  │
│     [ ] Threshold    │ Random Amount: [100%]               │
│     [✓] Ratio = 4.0  │                                     │
│ ▼ Track 1            │ [========== RANDOMIZE! ==========]  │
│   ▼ EQ (16)          │                                     │
│     [ ] Freq         │ Snapshots [Snap A][Snap B][Restore A]│
│     [ ] Gain         │           [Restore B]                │
│                      │ History: [Undo Last Randomize] (3/5) │
│                      │ Presets: [Load][Del] MyPreset        │
│                      │ [Preset Name____] [Save Preset]      │
└───────────────────────┴─────────────────────────────────────┘
```

---

## Architecture

```
FX Randomizer.lua
├── Config & State Management
├── Ext State Persistence (settings, snapshots, presets)
├── Parameter Scanning (TrackFX API)
├── Random Algorithms
│   ├── Uniform
│   ├── Normal (Box-Muller)
│   ├── Weighted (power curve)
│   └── Stepped (discrete)
├── Parameter Mapping
├── Randomization Engine
├── History / Undo Stack
├── Snapshot System (A/B)
├── Preset System
└── ReaImGui UI
    ├── Parameter Browser (Tree)
    ├── Mapped Params Table
    └── Control Panel
```

---

## Technical Notes

- All parameter values are handled in **normalized** form (0.0 – 1.0), which is REAPER's native parameter representation.
- Toggle parameters (detected via `GetParameterStepSizes`) are randomized as binary (0 or 1).
- The tool uses REAPER's ExtState for persistence, so settings are stored in `reaper-extstate.ini`.
- Randomization is wrapped in `Undo_BeginBlock` / `Undo_EndBlock` for native REAPER undo support.

---

## Future Enhancements

- [ ] Exclude ranges UI (set forbidden value intervals per parameter)
- [ ] Smooth/gradual parameter transitions to prevent audio pops
- [ ] MIDI CC / OSC remote control
- [ ] Parameter linking (mathematical relationships between parameters)
- [ ] Scene/morph between snapshots over time
- [ ] Batch randomization with probability per parameter
- [ ] Export/import presets as JSON

---

## License

MIT License — Part of the VibeCoding audio automation toolkit.

---

## Credits

- Built for the **VibeCoding 七项目深度规划** initiative
- Inspired by [MPL's Randomize FX parameters](https://forum.cockos.com/showthread.php?t=233358)
- UI powered by [ReaImGui](https://github.com/cfillion/reaimgui)
