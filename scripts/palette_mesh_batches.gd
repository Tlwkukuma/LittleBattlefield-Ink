extends Node3D
## Rigid subparts share geometry submissions while retaining independent transforms.
var entries: Array=[]
var groups: Dictionary={}
var palette: Image
var texture: ImageTexture
var last_ms=0.0
var active_groups=0
var bounds=AABB(Vector3(-128,-64,-128),Vector3(256,256,256))
func gather(root: Node,found: Array):
	if root is MeshInstance3D and not root.has_meta("palette_batched") and root.mesh!=null and root.skin==null and root.material_override is ShaderMaterial and root.material_override.shader.resource_path in ["res://shaders/vehicle_ink.gdshader","res://shaders/ink_surface.gdshader"]:found.append(root)
	for child in root.get_children():gather(child,found)
func configure(roots: Array,fixed_roots: Array=[]):
	var nodes=[]
	for root in roots:gather(root,nodes)
	var fixed_ids={}
	for root in fixed_roots:
		var children=[];gather(root,children);nodes.append_array(children)
		for child in children:fixed_ids[child.get_instance_id()]=root
	palette=Image.create(3,maxi(1,nodes.size()),false,Image.FORMAT_RGBAF);texture=ImageTexture.create_from_image(palette)
	for source in nodes:
		var slot=entries.size();var fixed=fixed_ids.has(source.get_instance_id())
		var entry={"source":source,"fixed":fixed,"force":true,"pose":Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO),"translation":preload("res://scripts/batch_render_translation.gd").find(source)};entries.append(entry)
		if fixed:fixed_ids[source.get_instance_id()].visibility_changed.connect(func():entry.force=true)
		for surface in range(source.mesh.get_surface_count()):
			var material: ShaderMaterial=source.get_active_material(surface)
			var primitive=source.mesh.surface_get_primitive_type(surface) if source.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			var key=str(material.get_instance_id())+"/"+str(primitive)
			if material.shader.resource_path=="res://shaders/ink_surface.gdshader":
				var uniforms=[]
				for uniform in material.shader.get_shader_uniform_list():uniforms.append(material.get_shader_parameter(uniform.name))
				key="ink/"+str(primitive)+var_to_str(uniforms)
			if not groups.has(key):groups[key]={"material":material,"primitive":primitive,"sources":[]}
			groups[key].sources.append({"node":source,"surface":surface,"slot":slot})
			# Vehicle paints/damage stay per vehicle. Their identical contour can
			# share one draw instead of one next_pass for each hull/operator weapon.
			if material.shader.resource_path=="res://shaders/vehicle_ink.gdshader" and material.next_pass is ShaderMaterial and material.next_pass.next_pass==null:
				var outline: ShaderMaterial=material.next_pass;var parameters=[]
				for uniform in outline.shader.get_shader_uniform_list():parameters.append(outline.get_shader_parameter(uniform.name))
				var outline_key="outline/"+str(primitive)+outline.shader.resource_path+var_to_str(parameters)
				if not groups.has(outline_key):groups[outline_key]={"material":outline,"primitive":primitive,"sources":[]}
				groups[outline_key].sources.append({"node":source,"surface":surface,"slot":slot});groups[key].split_outline=true
		preload("res://scripts/batched_source.gd").suspend(source);source.set_meta("palette_batched",true)
	for group in groups.values():build(group)
	refresh()
func posed_shader(source: Shader) -> Shader:
	var code=source.code
	var helper="\nuniform sampler2D part_palette : filter_nearest, repeat_disable;\nmat4 part_pose(int row) {vec4 a=texelFetch(part_palette,ivec2(0,row),0);vec4 b=texelFetch(part_palette,ivec2(1,row),0);vec4 c=texelFetch(part_palette,ivec2(2,row),0);return mat4(vec4(a.x,b.x,c.x,0.0),vec4(a.y,b.y,c.y,0.0),vec4(a.z,b.z,c.z,0.0),vec4(a.w,b.w,c.w,1.0));}\n"
	var at=code.find("void ");code=code.insert(at,helper)
	var pose="mat4 pose=part_pose(int(CUSTOM0.x));VERTEX=(pose*vec4(VERTEX,1.0)).xyz;mat3 normal_pose=mat3(cross(pose[1].xyz,pose[2].xyz),cross(pose[2].xyz,pose[0].xyz),cross(pose[0].xyz,pose[1].xyz));NORMAL=normalize(normal_pose*NORMAL);"
	if source.resource_path=="res://shaders/ink_surface.gdshader":code=code.replace("local_position = VERTEX;","local_position = VERTEX;"+pose)
	elif source.resource_path=="res://shaders/vehicle_ink.gdshader":code=code.replace("range2_local_normal=NORMAL;","range2_local_normal=NORMAL;"+pose)
	elif code.contains("void vertex() {"):code=code.replace("void vertex() {","void vertex() {"+pose)
	else:code=code.insert(code.find("void fragment()"),"void vertex() {"+pose+"}\n")
	var shader=Shader.new();shader.code=code;return shader
func build(group: Dictionary):
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray();var indices=PackedInt32Array();var slots=PackedFloat32Array()
	for part in group.sources:
		var arrays=part.node.mesh.surface_get_arrays(part.surface);var base=vertices.size();var count=arrays[Mesh.ARRAY_VERTEX].size()
		vertices.append_array(arrays[Mesh.ARRAY_VERTEX]);normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		if arrays[Mesh.ARRAY_COLOR]!=null and not arrays[Mesh.ARRAY_COLOR].is_empty():colors.append_array(arrays[Mesh.ARRAY_COLOR])
		else:
			var white=PackedColorArray();white.resize(count);white.fill(Color.WHITE);colors.append_array(white)
		var ids=PackedFloat32Array();ids.resize(count);ids.fill(float(part.slot));slots.append_array(ids)
		var source_indices=arrays[Mesh.ARRAY_INDEX]
		if source_indices!=null and not source_indices.is_empty():
			for index in source_indices:indices.append(base+index)
		else:
			for index in range(count):indices.append(base+index)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_CUSTOM0]=slots
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(group.primitive,arrays,[],{},Mesh.ARRAY_CUSTOM_R_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var material: ShaderMaterial=group.material.duplicate(true);group.batched_material=material;material.shader=posed_shader(group.material.shader);material.set_shader_parameter("part_palette",texture)
	if group.get("split_outline",false):material.next_pass=null
	if material.next_pass!=null:material.next_pass.shader=posed_shader(material.next_pass.shader);material.next_pass.set_shader_parameter("part_palette",texture)
	var node=MeshInstance3D.new();node.name="RigidPartsBatch";node.mesh=mesh;node.material_override=material;node.custom_aabb=bounds;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node);group.node=node
func _process(_delta: float):refresh()
func refresh():
	var started=Time.get_ticks_usec();var dirty=false
	for index in range(entries.size()):
		var entry: Dictionary=entries[index]
		if entry.fixed and not entry.force:continue
		entry.force=false
		var pose: Transform3D=entry.source.global_transform if is_instance_valid(entry.source) and entry.source.is_inside_tree() and entry.source.is_visible_in_tree() else Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
		if entry.translation!=null and not pose.basis.x.is_zero_approx():pose.origin+=entry.translation.offset
		if pose==entry.pose:continue
		entry.pose=pose;dirty=true
		palette.set_pixel(0,index,Color(pose.basis.x.x,pose.basis.y.x,pose.basis.z.x,pose.origin.x));palette.set_pixel(1,index,Color(pose.basis.x.y,pose.basis.y.y,pose.basis.z.y,pose.origin.y));palette.set_pixel(2,index,Color(pose.basis.x.z,pose.basis.y.z,pose.basis.z.z,pose.origin.z))
	if dirty:texture.update(palette)
	active_groups=0
	for group in groups.values():
		var active=false
		for part in group.sources:
			if is_instance_valid(part.node) and part.node.is_inside_tree() and part.node.is_visible_in_tree():active=true;break
		group.node.visible=active
		if active:active_groups+=1
		var damage=group.material.get_shader_parameter("damage")
		if damage!=null:group.batched_material.set_shader_parameter("damage",damage)
	last_ms=(Time.get_ticks_usec()-started)/1000.0
