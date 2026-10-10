extends SceneTree
## Fixed movement/query work on restored snapshots; no battle step, shooting or input.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
var world
var label="before"
var samples: Array=[]
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	var catalog=Catalog.new();world=World.new();world.setup(Orchard.plan(catalog),catalog)
	for unit in world.units:samples.append(unit.duplicate(true))
	var results={"units":samples.size(),"battle_steps":0,"simulation_time":world.time,"timings":{}}
	results.timings.ground=bench(func():
		for u in samples:world.ground_height(u.position,.28,u.elevation+.221))
	results.timings.blocked=bench(func():
		for u in samples:world.blocked(u.position,.28,1.95,-1,u.elevation))
	results.timings.steer=bench(func():
		for u in samples:world.campaign_ai.tactics.steer(u,Vector2(0,-2.8)))
	if world.has_method("build_unit_index"):
		world.build_unit_index()
		results.timings.steer_indexed=bench(func():
			for u in samples:world.campaign_ai.tactics.steer(u,Vector2(0,-2.8)))
		world.unit_grid_active=false
	results.timings.movement=bench(func():
		for saved in samples:
			var u=saved.duplicate(true);world.move_unit(u,Vector2(1.2,-2.5),1.0/30.0))
	results.timings.vertical=bench(func():
		for saved in samples:
			var u=saved.duplicate(true);World.Traversal.vertical_step(world,u,1.0/30.0))
	results.timings.paths=bench(func():
		for i in range(2):world.campaign_ai.path_between(samples[i].position,Vector2.ZERO))
	results.timings.perception=bench(func():
		for u in samples:world.campaign_ai.perception.refresh(u))
	var output=FileAccess.open("user://movement-"+label+".json" if not OS.has_feature("editor") else "res://qa/performance/movement-"+label+".json",FileAccess.WRITE)
	if output!=null:output.store_string(JSON.stringify(results,"\t"))
	print("MOVEMENT_COST "+JSON.stringify(results));quit()
func bench(action: Callable) -> Dictionary:
	action.call();var values=[]
	for i in range(21):
		var started=Time.get_ticks_usec();action.call();values.append((Time.get_ticks_usec()-started)/1000.0)
	values.sort();return {"p50_ms":values[10],"p95_ms":values[19],"max_ms":values[-1]}
