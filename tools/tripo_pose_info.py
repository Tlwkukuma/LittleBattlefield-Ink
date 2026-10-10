import bpy,json
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];path=root/'art/tripo-soldier'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(next((path/'source').glob('*.fbx'))))
a=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
bpy.context.view_layer.update()
info={b.name:dict(head=list(a.matrix_world@b.head),tail=list(a.matrix_world@b.tail),parent=b.parent.name if b.parent else None) for b in a.pose.bones}
(path/'posed-joints.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
print(json.dumps(info))
