"""Read original combat actions without modifying the supplied rig or Blender file."""
import bpy, json, math
from pathlib import Path
from mathutils import Matrix

root = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root / 'art/tripo-soldier/source-rig-equipped.blend'))
rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
convert = Matrix.Rotation(math.pi / 2, 4, 'X').inverted()
report = {}
names = ['fall', 'defeat_02', 'defeat_03', 'hit_to_body_01', 'hit_to_body_02', 'hit_to_head', 'hit_to_side', 'hit_to_stomach']
for name in names:
    action = bpy.data.actions['Armature|' + name]
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    start, end = map(int, action.frame_range)
    samples = []
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        points = {bone: [round(x, 5) for x in (convert @ rig.matrix_world @ rig.pose.bones[bone].head)] for bone in ['Hip', 'Spine02', 'Head', 'L_Foot', 'R_Foot']}
        samples.append(points)
    report[name] = {'start': start, 'end': end, 'duration': (end-start)/24, 'samples': samples}
out = root / 'assets/tripo_source/combat-clips.json'
out.write_text(json.dumps(report, separators=(',', ':')), encoding='utf-8')
for name, clip in report.items():
    print(name, 'frames', clip['end'], 'sample(Hip,Head)', [(round(i/(len(clip['samples'])-1), 2), clip['samples'][i]['Hip'], clip['samples'][i]['Head']) for i in [0, len(clip['samples'])//4, len(clip['samples'])//2, len(clip['samples'])-1]])
