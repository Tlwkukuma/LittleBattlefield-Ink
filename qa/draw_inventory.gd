extends SceneTree
var groups: Dictionary={}
var meshes: Array=[]
func _initialize():call_deferred("run")
func scan(node: Node,section: String):
	if node is MeshInstance3D and node.layers!=0 and node.is_visible_in_tree() and node.mesh!=null:
		for surface in range(node.mesh.get_surface_count()):
			var mat: Material=node.get_active_material(surface)
			var shader=mat.shader.resource_path if mat is ShaderMaterial else mat.get_class() if mat!=null else "none"
			var key=section+" / "+shader
			groups[key]=int(groups.get(key,0))+1
			meshes.append({"section":section,"path":str(node.get_path()),"shader":shader,"skin":node.skin!=null,"vertices":node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()})
	for child in node.get_children():scan(child,section)
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game);game.update_camera(0);game.update_views(1.0/60)
	var actor: Dictionary=game.actors[0];var body: MeshInstance3D=actor.model.find_child("Source_Body",true,false)
	var skin: Skin=body.skin;var rig: Skeleton3D=actor.skeleton;var difference=0.0
	for i in range(skin.get_bind_count()):
		var bone=skin.get_bind_bone(i)
		if bone<0:bone=rig.find_bone(skin.get_bind_name(i))
		var error=skin.get_bind_pose(i)*rig.get_bone_global_rest(bone)
		difference=maxf(difference,error.origin.length()+error.basis.x.distance_to(Vector3.RIGHT)+error.basis.y.distance_to(Vector3.UP)+error.basis.z.distance_to(Vector3.BACK))
	print("SKIN_LAYOUT ",skin.get_bind_count()," bones=",rig.get_bone_count()," bind_error=",difference," source_transform=",body.transform)
	for actor_view in game.actors:scan(actor_view.root,"actors")
	for view in game.object_views.values():scan(view.root,"objects")
	for view in game.vehicle_views:scan(view.root,"vehicles")
	scan(game.static_prop_batches,"baked_props")
	if game.wall_batches!=null:scan(game.wall_batches,"wall_batches")
	if game.crowd_batches!=null:
		game.crowd_batches.refresh();print("CROWD_BATCHES groups=",game.crowd_batches.groups.size()," instances=",game.crowd_batches.entries.size()," cpu_ms=",game.crowd_batches.last_ms)
	if game.rigid_batches!=null:
		game.rigid_batches.refresh();print("RIGID_BATCHES groups=",game.rigid_batches.groups.size()," active=",game.rigid_batches.active_groups," instances=",game.rigid_batches.entries.size()," cpu_ms=",game.rigid_batches.last_ms)
	if game.vehicle_part_batches!=null:
		game.vehicle_part_batches.refresh();print("PALETTE_BATCHES groups=",game.vehicle_part_batches.groups.size()," active=",game.vehicle_part_batches.active_groups," nodes=",game.vehicle_part_batches.entries.size()," cpu_ms=",game.vehicle_part_batches.last_ms)
	var file=FileAccess.open("res://qa/performance/draw-inventory.json",FileAccess.WRITE);file.store_string(JSON.stringify({"groups":groups,"meshes":meshes},"\t"))
	print("DRAW_INVENTORY "+JSON.stringify(groups));game.free();quit()
