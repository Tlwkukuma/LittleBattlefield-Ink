import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[1];art=root/'art/tripo-soldier'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(next((art/'source').glob('*.fbx'))))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
def curves(a):
    if hasattr(a,'fcurves'):return list(a.fcurves)
    return [fc for layer in a.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
actions=[]
for a in bpy.data.actions:
    fc=curves(a);paths=sorted(set(c.data_path for c in fc))
    actions.append(dict(name=a.name,range=list(a.frame_range),curves=len(fc),keys=sum(len(c.keyframe_points) for c in fc),paths=paths))
report=dict(fps=bpy.context.scene.render.fps,frame=bpy.context.scene.frame_current,active=rig.animation_data.action.name if rig.animation_data and rig.animation_data.action else None,bones=len(rig.data.bones),actions=actions,nla=[t.name for t in rig.animation_data.nla_tracks] if rig.animation_data else [])
(art/'source-actions.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='actions'}))
for a in actions:print(a['name'],a['range'],a['curves'],a['keys'])
bpy.ops.export_scene.gltf(filepath=str(art/'source-original.glb'),export_format='GLB',export_animations=True,export_animation_mode='ACTIONS')
