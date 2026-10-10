"""Keep the supplied 41-bone FBX rig, skin weights and all 20 source actions.
Only equipment and upper-body rifle layers are authored; leg curves are untouched.
"""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];ART=ROOT/'art/tripo-soldier';OUT=ROOT/'assets/tripo_source';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(next((ART/'source').glob('*.fbx'))))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');body=next(o for o in bpy.context.scene.objects if o.type=='MESH');body.name='Source_Body';rig.name='Source_Armature'
scene=bpy.context.scene;original_actions=list(bpy.data.actions)
def curves(action):
    return [(bag,fc) for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
def curve_signature(action,legs_only=False):
    values=[]
    for _,fc in curves(action):
        if legs_only and any(k in fc.data_path for k in ['Clavicle','Upperarm','Forearm','Hand']):continue
        values.append((fc.data_path,fc.array_index,[(list(k.co),list(k.handle_left),list(k.handle_right),k.interpolation) for k in fc.keyframe_points]))
    return hashlib.sha256(json.dumps(sorted(values)).encode()).hexdigest()
original_signatures={a.name:curve_signature(a) for a in original_actions}
weight_signature=hashlib.sha256(json.dumps([[(g.group,g.weight) for g in v.groups] for v in body.data.vertices]).encode()).hexdigest()
rest_signature=hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in rig.data.bones]).encode()).hexdigest()
def select_action(action,frame):
    rig.animation_data.action=action
    if action.slots:rig.animation_data.action_slot=action.slots[0]
    scene.frame_set(int(frame));bpy.context.view_layer.update()
idle=bpy.data.actions['Armature|idle'];fire=bpy.data.actions['Armature|fire'];select_action(idle,1)
# Constant coordinate conversion is placed above the original rig, not baked into it.
scale=1.86/(max(v.co.z for v in body.data.vertices)-min(v.co.z for v in body.data.vertices))
floor=min(v.co.z for v in body.data.vertices);root_head=rig.data.bones['Root'].head_local.copy()
C=Matrix.Translation(Vector((root_head.y*scale,-root_head.x*scale,-floor*scale)))@Matrix.Rotation(math.pi/2,4,'Z')@Matrix.Scale(scale,4)
B=Matrix.Rotation(math.pi/2,4,'X') # Godot metres -> Blender world metres.
def godot(p):return B.inverted()@p
def worldpoint(name):return godot(C@rig.matrix_world@rig.pose.bones[name].head)
def worldmatrix(name):return B.inverted()@C@rig.matrix_world@rig.pose.bones[name].matrix
idle_head=worldpoint('Head');idle_chest=worldpoint('Spine02')

# Use the supplied fire pose for the rifle layer, including twist bones and hands.
select_action(fire,12)
upper_names=[b.name for b in rig.pose.bones if any(k in b.name for k in ['Clavicle','Upperarm','Forearm','Hand'])]
upper={n:(rig.pose.bones[n].location.copy(),rig.pose.bones[n].rotation_quaternion.copy(),rig.pose.bones[n].scale.copy()) for n in upper_names}
fire_chest=worldmatrix('Spine02')
palms=[]
for name in ['L_Hand','R_Hand']:
    pb=rig.pose.bones[name];palms.append(godot(C@rig.matrix_world@(pb.head+(pb.tail-pb.head)*.45)))
forward=(palms[0]-palms[1]);forward.y=0;forward.normalize();yaw=math.atan2(-forward.x,-forward.z)
gun_basis=Matrix.Rotation(yaw,4,'Y');gun_origin=palms[1]-gun_basis.to_3x3()@Vector((0,-.085,.085));gun_matrix=Matrix.Translation(gun_origin)@gun_basis
gun_chest_local=fire_chest.inverted()@gun_matrix
derived=[];checks={}
for name in ['idle','walk','run','jump']:
    source=bpy.data.actions['Armature|'+name];action=source.copy();action.name='Rifle_'+name
    for bag,fc in list(curves(action)):
        if any(('pose.bones["'+n+'"]') in fc.data_path for n in upper_names):bag.fcurves.remove(fc)
    select_action(action,action.frame_range[0])
    start,end=source.frame_range
    for frame in [int(start),int(end)]:
        scene.frame_set(frame)
        for n,(loc,quat,scl) in upper.items():
            pb=rig.pose.bones[n];pb.location=loc;pb.rotation_mode='QUATERNION';pb.rotation_quaternion=quat;pb.scale=scl
            for prop in ['location','rotation_quaternion','scale']:pb.keyframe_insert(prop,frame=frame,group=n)
    checks[name]=curve_signature(source,True)==curve_signature(action,True)
    derived.append(action)

# Reuse independently authored equipment, fitted in the original idle pose.
select_action(idle,1)
with bpy.data.libraries.load(str(ART/'soldier-equipped.blend'),link=False) as (available,loaded):
    loaded.objects=[n for n in ['Helmet_Detachable','Backpack','Rifle_Pose_Prop'] if n in available.objects]
oldmeta=json.loads((ROOT/'assets/tripo_soldier/rig.json').read_text())
parts={}
for o in loaded.objects:
    bpy.context.collection.objects.link(o);name=o.name.split('.')[0];parts[name]=o
    o.parent=None;o.animation_data_clear();o.modifiers.clear();o.vertex_groups.clear();o.matrix_world=Matrix.Identity(4)
    for poly in o.data.polygons:poly.use_smooth=True
    if name=='Helmet_Detachable':
        delta=idle_head-Vector(oldmeta['points'][12]);pivot=Vector(oldmeta['helmet_center'])+delta;bind='Head'
    elif name=='Backpack':
        delta=idle_chest-Vector(oldmeta['points'][7]);pivot=Vector((0,idle_chest.y+.06,.22));bind='Spine02'
    else:
        bind='Spine02';pivot=Vector(oldmeta['rifle_rest']);delta=Vector((0,0,0))
    for v in o.data.vertices:v.co=B@(godot(v.co)+delta-pivot)
    if name=='Rifle_Pose_Prop':desired=C.inverted()@B@(worldmatrix('Spine02')@gun_chest_local)
    else:desired=C.inverted()@B@Matrix.Translation(pivot)
    o.parent=rig;o.parent_type='BONE';o.parent_bone=bind;bpy.context.view_layer.update();o.matrix_world=desired@B.inverted()
    o['source_bone']=bind

alignment=bpy.data.objects.new('Character_Alignment',None);bpy.context.collection.objects.link(alignment);alignment.matrix_world=C;rig.parent=alignment
for action in list(bpy.data.actions):
    if action not in original_actions and action not in derived:bpy.data.actions.remove(action)
# Matte display uses the supplied base-color texture; source weights/geometry stay intact.
for mat in body.data.materials:
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for socket in ['Metallic','Normal']:
        for link in list(bs.inputs[socket].links):mat.node_tree.links.remove(link)
    bs.inputs['Metallic'].default_value=0;bs.inputs['Roughness'].default_value=.95
for p in body.data.polygons:p.use_smooth=True

# Provenance: unchanged source curves, rest matrices and per-vertex weights.
assert len(rig.data.bones)==41
assert all(original_signatures[a.name]==curve_signature(a) for a in original_actions)
assert all(checks.values())
assert rest_signature==hashlib.sha256(json.dumps([(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in rig.data.bones]).encode()).hexdigest()
assert weight_signature==hashlib.sha256(json.dumps([[(g.group,g.weight) for g in v.groups] for v in body.data.vertices]).encode()).hexdigest()
report=dict(bones=41,original_actions=[a.name for a in original_actions],derived_actions=[a.name for a in derived],source_actions_unchanged=True,skin_weights_unchanged=True,rest_matrices_unchanged=True,lower_body_curves_unchanged=checks,scale=scale,fps=scene.render.fps,clips={})
# Measure displacement and collect exact source pose samples for engine comparison.
for short in ['idle','walk','run','jump','fall','fire','defeat_02']:
    a=bpy.data.actions['Armature|'+short];sample=[];start,end=map(int,a.frame_range)
    for frame in range(start,end+1):
        select_action(a,frame)
        sample.append({n:[list(row) for row in (B.inverted()@rig.matrix_world@rig.pose.bones[n].matrix)] for n in ['Root','Hip','L_Foot','R_Foot','L_ToeBase','R_ToeBase']})
    # rig.matrix_world already includes the static alignment here.
    first=Vector((sample[0]['Hip'][0][3],sample[0]['Hip'][1][3],sample[0]['Hip'][2][3]));last=Vector((sample[-1]['Hip'][0][3],sample[-1]['Hip'][1][3],sample[-1]['Hip'][2][3]));distance=Vector((last.x-first.x,0,last.z-first.z)).length
    report['clips'][short]=dict(start=start,end=end,duration=(end-start)/scene.render.fps,distance=distance,samples=sample)
(OUT/'provenance.json').write_text(json.dumps(report,separators=(',',':')),encoding='utf-8')
select_action(bpy.data.actions['Rifle_idle'],1)
scene.frame_start=1;scene.frame_end=57
for image in bpy.data.images:
    if image.source=='FILE':image.pack()
bpy.ops.object.select_all(action='DESELECT')
for o in [alignment,rig,body,*parts.values()]:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'source-rig-soldier.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_def_bones=False)

# Editable file opens on the original walk, with the rifle layer as a separate action.
select_action(bpy.data.actions['Rifle_walk'],1)
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.6,.62,.68,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7;scene.view_settings.view_transform='Standard'
bpy.ops.mesh.primitive_plane_add(size=200);ground=bpy.context.object;ground.name='Studio_Floor'
mat=bpy.data.materials.new('Studio_Floor');mat.diffuse_color=(.55,.54,.64,1);ground.data.materials.append(mat)
bpy.ops.object.light_add(type='AREA',location=B@Vector((3,5,-4)));light=bpy.context.object;light.data.energy=300;light.data.size=5
bpy.ops.object.camera_add(location=B@Vector((3.8,3.1,-6)));cam=bpy.context.object;cam.rotation_euler=(B@Vector((0,1,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.8;scene.camera=cam
scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
text=bpy.data.texts.new('READ_ME_原骨骼与动作');text.write('原始 41 根骨骼、20 段动作及蒙皮权重均保留。\n当前 Rifle_walk 只替换锁骨以下持枪姿态，根节点、腿、脚踝、脚趾曲线与原 walk 完全相同。\n切换到 Armature|walk 可播放原始动作；空格播放时间轴。\n')
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'source-rig-equipped.blend'))
scene.render.filepath=str(ART/'source-rig-equipped.png');bpy.ops.render.render(write_still=True)
print('SOURCE_RIG_PRESERVED',json.dumps({k:v for k,v in report.items() if k!='clips'}))
