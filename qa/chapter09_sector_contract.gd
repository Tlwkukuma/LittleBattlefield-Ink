extends SceneTree
## Frozen chapter09 geometry. No battle update, movement, firing or input.
const World=preload("res://scripts/proving_world.gd")
class CountWorld extends World:
	var rays=0
	func trace_3d(origin: Vector3,direction: Vector3,distance: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
		rays+=1;return super.trace_3d(origin,direction,distance,p,walls_only)
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var world=CountWorld.new();world.setup(preload("res://scripts/campaign_catalog.gd").plan(catalog,9),catalog)
	var controller=world.campaign_ai.vehicle_ai;var mount={}
	for v in world.vehicles:
		if v.source_id=="emplacement-002":mount=v;break
	check(not mount.is_empty(),"original second chapter09 HMG exists")
	world.rays=0
	check(not controller.prepare_mission(mount) and world.rays==4,"actual geometry blocks all four legacy fast bearings")
	var visits=0
	while controller.mission_jobs.has(mount.id) and not controller.mission_jobs[mount.id].done and visits<6:
		world.ai_budget_usec=2000;var previous=world.rays;controller.tick();visits+=1
		check(world.rays-previous<=1,"actual scheduler visits at most one fallback ray")
	check(controller.prepare_mission(mount),"actual quarter/end-point opening makes original HMG eligible")
	var result: Dictionary=controller.missions[mount.id].result
	var angle=(Vector2(result.focus)-Vector2(mount.position)).angle()
	check(absf(wrapf(angle-mount.angle,-PI,PI))<=float(mount.profile.traverse)+.0001,"resolved direction respects original mechanical traverse")
	check(world.time==0 and world.shots==0,"frozen check never advances combat")
	print("CHAPTER09_SECTOR checks=%d failures=%d visits=%d rays=%d angle_fraction=%.4f"%[checks,failures,visits,world.rays,wrapf(angle-mount.angle,-PI,PI)/float(mount.profile.traverse)])
	quit(0 if failures==0 else 1)
