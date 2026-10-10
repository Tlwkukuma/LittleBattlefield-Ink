extends SceneTree
## Frozen scene resource check: no simulation, input, movement or firing.
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():run.call_deferred()
func run():
	var scene="res://proving_ground_2.tscn" if "--range2" in OS.get_cmdline_user_args() else "res://proving_ground.tscn"
	var game=load(scene).instantiate()
	game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.armory.hide();game._process(0);game.rigid_batches.refresh()
	var shadows=0
	for view in game.vehicle_views:
		var shadow=view.body.get_node_or_null("GroundShadow")
		if shadow==null:continue
		shadows+=1
		var stale=false
		var cached_bounds=AABB()
		if game.rigid_batches.entries.has(shadow.get_instance_id()):
			for handle in game.rigid_batches.entries[shadow.get_instance_id()].handles:
				var drawn=game.rigid_batches.groups[handle.key].instances.mesh
				stale=stale or drawn!=shadow.mesh
				cached_bounds=handle.pose*drawn.get_aabb()
		var actual_bounds=shadow.global_transform*shadow.mesh.get_aabb()
		print("SHADOW_RESOURCE "+JSON.stringify({"stale_mesh":stale,"cached_bounds":str(cached_bounds),"actual_bounds":str(actual_bounds),"source_layers":shadow.layers,"transform":str(shadow.global_transform)}))
		check(not stale,"vehicle shadow must draw its current terrain-conforming mesh")
		check(shadow.layers!=0,"dynamic vehicle shadow must retain its live renderer")
		check(not game.rigid_batches.entries.has(shadow.get_instance_id()),"static mesh batch must exclude dynamic geometry")
		check(shadow.global_transform.is_equal_approx(Transform3D.IDENTITY),"world-space shadow mesh has identity transform")
		check(Vector2(actual_bounds.get_center().x,actual_bounds.get_center().z).distance_to(view.root.vehicle.position)<.01,"shadow stays at the vehicle, never at map origin")
		var original=shadow.mesh
		preload("res://scripts/vehicle_ground_effects.gd").update_shadow(view,view.root.vehicle,game.world.terrain)
		check(shadow.mesh==original,"unchanged vehicle does not rebuild its shadow")
	check(shadows>0,"scene contains vehicle shadows")
	check(game.world.time==0 and game.world.shots==0,"no gameplay was advanced")
	print("VEHICLE_SHADOW_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"scene":game.plan.id,"shadows":shadows,"simulation_time":game.world.time,"shots":game.world.shots}))
	game.free();quit(0 if failures==0 else 1)
