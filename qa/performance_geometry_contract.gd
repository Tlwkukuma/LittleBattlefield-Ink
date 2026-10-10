extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const BeforeWorld=preload("res://qa/performance/baseline-source/proving_world.gd")
const BeforeTerrain=preload("res://qa/performance/baseline-source/terrain_surface.gd")
var checks=0
var failures=0
func check(ok: bool,description: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<=12:printerr("FAIL "+description)
func same_hit(a: Dictionary,b: Dictionary) -> bool:
	return a.is_empty() and b.is_empty() or (not a.is_empty() and not b.is_empty() and a.type==b.type and absf(float(a.distance)-float(b.distance))<.0002)
func _initialize():
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	var old=BeforeWorld.new();old.objects=world.objects;old.units=world.units;old.vehicles=world.vehicles;old.obstacle_grid=world.obstacle_grid;old.bounds=world.bounds
	var terrain=BeforeTerrain.new();old.terrain=terrain
	for key in ["bounds","cell","size","heights","features","active"]:terrain.set(key,world.terrain.get(key))
	var rng=RandomNumberGenerator.new();rng.seed=92801
	for iteration in range(1200):
		var p=Vector2(rng.randf_range(-41.25,41.25),rng.randf_range(-26.25,26.25))
		check(absf(world.terrain.height(p)-terrain.height(p))<.0001,"height %d"%iteration)
		check(absf(world.terrain.grade(p)-terrain.grade(p))<.0001,"grade %d"%iteration)
		var origin=Vector3(p.x,rng.randf_range(-1.6,5),p.y)
		var end=Vector3(rng.randf_range(-45,45),rng.randf_range(-2,5),rng.randf_range(-30,30))
		if iteration%8==0:end=origin+Vector3.DOWN*10
		elif iteration%8==1:end=origin+Vector3.RIGHT*40
		elif iteration%8==2:end=origin+Vector3.FORWARD*40
		var vector=end-origin;var direction=vector.normalized();var length=vector.length()
		check(same_hit(world.terrain.ray(origin,direction,length),terrain.ray(origin,direction,length)),"terrain ray %d"%iteration)
		var settings={"radius":[0,.04,.16,.8][iteration%4]}
		check(same_hit(world.trace_3d(origin,direction,length,settings),old.trace_3d(origin,direction,length,settings)),"world ray %d"%iteration)
		var elevation=terrain.height(p)
		check(absf(world.collision_depth(p,.31,1.95,-1,elevation)-old.collision_depth(p,.31,1.95,-1,elevation))<.0001,"body clearance %d"%iteration)
		check(absf(world.ground_height(p,.31,elevation+.23)-old.ground_height(p,.31,elevation+.23))<.0001,"support %d"%iteration)
		if iteration==599:
			# Same live destructive grid for both algorithms; no gameplay or events.
			for object in world.objects:
				for index in range(0,object.hp.size(),3):object.hp[index]=0
			for vehicle in world.vehicles:vehicle.position+=Vector2(2,-1);vehicle.angle+=.37;vehicle.turret_angle-=.49
	check(world.time==0 and world.shots==0,"no battle progression")
	print("PERFORMANCE_GEOMETRY checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
