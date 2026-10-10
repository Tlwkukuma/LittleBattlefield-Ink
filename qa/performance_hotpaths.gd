extends SceneTree
## Frozen geometry/animation workload. Never steps battle, fires or calls Laya.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
var world
var output="baseline"
var jobs: Array=[]
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):output=arg.trim_prefix("--label=")
	var catalog=Catalog.new();world=World.new();world.setup(Orchard.plan(catalog),catalog)
	for unit in world.units:
		for offset in [0,7,17,23]:
			var target: Dictionary=world.units[(30 if unit.team==0 else 0)+(unit.id+offset)%30]
			var origin=Vector3(unit.position.x,unit.elevation+1.55,unit.position.y)
			var end=Vector3(target.position.x,target.elevation+1.25,target.position.y)
			jobs.append([origin,(end-origin).normalized(),origin.distance_to(end)])
	var result={"battle_steps":0,"model_requests":0,"units":world.units.size(),"ray_count":jobs.size(),"timings":{}}
	result.timings.terrain_rays=bench(func():
		for job in jobs:world.terrain.ray(job[0],job[1],job[2]))
	result.timings.world_rays=bench(func():
		for job in jobs:world.trace_3d(job[0],job[1],job[2],{},true))
	result.timings.movement_queries=bench(func():
		for unit in world.units:
			for offset in [Vector2.ZERO,Vector2(.08,0),Vector2(0,.08),Vector2(.08,.08)]:
				var at=unit.position+offset;world.ground_height(at,.31,unit.elevation+.221);world.blocked(at,.31,1.95,-1,world.terrain.height(at));world.terrain.speed_at(at))
	result.timings.perception=bench(func():
		for unit in world.units:
			if not unit.player:world.campaign_ai.perception.refresh(unit))
	DirAccess.make_dir_recursive_absolute("res://qa/performance")
	var file=FileAccess.open("res://qa/performance/"+output+"-hotpaths.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("FROZEN_PERFORMANCE "+JSON.stringify(result));quit()
func bench(action: Callable) -> Dictionary:
	action.call()
	var times=[]
	for repeat in range(7):
		var before=Time.get_ticks_usec();action.call();times.append((Time.get_ticks_usec()-before)/1000.0)
	times.sort()
	return {"median_ms":times[3],"min_ms":times[0],"max_ms":times[-1]}
