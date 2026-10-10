extends RefCounted
## Collapse rigid details to one coloured triangle surface and one line surface.
## Skinned garments, hidden effects and transparent shadows retain separate draws.
const SHADER = preload("res://shaders/ink_surface.gdshader")
static var cache: Dictionary = {}

static func skin_attachments(skeleton: Skeleton3D, keep: Array, key: String) -> void:
	var sources: Array=[]
	var groups: Dictionary={}
	for attachment in skeleton.get_children():
		if not attachment is BoneAttachment3D: continue
		var meshes: Array=[]
		gather(attachment,attachment,keep,meshes)
		for node in meshes:
			sources.append(node)
			if cache.has(key): continue
			var transform=skeleton.get_bone_global_rest(attachment.bone_idx)*attachment.global_transform.affine_inverse()*node.global_transform
			for surface in range(node.mesh.get_surface_count()):
				var primitive=node.mesh.surface_get_primitive_type(surface)
				if not groups.has(primitive):
					groups[primitive]={"v":PackedVector3Array(),"n":PackedVector3Array(),"c":PackedColorArray(),"b":PackedInt32Array(),"w":PackedFloat32Array()}
				var g: Dictionary=groups[primitive]
				var arrays=node.mesh.surface_get_arrays(surface)
				for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
					g.v.append(transform*arrays[Mesh.ARRAY_VERTEX][i])
					g.n.append((transform.basis*arrays[Mesh.ARRAY_NORMAL][i]).normalized())
					g.c.append(arrays[Mesh.ARRAY_COLOR][i])
					g.b.append_array(PackedInt32Array([attachment.bone_idx,0,0,0]))
					g.w.append_array(PackedFloat32Array([1,0,0,0]))
	if not cache.has(key):
		var mesh=ArrayMesh.new()
		for primitive in groups:
			var g: Dictionary=groups[primitive]
			var arrays=[]
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=g.v
			arrays[Mesh.ARRAY_NORMAL]=g.n
			arrays[Mesh.ARRAY_COLOR]=g.c
			arrays[Mesh.ARRAY_BONES]=g.b
			arrays[Mesh.ARRAY_WEIGHTS]=g.w
			mesh.add_surface_from_arrays(primitive,arrays)
		cache[key]=mesh
	for node in sources: node.free()
	var mesh_node=MeshInstance3D.new()
	mesh_node.mesh=cache[key]
	var mat=ShaderMaterial.new()
	mat.shader=SHADER
	mat.set_shader_parameter("vertex_tint",true)
	mat.set_shader_parameter("hatch_strength",.12)
	mesh_node.material_override=mat
	var skin=Skin.new()
	for i in range(skeleton.get_bone_count()): skin.add_bind(i,skeleton.get_bone_global_rest(i).affine_inverse())
	mesh_node.skin=skin
	skeleton.get_parent().add_child(mesh_node)
	mesh_node.skeleton=mesh_node.get_path_to(skeleton)
	prune_empty(skeleton,keep)

static func prune_empty(root: Node, keep: Array) -> void:
	for child in root.get_children():
		if child in keep: continue
		prune_empty(child,keep)
		if child.get_child_count()==0 and not child is MeshInstance3D:
			child.free()

static func gather(node: Node, root: Node, skip: Array, output: Array) -> void:
	for child in node.get_children():
		if child in skip or child is Skeleton3D or child is BoneAttachment3D:
			continue
		if child is MeshInstance3D:
			if child.skin != null or not child.visible:
				continue
			var mat = child.material_override
			if mat is StandardMaterial3D and mat.albedo_color.a < 1:
				continue
			output.append(child)
		gather(child,root,skip,output)

static func collapse(root: Node3D, skip: Array = [], cache_key: String = "") -> Array:
	var sources: Array = []
	gather(root,root,skip,sources)
	var resources: Array = []
	if not cache_key.is_empty() and cache.has(cache_key):
		resources=cache[cache_key]
	else:
		var groups: Dictionary = {}
		for node in sources:
			var transform: Transform3D = root.global_transform.affine_inverse()*node.global_transform
			for s in range(node.mesh.get_surface_count()):
				var primitive = node.mesh.surface_get_primitive_type(s) if node.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
				if primitive not in [Mesh.PRIMITIVE_TRIANGLES,Mesh.PRIMITIVE_LINES]:
					continue
				if not groups.has(primitive):
					groups[primitive]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
				var group: Dictionary = groups[primitive]
				var data = node.mesh.surface_get_arrays(s)
				var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
				var normals = data[Mesh.ARRAY_NORMAL]
				var colors = data[Mesh.ARRAY_COLOR]
				var indices = data[Mesh.ARRAY_INDEX]
				var mat = node.material_override
				var tint = Color.WHITE
				var vertex_color = false
				if mat is ShaderMaterial:
					tint=mat.get_shader_parameter("pigment")
					vertex_color=mat.get_shader_parameter("vertex_tint")
				elif mat is StandardMaterial3D:
					tint=mat.albedo_color
				var count = indices.size() if indices != null and not indices.is_empty() else vertices.size()
				for i in range(count):
					var k = indices[i] if indices != null and not indices.is_empty() else i
					group.vertices.append(transform*vertices[k])
					group.normals.append((transform.basis*normals[k]).normalized() if normals != null and not normals.is_empty() else Vector3.UP)
					group.colors.append(colors[k] if vertex_color and colors != null and not colors.is_empty() else tint)
		for primitive in groups:
			var g: Dictionary = groups[primitive]
			var arrays = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=g.vertices
			arrays[Mesh.ARRAY_NORMAL]=g.normals
			arrays[Mesh.ARRAY_COLOR]=g.colors
			var mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(primitive,arrays)
			var mat = ShaderMaterial.new()
			mat.shader=SHADER
			mat.set_shader_parameter("vertex_tint",true)
			mat.set_shader_parameter("hatch_strength",0.14 if primitive==Mesh.PRIMITIVE_TRIANGLES else 0.0)
			resources.append([mesh,mat])
		if not cache_key.is_empty():
			cache[cache_key]=resources
	for source in sources:
		source.free()
	var nodes: Array = []
	for resource in resources:
		var node = MeshInstance3D.new()
		node.mesh=resource[0]
		node.material_override=resource[1]
		root.add_child(node)
		nodes.append(node)
	return nodes
