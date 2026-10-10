extends Node3D
## Persistent dense GPU instance pools. Only changed instances are uploaded.
## The owner keeps lightweight motion state; no per-particle render node is needed.
const CAPACITY=360
var capacity: int=CAPACITY
var groups: Dictionary={}
var bounds=AABB(Vector3(-128,-64,-128),Vector3(256,256,256))
var writes=0
var case_image: Image
var case_texture: ImageTexture
var case_mesh: ArrayMesh
var case_material: ShaderMaterial
var case_sources: Dictionary={}
var case_cursor=0
var magazine_mesh: ArrayMesh
var magazine_material: ShaderMaterial
var magazine_sources: Dictionary={}
const CASE_VERTICES=216
const CASE_WIDTH=512
const CASE_HEIGHT=256

func _init(capacity_per_group: int=CAPACITY):
	assert(capacity_per_group>0)
	capacity=capacity_per_group

func add_case(mesh: Mesh,material: Material,pose: Transform3D) -> Dictionary:
	if case_image==null:prepare_cases(material)
	var shape=store_geometry(mesh,CASE_VERTICES,case_sources)
	if shape.is_empty():return add(mesh,material,pose)
	return atlas_handle(case_mesh,case_material,shape,pose)

func store_geometry(mesh: Mesh,maximum: int,library: Dictionary) -> Dictionary:
	var id=mesh.get_instance_id()
	if not library.has(id):
		var data=mesh.surface_get_arrays(0);var vertices=data[Mesh.ARRAY_VERTEX]
		if vertices.size()>maximum or case_cursor+vertices.size()*3>CASE_WIDTH*CASE_HEIGHT:return {}
		library[id]={"offset":case_cursor,"count":vertices.size()}
		for i in range(vertices.size()):
			var at: Vector3=vertices[i];var normal: Vector3=data[Mesh.ARRAY_NORMAL][i]
			for value in [Color(at.x,at.y,at.z,1),Color(normal.x,normal.y,normal.z,0),data[Mesh.ARRAY_COLOR][i]]:
				case_image.set_pixel(case_cursor%CASE_WIDTH,int(case_cursor/CASE_WIDTH),value);case_cursor+=1
		case_texture.update(case_image)
	return library[id]

func atlas_handle(mesh: Mesh,material: Material,shape: Dictionary,pose: Transform3D,local: Transform3D=Transform3D.IDENTITY) -> Dictionary:
	var handle=add(mesh,material,pose,local)
	# Compatibility packs instance data to half floats: split the pixel address so
	# every integer is <= 1020 and stays exact instead of rounding large offsets.
	var custom=Color(int(shape.offset)%CASE_WIDTH,int(shape.offset/CASE_WIDTH),int(shape.count)%1024,int(shape.count/1024))
	handle.custom=custom;groups[handle.key].instances.set_instance_custom_data(handle.slot,custom)
	return handle

func add_magazine(mesh: Mesh,material: Material,pose: Transform3D,local: Transform3D) -> Dictionary:
	if case_image==null:prepare_cases(preload("res://scripts/weapon_effects.gd").outlined_material(Color.WHITE,true))
	if magazine_mesh==null:
		var arrays=[];arrays.resize(Mesh.ARRAY_MAX);var v=PackedVector3Array();var n=PackedVector3Array()
		for i in range(4092):v.append(Vector3(i,0,0));n.append(Vector3.UP)
		arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_NORMAL]=n;magazine_mesh=ArrayMesh.new();magazine_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var shader=Shader.new();var code=FileAccess.get_file_as_string("res://shaders/ink_surface.gdshader")
		code=code.replace("void vertex() {",atlas_helper()+"void vertex() {"+atlas_read());shader.code=code
		magazine_material=material.duplicate();magazine_material.shader=shader;magazine_material.set_shader_parameter("case_atlas",case_texture)
	var shape=store_geometry(mesh,4092,magazine_sources)
	if shape.is_empty():return add(mesh,material,pose,local)
	return atlas_handle(magazine_mesh,magazine_material,shape,pose,local)

func atlas_helper() -> String:return "uniform sampler2D case_atlas : filter_nearest, repeat_disable;\nvec4 case_value(int index){return texelFetch(case_atlas,ivec2(index%512,index/512),0);}\n"
func atlas_read() -> String:return "int index=int(VERTEX.x);if(index>=int(INSTANCE_CUSTOM.z)+int(INSTANCE_CUSTOM.w)*1024){VERTEX=vec3(0.0);NORMAL=vec3(0.0,1.0,0.0);}else{int start=int(INSTANCE_CUSTOM.x)+int(INSTANCE_CUSTOM.y)*512+index*3;VERTEX=case_value(start).xyz;NORMAL=case_value(start+1).xyz;COLOR=case_value(start+2); }"

func prepare_cases(source_material: Material):
	case_image=Image.create(CASE_WIDTH,CASE_HEIGHT,false,Image.FORMAT_RGBAF);case_texture=ImageTexture.create_from_image(case_image)
	var vertices=PackedVector3Array();var normals=PackedVector3Array()
	for i in range(CASE_VERTICES):vertices.append(Vector3(i,0,0));normals.append(Vector3.UP)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	case_mesh=ArrayMesh.new();case_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var helper=atlas_helper();var read=atlas_read()
	var shader=Shader.new();shader.code="shader_type spatial;render_mode unshaded,cull_back;\n"+helper+"void vertex(){"+read+"}\nvoid fragment(){ALBEDO=COLOR.rgb;}"
	case_material=ShaderMaterial.new();case_material.shader=shader;case_material.set_shader_parameter("case_atlas",case_texture)
	# Tiny brass cases use vertex-colored shading in one pass; no enlarged shell outline.

func add(mesh: Mesh,material: Material,pose: Transform3D,local: Transform3D=Transform3D.IDENTITY,color: Color=Color.WHITE) -> Dictionary:
	var key=str(mesh.get_instance_id())+"/"+str(material.get_instance_id() if material!=null else 0)
	if not groups.has(key):
		var instances=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D
		instances.use_custom_data=true;instances.use_colors=true
		instances.mesh=mesh;instances.instance_count=capacity;instances.visible_instance_count=0;instances.custom_aabb=bounds
		var node=MultiMeshInstance3D.new();node.name="FXBatch";node.multimesh=instances;node.material_override=material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
		groups[key]={"node":node,"instances":instances,"entries":[]}
	var group: Dictionary=groups[key]
	assert(group.entries.size()<capacity)
	var handle={"key":key,"slot":group.entries.size(),"local":local,"pose":pose*local,"color":color,"custom":Color(0,0,0,0)}
	if not group.instances.custom_aabb.has_point(handle.pose.origin):group.instances.custom_aabb=group.instances.custom_aabb.expand(handle.pose.origin).grow(4)
	group.entries.append(handle);group.instances.set_instance_transform(handle.slot,handle.pose);writes+=1
	group.instances.set_instance_color(handle.slot,color);group.instances.set_instance_custom_data(handle.slot,handle.custom)
	group.instances.visible_instance_count=group.entries.size()
	return handle

func sync(handles: Array,pose: Transform3D):
	for handle in handles:
		var transformed=pose*Transform3D(handle.local)
		if handle.pose==transformed:continue
		handle.pose=transformed
		var group: Dictionary=groups[handle.key]
		# Normal battlefield effects fit in the fixed bounds. Expand only for outliers.
		if not group.instances.custom_aabb.has_point(transformed.origin):group.instances.custom_aabb=group.instances.custom_aabb.expand(transformed.origin).grow(4)
		group.instances.set_instance_transform(handle.slot,transformed);writes+=1

func release(handles: Array):
	for handle in handles:
		var group: Dictionary=groups[handle.key];var entries: Array=group.entries
		var last: Dictionary=entries.pop_back()
		if int(handle.slot)<entries.size():
			last.slot=handle.slot;entries[last.slot]=last
			group.instances.set_instance_transform(last.slot,last.pose);writes+=1
			group.instances.set_instance_color(last.slot,last.color);group.instances.set_instance_custom_data(last.slot,last.custom)
		group.instances.visible_instance_count=entries.size()
		if entries.is_empty():group.instances.custom_aabb=bounds
	handles.clear()

func stats() -> Dictionary:
	var count=0;var batches=0;var passes=0
	for group in groups.values():
		count+=group.entries.size()
		if group.entries.is_empty():continue
		batches+=1
		var material: Material=group.node.material_override;var draws=1
		while material!=null and material.next_pass!=null:draws+=1;material=material.next_pass
		passes+=group.instances.mesh.get_surface_count()*draws
	return {"instances":count,"batches":batches,"surface_passes":passes,"uploads":writes}
