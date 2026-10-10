extends SceneTree
## Frozen resource microbenchmark. Never advances battle or sends game input.
const Terrain=preload("res://scripts/terrain_art.gd")
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	var records=[];var total=0;var cells=0
	for object in game.world.objects:
		if not game.wall_batches.members.has(object.id):continue
		var node=game.object_views[object.id].mesh
		total+=node.mesh.surface_get_array_len(0) if node.mesh.get_surface_count()>0 else 0;cells+=object.hp.size()
		if records.size()>=20:continue
		var began=Time.get_ticks_usec();var mesh=Terrain.wall_mesh(object);var generated=Time.get_ticks_usec()
		node.mesh=mesh;game.wall_batches.changed(object);game.wall_batches.flush()
		records.append({"id":object.id,"cells":object.hp.size(),"vertices":mesh.surface_get_array_len(0) if mesh.get_surface_count()>0 else 0,"generate_ms":(generated-began)/1000.0,"merge_ms":game.wall_batches.last_ms})
	print("WALL_RESOURCE_BASELINE "+JSON.stringify({"total_vertices":total,"cells":cells,"sectors":game.wall_batches.sectors.size(),"records":records,"time":game.world.time,"shots":game.world.shots}))
	game.free();quit()
