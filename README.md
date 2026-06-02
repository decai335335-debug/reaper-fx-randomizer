# FX Randomizer —— REAPER 多参数随机化探索工具

为 REAPER 提供多算法 FX 参数随机化能力，配合 A/B 快照对比和预设系统，帮助声音设计师和音乐人快速探索参数空间的意外可能性。调试混音找不到感觉时，一键随机或许能撞出惊喜。

---

## 解决什么痛点

**以前是这样的：**

- 调混音参数时靠经验手动拧旋钮，试了半天还是那几种熟悉的组合
- 想尝试更大胆的参数搭配，但手动逐个调整效率太低，热情很快被磨光
- 随机出了一组好听的设置，但没法保存，下次打开工程又得重新调
- 想对比 A/B 两种参数组合，只能手动记笔记或靠耳朵硬记
- ReaImGui 升级后，旧脚本因为 API 不兼容直接报错无法运行

**现在是这样的：**

- 从任意轨道、任意 FX、任意参数中勾选想要随机的目标，一键批量随机
- 4 种随机算法（均匀/正态/加权/阶梯），从细微变化到彻底颠覆都可控制
- 随机出好听的组合？按 Snap A 保存，继续随机，随时 A/B 对比
- 整组随机配置可以保存为预设，换工程也能一键调用
- 已适配 ReaImGui v0.10，安装即用

**适合谁用：**

- **声音设计师** —— 设计特殊音效时需要突破常规参数组合，寻找意外音色
- **混音工程师** —— 卡在"调来调去都不对"的瓶颈期，用随机打破思维定式
- **电子音乐人** —— 制作过程中快速生成变体，筛选有趣的音色方向
- **声音实验创作者** —— 系统性地探索插件参数空间的边界效果

---

## 核心功能

| 功能 | 解决什么问题 |
|------|-------------|
| **树形参数浏览器** | 展开 Track → FX → Parameter 三级树，勾选即可加入随机池，不用记参数编号 |
| **4 种随机算法** | 均匀（经典均匀分布）、正态（聚集在中心值附近）、加权（偏向最小或最大值）、阶梯（离散跳跃），覆盖从保守到激进的所有探索需求 |
| **单参数独立范围** | 每个参数可单独设定 Min/Max，避免随机到极端离谱的值（如混响时间随机到 0.01ms） |
| **随机种子复现** | 输入固定种子数字，完全复现同一组随机结果，"撞"到好听的组合可以精确还原 |
| **全局随机量** | 0%~100% 控制随机化强度，100% 完全随机，20% 只做微调，在熟悉和意外之间自由调节 |
| **A/B 快照** | Snap A / Snap B 保存两组参数状态，一键切换对比，决策有据 |
| **撤销历史** | 每次随机化自动记录，点 Undo 回退一步，不怕随机后回不到原来 |
| **预设系统** | 整组随机配置（参数映射 + 算法 + 范围）保存为预设，跨工程复用 |
| **工程持久化** | 配置、快照、预设随 REAPER 工程自动保存，重启后仍在 |

---

## 安装方法

### 依赖要求

- **REAPER 6.0+**
- **ReaImGui 扩展 v0.10+**（UI 核心依赖）

**安装 ReaImGui**：
1. 访问 [reapack.com](https://reapack.com) 下载安装 ReaPack
2. 在 REAPER 中点击 `Extensions → ReaPack → Import repositories`
3. 导入 ReaTeam 仓库，搜索并安装 **ReaImGui**
4. 重启 REAPER

> 如果 ReaPack 连不上 GitHub，可以手动下载 `reaper_imgui-x64.dll` 放到 `%APPDATA%\REAPER\UserPlugins\`，并下载 `imgui.lua` 放到 `Scripts/ReaTeam Extensions/API/`。

### 安装步骤

1. 将 `FX Randomizer.lua` 复制到 REAPER Scripts 目录：
   - **Windows**：`%APPDATA%\REAPER\Scripts\`
   - **macOS**：`~/Library/Application Support/REAPER/Scripts/`
   - **Linux**：`~/.config/REAPER/Scripts/`

2. 在 REAPER 中按 **`?`** 打开 Action List，点击 **Load...**，选择 `FX Randomizer.lua`

3. （可选）分配工具栏按钮或键盘快捷键，方便随时调用

---

## 使用方法

### 场景一：探索性声音设计（最常见）

**什么时候用**：设计一个全新音效，想快速尝试不同的 FX 参数组合，寻找意想不到的音色。

1. **打开工具**：从 Action List 运行 `FX Randomizer`，或按分配的快捷键
2. **选择参数**：
   - 左侧面板展开 **Track → FX → Parameters**
   - 勾选想要随机的参数（如混响的 Decay、Damping、Wet）
   - 点击 **Rescan Project** 如果中途添加/删除了轨道或 FX
3. **设置范围**：右上面板为每个参数设定 Min / Max（如 Decay 限定在 0.2~0.8，避免太短或太长）
4. **执行随机**：
   - 调整 **Random Amount**（建议从 50% 开始）
   - 选择算法（**Uniform** 或 **Normal** 比较适合保守探索）
   - 点击 **RANDOMIZE!**
5. **保存好结果**：
   - 听到满意的音色，点击 **Snap A** 保存
   - 继续随机，不满意时点 **Restore A** 回到刚才的好状态

### 场景二：批量生成变体

**什么时候用**：需要为同一个素材生成 5~10 种不同处理版本，从中挑选最佳。

1. 勾选目标参数并设定合理范围
2. 设 **Random Seed = 0**（每次随机不同）
3. 设 **Random Amount = 80%**
4. 每点击一次 **RANDOMIZE!**，REAPER 会自动创建撤销点
5. 用 REAPER 自带的 **Undo**（Ctrl+Z）在历史状态间来回对比

### 场景三：A/B 对比两种混音思路

**什么时候用**：纠结两种参数设置哪种更好，需要快速来回切换对比。

1. 调好第一组参数，点击 **Snap A**
2. 随机或手动调出第二组参数，点击 **Snap B**
3. 播放音频，点击 **Restore A** → **Restore B** 快速切换
4. 确定胜方后，可删除败方的快照，继续细化

### 场景四：保存常用随机配置

**什么时候用**：发现某一类随机配置（如"人声轻度随机化"）经常用，想做成模板。

1. 配置好参数映射、算法、范围
2. 在 Presets 区域输入名称（如 `Vocal_Light`）
3. 点击 **Save Preset**
4. 以后换工程后，直接 **Load** 该预设即可恢复完整配置

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 脚本语言 | ReaScript (Lua) |
| UI 框架 | ReaImGui (`imgui` v0.10) |
| FX 操作 | REAPER TrackFX API (`TrackFX_GetParam`, `TrackFX_SetParam`) |
| 随机算法 | 纯 Lua 数学实现（Uniform、Box-Muller Normal、Power Curve Weighted、Stepped） |
| 持久化 | REAPER ExtState (`reaper.GetExtState` / `SetExtState`) |
| 撤销支持 | `Undo_BeginBlock` / `Undo_EndBlock` |

**依赖**：零第三方 Lua 库，仅需 REAPER + ReaImGui。

---

## 文件结构

```
reaper-fx-randomizer/
├── FX Randomizer.lua      # 主脚本（单文件，~1145 行）
│   ├── 参数浏览器          # Track → FX → Parameter 树形控件
│   ├── 随机算法引擎        # Uniform / Normal / Weighted / Stepped
│   ├── 快照系统            # A/B 状态保存与恢复
│   ├── 预设系统            # 配置序列化与反序列化
│   └── ReaImGui UI         # 完整图形界面（适配 v0.10 API）
└── README.md / DEV_LOG.md  # 文档
```

---

## 常见问题

**Q: 运行脚本提示 "This script requires the ReaImGui extension"？**
A: 未安装 ReaImGui 扩展。按上方"安装 ReaImGui"步骤操作，安装后重启 REAPER。

**Q: 报错 `attempt to access a nil value (field 'Columns')`？**
A: 你用的是 ReaImGui v0.10+，但脚本旧版使用了已移除的 `Columns` API。请更新到本仓库最新版脚本，已改用 `BeginTable` 实现。

**Q: 报错 `attempt to call a number value`？**
A: 同样是因为 ReaImGui v0.10 中标志位（如 `TableFlags_Resizable`）从函数变成了数字常量，不能加 `()` 调用。最新版脚本已修复。

**Q: 随机结果无法复现？**
A: 检查 **Random Seed** 设置。Seed = 0 时每次结果都不同；设为固定数字（如 42）即可复现完全相同的随机序列。

**Q: 某些参数随机后声音爆了/没了？**
A: 建议为每个参数设置合理的 Min/Max 范围。例如 Gain 类参数可限制在 0.3~0.8，避免随机到 0（静音）或 1（最大增益导致削波）。

**Q: Undo 后无法再次撤销？**
A: 脚本内部维护了独立的 History 栈（最多 50 步），与 REAPER 原生撤销分开。点击 **Undo Last Randomize** 回退脚本的历史记录。如需回退更早的操作，连续点击即可。

**Q: 预设保存后换电脑还能用吗？**
A: 预设保存在 `reaper-extstate.ini` 中（位于 REAPER 配置目录），与 REAPER 配置一起迁移即可。但预设中引用的轨道/FX 名称需要在新工程中保持一致才能正确映射。

**Q: 切换工程后参数映射乱了？**
A: 参数映射按轨道名和 FX 名匹配。如果新工程中轨道名或 FX 名不同，映射会失效。建议换工程后点击 **Rescan Project** 重新扫描并勾选参数。

**Q: 点击 RANDOMIZE! 后界面崩溃，提示 Missing EndChild()？**
A: 这是因为随机化函数内部遇到异常（如参数为 nil、deep_copy 递归出错），导致 UI 绘制中断。请更新到最新版脚本，已增加 `pcall` 崩溃保护和 nil 安全检查。

---

## 更新日志

### v1.1.1（2026-06-03）

- **崩溃修复**：
  - `do_randomize()` 增加 `pcall` 保护，底层报错不会闪退整个 UI
  - 增加 nil 安全检查（`mp`、`mp.uid`、`tr_idx`、`fx_idx`）
  - 算法调用用 `pcall` 包裹，防止算法函数异常
  - 历史记录改用扁平拷贝代替 `deep_copy`，避免递归表拷贝崩溃
  - 随机种子设置也用 `pcall` 保护
  - `RANDOMIZE!` 按钮包裹 `pcall`，错误信息输出到控制台而非闪退

### v1.1.0（2026-06-03）

- **ReaImGui v0.10 兼容**：
  - `ImGui.Columns` → `ImGui.BeginTable`
  - `BeginChild` 布尔边框 → `ChildFlags_Border` 数字常量
  - 标志位函数调用 `()` → 直接引用数字常量
  - `require 'imgui' '0.9'` → `require 'imgui' '0.10'`

### v1.0.0（初始版本）

- 多参数映射：Track → FX → Parameter 三级树形浏览器
- 4 种随机算法：Uniform、Normal（Box-Muller）、Weighted（幂曲线）、Stepped（离散）
- 单参数独立 Min/Max 范围控制
- 随机种子系统（0 = 随机，固定数字 = 可复现）
- 全局 Random Amount 混合控制（0%~100%）
- A/B 快照系统（Snap / Restore）
- 独立 History / Undo 栈（最多 50 步）
- 预设系统（Save / Load / Delete）
- 工程持久化（ExtState 存储）
- ReaImGui 完整图形界面
