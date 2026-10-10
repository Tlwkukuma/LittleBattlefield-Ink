import bpy, json, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art/tripo-soldier'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(next((OUT/'source').glob('*.fbx'))))
info=[]
for o in bpy.context.scene.objects:
    item=dict(name=o.name,type=o.type,location=list(o.location),rotation=list(o.rotation_euler),scale=list(o.scale))
    if o.type=='MESH':
        item.update(vertices=len(o.data.vertices),polygons=len(o.data.polygons),materials=[m.name for m in o.data.materials],bounds=[list(o.matrix_world@Vector(v)) for v in o.bound_box],groups=[g.name for g in o.vertex_groups])
    if o.type=='ARMATURE':item['bones']=[dict(name=b.name,head=list(b.head_local),tail=list(b.tail_local)) for b in o.data.bones]
    info.append(item)
(OUT/'source-inspection.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
points=[o.matrix_world@Vector(v) for o in bpy.context.scene.objects if o.type=='MESH' for v in o.bound_box]
lo=Vector(tuple(min(v[k] for v in points) for k in range(3)));hi=Vector(tuple(max(v[k] for v in points) for k in range(3)));center=(lo+hi)*.5;size=max(hi-lo)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=20
scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.55,.62,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7
scene.view_settings.view_transform='Standard'
bpy.ops.object.camera_add(location=center+Vector((size*1.6,-size*2.5,size*1.1)))
cam=bpy.context.object;cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=size*1.25;scene.camera=cam
bpy.ops.object.light_add(type='AREA',location=center+Vector((size,-size*2,size*3)));bpy.context.object.data.energy=700; bpy.context.object.data.shape='DISK';bpy.context.object.data.size=size*2
scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.filepath=str(OUT/'source-preview.png');bpy.ops.render.render(write_still=True)
print('SOURCE_INFO',json.dumps(info))
