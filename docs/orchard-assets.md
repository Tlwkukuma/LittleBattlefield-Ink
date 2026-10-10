# 石墙果园资产实现

2026-09-26。资产模块已实现，供首关派生计划接入；原始 `data/original` 与原 52 项预制体定义未修改。战斗规则、具体布置、AI、HUD 和启动验收由关卡侧管理。

2026-09-28：首关已改为 1.6 米深沟、0.6 / 0.3 米前后土堆及 0.9 米射击踏步，详见 [壕沟掩护修正](trench-defenses.md)。下方 1.3 米 / 0.36 米等仍为通用接口初始示例，不是首关最新布置。

## 建筑与原坐标

`OrchardPrefabs.convert_plan(plan,catalog)` 返回深复制的新计划，只在一个分组的全部原 ID 都存在时替换该组，重复调用不重复添加。

- `building.orchard-house-a/b/c`
- `building.orchard-barn`
- `rural.orchard-stone-yard`

每个定义都具有 `source_origin:[x,y]`、`source_ids:[...]`，模板相对原中心归零。每个编译墙段具有 `source_id`。门洞沿用原编译器的开口裁剪，包括原来的 4 单位留缝；A 的隔间、B/C 门偏位、谷仓北门/东门/隔间、农院西门保持原坐标。四栋房屋有屋顶，围院不封顶。实例明确 `windows=false`，没有自动增加新射孔。

旧大小果树保持源 ID、140 个位置与作者树冠半径，默认高度分为 3.65 / 2.45 米；冠团数、分枝及颜色也不同。树干仍是原来的 0.35 米通行/挡弹截面，树冠不变成实体墙。新树石库与两层住宅不受替换。

## 地形数据接口

所有地形放在 `plan.world.groundFeatures`。`points` 为原坐标，40 单位/米；下列 `_m` 参数均为米，不再换算。参数可放在 feature 根级或 `godot3d`，根级优先。

| componentId | 字段 |
| --- | --- |
| `landform.low-hill` | 四角矩形 `points`（首边为局部 X 轴），`height_m:1.5`，`plateau_size_m:[2,2]`；可选 `slope_runs_m:[西,东,北,南]`，各值应小于对应半边长。两点形式用旧 `width` 定义矩形总宽。 |
| `landform.trench-network` | 连续 `points`；`depth_m:1.3`、`bottom_width_m:2.4`、`bank_run_m:1`、`corner_radius_m:2`、`corner_widen_m:.35`；`ramps` 为坡口数组。 |
| `landform.level-pad` | 平台多边形 `points`；`height_m:0`、`transition_m:1`。路径形式另加 `kind:"path"`、`width_m`。 |

`height` / `depth` 也作为对应高度/深度的兼容别名。低丘是线性坡，避免整段 smoothstep 把局部坡度提高到平均坡度的 1.5 倍；最终行走、射线和渲染仍使用实际三角网格。

沟网转角使用圆弧倒角，空间不足时切点最多占相邻段 40%，实际半径随之收缩。沟底宽度是解析高度场的设计净宽；0.5 米网格会使斜向沟边过渡跨越一个采样格，AI 必须检查实际 `height/grade`，不能直接用参数宽度判连通。

每个坡口如下，点序必须从深端到地面端，长度由实际点距确定：

```json
{"points":[[1030,1760],[1280,1800]],"width_m":2.8,"landing_length_m":1.25,"surface_height_m":0}
```

坡道主动替换其通行宽度内的旧沟端陡坡。出口后生成真实平整落脚区，`surface_height_m` 为落脚平台绝对高度，默认 0。多段/重叠沟网以开挖深度的最大值形成并集，不累加成双倍深坑。

高度顺序固定为丘坡 → 沟网开挖 → 平台/道路保平，不依赖 JSON 中的先后顺序。多个同高平台重叠时选最大约束权重；不同标高的平台不应重叠。

## 道路

`terrain_paths.gd` 使用原项目 Catmull–Rom 多项式，每段 18 个采样点，支持原 `polyline`。绘制、`terrain.contains` 和保平带读取同一采样结果。保留 `surface=track`、原 fill/alpha、路肩颜色/宽度，以及贯穿样条的中心虚线节奏。

在原道路 feature 上加：

```json
{"level_height_m":0,"level_width_m":6,"level_transition_m":1}
```

`level_width_m` 是需要保障整车通行的总宽，不默认等同车身宽；未提供时取原路肩总宽。为确保请求宽度内整个三角面都为 y=0，网格内部每侧额外保平 `cell*sqrt(2)`，首关 0.5 米网格约 0.707 米，然后才进入外侧过渡。沟与车道布局必须计入此额外空间。

`terrain.conflicts` 返回 `{type:"trench-pad-overlap",trench:原featureID,pad:原featureID,point:Vector2}`；检查包括主沟、坡口和网格扩展。它是布局冲突提示，不自动挪动控制点。

## 射击踏步和护壁

两者可作为 ground feature，也可作为同名 prefab 实例，编译成现有实体物件。

- `defense.trench-firing-step`：`points` 沿台长方向；`width_m:.9`、`step_height_m:.36`、`step_count:3`、`step_run_m:.35`、`elevation_m:-1.3`。双端各三级接入，单级不超过 0.18 米。使用 `structure.stair` 的真实显示、射线、通行、承托面；不是地面贴图。实例可另给 `godot3d.length_m`。
- `defense.trench-revetment`：`points` 沿护壁；`width_m:.16`、`height_m:1.1`、`elevation_m:-1.3`，`material:"wood"` 或 `"stone"`；仍为可破坏墙格。

未给 `elevation_m` 时，贴地 helper 会把底部放在该段中心的地表高度；明确海拔时视为绝对底高，不再叠加地形。长护壁应由布置侧分段放在沟坡合适位置，不能让护壁遮断坡口。地形本体不随木板/石墙被炸开而挖掉。

## 普通林地贴地接线

在 `world.setup` 的 `terrain.configure(compiled,catalog,plan)` 后、准备物件 HP 与空间索引前调用：

```gdscript
preload("res://scripts/terrain_landforms.gd").ground_objects(compiled,terrain)
```

helper 保持 `compiled.objects` 原数组引用：旧树/岩石逐个贴地；坡墙按不超过 0.55 米细分，以最低脚点埋入地形，并保留最高脚点以上的原掩护高度。物理墙格与显示共享底高，不增加纯外观地基。重复调用不叠高。新 natural 物件及已有雪/沙基础处理由现有 world 逻辑管理，不重复贴地。房屋/机枪平台须由关卡保持平整。

## 检查

`qa/orchard_asset_contract.gd` 266 项纯数据/几何检查通过：原墙段/开口双向映射、转换幂等、140 树冠、低丘坡度、折线/旋转沟网、双坡口/落脚区、并集开挖、道路保平/冲突、坡墙贴地、踏步承托。石墙破口/挡弹/寻路失效及附属石块随 HP 消失另拆为 `qa/orchard_wall_contract.gd` 5 项并独立运行通过。

已有地形 146、地貌 61、住宅 38、树石 143 项检查通过。未自动游玩或截图，未另开验收场景；首关实际 AI 通路、车辆扫掠、攻防节奏和表现仍由统一关卡接入后验收。
