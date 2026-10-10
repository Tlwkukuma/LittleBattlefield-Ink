# Tripo 小兵：原骨骼、原动作与线稿渲染

当前使用用户提供的 Tripo 模型，保留原身体 9688 个三角面、UV、41 根骨骼、蒙皮权重、绑定矩阵及 20 段原动作。旧版 15 骨骼重绑已停用。

## 当前文件

- `art/tripo-soldier/source-rig-equipped.blend`：可编辑 Blender 文件，贴图打包，打开后为 Rifle_walk。空格播放；选择 Armature|walk 可查看原走路动作。
- `OPEN_BLENDER_CHARACTER.bat`：打开上述文件。
- `assets/tripo_source/source-rig-soldier.glb`：Godot 当前原生模型及动画。
- `assets/tripo_source/provenance.json`：原数据保留检查与原动画脚部采样。
- `tools/build_source_rig_soldier.py`：重建当前资产。会覆盖生成文件，手工加工前请另存副本。
- `scripts/source_rig_character.gd` / `source_rig_motion.gd`：原生模型载入与动作驱动。

原 20 段动作全部保留。Rifle_idle、Rifle_walk、Rifle_run、Rifle_jump 使用原 fire 中的上半身持枪姿态；腿、脚踝、脚趾和躯干曲线保持原样。游戏按移动距离推进步态，消除前向根位移与物理移动的叠加。原文件没有蹲伏、卧倒和翻越，这些状态在原骨骼上另加调整。

Godot 按原始 24 FPS 导入，关闭动画轨道优化和压缩，避免脚部关键帧被简化。Helmet_Detachable 和 Backpack 分别附着原 Head 和 Spine02 骨骼；Rifle_Pose_Prop 用于 Blender 持枪校准，游戏替换为武器库模型。旧 tripo_character.gd、assets/tripo_soldier/ 和 soldier-equipped.blend 保留作历史文件。

## 线稿风格

Godot 的 tripo_character.gdshader 将原贴图转为场景一致的灰紫纸色、墨线轮廓及断续排线，保留眼睛、头发、衣缝和口袋的识别信息；我方军装偏蓝、敌方军装偏红，头盔与背包同步带阵营色调，色带进一步加强区分。头盔、背包使用同一材质，脱落头盔继承线稿效果。character_outline.gdshader 提供随骨骼变形的像素宽度轮廓。武器沿用场景已有线稿材质。Blender 源文件保留彩色材质，线稿表现位于 Godot 渲染层。

## 体验

START_RANGE.bat 打开演武场，START_CHARACTER.bat 打开角色近景。WASD 移动、Shift 快跑、空格跳跃/翻越、C 蹲伏、Z 卧倒、F1 切换近景。近景 H 演示掉帽，F5 重置。

演武场头部命中造成 2 倍伤害，首次头部命中使头盔飞出、旋转、弹跳并落地；躯干命中不脱帽。尸体保持脱帽，补给或重生恢复。使用地面/墙体简化碰撞，最多保留 24 顶、60 秒回收。

## 本轮记录

恢复原骨骼后，Godot 待机/走路/跑步与 Blender 原脚掌、脚趾位置最大偏差约 0.00000631 米；持枪副本与原动作腿脚位置偏差为 0。头盔回归 141/141、翻越回归 63/63、84 种武器构建通过。

追加持枪跳跃、动作切换位移修正和线稿材质后，按用户要求停止自动演武场测试，打开实际场景供用户体验；上述数字不代表这些最后调整已经人工验收。线稿版本尚未重新测百人性能。

