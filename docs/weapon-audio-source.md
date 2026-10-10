# 枪声按小小战地原版恢复 · v2026.09.29.23

> 历史基线：v2026.09.29.30 用户明确禁止继续使用原音效，现已 [全部替换为免费素材及离线近似设计](free-combat-audio-complete.md)。本文保留历史研究，原音源不再加载或打包，也不得作为缺失项回退。

用户要求严格参考小小战地。本轮依据本机 `Pixi-Battlefield1-Blue/src/audio.js`、`src/Game.js` 与已导入 `data/original/catalog.json`，恢复原版音源选择和播放参数。

## 已实现

- `tools/sync_source_weapon_audio.py` 从原声音表提取 32 个有采样的配置及 3 个别名，写入 `data/source-weapon-audio.json`。该文件记录源代码与每个 WAV 的 SHA-256；13 个枪声 WAV 共 2,226,396 字节，直接复制，PCM 导入，不裁剪、不归一化、不改变采样率或声道。
- 按武器真实 `sound` 选音，覆盖原 84 项随身装备及 17 个车载 / 固定武器槽。近战与手投雷不进入开枪播放路径。
- 移除 `combat_feedback_profile.gd` 的声音、变调、增益字段，保留其后坐和镜头参数。枪声播放速度固定 1；不再按口径降调、给 SMG 升调或额外把消音武器缩小到 35%。原声音表本身没有这些规则。
- 原 master gain 为 0.22。每枪保留 sampleGain、lowpass，距离近区为 90 原单位 / 2.25 m，衰减指数 1.42；步兵、各车载及固定武器的范围、音量倍率按原调用点换算。
- 每次真实 shot 事件触发一次采样，播放完整录音；没有人为压短尾音、随机变调或额外合成爆破层。忙碌时仍允许声音池按优先级抢占。

| 原 sound | 采样 | sampleGain | 低通 Hz |
| --- | --- | ---: | ---: |
| machinePistol | 自动手枪原独立录音（补齐） | 0.60 | 7000 |
| smg | gun_shot | 0.64 | 6100 |
| assaultRifle | gun_shot | 0.78 | 5700 |
| marksmanRifle | sniper_shot | 0.82 | 5000 |
| lightMachineGun | gun_shot | 0.67 | 4400 |
| fixedHmg | macrophage_shot | 0.82 | 3300 |
| autocannon | macrophage_shot | 0.63 | 4000 |
| tankCannon | cannon_shot | 0.84 | 2200 |
| heavyCannon | cannon_shot | 1.00 | 1850 |
| vehicleCanister | shotgun（纠正原误用 cannon） | 0.84 | 2900 |

完整表以生成 JSON 为准。同一原音源的枪械使用原本的音量 / 频段差异，不另造一套音色。

## 原生实现及性能边界

- 保留最多 24 个声音：本地 8、世界 12、爆炸 4。每帧本地和世界各最多开始 8 个声音。开火时不分配声音节点或加载音频。
- 原组限频 11 / 18 / 32 / 58 ms 随声量选择；本地与远处分组限频分开，防止 AI 抢掉玩家开火。滤波器和声像随声道固定预建，换枪不改变其他声音的尾音。
- AudioStreamPlayer 直接播放立体声采样，避免 AudioStreamPlayer3D 额外的镜头距离 / 空间滤波。原版声像参数范围 ±0.82 保留；Godot Panner 和 Web Audio StereoPanner 的声道混合算法不同，因此不宣称最终输出逐采样一致。
- 原版 Web Audio 的低通 Q 使用 dB，转换为 `10^(Q/20)` 后传给 Godot 线性 resonance。Godot 4.6 的 `FILTER_6DB` 实际实现为一个 biquad stage，使用该单级而非两级串联。依据：[Web Audio 低通定义](https://webaudio.github.io/web-audio-api/#filters-characteristics)、[Godot filter 系数](https://github.com/godotengine/godot/blob/4.6/servers/audio/audio_filter_sw.cpp)、[Godot stage 实现](https://github.com/godotengine/godot/blob/4.6/servers/audio/effects/audio_effect_filter.cpp)。
- 原版二维墙厚声学迁移为原生三维遮挡近似：最多每帧 2 条射线，4.5 m 空间格 / 125 ms 缓存，最多 256 条，破坏修订清空。遮挡系数暂为 0.40；音量采用 transmission^0.46、低通采用原 muffle 公式。未移植原二维逐墙厚积分，不影响伤害或 AI 可见性。
- 命中、爆炸与近战采样选择及增益仍沿用当前打击感设置。本轮专门恢复开枪 / 发射音效。

## 交付记录

- 资源检查：101 个目录条目均找到源声音配置；13 个 WAV 哈希与本机原库一致，PCM 导入参数一致。
- 必要的 Godot 4.6.3 资源导入 / 场景编译检查通过。实际连发听感、多人交火混音和性能由用户在原联合演武场试玩；没有自动开枪或用独立音频预览替代游戏验收。
- 原 Tab 选择 M416、AKM、Vector、自动手枪、精确射手步枪与狙击对照；「车辆 / 固定武器」继续使用原立即操作入口。

启动验收：Godot 4.6.3 stable / 项目 v2026.09.29.23，联合演武场，2026-09-29 16:33:22，PID 12764。实际窗口标题已核对，后续进程响应状态为 True；原 Tab 武器库已打开，等待用户试听。
