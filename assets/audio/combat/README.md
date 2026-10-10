# 本地战斗声音来源

由旧 Pixi 小小战地 `src/audio.js` 的声音映射选取，本轮未联网下载或从游戏安装包提取。

- `shot_hit.wav`、`wall_hit.wav`、`deflect_shot.wav`：`G:/I00009/client/web/Pixi-Battlefield1-Blue/public/assets/audio/sfx/`。
- 枪声、火炮、爆炸、近战采样：`G:/I00009/client/web/Pixi-Pathogenic/reference/pathogenic-original/audio/sfx/shots/` 中与旧声音表同名的本地文件。
- `pistol.wav` 原文件名：`ESM_GW_gun_one_shot_pistol_hi_tech_type_short_laser_tech_small_arm_short_4_long_deep.wav`。
- `rocket.wav` 原文件名：`ESM_SFSG_cinematic_fx_science_fiction_weapon_firearm_launcher_buzz_smooth_recoil_01.wav`。

早期 14 个 WAV 共 3,270,984 字节。v2026.09.29.23 补齐自动手枪等源表采样：枪声部分为 13 个 WAV / 2,226,396 字节，原文件内容直接复制、PCM 导入。`machine_pistol.wav` 对应同目录的 `ESM_GW_gun_one_shot_pistol_hi_tech_type_short_laser_tech_small_arm_short_5_long_deep.wav`。

枪声现在严格读取原武器 `sound` 对应的音源、sampleGain、lowpass，播放速度固定 1，移除早期按口径变调。完整文件名 / SHA-256 及声音表见 `data/source-weapon-audio.json`，可用 `tools/sync_source_weapon_audio.py` 重新导入。运行细节见 [枪声恢复记录](../../../docs/weapon-audio-source.md)。本记录仅说明现有本地素材来源，不声明额外授权或公共领域状态。
