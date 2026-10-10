extends SceneTree
## Build the actual maximum-registration chapter, paused. No game inputs or ticks.
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	change_scene_to_file("res://proving_ground.tscn")
	for frame in range(10):await process_frame
	var game=current_scene
	if game==null:printerr("FAIL scene unavailable");quit(2);return
	game.process_mode=Node.PROCESS_MODE_DISABLED
	check(int(game.plan.godot3d.campaign_chapter)==4,"maximum mounted roster chapter selected")
	check(game.armory.visible and is_zero_approx(game.world.time),"native scene remains frozen in briefing")
	var count=0
	for group in game.flash_batches.pool.groups.values():
		count+=group.entries.size()
		check(group.instances.visible_instance_count==group.entries.size(),"draw count equals registered pieces")
		for handle in group.entries:check(int(handle.slot)<group.instances.instance_count,"native slot fits storage")
	var modeled=0
	for actor in game.actors:modeled+=physical_flash_pieces(actor.held)
	for vehicle in game.vehicle_views:modeled+=physical_flash_pieces(vehicle.root)
	check(count==modeled,"every actual modeled flash piece is registered")
	check(count>360,"native source roster exercises former overflow")
	check(game.flash_batches.pool.capacity==880,"muzzle-specific storage remains bounded")
	print("NATIVE_FLASH_STORAGE chapter=4 pieces=%d capacity=%d"%[count,game.flash_batches.pool.capacity])
	print("campaign_native_flash_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func physical_flash_pieces(node: Node) -> int:
	var result=0
	if node.name=="MuzzleFlash":
		for child in node.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:result+=1
		return result
	for child in node.get_children():result+=physical_flash_pieces(child)
	return result
