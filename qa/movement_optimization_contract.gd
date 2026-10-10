extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const BeforeWorld=preload("res://qa/performance/movement-before-source/proving_world.gd")
const BeforeTactics=preload("res://qa/performance/movement-before-source/campaign_tactics.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const RenderMotion=preload("res://scripts/render_motion.gd")
class ReferenceWorld extends BeforeWorld:
	# The vehicle task independently replaced its narrow phase. Keep that shared
	# contact model equal while comparing the old and new obstacle spatial indexes.
	func collision_depth(point: Vector2,radius: float,height: float,ignore_vehicle: int=-1,base_height: float=0.0,first_only: bool=false) -> float:
		var saved=vehicles;vehicles=[]
		var depth=super.collision_depth(point,radius,height,ignore_vehicle,base_height,first_only);vehicles=saved
		for vehicle in saved:
			if vehicle.id==ignore_vehicle:continue
			var contact=preload("res://scripts/vehicle_person_contact.gd").contact(vehicle,point,radius,base_height,height,first_only)
			if contact.is_empty():continue
			if first_only:return maxf(depth,contact.depth)
			depth=maxf(depth,contact.depth)
		return depth
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<=15:printerr("FAIL "+label)
func _initialize():
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	var before=ReferenceWorld.new()
	# The cover-pose work now derives fallback head height from the supplied rig.
	# Give both implementations the same explicit CURRENT hit capsules so this
	# regression test compares indexing/ray traversal, not two head-height designs.
	for unit in world.units:
		var base=Vector3(unit.position.x,unit.elevation,unit.position.y);var head=World.head_center(unit)
		unit.hit_shapes=[{"a":head,"b":head,"radius":.27,"region":"head"},{"a":base+Vector3.UP*.18,"b":head-Vector3.UP*.35,"radius":.28,"region":"body"}]
	for key in ["objects","units","vehicles","bounds","terrain","catalog","player","campaign"]:before.set(key,world.get(key))
	before.build_index()
	var random=RandomNumberGenerator.new();random.seed=92860
	for i in range(1600):
		var point=Vector2(random.randf_range(-42,42),random.randf_range(-27,27))
		if i%2==0:
			var object: Dictionary=world.objects[i%world.objects.size()]
			point=object.position+Vector2(random.randf_range(-2,2),random.randf_range(-2,2))
		var base=world.terrain.height(point);var radius=[.025,.28,.31,.6,.8][i%5]
		check(absf(world.ground_height(point,radius,base+.221)-before.ground_height(point,radius,base+.221))<.0001,"support %d"%i)
		check(absf(world.collision_depth(point,radius,1.95,-1,base)-before.collision_depth(point,radius,1.95,-1,base))<.0001,"collision %d"%i)
		if absf(world.collision_depth(point,radius,1.95,-1,base)-before.collision_depth(point,radius,1.95,-1,base))>=.0001:print("COLLISION_DETAIL ",point," r=",radius," height=",base," current=",world.collision_depth(point,radius,1.95,-1,base)," prior=",before.collision_depth(point,radius,1.95,-1,base))
		var material="grass"
		for feature in world.terrain.features:
			if world.terrain.contains(feature,point):material=feature.id
		check(world.terrain.material_at(point)==material,"exact material %d"%i)
		var profile=world.terrain.profile_at(point)
		var speed=lerpf(.98,.64,float(profile.softness)) if "snow" in material else lerpf(.96,.73,float(profile.softness)) if "desert" in material else .82 if "sand" in material else .94 if "trench" in material or "red-earth" in material else 1.0
		check(is_equal_approx(world.terrain.speed_at(point),speed),"exact speed %d"%i)
		var origin=Vector3(point.x,random.randf_range(-1.6,5),point.y)
		var line=Vector3(random.randf_range(-42,42),random.randf_range(-2,5),random.randf_range(-27,27))-origin
		var query={"radius":[0,.04,.16,.8][i%4]}
		var a=world.trace_3d(origin,line.normalized(),line.length(),query)
		var b=before.trace_3d(origin,line.normalized(),line.length(),query)
		check(a.is_empty() and b.is_empty() or not a.is_empty() and not b.is_empty() and a.type==b.type and absf(a.distance-b.distance)<.0002,"ray before/after %d"%i)
		if i==799:
			for object in world.objects:
				for index in range(0,object.hp.size(),3):object.hp[index]=0
			for vehicle in world.vehicles:vehicle.position+=Vector2(2,-1);vehicle.angle+=.37;vehicle.turret_angle-=.49
	var old_tactics=BeforeTactics.new();old_tactics.configure(before,world.campaign_ai)
	world.build_unit_index()
	for u in world.units:
		var velocity=Vector2(1.2,-2.5)
		check(world.campaign_ai.tactics.steer(u,velocity).distance_to(old_tactics.steer(u,velocity))<.00001,"neighbor equivalence %d"%u.id)
		u.position+=Vector2(2.1,-1.3);world.index_unit(u)
		check(world.campaign_ai.tactics.steer(u,velocity).distance_to(old_tactics.steer(u,velocity))<.00001,"neighbor cell crossing %d"%u.id)
	world.unit_grid_active=false
	for u in world.units:
		for velocity in [Vector2.ZERO,Vector2(2.8,0),Vector2(0,-2.8),Vector2(2,2)]:
			var a=u.duplicate(true);var b=u.duplicate(true)
			a.position=u.spawn;b.position=u.spawn;a.elevation=world.terrain.height(a.position);b.elevation=a.elevation
			a.requested_velocity=velocity;b.requested_velocity=velocity
			world.overlap_budget_usec=200000;before.overlap_budget_usec=200000
			world.move_unit(a,velocity,1.0/30);before.move_unit(b,velocity,1.0/30)
			check(a.position.distance_to(b.position)<.0001 and absf(a.elevation-b.elevation)<.0001,"same movement %d"%u.id)
			if a.position.distance_to(b.position)>=.0001 or absf(a.elevation-b.elevation)>=.0001:print("MOVEMENT_DETAIL ",u.id," velocity=",velocity," start=",u.spawn," current=",a.position," prior=",b.position," heights=",a.elevation,"/",b.elevation)
	var actor={"position":Vector2.ZERO,"elevation":0.0,"alive":true,"mounted":-1}
	RenderMotion.before_step([actor]);actor.position=Vector2(1,0);RenderMotion.after_step([actor])
	check(RenderMotion.sample(actor,.5)==Vector3(.5,0,0),"render half-step")
	check(actor.position==Vector2(1,0),"interpolation never moves simulation")
	actor.position=Vector2(4,0)
	check(RenderMotion.sample(actor,.5)==Vector3(4,0,0),"teleports discard stale endpoints")
	check(world.time==0 and world.shots==0,"no battle progression")
	print("MOVEMENT_OPTIMIZATION checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
