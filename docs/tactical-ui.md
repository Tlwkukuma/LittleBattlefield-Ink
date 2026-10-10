# 统一战术 UI

本次为丢失修改的重建，不代表找回原提交。采用用户指定的《战地》方向；未假定某一代作品，也不复制 EA 美术资产。

## 资源与入口

`scripts/tactical_ui.gd` 在进程内仅构建一次 Theme、SystemFont 和命名 StyleBox，根控件共享引用。石墨背景、冷白正文、青色焦点；警告、生命和蓝红队伍继续原语义。

- 首页 / 战役章节 / 任务简报 / LAN：`home_screen.gd` 的真实 `setup` 入口，移除旧云图与插画标题，使用原生文字标题、按钮、列表、输入框及纵向滚动
- 配装 / 场景工坊 / Debug / 战斗结果：`proving_ground.gd` 的同一个 `ui.theme`；没有第二演武场 UI 分支
- 拾取：`loot_panel.gd` 共享主题，保留真实物品操作
- 战术轮盘：`equipment_wheel.gd` 共享文字与交互色，原扇区和选择语义不变
- 战斗 HUD：`combat_hud.gd` 共享面板/字体，`battle_status_hud.gd` 正文字色统一；顶部兵力、左下生命、右下弹药布局不动
- 暂停：现有暂停通知继承根主题；没有额外常驻战斗文字
- 旧 `main.tscn` 原型：`hud.gd` 也使用缓存字体和色板，原蓝红色保留
- 载入层：由 `campaign_loading.gd` 接入同一个 `apply(control)` API（另一个恢复分支交付）

首页普通可见「录制游玩日志」CheckButton 绑定 `set_play_recording` 与 `play_recording_changed`；不依赖 Debug 的详细性能采样开关。

## 布局

菜单小窗口采用原生 ScrollContainer，所有操作均在可滚动内容内；长按钮标题省略且 tooltip 保留全文。LAN 刷新行以 `get_combined_minimum_size()` 实测高度后加 10 px 间距排列表格，避免请求 30 px 但实际控件更高时重叠。章节在窄窗切成单列。页面切换重置滚动位置。

## 验证边界

`qa/tactical_ui_contract.gd` 创建实际 proving_ground 实例，执行真实 Home.setup，检查真实首页 / LAN / 章节 / Debug / 结果控件，包含 1440×900、1280×720、800×600、480×640 和长章节标题。场景在加入树前禁用处理，不发送战斗输入或推进 world。

本文件不把资源主题检查、旧通过计数或自动截图当作玩家的视觉验收。最终运行结果见该契约的实际日志。

### 2026-10-10 本批实测

Godot 4.6.3 headless，真实实例契约 **1225 checks / 0 failures**，`theme_builds=1`、`simulation_time=0`、`shots=0`。除四种窄逻辑尺寸，另保留项目默认 1440×900 canvas 映射到 1280×720、800×600、480×640 物理窗口的路径，按真实 viewport 坐标和 `get_final_transform()` 检查裁切。实测日志：`qa/reports/tactical-ui-20261010.txt`。

测试使用本分支 UI 加载器单文件临时副本；加载层代码由 loading 分支提交，未重复纳入 UI 提交。最终集成后仍须再次执行契约与录制真实API检查。无自动战斗、截图视觉验收或性能达标结论。
