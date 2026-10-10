extends Node3D
## Same source skin and class geometry, drawn by class using a shared bone palette.
## Original scene nodes remain the authoritative animation/muzzle/hit-shape owners.
const CAPACITY=128
const BONES=64
const Classes=preload("res://scripts/soldier_classes.gd")
var palette: Image
var texture: ImageTexture
var groups: Dictionary={}
var entries: Dictionary={}
var templates: Dictionary={}
var free_slots: Array=[]
var shaders: Dictionary={}
var bounds=AABB(Vector3(-128,-64,-128),Vector3(256,256,256))
var last_ms=0.0
var skin_uploads=0
var shadows: MultiMesh
var camera: Camera3D
var screen_rect=Rect2()

func _process(_delta: float):refresh()

func configure(views: Array,units: Array):
	palette=Image.create(3,CAPACITY*BONES,false,Image.FORMAT_RGBAF);texture=ImageTexture.create_from_image(palette)
	build_shadows(views[0].shadow.mesh)
	for slot in range(CAPACITY-1,-1,-1):free_slots.append(slot)
	for index in range(views.size()):
		var view: Dictionary=views[index];Classes.apply(view,str(units[index].get("class_id","assault")),int(units[index].team))
		var role=str(view.class_key).get_slice("/",0);var team=int(units[index].team)
		if not templates.has(role):templates[role]={}
		templates[role][team]=view
	# One shared body/helmet plus the five small profession kits. Selecting a kit
	# collapses only the other kits' triangles; body UVs and skin stay original.
	# Prepare missing teams/roles at entry, never on the first class switch.
	var temporary=[]
	for role in Classes.IDS:
		if not templates.has(role):templates[role]={}
		for team in [0,1]:
			if templates[role].has(team):continue
			var view=preload("res://scripts/ink_art.gd").soldier(self,team,false,false)
			Classes.apply(view,role,team);templates[role][team]=view;temporary.append(view.root)
	build_group("shared",templates.assault[0],templates.assault[1])
	# Dropped helmets keep their exact original geometry and shader, but no longer
	# submit the body/backpack vertices that the shader would merely collapse.
	build_group("helmets",templates.assault[0],templates.assault[1],true)
	for node in temporary:node.free()
	templates.clear()
	for index in range(views.size()):register(views[index],int(units[index].team))
	refresh()

func shader_for(outline: bool) -> Shader:
	if shaders.has(outline):return shaders[outline]
	var code=FileAccess.get_file_as_string("res://shaders/character_outline.gdshader" if outline else "res://shaders/tripo_character.gdshader")
	var include="\n#include \"res://shaders/crowd_skin.gdshaderinc\"\n"
	code=code.replace("uniform vec4 ink",include+"uniform vec4 ink")
	var posing="\n\tcrowd_style=CUSTOM0;crowd_team=INSTANCE_CUSTOM.y;crowd_color=mix(COLOR.rgb,CUSTOM1.rgb,crowd_team);crowd_rest_normal=NORMAL;\n\tmat4 pose=crowd_pose(int(INSTANCE_CUSTOM.x),BONE_INDICES,BONE_WEIGHTS);VERTEX=(pose*vec4(VERTEX,1.0)).xyz;NORMAL=normalize(mat3(pose)*NORMAL);\n\tif (CUSTOM0.y>0.5 && INSTANCE_CUSTOM.z>0.5) VERTEX=vec3(0.0);\n"
	var skipped="INSTANCE_CUSTOM.w<-.5 || (CUSTOM0.z>.5 && abs(CUSTOM0.z-mod(INSTANCE_CUSTOM.w,8.0))>.25) || (INSTANCE_CUSTOM.w>7.5 && CUSTOM0.y<.5)"
	posing="if("+skipped+"){VERTEX=vec3(0.0);NORMAL=vec3(0.0,1.0,0.0);}else{"+posing+"}\n"
	if outline:
		code=code.replace("void vertex() {","void vertex() {"+posing)
		code=code.replace("void fragment() { ALBEDO=ink.rgb; }","void fragment() { if (crowd_style.x>1.5) discard; ALBEDO=ink.rgb; }")
	else:
		code=code.replace("void fragment() {","void vertex() {"+posing+"}\nvoid fragment() {\n\tbool use_texture=crowd_style.x<0.5;")
		code=code.replace("vec3 color=textured ? texture(base_texture,UV).rgb : COLOR.rgb;","vec3 color=use_texture ? texture(base_texture,UV).rgb : crowd_color;")
		code=code.replace("if (!textured && from_material) color=solid_color.rgb;", "")
		# Keep the authored texture ink; remove four texture-gradient taps per pixel.
		var edge_start=code.find("\tif (textured) {")
		var edge_end=code.find("\n\tfloat facing=",edge_start)
		if edge_start>=0 and edge_end>edge_start:code=code.substr(0,edge_start)+code.substr(edge_end)
		code=code.replace("smoothstep(.07,.20,facing))*.50","smoothstep(.06,.24,facing))*.72")
		code=code.replace("if (textured)","if (use_texture)").replace("textured ?","use_texture ?").replace("!textured &&","!use_texture &&")
		code=code.replace("uniform vec4 team_paper", "uniform vec4 red_paper : source_color = vec4(1.0);\nuniform vec4 team_paper")
		code=code.replace("team_paper.rgb","mix(team_paper.rgb,red_paper.rgb,crowd_team)").replace("red_team ?","crowd_team>0.5 ?")
		var ink="\n\tif(crowd_style.x>1.5) {\n\t\tfloat slope=1.0-abs(crowd_rest_normal.y);float h=(1.0-smoothstep(.35,.95,mod(coordinate,3.2)))*broken*slope;\n\t\tfloat grain=fract(sin(dot(floor(FRAGCOORD.xy),vec2(12.9898,78.233)))*43758.5453);\n\t\tALBEDO=crowd_color*(1.0-h*.14)+(grain-.5)*.018*.35;\n\t\tALBEDO=mix(vec3(.10,.085,.15),ALBEDO,smoothstep(.04,.24,facing));\n\t}\n"
		code=code.insert(code.find("\t// RANGE2_FINISH"),ink)
		code=code.replace("// RANGE2_KIT_BASE","if(crowd_style.x>1.5) graphic_base=crowd_color;")
	var shader=Shader.new();shader.code=code;shaders[outline]=shader;return shader

func parts(view: Dictionary) -> Array:
	var result=[];var body: MeshInstance3D=view.model.find_child("Source_Body",true,false)
	result.append({"node":body,"type":0,"bone":-1,"pose":Transform3D.IDENTITY,"helmet":0})
	var head: Node3D=view.helmet.get_parent();var chest: Node3D=view.backpack.get_parent()
	result.append({"node":view.helmet,"type":1,"bone":41,"pose":head.global_transform.affine_inverse()*view.helmet.global_transform,"helmet":1})
	for anchor in [[view.helmet.get_node_or_null("ClassHelmet"),head,41,1],[view.backpack.get_node_or_null("ClassEquipment"),chest,42,0]]:
		if anchor[0]==null:continue
		for node in anchor[0].get_children():
			if node is MeshInstance3D:result.append({"node":node,"type":2,"bone":anchor[2],"pose":anchor[1].global_transform.affine_inverse()*node.global_transform,"helmet":anchor[3]})
	return result

func merged_mesh(blue: Dictionary,red: Dictionary,helmet_only: bool=false) -> ArrayMesh:
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray();var uv=PackedVector2Array();var bones=PackedInt32Array();var weights=PackedFloat32Array();var styles=PackedFloat32Array();var reds=PackedFloat32Array();var indices=PackedInt32Array()
	var blue_parts=[];var red_parts=[]
	for part in parts(blue):
		if part.type<2:part.role=0;blue_parts.append(part)
	for part in parts(red):
		if part.type<2:red_parts.append(part)
	for role in Classes.IDS:
		for part in parts(templates[role][0]):
			if part.type==2:part.role=Classes.IDS.find(role)+1;blue_parts.append(part)
		for part in parts(templates[role][1]):
			if part.type==2:red_parts.append(part)
	for pindex in range(blue_parts.size()):
		var part: Dictionary=blue_parts[pindex];var node: MeshInstance3D=part.node
		if helmet_only and not bool(part.helmet):continue
		var red_node: MeshInstance3D=red_parts[pindex].node
		for surface in range(node.mesh.get_surface_count()):
			var source=node.mesh.surface_get_arrays(surface);var red_source=red_node.mesh.surface_get_arrays(surface)
			var base=vertices.size();var transform: Transform3D=part.pose;var normal_basis=transform.basis.inverse().transposed()
			var source_colors=source[Mesh.ARRAY_COLOR];var red_colors=red_source[Mesh.ARRAY_COLOR]
			var material: ShaderMaterial=node.get_active_material(surface);var red_material: ShaderMaterial=red_node.get_active_material(surface)
			var tint: Color=material.get_shader_parameter("solid_color") if part.type==1 else Color.WHITE
			var red_tint: Color=red_material.get_shader_parameter("solid_color") if part.type==1 else Color.WHITE
			for index in range(source[Mesh.ARRAY_VERTEX].size()):
				vertices.append(transform*source[Mesh.ARRAY_VERTEX][index]);normals.append((normal_basis*source[Mesh.ARRAY_NORMAL][index]).normalized())
				var color: Color=source_colors[index] if source_colors!=null and source_colors.size()>index and part.type!=1 else tint
				var red_color: Color=red_colors[index] if red_colors!=null and red_colors.size()>index and part.type!=1 else red_tint
				colors.append(color);reds.append_array(PackedFloat32Array([red_color.r,red_color.g,red_color.b,1.0]))
				uv.append(source[Mesh.ARRAY_TEX_UV][index] if source[Mesh.ARRAY_TEX_UV]!=null and source[Mesh.ARRAY_TEX_UV].size()>index else Vector2.ZERO)
				styles.append_array(PackedFloat32Array([float(part.type),float(part.helmet),float(part.role),0]))
				for component in range(4):
					bones.append(source[Mesh.ARRAY_BONES][index*4+component] if part.bone<0 else part.bone)
					weights.append(source[Mesh.ARRAY_WEIGHTS][index*4+component] if part.bone<0 else 1.0 if component==0 else 0.0)
			var source_indices=source[Mesh.ARRAY_INDEX]
			if source_indices!=null and not source_indices.is_empty():
				for index in source_indices:indices.append(base+index)
			else:
				for index in range(source[Mesh.ARRAY_VERTEX].size()):indices.append(base+index)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights;arrays[Mesh.ARRAY_INDEX]=indices
	arrays[Mesh.ARRAY_CUSTOM0]=styles;arrays[Mesh.ARRAY_CUSTOM1]=reds
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT|Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	return mesh

func build_group(role: String,blue: Dictionary,red: Dictionary,helmet_only: bool=false):
	var material=ShaderMaterial.new();material.shader=shader_for(false);material.set_shader_parameter("bone_palette",texture)
	var body: MeshInstance3D=blue.model.find_child("Source_Body",true,false)
	material.set_shader_parameter("base_texture",body.get_active_material(0).get_shader_parameter("base_texture"))
	material.set_shader_parameter("team_paper",body.get_active_material(0).get_shader_parameter("team_paper"))
	material.set_shader_parameter("red_paper",red.model.find_child("Source_Body",true,false).get_active_material(0).get_shader_parameter("team_paper"))
	# The original texture seams and facing contour provide ink in the main
	# pass. A second full skin pass costs more than the 1 px expanded silhouette.
	var instances=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.use_colors=true;instances.use_custom_data=true;instances.mesh=merged_mesh(blue,red,helmet_only);instances.instance_count=CAPACITY;instances.visible_instance_count=0;instances.custom_aabb=bounds
	# GLES packs custom data beside instance color. Explicit neutral color keeps
	# COLOR's original helmet/kit vertex tint from being multiplied by zero.
	for index in range(CAPACITY):instances.set_instance_color(index,Color.WHITE)
	var node=MultiMeshInstance3D.new();node.name="Crowd_"+role;node.multimesh=instances;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
	groups[role]={"node":node,"instances":instances,"entries":[]}

func build_shadows(mesh: Mesh):
	var code=FileAccess.get_file_as_string("res://shaders/soldier_shadow.gdshader")
	for field in ["head","chest","hip","left_foot","right_foot"]:
		var line="uniform vec2 "+field
		var start=code.find(line);var end=code.find(";",start)
		code=code.substr(0,start)+"varying vec2 "+field+";"+code.substr(end+1)
	code=code.replace("uniform float softness=0.025;","uniform sampler2D bone_palette : filter_nearest, repeat_disable;\nvarying float softness;")
	code=code.replace("ground=VERTEX.xz;","ground=VERTEX.xz;int row=INSTANCE_ID*64+63;vec4 a=texelFetch(bone_palette,ivec2(0,row),0);vec4 b=texelFetch(bone_palette,ivec2(1,row),0);vec4 c=texelFetch(bone_palette,ivec2(2,row),0);head=a.xy;chest=a.zw;hip=b.xy;left_foot=b.zw;right_foot=c.xy;softness=c.z;")
	var shader=Shader.new();shader.code=code;var material=ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("bone_palette",texture)
	shadows=MultiMesh.new();shadows.transform_format=MultiMesh.TRANSFORM_3D;shadows.mesh=mesh;shadows.instance_count=CAPACITY;shadows.custom_aabb=bounds
	for i in range(CAPACITY):shadows.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO))
	var node=MultiMeshInstance3D.new();node.name="CrowdShadows";node.multimesh=shadows;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)

func register(view: Dictionary,team: int):
	if not view.get("source_rig",false):return
	var role=str(view.class_key).get_slice("/",0)
	var id=view.root.get_instance_id()
	if entries.has(id):
		var old: Dictionary=entries[id]
		if old.role==role and old.team==team:return
		unregister(id)
	if free_slots.is_empty():return
	if not role in Classes.IDS:return
	var entry={"view":view,"team":team,"slot":free_slots.pop_back(),"role":role,"index":groups.shared.entries.size(),"draw_index":-1,"revision":-1,"transform":Transform3D(),"custom":Color(-1,-1,-1,-1)}
	var body: MeshInstance3D=view.model.find_child("Source_Body",true,false);entry.skin=body.skin;entry.bone_map=[]
	for i in range(entry.skin.get_bind_count()):
		var bone=entry.skin.get_bind_bone(i)
		entry.bone_map.append(bone if bone>=0 else view.skeleton.find_bone(entry.skin.get_bind_name(i)))
	# The GPU palette already skins this body. Detach only its disabled renderer's
	# native SkinReference, while retaining the original Skin, Skeleton3D and mesh.
	# Otherwise every bone update also rebuilds/uploads an unused native palette.
	body.skeleton=NodePath("")
	for part in parts(view):preload("res://scripts/batched_source.gd").suspend(part.node)
	preload("res://scripts/batched_source.gd").suspend(view.shadow)
	entries[view.root.get_instance_id()]=entry;groups.shared.entries.append(entry)
	groups.shared.instances.visible_instance_count=groups.shared.entries.size()

func unregister(id: int):
	var entry: Dictionary=entries[id];var group: Dictionary=groups.helmets if entry.has("helmet") else groups.shared;var last: Dictionary=group.entries.pop_back()
	if entry.index<group.entries.size():last.index=entry.index;group.entries[last.index]=last;last.custom=Color(-1,-1,-1,-1);last.transform=Transform3D()
	group.instances.visible_instance_count=group.entries.size();shadows.set_instance_transform(entry.slot,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO));free_slots.append(entry.slot);entries.erase(id)

func register_helmet(node: MeshInstance3D,view: Dictionary) -> bool:
	if free_slots.is_empty() or not entries.has(view.root.get_instance_id()):return false
	var original: Dictionary=entries[view.root.get_instance_id()];var role: String=original.role
	var entry={"helmet":node,"local":view.helmet.transform.affine_inverse(),"team":original.team,"slot":free_slots.pop_back(),"role":role,"index":groups.helmets.entries.size(),"draw_index":-1,"revision":-1,"transform":Transform3D(),"custom":Color(-1,-1,-1,-1)}
	preload("res://scripts/batched_source.gd").suspend(node)
	for child in node.find_children("*","MeshInstance3D",true,false):preload("res://scripts/batched_source.gd").suspend(child)
	entries[node.get_instance_id()]=entry;groups.helmets.entries.append(entry);groups.helmets.instances.visible_instance_count=groups.helmets.entries.size()
	return true

func write_pose(row: int,pose: Transform3D):
	palette.set_pixel(0,row,Color(pose.basis.x.x,pose.basis.y.x,pose.basis.z.x,pose.origin.x))
	palette.set_pixel(1,row,Color(pose.basis.x.y,pose.basis.y.y,pose.basis.z.y,pose.origin.y))
	palette.set_pixel(2,row,Color(pose.basis.x.z,pose.basis.y.z,pose.basis.z.z,pose.origin.z))

func refresh():
	var started=Time.get_ticks_usec();var dirty=false;var drawing=0;var helmet_drawing=0
	if is_instance_valid(camera):screen_rect=get_viewport().get_visible_rect().grow(maxf(120,2.5*get_viewport().get_visible_rect().size.y/maxf(.1,camera.size)))
	for id in entries.keys():
		var entry: Dictionary=entries[id];var helmet_only=entry.has("helmet")
		var root=entry.helmet if helmet_only else entry.view.root
		if not is_instance_valid(root):
			unregister(id);continue
		if helmet_only:
			if not root.is_visible_in_tree() or not in_view(root.global_position):entry.draw_index=-1;continue
			var helmet_pose: Transform3D=root.global_transform*entry.local
			var helmet_custom=Color(entry.slot,entry.team,0,9+Classes.IDS.find(entry.role));var helmet_instances: MultiMesh=groups.helmets.instances
			if entry.draw_index!=helmet_drawing or helmet_pose!=entry.transform:helmet_instances.set_instance_transform(helmet_drawing,helmet_pose);entry.transform=helmet_pose
			if entry.draw_index!=helmet_drawing or helmet_custom!=entry.custom:helmet_instances.set_instance_custom_data(helmet_drawing,helmet_custom);entry.custom=helmet_custom
			entry.draw_index=helmet_drawing;helmet_drawing+=1
			if entry.revision<0:
				# The dedicated mesh binds only to the original head attachment row.
				write_pose(entry.slot*BONES+41,Transform3D.IDENTITY)
				entry.revision=0;dirty=true
			continue
		var view: Dictionary=entry.view
		var translation: Vector3=view.render_translation.offset if view.has("render_translation") else Vector3.ZERO
		var rig: Skeleton3D=view.skeleton
		var visible=view.root.is_visible_in_tree() and in_view(view.root.global_position+translation)
		var shadow_pose: Transform3D=view.shadow.global_transform if visible and view.shadow.is_visible_in_tree() else Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
		if visible:shadow_pose.origin+=translation
		shadows.set_instance_transform(entry.slot,shadow_pose)
		if not visible:entry.draw_index=-1;continue
		var pose=rig.global_transform
		pose.origin+=translation
		var instances: MultiMesh=groups.shared.instances
		if entry.draw_index!=drawing or pose!=entry.transform:instances.set_instance_transform(drawing,pose);entry.transform=pose
		var custom=Color(entry.slot,entry.team,0 if view.helmet.is_visible_in_tree() else 1,1+Classes.IDS.find(entry.role))
		if entry.draw_index!=drawing or custom!=entry.custom:instances.set_instance_custom_data(drawing,custom);entry.custom=custom
		entry.draw_index=drawing;drawing+=1
		var revision=int(view.get("render_pose_revision",0))
		if not visible or entry.revision==revision:continue
		entry.revision=revision;dirty=true;skin_uploads+=1
		for i in range(entry.skin.get_bind_count()):write_pose(entry.slot*BONES+i,rig.get_bone_global_pose(entry.bone_map[i])*entry.skin.get_bind_pose(i))
		write_pose(entry.slot*BONES+41,rig.get_bone_global_pose(view.bone_indices.Head));write_pose(entry.slot*BONES+42,rig.get_bone_global_pose(view.bone_indices.Spine02))
		var shadow_material: ShaderMaterial=view.shadow.material_override
		if shadow_material.get_shader_parameter("head")==null:continue
		var head: Vector2=shadow_material.get_shader_parameter("head");var chest: Vector2=shadow_material.get_shader_parameter("chest");var hip: Vector2=shadow_material.get_shader_parameter("hip");var left: Vector2=shadow_material.get_shader_parameter("left_foot");var right: Vector2=shadow_material.get_shader_parameter("right_foot")
		palette.set_pixel(0,entry.slot*BONES+63,Color(head.x,head.y,chest.x,chest.y));palette.set_pixel(1,entry.slot*BONES+63,Color(hip.x,hip.y,left.x,left.y));palette.set_pixel(2,entry.slot*BONES+63,Color(right.x,right.y,float(shadow_material.get_shader_parameter("softness")),1))
	groups.shared.instances.visible_instance_count=drawing
	groups.helmets.instances.visible_instance_count=helmet_drawing
	if dirty:texture.update(palette)
	last_ms=(Time.get_ticks_usec()-started)/1000.0

func in_view(point: Vector3) -> bool:
	return not is_instance_valid(camera) or not camera.is_position_behind(point) and screen_rect.has_point(camera.unproject_position(point))
