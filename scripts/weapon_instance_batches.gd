extends Node3D
## Original weapon meshes live once in a GPU atlas. Switching/reinforcement only
## changes instance transforms and geometry addresses, never splits per gun type.
const SIZE=2048
const CAPACITY=256
const Props=preload("res://scripts/proving_art.gd")
var image=Image.create(SIZE,SIZE,false,Image.FORMAT_RGBAF)
var texture: ImageTexture
var cursor=0
var library: Dictionary={}
var groups: Dictionary={}
var entries: Dictionary={}
var last_ms=0.0
var active_groups=0
var draw_meshes: Dictionary={}
var camera: Camera3D
var screen_rect:=Rect2()
var camera_frame:=Transform3D.IDENTITY
var view_half:=Vector2.ONE
var mesh_bounds: Dictionary={}
var bounds=AABB(Vector3(-128,-64,-128),Vector3(256,256,256))
func supported(node) -> bool:
	return node is MeshInstance3D and node.mesh!=null and node.skin==null and not node.has_meta("palette_batched") and node.material_override is ShaderMaterial and node.material_override.shader.resource_path=="res://shaders/ink_surface.gdshader"
func gather(node,found: Array):
	if supported(node):found.append(node)
	for child in node.get_children():gather(child,found)
func prepare(catalog):
	# Includes replacement waves and loot/quick-slot equipment before gameplay.
	var parent=Node3D.new();add_child(parent);parent.hide()
	for weapon in catalog.weapons.values():
		var model=Props.weapon(parent,weapon);var found=[];gather(model,found)
		for node in found:
			for surface in range(node.mesh.get_surface_count()):
				var shape: Dictionary=store(node.mesh,surface)
				if not shape.is_empty():draw_mesh(node.mesh.surface_get_primitive_type(surface) if node.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES,shape.count)
		model.free()
		if weapon.kind in ["rocket","mortar","vehicleMortar","grenadeProjectile","grenade"]:
			var round_model=preload("res://scripts/weapon_effects.gd").projectile(parent,weapon,true)
			var round_parts=[];gather(round_model,round_parts)
			for node in round_parts:
				for surface in range(node.mesh.get_surface_count()):
					var shape=store(node.mesh,surface)
					if not shape.is_empty():draw_mesh(Mesh.PRIMITIVE_TRIANGLES,shape.count)
			round_model.free()
	parent.free();texture=ImageTexture.create_from_image(image)
func store(mesh: Mesh,surface: int) -> Dictionary:
	var key=str(mesh.get_instance_id(),"/",surface)
	if library.has(key):return library[key]
	var arrays=mesh.surface_get_arrays(surface);var vertices=arrays[Mesh.ARRAY_VERTEX];var indices=arrays[Mesh.ARRAY_INDEX]
	var indexed=indices!=null and not indices.is_empty();var count=indices.size() if indexed else vertices.size()
	assert(cursor+count*3<=SIZE*SIZE,"Weapon geometry atlas capacity exceeded")
	if cursor+count*3>SIZE*SIZE:return {}
	var shape={"offset":cursor,"count":count};library[key]=shape
	for i in range(count):
		var index=indices[i] if indexed else i;var at: Vector3=vertices[index];var normal: Vector3=arrays[Mesh.ARRAY_NORMAL][index]
		var color: Color=arrays[Mesh.ARRAY_COLOR][index] if arrays[Mesh.ARRAY_COLOR]!=null else Color.WHITE
		for pixel in [Color(at.x,at.y,at.z,1),Color(normal.x,normal.y,normal.z,0),color]:image.set_pixel(cursor%SIZE,int(cursor/SIZE),pixel);cursor+=1
	if texture!=null:texture.update(image)
	return shape
func group_for(material: ShaderMaterial,primitive: int,count: int) -> Dictionary:
	var maximum=24576
	while maximum<count:maximum*=4
	var uniforms=[]
	for uniform in material.shader.get_shader_uniform_list():uniforms.append(material.get_shader_parameter(uniform.name))
	var key=str(primitive,"/",maximum,"/",var_to_str(uniforms))
	if groups.has(key):return groups[key]
	var mesh=draw_mesh(primitive,count)
	var shader=Shader.new()
	var helper="uniform sampler2D weapon_atlas : filter_nearest,repeat_disable;\nvec4 weapon_value(int i){return texelFetch(weapon_atlas,ivec2(i%2048,i/2048),0);}\n"
	var read="int i=int(VERTEX.x);int count=int(INSTANCE_CUSTOM.z)+int(INSTANCE_CUSTOM.w)*1024;if(i>=count){VERTEX=vec3(0);NORMAL=vec3(0,1,0);}else{int at=int(INSTANCE_CUSTOM.x)+int(INSTANCE_CUSTOM.y)*2048+i*3;VERTEX=weapon_value(at).xyz;NORMAL=weapon_value(at+1).xyz;COLOR=weapon_value(at+2); }"
	shader.code=material.shader.code.replace("void vertex() {",helper+"void vertex() {"+read)
	var drawn: ShaderMaterial=material.duplicate();drawn.shader=shader;drawn.set_shader_parameter("weapon_atlas",texture)
	var instances=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.use_colors=true;instances.use_custom_data=true;instances.mesh=mesh;instances.instance_count=CAPACITY;instances.visible_instance_count=0;instances.custom_aabb=bounds
	for i in range(CAPACITY):instances.set_instance_color(i,Color.WHITE)
	var node=MultiMeshInstance3D.new();node.name="WeaponAtlasBatch";node.multimesh=instances;node.material_override=drawn;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
	groups[key]={"key":key,"node":node,"instances":instances,"active":0,"primitive":primitive,"draw_count":0};return groups[key]
func draw_mesh(primitive: int,count: int) -> ArrayMesh:
	# Each instance reads the same prefix of its atlas. The batch only needs the
	# largest visible prefix, not 24,576 vertices for every small rifle or pistol.
	var key:=Vector2i(primitive,count)
	if draw_meshes.has(key):return draw_meshes[key]
	var vertices:=PackedVector3Array();vertices.resize(count)
	for i: int in range(count):vertices[i]=Vector3(i,0,0)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(primitive,arrays)
	draw_meshes[key]=mesh;return mesh
func register_tree(node):
	if supported(node):
		var handles=[]
		for surface in range(node.mesh.get_surface_count()):
			var shape=store(node.mesh,surface)
			if shape.is_empty():continue
			var primitive=node.mesh.surface_get_primitive_type(surface) if node.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			var group=group_for(node.get_active_material(surface),primitive,shape.count)
			handles.append({"group":group,"index":-1,"pose":Transform3D.IDENTITY,"count":int(shape.count),"custom":Color(int(shape.offset)%SIZE,int(shape.offset/SIZE),int(shape.count)%1024,int(shape.count/1024))})
		if not handles.is_empty():entries[node.get_instance_id()]={"source":node,"handles":handles,"translation":preload("res://scripts/batch_render_translation.gd").find(node)};preload("res://scripts/batched_source.gd").suspend(node);node.set_meta("palette_batched",true)
	for child in node.get_children():register_tree(child)
func _process(_delta: float):refresh()
func refresh():
	var start=Time.get_ticks_usec()
	if is_instance_valid(camera):
		screen_rect=get_viewport().get_visible_rect()
		camera_frame=camera.get_camera_transform().affine_inverse()
		var projection: Projection=camera.get_camera_projection()
		view_half=Vector2(1.0/absf(projection.x.x),1.0/absf(projection.y.y))
	for group in groups.values():group.active=0;group.draw_count=0
	for id in entries.keys():
		var entry: Dictionary=entries[id]
		if not is_instance_valid(entry.source):entries.erase(id);continue
		if not entry.source.is_inside_tree() or not entry.source.is_visible_in_tree():
			for handle in entry.handles:handle.index=-1
			continue
		var pose: Transform3D=entry.source.global_transform
		if entry.translation!=null:pose.origin+=entry.translation.offset
		if not in_view(entry.source,pose):
			for handle in entry.handles:handle.index=-1
			continue
		for handle in entry.handles:
			var group: Dictionary=handle.group;var index: int=group.active
			assert(index<CAPACITY)
			if index>=CAPACITY:continue
			if handle.index!=index or handle.pose!=pose:group.instances.set_instance_transform(index,pose);handle.pose=pose
			if handle.index!=index:group.instances.set_instance_custom_data(index,handle.custom)
			handle.index=index;group.active+=1
			group.draw_count=maxi(group.draw_count,handle.count)
	active_groups=0
	for group in groups.values():
		group.instances.visible_instance_count=group.active;group.node.visible=group.active>0
		if group.active>0:
			var mesh: ArrayMesh=draw_mesh(group.primitive,group.draw_count)
			if group.instances.mesh!=mesh:group.instances.mesh=mesh
			active_groups+=1
	last_ms=(Time.get_ticks_usec()-start)/1000.0
func in_view(source: MeshInstance3D,pose: Transform3D) -> bool:
	if not is_instance_valid(camera):return true
	if camera.projection!=Camera3D.PROJECTION_ORTHOGONAL:return true
	var id: int=source.mesh.get_instance_id()
	if not mesh_bounds.has(id):
		var box: AABB=source.mesh.get_aabb()
		mesh_bounds[id]={"center":box.get_center(),"radius":box.size.length()*.5}
	var box: Dictionary=mesh_bounds[id]
	var center: Vector3=camera_frame*(pose*Vector3(box.center))
	# Frobenius norm bounds any rotated/nonuniform basis, including shear. Screen
	# margin encloses the complete mesh, not merely its origin or owner soldier.
	var radius: float=float(box.radius)*sqrt(pose.basis.x.length_squared()+pose.basis.y.length_squared()+pose.basis.z.length_squared())
	var margin: float=radius+8.0*maxf(view_half.x,view_half.y)/maxf(1,minf(screen_rect.size.x,screen_rect.size.y))
	return absf(center.x)<=view_half.x+margin and absf(center.y)<=view_half.y+margin
