import bpy,math,json
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1];out=root/'art/tripo-soldier'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(next((out/'source').glob('*.fbx'))))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');body=next(o for o in bpy.context.scene.objects if o.type=='MESH')
for p in body.data.polygons:p.use_smooth=True
mat=body.data.materials[0];bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Metallic'].default_value=0
for sock in ['Metallic','Normal']:
    for link in list(bs.inputs[sock].links):mat.node_tree.links.remove(link)
bs.inputs['Roughness'].default_value=.9
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=12;s.world=bpy.data.worlds.new('Preview');s.world.use_nodes=True;s.world.node_tree.nodes['Background'].inputs[0].default_value=(.6,.6,.65,1);s.world.node_tree.nodes['Background'].inputs[1].default_value=.8;s.view_settings.view_transform='Standard'
bpy.ops.object.camera_add(location=(2,-2.5,1.6));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.45))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=1.2;s.camera=cam
bpy.ops.object.light_add(type='AREA',location=(2,-1,3));bpy.context.object.data.energy=80;bpy.context.object.data.size=4
s.render.resolution_x=600;s.render.resolution_y=700;s.render.resolution_percentage=100
result={}
for clip,frame in [('idle',1),('walk',1),('walk',15),('fire',12),('run',8)]:
    action=bpy.data.actions['Armature|'+clip];rig.animation_data.action=action;s.frame_set(frame);bpy.context.view_layer.update()
    result[clip+str(frame)]={n:list(rig.matrix_world@rig.pose.bones[n].head) for n in ['L_Foot','R_Foot','L_Hand','R_Hand','Head','Spine02']}
    s.render.filepath=str(out/('original-'+clip+'-'+str(frame)+'.png'));bpy.ops.render.render(write_still=True)
(out/'source-clip-poses.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
