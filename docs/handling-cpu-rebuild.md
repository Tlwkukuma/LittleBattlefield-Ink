# 枪械处理 CPU 去重 · 2026-10-10

## 比较边界

本批只比较重新恢复俯视后坐玩法后的代码与 CPU 候选。冻结参考为 `qa/fixtures/weapon_handling_topdown_baseline.gd`，它逐字复制玩法提交 `4562b68` 中的 `scripts/weapon_handling.gd`，SHA-256 为 `66dc990cf8a14af702154a00d95f1644a811fe0e73bd3dcf641180b7140e2046`。测试在运行前校验哈希；不是用 v3 原玩法与新后坐系统做虚假的等价比较，也没有采用历史 72k/2215 成绩。

## 改动

- 每次 tick 取一次 profile，调用一次脚架资格判断；只在该次 tick 内复用。支撑值仍先更新，再用于 damping，不能错误复用上一帧或更新前的支撑值。
- 公开 `braced(w,u)` / `support(w,u)` 继续按当前姿态、移动、接地、翻越和攀爬状态判断，不引入跨 tick 状态缓存。
- `_follow_target` 只有 target、kick_angle 和 kick_velocity 三个向量全都精确等于 ZERO 才跳过指数/弹簧向量计算，并写回 ZERO 速度。角度和目标为零但速度非零时原方程仍会产生运动，必须保留；微小非零也不能用近似零提前丢弃。

## 新验证

Godot 4.6.3 headless 新运行结果：**198,077 checks，0 failures**。`qa/handling_cpu_contract.gd` 深拷贝独立状态，对实际 101 项装备检查 20 个状态变体、6 个 delta、连续 6 步，共 72,720 组 tick。逐步使用整字典严格相等，不用容差；再比较 profile、fired、support、散布与枪口 offset。

变体包含完全静止、零角度/目标但非零速度、±1e-12、脚架速度和姿态边界、运动、离地、翻越、梯子、挂载、换弹、死亡、切枪及门限两侧。步间主动改变运动和接地，验证不能跨 tick 缓存资格。动态插桩只统计 profile/脚架查询与弹簧路径，不改变状态；证明 CPU 候选每 tick 各一次查询，精确静止跳过弹簧，其余路径仍完整计算。

没有驱动实战，没有新增 FPS 目标，也不把冻结函数去重当作整场景帧率证明。

### 调用次数与计时

对 2,020 次插桩 tick：profile 调用 **5,540 → 2,020**，脚架资格判断 **3,520 → 2,020**；候选每次 tick 两者各一次。

每种基准各 50,500 次 tick，预热后 5 轮交替 baseline/candidate 顺序，fixture 初始化不计时。本机这次运行中位数：

- idle：1,024.772 → 769.674 ms（-24.89%）
- mixed：1,040.138 → 853.406 ms（-17.95%）

原始排序样本（ms）：idle baseline [841.469, 957.923, 1024.772, 1050.634, 1543.809]，candidate [664.912, 739.280, 769.674, 854.784, 999.217]；mixed baseline [988.972, 1034.281, 1040.138, 1095.771, 1154.253]，candidate [809.633, 810.236, 853.406, 884.729, 952.318]。云机器调度仍会产生噪声，不能把该比例外推为完整游戏帧率收益。

CPU 候选上再次运行 `qa/topdown_recoil_contract.gd`：**9,365 checks，0 failures**。最终 editor/import 无 ERROR，退出 0。HOME 与 XDG 均隔离在 `/tmp/recoil-rebuild/`。没有实战驱动。

```sh
HOME=/tmp/recoil-rebuild/home XDG_DATA_HOME=/tmp/recoil-rebuild/data \
XDG_CONFIG_HOME=/tmp/recoil-rebuild/config XDG_CACHE_HOME=/tmp/recoil-rebuild/cache \
/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --script qa/handling_cpu_contract.gd
```
