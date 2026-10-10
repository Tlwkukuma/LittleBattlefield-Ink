# 俯视随身枪械后坐恢复 · 2026-10-10

这是在恢复基线 `6b3a0e4` 上重新实施的玩法修复，不是找回丢失提交，也不引用旧测试成绩。只覆盖实际目录中的 75 支随身直射枪：68 项 bullet（包含霰弹枪）及 7 项 hitscan。另 9 项随身特殊装备和 17 项原目录挂载槽不启用新 profile；共检查 101 项。没有修改伤害、弹量、射速或 AI。

## 实现

- `weapon_handling.gd.is_topdown(w)` 明确筛选无 `mounted_fire_key` 的 bullet/hitscan/shotgun。按现有枪型调校的 pitch 乘 0.10、yaw 乘 3.0，保留原枪型差异和所有射速/模式。垂直累积上限 0.003–0.007 rad，横向累积上限 0.035–0.085 rad。数值是项目调校，不是真枪数据。
- 横向按武器 ID 固定肩偏方向，原 pattern 与每发有界随机量保留轻微变化；第 2–9 发逐渐增大，不再由左右正弦相互抵消。卧倒脚架仍要求真实接地、姿态完成、停稳、未翻越/攀爬/乘坐，移动即撤收益。
- `offset()` 仍是 source rig / minigun 真实枪口姿态和无模型 fallback 发射方向的共同来源。读取已偏转枪口的发射路径不再次叠加 carried 后坐。没有准心吸附、摄像机假后坐或伪造命中。
- `proving_world.gd` 在发射边界分别传入单发轴线与弹丸的竖直半角：前者最多 0.004 rad，霰弹子弹相对弹壳轴线最多 0.006 rad。只有椭圆的竖轴缩小，横向沿用源散布；两次分别属于枪轴误差和真实弹壳散布，不对同一值重复缩放。包络相对枪口瞄准方向，俯射/仰射目标高度不被强行压到水平。原狙击呼吸摆动仍保留。
- `proving_ground.gd` 仅在非 topdown 装备上保留旧鼠标移动补偿路径，随身直射枪不再把鼠标屏幕纵向位移当作俯仰压枪。mounted、投掷/曲射装备的输入保持。
- 停火恢复在 recover_delay 边界精确拆分本帧，使用指数衰减目标的临界阻尼解析解，而不是先移动目标再让弹簧跟随帧末值。真实瞄准线不被该恢复解修改。`_follow_target` 保留原临界阻尼方程，包括角度和目标均为零、但速度非零时仍继续积分，不能把这类状态当作静止。
- 切枪、死亡重置、连发结束门限、换弹/空仓发射门控和有限弹药保持原系统；没有新增自动发射/实战驱动。

## 新验证

`qa/topdown_recoil_contract.gd` 在 Godot 4.6.3 headless 下完成 **9,365 checks，0 failures**。检查全目录资格、75 支枪累积方向与上限、30/120 Hz 跨恢复门限解析等价、停火恢复、脚架即时失效、切枪/死亡重置、俯仰瞄准相对散布和霰弹高度包络、真实枪口单次接线、有限弹药与原实体弹道接线。静态接线检查不能替代用户实战射击。最初测试把低射速枪的 burst 结束截止设得过短；修正断言观察时长后重新全量运行通过，没有修改原 burst 结束规则。

全量 editor/import 退出 0，无 ERROR/Parse Error。所有 HOME 与 XDG 目录放在 `/tmp/recoil-rebuild/`；没有驱动游戏战斗。实际手感与高低处命中仍由用户在正常场景操作验收，不宣称已通过实战。

```sh
HOME=/tmp/recoil-rebuild/home XDG_DATA_HOME=/tmp/recoil-rebuild/data \
XDG_CONFIG_HOME=/tmp/recoil-rebuild/config XDG_CACHE_HOME=/tmp/recoil-rebuild/cache \
/opt/godot/4.6.3/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --script qa/topdown_recoil_contract.gd
```

## 实际覆盖 ID

m16a4, m416, scar-l, g36c, qbz, k2, aug, famas, akm, beryl-m762, mk47-mutant, groza, ace32, mini14, mk12, sks, slr, mk14, vss, dragunov, tommy-gun, ump, micro-uzi, vector, mp5k, mp9, p90, js9, kar98k, m24, awm, win94, lynx-amr, s12k, s1897, s686, dbs, sawed-off, o12, p18c, p92, skorpion, deagle, r1895, m249, mg3, rpd, ak-47, galil-ar, m4a4, m4a1-s, sg-553, awp, ssg-08, g3sg1, scar-20, mac-10, mp7, mp5-sd, ump-45, pp-bizon, nova, xm1014, mag-7, negev, glock-18, p2000, usp-s, p250, five-seven, tec-9, cz75-auto, dual-berettas, r8-revolver, minigun
