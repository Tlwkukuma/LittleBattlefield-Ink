"""Preserve the supplied FBX character; author equipment and an editable rig in Blender.

The GLB and the runtime mesh data are exported from the same Blender meshes.
No network or generated replacement character is used.
"""
import bpy, json, math, shutil
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'art/tripo-soldier'
OUT=ROOT/'assets/tripo_soldier'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(next((ART/'source').glob('*.fbx'))))
source=next(o for o in bpy.context.scene.objects if o.type=='MESH')
oldrig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
bpy.context.view_layer.update()
deps=bpy.context.evaluated_depsgraph_get()
mesh=bpy.data.meshes.new_from_object(source.evaluated_get(deps),depsgraph=deps)
old_positions=[source.matrix_world@v.co for v in mesh.vertices]
scale=1.86/(max(p.z for p in old_positions)-min(p.z for p in old_positions))
floor=min(p.z for p in old_positions)
hip=oldrig.matrix_world@oldrig.pose.bones['Hip'].head
def canonical(p):return Vector((-(p.y-hip.y)*scale,(p.z-floor)*scale,-(p.x-hip.x)*scale))
def bvec(p):return Vector((p[0],-p[2],p[1]))
def gvec(p):return Vector((p[0],p[2],-p[1]))
names=['pelvis','left_hip','left_knee','right_hip','right_knee','left_ankle','right_ankle','chest','left_arm','left_forearm','right_arm','right_forearm','neck','left_wrist','right_wrist']
sources=[None,'L_Thigh','L_Calf','R_Thigh','R_Calf','L_Foot','R_Foot','Spine02','L_Upperarm','L_Forearm','R_Upperarm','R_Forearm','Head','L_Hand','R_Hand']
parents=[-1,0,1,0,3,2,4,0,7,8,7,10,7,9,11]
points=[Vector((0,0,0)) if n is None else canonical(oldrig.matrix_world@oldrig.pose.bones[n].head) for n in sources]
def bone_index(n):
    for side,prefix in enumerate(['L_','R_']):
        if n.startswith(prefix):
            if 'Thigh' in n:return 1+side*2
            if 'Calf' in n:return 2+side*2
            if 'Foot' in n or 'Toe' in n:return 5+side
            if 'Upperarm' in n:return 8+side*2
            if 'Forearm' in n:return 9+side*2
            if 'Hand' in n:return 13+side
    if 'Head' in n or 'Neck' in n:return 12
    return 7 if 'Spine' in n or 'Clavicle' in n else 0
groups={g.index:bone_index(g.name) for g in source.vertex_groups}
weights=[]
for v in source.data.vertices:
    merged={}
    for item in v.groups:
        index=groups[item.group];merged[index]=merged.get(index,0)+item.weight
    values=sorted(merged.items(),key=lambda x:-x[1])[:4] or [(0,1)]
    total=sum(w for _,w in values);weights.append([(i,w/total) for i,w in values])
for v,p in zip(mesh.vertices,old_positions):v.co=bvec(canonical(p))
body=bpy.data.objects.new('Soldier_Body',mesh);bpy.context.collection.objects.link(body)
# Evaluated FBX meshes retain deformation-group indices without object labels.
# Remove that layer before assigning the compact rig, or old weights leak in.
for i in range(len(source.vertex_groups)):body.vertex_groups.new(name='old_'+str(i))
body.vertex_groups.clear()
body.data.materials.clear()
base_image=next((ART/'source').rglob('*basecolor*'))
shutil.copy2(base_image,OUT/'body_basecolor.jpg')
mat=bpy.data.materials.new('Original_Uniform_Texture');mat.diffuse_color=(.47,.57,.74,1);mat.use_nodes=True
bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.95
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'body_basecolor.jpg'));mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color']);body.data.materials.append(mat)
for o in [source,oldrig]:bpy.data.objects.remove(o,do_unlink=True)
for action in list(bpy.data.actions):bpy.data.actions.remove(action)
rigdata=bpy.data.armatures.new('Soldier_Rig');rig=bpy.data.objects.new('Soldier_Rig',rigdata);bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for i,n in enumerate(names):
    bone=rigdata.edit_bones.new(n);bone.head=bvec(points[i]);bone.tail=bone.head+Vector((0,0,.10));bone.roll=0
    if parents[i]>=0:bone.parent=rigdata.edit_bones[names[parents[i]]]
bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
for n in names:body.vertex_groups.new(name=n)
for i,items in enumerate(weights):
    for bone,weight in items:body.vertex_groups[bone].add([i],weight,'REPLACE')
mod=body.modifiers.new('Skin','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=True
body.parent=rig
for p in body.data.polygons:p.use_smooth=True

def material(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*color,1);m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.88;return m
blue=material('Helmet_BlueGrey',(.46,.56,.72));band=material('Team_Blue',(.08,.26,.62));edge=material('Helmet_Rim',(.34,.43,.59));olive=material('Canvas_Olive',(.34,.35,.22));olive_light=material('Canvas_Flap',(.42,.43,.28));leather=material('Webbing_Dark',(.12,.10,.14));metal=material('Rifle_Graphite',(.13,.14,.18));steel=material('Rifle_Steel',(.31,.34,.41))
def box(name,at,size,mat,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=bvec(at));o=bpy.context.object;o.name=name;o.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
    if bevel:
        m=o.modifiers.new('Soft_Edges','BEVEL');m.width=bevel;m.segments=3;bpy.ops.object.modifier_apply(modifier=m.name)
        m=o.modifiers.new('Weighted_Normals','WEIGHTED_NORMAL');m.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=m.name)
    return o
def loft(name,center,profiles,mat,segments=48):
    vertices=[];faces=[]
    for y,rx,rz in profiles:
        for i in range(segments):
            a=i*math.tau/segments;vertices.append(bvec(Vector(center)+Vector((rx*math.cos(a),y,rz*math.sin(a)))))
    for j in range(len(profiles)-1):
        for i in range(segments):
            k=j*segments+i;l=j*segments+(i+1)%segments;faces.append((k,k+segments,l+segments,l))
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update();o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.data.materials.append(mat)
    for p in data.polygons:p.use_smooth=True
    return o
def cylinder(name,at,radius,length,mat,axis='X'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=radius,depth=length,location=bvec(at));o=bpy.context.object;o.name=name
    o.rotation_euler[1 if axis=='X' else 0]=math.pi/2
    o.data.materials.append(mat);m=o.modifiers.new('Rounded_Ends','BEVEL');m.width=.009;m.segments=3;bpy.ops.object.modifier_apply(modifier=m.name)
    for p in o.data.polygons:p.use_smooth=True
    return o
def join(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=objects[0];o.name=name
    bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);return o
def rigid_bind(o,bone):
    o.parent=rig;g=o.vertex_groups.new(name=names[bone]);g.add(list(range(len(o.data.vertices))),1,'REPLACE');m=o.modifiers.new('Follow_Bone','ARMATURE');m.object=rig

# Full dome and closed inner rim; helmet can be detached as one object.
headverts=[canonical(p) for p,w in zip(old_positions,weights) if any(i==12 and v>.8 for i,v in w)]
head_top=max(p.y for p in headverts);hx=(max(p.x for p in headverts)+min(p.x for p in headverts))/2;hz=(max(p.z for p in headverts)+min(p.z for p in headverts))/2
helmet_base=head_top-.31;hrx=(max(p.x for p in headverts)-min(p.x for p in headverts))/2+.035;hrz=(max(p.z for p in headverts)-min(p.z for p in headverts))/2+.035
hc=Vector((hx,helmet_base,hz));helmet_parts=[]
helmet_parts.append(loft('Helmet_Shell',hc,[(0,hrx*1.06,hrz*1.06),(.025,hrx*1.08,hrz*1.08),(.06,hrx,hrz),(.16,hrx*.97,hrz*.97),(.25,hrx*.82,hrz*.82),(.32,hrx*.57,hrz*.57),(.365,hrx*.15,hrz*.15),(.37,.001,.001)],blue))
helmet_parts.append(loft('Helmet_Team_Band',hc,[(.072,hrx*1.01,hrz*1.01),(.119,hrx*.995,hrz*.995)],band))
helmet_parts.append(loft('Helmet_Inner_Rim',hc,[(0,hrx*1.06,hrz*1.06),(-.008,hrx*1.055,hrz*1.055),(-.008,hrx*.92,hrz*.92),(.065,hrx*.92,hrz*.92)],edge))
helmet=join(helmet_parts,'Helmet_Detachable');rigid_bind(helmet,12);helmet['detachable_on_headshot']=True
chest=points[7];backz=.22;packy=chest.y+.06
packparts=[box('Backpack_Main',(0,packy,backz),(.47,.50,.24),olive,.065),box('Backpack_Flap',(0,packy+.16,backz+.03),(.49,.19,.26),olive_light,.045),box('Backpack_FrontPocket',(0,packy-.07,backz+.135),(.33,.22,.09),olive_light,.025)]
for side in [-1,1]:
    packparts.append(box('Pack_SidePocket',(side*.275,packy-.035,backz),(.13,.28,.20),olive_light,.04))
    packparts.append(box('Pack_VerticalStrap',(side*.16,packy,backz+.155),(.045,.47,.02),leather,.008))
    packparts.append(box('Strap_Buckle',(side*.16,packy-.10,backz+.17),(.065,.060,.027),steel,.008))
packparts.append(cylinder('Bedroll',(0,packy+.35,backz),.12,.61,olive_light))
for side in [-1,1]:
    packparts.append(cylinder('Bedroll_Strap',(side*.19,packy+.35,backz),.124,.040,leather))
    packparts.append(cylinder('Bedroll_End',(side*.31,packy+.35,backz),.090,.006,olive))
    packparts.append(cylinder('Bedroll_Center',(side*.315,packy+.35,backz),.045,.008,olive_light))
pack=join(packparts,'Backpack');rigid_bind(pack,7)

# Small rifle proxy for Blender posing; Godot retains the existing weapon library.
rifle_origin=Vector((.04,1.16,-.31))
gunparts=[box('Receiver',rifle_origin,(.07,.105,.28),metal,.012),box('Handguard',rifle_origin+Vector((0,.015,-.24)),(.066,.086,.23),steel,.009),box('Stock',rifle_origin+Vector((0,-.006,.27)),(.066,.095,.22),metal,.012),box('Pistol_Grip',rifle_origin+Vector((0,-.105,.085)),(.048,.15,.065),leather,.009),box('Magazine',rifle_origin+Vector((0,-.13,-.045)),(.052,.19,.085),metal,.009),cylinder('Barrel',rifle_origin+Vector((0,.016,-.455)),.015,.20,metal,'Z')]
rifle=join(gunparts,'Rifle_Pose_Prop')
grips=[rifle_origin+Vector((-.050,-.052,-.18)),rifle_origin+Vector((.03,-.075,.075))]
def joint(s,t,p,a,b):
    axis=(t-s).normalized();d=max(abs(a-b)+.001,min((t-s).length,a+b-.002));along=(a*a-b*b+d*d)/(2*d);perp=p-s-axis*(p-s).dot(axis);return s+axis*along+perp.normalized()*math.sqrt(max(0,a*a-along*along))
def pose_rotation(index,q):
    # Bones point up in Blender, so their local axes equal canonical Godot axes.
    rig.pose.bones[names[index]].rotation_mode='QUATERNION';rig.pose.bones[names[index]].rotation_quaternion=q
armrots={}
for side in [0,1]:
    s,e,w=points[8+side*2],points[9+side*2],points[13+side]
    elbow=joint(s,grips[side],e+Vector((-.24 if side==0 else .24,-.18,.08)),(e-s).length,(w-e).length)
    upper=(e-s).rotation_difference(elbow-s);lower=(w-e).rotation_difference(grips[side]-elbow)
    armrots[8+side*2]=upper;armrots[9+side*2]=upper.inverted()@lower;armrots[13+side]=lower.inverted()
for index,q in armrots.items():pose_rotation(index,q)

def mesh_json(o,kind):
    data=o.data;data.calc_loop_triangles();uv=data.uv_layers.active;result=dict(vertices=[],normals=[],uvs=[],bones=[],weights=[],colors=[],indices=[])
    for tri in data.loop_triangles:
        for loop_id in tri.loops:
            loop=data.loops[loop_id];v=data.vertices[loop.vertex_index];p=gvec(o.matrix_world@v.co);normal=gvec(o.matrix_world.to_3x3()@data.corner_normals[loop_id].vector).normalized()
            result['vertices'].extend(round(x,6) for x in p);result['normals'].extend(round(x,6) for x in normal)
            coords=uv.data[loop_id].uv if uv else (0,0);result['uvs'].extend([float(coords[0]),1-float(coords[1])])
            if kind=='body':vw=weights[loop.vertex_index]
            else:vw=[(12 if kind=='helmet' else 7,1)]
            vw=vw+[(0,0)]*(4-len(vw));result['bones'].extend(i for i,w in vw);result['weights'].extend(round(w,6) for i,w in vw)
            color=data.materials[tri.material_index].diffuse_color;result['colors'].extend(list(color))
        start=len(result['indices']);result['indices'].extend([start,start+2,start+1])
    (OUT/(kind+'.mesh.json')).write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
for o,kind in [(body,'body'),(helmet,'helmet'),(pack,'backpack')]:mesh_json(o,kind)
metadata=dict(source='User-supplied Tripo FBX',bones=names,parents=parents,points=[list(p) for p in points],grips=[list(p) for p in grips],rifle_rest=list(rifle_origin),helmet_center=list(hc+Vector((0,.16,0))),triangles={o.name:len(o.data.polygons) for o in [body,helmet,pack]},height=1.86)
(OUT/'rig.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')

# Editable breathing/holding action. Source mesh and paint are preserved.
scene=bpy.context.scene;scene.render.fps=30;scene.frame_start=1;scene.frame_end=60
for frame in [1,16,31,46,60]:
    scene.frame_set(frame)
    breath=math.sin((frame-1)/59*math.tau)
    for index,q in armrots.items():
        pose_rotation(index,q)
        rig.pose.bones[names[index]].keyframe_insert('rotation_quaternion',frame=frame,group=names[index])
    rig.pose.bones['chest'].location=(0,.005*breath,0);rig.pose.bones['chest'].keyframe_insert('location',frame=frame)
if rig.animation_data and rig.animation_data.action:rig.animation_data.action.name='Rifle_Hold'
scene.frame_set(1)
for image in bpy.data.images:
    if image.source=='FILE':image.pack()
bpy.ops.object.select_all(action='DESELECT')
for o in [rig,body,helmet,pack,rifle]:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'soldier.glb'),export_format='GLB',use_selection=True,export_animations=True,export_skins=True)

# Render stage belongs only to the editable Blender file.
groundmat=material('Studio_Floor',(.56,.55,.65));box('Studio_Floor',(0,-.065,0),(200,.1,200),groundmat,0)
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.62,.64,.72,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast' if False else 'None'
def area(name,at,energy,size):
    bpy.ops.object.light_add(type='AREA',location=bvec(at));o=bpy.context.object;o.name=name;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(bvec((0,1,0))-o.location).to_track_quat('-Z','Y').to_euler()
area('Key_Softbox',(3,5,-4),320,5);area('Fill_Softbox',(-3,3,-1),100,4)
bpy.ops.object.camera_add(location=bvec((3.8,3.1,-6)));cam=bpy.context.object;cam.name='Portrait_Camera';cam.rotation_euler=(bvec((0,1,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.7;scene.camera=cam
scene.render.resolution_x=1000;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'soldier-equipped.blend'))
scene.render.filepath=str(ART/'soldier-equipped.png');bpy.ops.render.render(write_still=True)
print('TRIPO_EXPORT',json.dumps(metadata))
