extends Node3D
## Shared meshes and materials use dense instance pools; source sockets stay live.
const CAPACITY=512
var groups: Dictionary={}
var entries: Dictionary={}
var surface_meshes: Dictionary={}
var bounds=AABB(Vector3(-128,-64,-128),Vector3(256,256,256))
var last_ms=0.0
var active_groups=0
func register_tree(root: Node):
	if root is MeshInstance3D and root.mesh!=null and root.skin==null and not root.has_meta("palette_batched"):register(root)
	for child in root.get_children():register_tree(child)
func register(source: MeshInstance3D):
	# These meshes are rebuilt by their owner; retain the live renderer instead
	# of caching a stale mesh while continuing to copy its new transform.
	if source.get_meta("dynamic_geometry",false):return
	var id=source.get_instance_id()
	if entries.has(id):return
	var handles=[]
	for surface in range(source.mesh.get_surface_count()):
		var material=source.get_active_material(surface)
		var mesh_key=str(source.mesh.get_instance_id())+"/"+str(surface)
		var key=mesh_key+"/"+str(material.get_instance_id() if material!=null else 0)
		if not groups.has(key):
			if not surface_meshes.has(mesh_key):
				if source.mesh.get_surface_count()==1:surface_meshes[mesh_key]=source.mesh
				else:
					var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(source.mesh.surface_get_primitive_type(surface),source.mesh.surface_get_arrays(surface));surface_meshes[mesh_key]=mesh
			var instances=MultiMesh.new();instances.transform_format=MultiMesh.TRANSFORM_3D;instances.mesh=surface_meshes[mesh_key];instances.instance_count=CAPACITY;instances.visible_instance_count=0;instances.custom_aabb=bounds
			var node=MultiMeshInstance3D.new();node.name="RigidBatch";node.multimesh=instances;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
			groups[key]={"node":node,"instances":instances,"entries":[]}
		var group: Dictionary=groups[key]
		var handle={"key":key,"index":group.entries.size(),"pose":Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)}
		group.entries.append(handle);group.instances.visible_instance_count=group.entries.size();handles.append(handle)
	if not handles.is_empty():preload("res://scripts/batched_source.gd").suspend(source);entries[id]={"source":source,"handles":handles,"translation":preload("res://scripts/batch_render_translation.gd").find(source)}
func _process(_delta: float):refresh()
func refresh():
	var started=Time.get_ticks_usec()
	for group in groups.values():group.active=0
	for id in entries.keys():
		var entry: Dictionary=entries[id]
		if not is_instance_valid(entry.source):
			for handle in entry.handles:
				var group: Dictionary=groups[handle.key];var last: Dictionary=group.entries.pop_back()
				if handle.index<group.entries.size():last.index=handle.index;group.entries[last.index]=last;group.instances.set_instance_transform(last.index,last.pose)
				group.instances.visible_instance_count=group.entries.size()
			entries.erase(id);continue
		var visible=entry.source.is_inside_tree() and entry.source.is_visible_in_tree()
		var pose: Transform3D=entry.source.global_transform if visible else Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
		if visible and entry.translation!=null:pose.origin+=entry.translation.offset
		for handle in entry.handles:
			if visible:groups[handle.key].active+=1
			if handle.pose!=pose:groups[handle.key].instances.set_instance_transform(handle.index,pose);handle.pose=pose
	active_groups=0
	for group in groups.values():
		group.node.visible=group.active>0
		if group.node.visible:active_groups+=1
	last_ms=(Time.get_ticks_usec()-started)/1000.0
