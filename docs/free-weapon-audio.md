# 免费真枪录音接入 · v2026.09.29.28

> 以下为首批历史记录。用户随后要求未覆盖武器也不得使用旧声音；当前 v2026.09.29.30 已完成 [全量免费音效替换](free-combat-audio-complete.md)，本页的「19 项回退」和旧内存数量不再描述当前运行版本。

用户认为现有枪声不够拟真，并要求接入匹配的免费资源。本次使用真实录音替换可匹配的步兵开枪声音，保留原游戏的武器、射速、弹药、伤害和音频预算。未使用商业游戏提取的声音。

## 素材与许可

- [The Free Firearm Sound Library 原始发布](https://opengameart.org/content/the-free-firearm-sound-library)，作者 Ben Jaszczak、Brian Nelson、Kevin Heras、Matthew Nanney。
- 发布页面声明 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)，免费使用，无需版税。项目主动保留作者与来源记录。
- 从 [fps-asset-kit 素材镜像](https://github.com/petroulacl/fps-asset-kit/tree/a19b7458a593598211c95ec46ef4eb4b6d1f94d7) 选择下载原 WAV，固定提交 `a19b7458a593598211c95ec46ef4eb4b6d1f94d7`，逐文件验证 Git blob SHA-1、长度并记录 SHA-256。没有执行该仓库代码。
- `assets/audio/free-firearms/LICENSE.md` 保留许可和署名；`data/free-weapon-audio.json` 记录每个衍生片段的来源 URL、原文件和输出哈希、录音描述、声道与裁切采样坐标。
- 原录音缓存、下载日志和原始发布页面保存在 `qa/audio-free-sources/`，该目录带 `.gdignore` 并从发行包排除。原发布 7z 下载未完成，保留的部分文件不作为有效素材；实际使用的是已逐项验证的 WAV 镜像。

## 匹配范围

共 12 种录制枪型、57 段近 / 中距离单发、65 项游戏武器。**不等于 65 把枪各有原型号实录**；相同弹种也不保证声音完全相同。以下替代关系是本项目明确的声音设计选择，完整 ID 表在 JSON 的 `weapons` 中。

| 原录音枪型 | 代表游戏武器 | 匹配程度与限制 |
| --- | --- | --- |
| AR-15，5.56 mm | M416、M16A4、SCAR-L、AUG、M249 | 5.56 mm 长枪的枪声主体替代；机枪机械声没有单独重建 |
| AK-47，7.62×39 mm | AKM、Beryl、Groza、RPD | AK 类 / 相近弹种替代 |
| Carl Gustav M45，9 mm | MP5K、Micro Uzi、MP9、Vector | 9 mm 冲锋枪替代；并非各型号实录 |
| Walther PPQ，9 mm | P92、P18C、Glock-18、Tec-9 | 9 mm 手枪类替代 |
| 1911，.45 ACP | Tommy Gun、UMP、MAC-10 | 仅借用 .45 枪声主体；不是这些冲锋枪的机械 / 连发实录 |
| Benelli Nova，12 gauge | Nova、S1897、S12K、O12、XM1014 | 12 gauge 霰弹枪主体替代；不代表独头弹或所有动作机构 |
| Mossberg Model 190，12 gauge | S686、DBS、Sawed-off、MAG-7 | 不同机构的 12 gauge 主体替代；内部 bank 名 `pump` 为键名，原录音描述是栓动 Mossberg 190 |
| Mosin，7.62×54R | Kar98k、Dragunov、SLR、Mk14、MG3 | 全威力步枪主体近似；不能称为这些枪各自的实录 |
| Norinco SKS | SKS | 型号家族对应 |
| Tikka T3，.30-06 | M24、AWM、AWP、SSG 08 | 栓动大威力步枪音色近似，尤其不宣称 AWM 的 Magnum 口径对应 |
| Winchester 1894，.32 Winchester Special | Win94 | 型号对应，但与游戏标注弹种不同 |
| S&W 642，.38 Special | R1895、R8 Revolver | 左轮类别近似，非对应型号 / 口径 |

消音 VSS / M4A1-S / MP5-SD / USP-S、P90、MP7、Five-SeveN、Lynx AMR、Deagle、Minigun 和爆炸 / 近战装备等 19 项目录装备保留原实现。所有车载 / 固定武器按 `mounted_fire_key` 优先回退，避免同名 ID 意外套用步兵录音。换弹、弹壳、命中与爆炸音源本轮未替换。

## 播放与处理

`tools/import_free_weapon_audio.py` 离线执行裁切：每个麦克风距离选择 2–3 次不同射击，保留枪口瞬态和短环境尾音。选取一个真实麦克风声道，避免立体声求和相位抵消；55 Hz 去低频杂音，重采样 48 kHz 单声道 PCM16，末尾淡出，峰值保留约 1.72 dB 余量，不变调。

本地始终使用近录音，其他枪声 12 m 内用近录音、外侧用中距离录音，并沿用原音量衰减与墙体遮挡。每组分别维护本地 / 世界轮换游标，一次开枪只播放一个短采样。采样最长 1.70 秒；近 / 中音源不同时叠播，无逐枪实时混响。

新录音使用独立增益与 14.5–16 kHz 基础低通，保留实录的清晰瞬态；遮挡及距离仍可压低频段。保留原 master=0.22、播放速度 1、原枪声组限频；不随机变调伪造新枪型。

## 资源与性能边界

- 57 个片段总 PCM 数据 **6,993,600 bytes（约 6.67 MiB）**，启动一次性预载，开火不访问磁盘。
- WAV 导入明确 `compress/mode=0`，保持 PCM16；不使用 Godot 默认 QOA 压缩。准备脚本同步维护导入参数，避免日后重新生成恢复默认压缩。
- 声音池保持 **24**：本地 8、世界 12、爆炸 4，滤波 / 声像仍复用预建效果。遮挡仍最多每帧 2 条射线并缓存，没有扩张声音节点或 AI 查询。
- 所有变体离线处理；这项资源检查不能证明多人战斗稳定 60 FPS，真实声音、混音平衡及实战性能仍由用户试听确认。

## 验证与验收

`qa/free_weapon_audio_contract.gd` 在禁止处理的原联合演武场执行资源验证：**699 项通过，0 失败**。检查 65 项路由、所有 57 个资源、PCM / 采样率 / 时长 / 非循环 / 哈希、所有距离变体预载、缺失项与车载回退、原表不可变、声道上限及内存预算。整个检查播放次数 0、开枪次数 0、世界时间 0，没有自动操作游戏。

仍使用 `res://proving_ground.tscn`。Tab 武器面板可比较 M416 → AKM → MP5K → P92 → Nova → M24；用户手动开火试听。第一关和演武场2复用同一 `combat_audio.gd`，无需另建音频验收场景。

Release 导出无脚本 / 资源错误，确认新 manifest 已打包、原始缓存未打包、57 项 PCM 导入参数正确。本次验收窗口：项目 v2026.09.29.28 / Godot 4.6.3 stable，联合演武场，窗口启动标识 **2026-09-29 17:14:30，PID 22216**（进程创建于 17:14:29）。已核对实际窗口标题，使用 `--weapon=m416 --armory --no-laya --startup-watch` 打开原配装面板，未自动试听或开枪。
