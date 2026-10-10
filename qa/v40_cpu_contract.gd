extends SceneTree
## Frozen resource, geometry and formula checks. No game stepping or inputs.
const World=preload("res://scripts/proving_world.gd")
const OldWorld=preload("res://qa/performance/frame-budget-v39-source/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Blood=preload("res://scripts/blood_effects.gd")
const OldBlood=preload("res://qa/performance/frame-budget-v39-source/blood_effects.gd")
const Index=preload("res://scripts/unit_ray_index.gd")
const OldIndex=preload("res://qa/performance/frame-budget-v39-source/unit_ray_index.gd")
const Summary=preload("res://scripts/runtime_performance.gd")
var checks: int=0
var failures: int=0
var result: Dictionary={}
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<12:push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new();var world=World.new();world.setup(Level.plan(catalog),catalog)
	var old=OldWorld.new()
	for key in ["objects","units","vehicles","bounds","terrain","catalog","player"]:old.set(key,world.get(key))
	old.build_index()
	var rng:=RandomNumberGenerator.new();rng.seed=2840
	var rays: Array=[]
	for i in range(2400):
		var at: Vector2=world.units[i%60].position if i%2==0 else world.objects[i%world.objects.size()].position
		at+=Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		rays.append({"origin":Vector3(at.x,world.terrain.height(at)+rng.randf_range(.04,2.4),at.y),"direction":Vector3(rng.randf_range(-1,1),rng.randf_range(-.5,.5),rng.randf_range(-1,1)).normalized(),"distance":rng.randf_range(.02,1.2) if i%3 else rng.randf_range(1,35),"radius":[0.0,.025,.12][i%3]})
	for r in rays:
		var a: Dictionary=old.trace_3d(r.origin,r.direction,r.distance,{"radius":r.radius},true)
		var b: Dictionary=world.trace_3d(r.origin,r.direction,r.distance,{"radius":r.radius},true)
		check(a.get("type","")==b.get("type","") and a.get("target",{}).get("id",-1)==b.get("target",{}).get("id",-1),"same ray target")
		check(a.get("distance",INF)==b.get("distance",INF) and a.get("col",-1)==b.get("col",-1) and a.get("row",-1)==b.get("row",-1),"same distance and wall cell")
	var times=[[],[]]
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var target=old if mode==0 else world;var started:=Time.get_ticks_usec()
			for r in rays:target.trace_3d(r.origin,r.direction,r.distance,{"radius":r.radius},true)
			times[mode].append((Time.get_ticks_usec()-started)/1000.0)
	result.rays={"queries":rays.size(),"before":Summary.summary(times[0]),"after":Summary.summary(times[1])}
	var previous=OldIndex.new();var current=Index.new()
	for phase in range(4):
		if phase>0:
			for unit in world.units:
				unit.position+=Vector2(1.1,-1.4);unit.alive=phase!=2 or int(unit.id)%3!=0
		previous.begin(world.units);current.begin(world.units)
		for r in rays:
			var a:=Vector2(r.origin.x,r.origin.z);var b:=a+Vector2(r.direction.x,r.direction.z)*float(r.distance)
			check(previous.query(a,b,.025)==current.query(a,b,.025),"persistent unit index matches rebuild including death and movement")
	times=[[],[]]
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var target=previous if mode==0 else current;var started:=Time.get_ticks_usec()
			for iteration in range(120):target.begin(world.units)
			times[mode].append((Time.get_ticks_usec()-started)/1000.0)
	result.unit_index={"refreshes":120,"before":Summary.summary(times[0]),"after":Summary.summary(times[1])}
	world.build_unit_index()
	for iteration in range(8):world.build_unit_index()
	var indexed: int=0
	for bucket in world.unit_grid.values():indexed+=bucket.size()
	check(indexed==world.units.size(),"persistent steering cells contain each unit exactly once")
	var original=OldBlood.new();var gpu=Blood.new()
	original.process_mode=Node.PROCESS_MODE_DISABLED;gpu.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(original);root.add_child(gpu);gpu.warming=false
	original.world=old;gpu.world=world
	for i in range(240):
		var r: Dictionary=rays[i]
		var p={"origin":r.origin,"velocity":r.direction*2,"gravity":12.0,"life":.7,"mark":true,"landing":Vector3.ZERO}
		var a=p.duplicate(true);var b=p.duplicate(true);original.trace_budget=96;gpu.trace_budget=96
		original.prepare_flight(a);gpu.prepare_flight(b)
		check(a==b,"blood contact arc and landing remain exact")
	for i in range(192):
		var p={"origin":Vector3(i*.01,1,0),"velocity":Vector3(1,2,.4),"gravity":3.0 if i%3==0 else 12.0,"age":.1,"life":.8,"radius":.07,"seed":i/192.0,"splash":i%3==0,"color":Color("b73443"),"mark":false}
		original.drops.append(p.duplicate(true));gpu.drops.append(p);gpu.gpu.add(p,gpu.age,false)
	for i in range(96):
		var stain={"radius":.07,"landing":Vector3(i*.02,0,0),"seed":i/96.0}
		original.add_stain(stain);gpu.add_stain(stain)
	original.write_batches();gpu.write_batches()
	check(gpu.spray_mesh==gpu.stain_mesh and gpu.get_child_count()==1,"drops and stains share one render resource")
	# Dummy rendering does not implement MultiMesh GPU readback. Actual slot
	# contents are checked in gpu_render_contract using the OpenGL renderer.
	var frame:=Basis(Vector3.RIGHT,-PI*.25);var max_error: float=0.0
	for p in gpu.drops:
		var origin: Color=gpu.gpu.image.get_pixel(0,p.gpu_slot);var motion: Color=gpu.gpu.image.get_pixel(1,p.gpu_slot);var style: Color=gpu.gpu.image.get_pixel(2,p.gpu_slot)
		for age: float in [0.0,.1,.35,.7]:
			var velocity: Vector3=p.velocity-Vector3.UP*float(p.gravity)*age
			var projected:=Vector2(velocity.dot(frame.x),velocity.dot(frame.y))
			var angle:=projected.angle()-PI*.5 if projected.length_squared()>.001 else 0.0
			var radius: float=maxf(p.radius,.015*1.8);var ratio: float=age/p.life
			var scale: float=lerpf(.65,1.25,smoothstep(0,.45,ratio)) if p.splash else 1.0
			var pose:=Transform3D(frame*Basis(Vector3.BACK,angle)*Basis.from_scale(Vector3(radius*scale,radius*(1.3 if p.splash else 1.9)*scale,1)),Blood.flight(p,age)+frame.z*.025)
			var shader_velocity:=Vector3(motion.r,motion.g,motion.b)-Vector3.UP*style.g*age
			var screen:=Vector2(shader_velocity.dot(frame.x),shader_velocity.dot(frame.y))
			var shader_angle:=screen.angle()-PI*.5 if screen.length_squared()>.001 else 0.0
			var shader_scale: float=lerpf(.65,1.25,smoothstep(0,.45,age/motion.a)) if style.a>.5 else 1.0
			var shader_radius:=maxf(style.r,.015*1.8)
			var position:=Vector3(origin.r,origin.g,origin.b)+Vector3(motion.r,motion.g,motion.b)*age-Vector3.UP*style.g*age*age*.5
			for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				var rotated: Vector2=(corner*Vector2(shader_radius,shader_radius*(1.3 if style.a>.5 else 1.9))*shader_scale).rotated(shader_angle)
				var actual:=position+frame*Vector3(rotated.x,rotated.y,.025)
				var expected:=pose*Vector3(corner.x,corner.y,0)
				max_error=maxf(max_error,actual.distance_to(expected));check(actual.distance_to(expected)<.00001,"GPU drop vertices preserve original visible motion")
	var uploads: int=gpu.gpu.uploads
	times=[[],[]]
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var target=original if mode==0 else gpu;var started:=Time.get_ticks_usec()
			for frame_index in range(120):target.write_batches()
			times[mode].append((Time.get_ticks_usec()-started)/1000.0)
	check(gpu.gpu.uploads==uploads,"no per-frame droplet/stain buffer uploads")
	result.blood_presentation={"drops":192,"stains":96,"frames":120,"max_vertex_error":max_error,"before":Summary.summary(times[0]),"after":Summary.summary(times[1])}
	gpu.advance(20);check(gpu.drops.is_empty() and gpu.stains.is_empty() and gpu.gpu.free_drops.size()==192 and gpu.gpu.free_stains.size()==96,"all expired GPU slots reusable")
	check(world.time==0 and world.shots==0,"no simulated battle")
	original.free();gpu.free();result.checks=checks;result.failures=failures
	FileAccess.open("res://qa/performance/v40-cpu.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("V40_CPU_CONTRACT "+JSON.stringify(result));quit(0 if failures==0 else 1)
