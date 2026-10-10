extends SceneTree
## Fixed wall-resource fixtures only: no game simulation, damage events or input.
const Surface=preload("res://qa/performance/frame-budget-v43-source/retained_wall_surface.gd")
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	var batch=preload("res://qa/performance/frame-budget-v43-source/wall_batches.gd").new();game.stage.add_child(batch);batch.configure(game.world.objects,game.object_views)
	var selected=[];var cells=0
	for object in game.world.objects:
		if not batch.members.has(object.id) or object.rows<3:continue
		selected.append(object);cells+=object.hp.size()
		if cells>=204:break
	var results=[]
	for state in [1.0,.4,0.0]:
		for object in selected:
			for index in range(object.hp.size()):
				if not object.get("opening_cells",{}).has(index):object.hp[index]=object.max_hp*state
		var generation=0;var packing=0;var upload=0;var vertices=0;var bytes=0
		for object in selected:
			var member=batch.members[object.id];var surface=batch.sectors[member.sector].surface
			for index in range(object.hp.size()):
				var start=Time.get_ticks_usec();var data=batch.geometry_at(object,index,INF);generation+=Time.get_ticks_usec()-start
				start=Time.get_ticks_usec();Surface.prepare(data);packing+=Time.get_ticks_usec()-start
				start=Time.get_ticks_usec();surface.update(member.chunks[index],data);upload+=Time.get_ticks_usec()-start
				vertices+=data.v.size()
			bytes+=surface.uploaded_bytes
		results.append({"state":state,"geometry_ms":generation/1000.0,"packing_ms":packing/1000.0,"upload_ms":upload/1000.0,"vertices":vertices,"cumulative_bytes":bytes})
	print("WALL_SPIKE_COST "+JSON.stringify({"cells":cells,"results":results,"time":game.world.time,"shots":game.world.shots}))
	game.free();quit()
