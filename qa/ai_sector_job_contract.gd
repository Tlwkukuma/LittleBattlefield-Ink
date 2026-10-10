extends SceneTree
## Bounded scheduler/query contract with synthetic ray results, no World or battle.
const Mission=preload("res://scripts/campaign_asset_mission.gd")
class Flat extends RefCounted:
	func height(_at: Vector2) -> float:return 0.0
class Coordinates extends RefCounted:
	func position(point,_plan: Dictionary) -> Vector2:return Vector2(float(point[0]),float(point[1]))
class Probe extends RefCounted:
	var terrain=Flat.new()
	var catalog=Coordinates.new()
	var plan={"godot3d":{"campaign_tactics":{"vehicle_frontage":[6,0]}}}
	var campaign={"points":[]}
	var time=0.0
	var topology_revision=0
	var ai_budget_usec=2000
	var vehicles=[]
	var units=[]
	var queries=0
	var clear_angle=INF
	func trace_3d(_origin: Vector3,direction: Vector3,_distance: float,_context: Dictionary,_walls: bool) -> Dictionary:
		queries+=1
		return {} if absf(wrapf(Vector2(direction.x,direction.z).angle()-clear_angle,-PI,PI))<.001 else {"blocked":true}
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():
	var world=Probe.new();var v={"id":0,"position":Vector2.ZERO,"angle":0.0,"profile":{"traverse":1.55},"emplacement":true,"destroyed":false}
	var job=Mission.begin_sector(v,Vector2.RIGHT)
	check(job.bearings.size()==6,"six remaining quarter/end-point candidates")
	Mission.pump_sector(world,v,job,0)
	check(world.queries==0 and job.next==0,"zero shared budget does no lane work")
	world.clear_angle=1.55*.25
	while not job.done:
		var previous=world.queries;Mission.pump_sector(world,v,job,1)
		check(world.queries-previous<=1,"positive residual budget cannot execute a multi-ray sweep")
	check(not job.result.is_empty() and is_equal_approx(Vector2(job.result.focus).angle(),world.clear_angle),"quarter-arc opening missed by fast probes is found")
	var completed=world.queries;Mission.pump_sector(world,v,job,350)
	check(world.queries==completed,"completed job cannot repeat geometry work")
	world.clear_angle=INF;job=Mission.begin_sector(v,Vector2.RIGHT)
	for i in range(6):
		var previous=world.queries;Mission.pump_sector(world,v,job)
		check(world.queries-previous==1,"blocked sector consumes exactly one query per visit")
	check(job.done and job.result.is_empty() and job.samples==6,"fully blocked legal arc terminates after finite candidates")
	job=Mission.begin_sector(v,Vector2.RIGHT);v.destroyed=true;completed=world.queries
	Mission.pump_sector(world,v,job)
	check(job.done and world.queries==completed,"destroyed emplacement cancels pending geometry")
	v.destroyed=false;job=Mission.begin_sector(v,Vector2.RIGHT);v.angle=.2;completed=world.queries
	Mission.pump_sector(world,v,job)
	check(job.done and job.get("invalidated",false) and world.queries==completed,"base rotation invalidates queued bearings before another ray")
	job=Mission.begin_sector(v,Vector2.RIGHT);v.position=Vector2(1,0)
	Mission.pump_sector(world,v,job)
	check(job.get("invalidated",false),"mount relocation invalidates queued sector")
	job=Mission.begin_sector(v,Vector2.RIGHT);v.id=1
	Mission.pump_sector(world,v,job)
	check(job.get("invalidated",false),"replacement gun cannot inherit previous sector job")
	v.id=0;v.position=Vector2.ZERO;v.angle=0.0;world.vehicles=[v];world.clear_angle=.25*1.55
	var controller=preload("res://scripts/campaign_vehicle_ai.gd").new();controller.world_ref=weakref(world);controller.assign_at=1000
	completed=world.queries
	check(not controller.prepare_mission(v) and world.queries-completed==4,"fallback is queued only after all four original fast probes fail")
	check(controller.mission_jobs.has(0),"failed fast probes produce one retained sector job")
	while not controller.mission_jobs[0].done:
		completed=world.queries;world.ai_budget_usec=2000;controller.tick()
		check(world.queries-completed<=1,"shared runtime scheduler services at most one fallback ray per tick")
	check(controller.prepare_mission(v) and controller.missions[0].sector_samples<=10,"completed sector grants use eligibility with observable bounded sample count")
	controller.missions.clear();world.clear_angle=0.0;completed=world.queries
	check(controller.prepare_mission(v) and world.queries-completed==1 and controller.mission_jobs.is_empty(),"passing fast probe does not enqueue fallback or add rays")
	controller.missions.clear();world.clear_angle=INF
	controller.prepare_mission(v)
	while not controller.mission_jobs[0].done:world.ai_budget_usec=2000;controller.tick()
	check(not controller.prepare_mission(v),"fully blocked fallback stores a negative mission cache")
	completed=world.queries;world.time=1.0
	check(not controller.prepare_mission(v) and world.queries==completed,"negative cache avoids repeating blocked work before expiry")
	world.time=6.0;controller.prepare_mission(v)
	check(world.queries-completed==4 and controller.mission_jobs.has(0),"negative cache expires and can recover after geometry changes")
	world.vehicles=[];controller.tick()
	check(controller.mission_jobs.is_empty(),"removing all guns invalidates queued sector work")
	print("AI_SECTOR_JOB checks=%d failures=%d; synthetic query budget only"%[checks,failures])
	quit(0 if failures==0 else 1)
