extends SceneTree
## Frozen geometry, motion integration and resource fixtures. No game/AI stepping.
const World=preload("res://scripts/proving_world.gd")
const OldWorld=preload("res://qa/performance/deep-before-source/reference_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Case=preload("res://scripts/spent_case_motion.gd")
const OldCase=preload("res://qa/performance/deep-before-source/spent_case_motion.gd")
const Particle=preload("res://scripts/fx_particle_state.gd")
const Canvas=preload("res://scripts/canvas_mesh_batch.gd")
const OldCanvas=preload("res://qa/performance/deep-before-source/canvas_mesh_batch.gd")
const Ring=preload("res://scripts/action_progress_ring.gd")
const Summary=preload("res://scripts/runtime_performance.gd")
var checks=0
var failures=0
var results={}
var rng:=RandomNumberGenerator.new()
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<12:push_error(label)
func same_float(a: float,b: float) -> bool:return a==b or is_equal_approx(a,b)
func _initialize():run.call_deferred()
func run():
	rng.seed=280938
	var catalog=Catalog.new();var current=World.new();var old=OldWorld.new()
	current.setup(Level.plan(catalog),catalog);old.setup(Level.plan(catalog),catalog)
	current.unit_grid_active=false;old.unit_grid_active=false
	var natural=0
	for o in current.objects:
		if o.has("nature_solids"):natural+=1
	results.nature_objects=natural
	queries(old,current);cases(old,current);canvas()
	check(current.time==0 and old.time==0 and current.shots==0 and old.shots==0,"no battle advancement")
	results.checks=checks;results.failures=failures
	FileAccess.open("res://qa/performance/deep-hotpath.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("DEEP_HOTPATH "+JSON.stringify(results));quit(0 if failures==0 else 1)

func queries(old,current):
	var fixtures=[];var ray_fixtures=[]
	for i in range(1800):
		var u: Dictionary=current.units[i%60].duplicate(true)
		var at: Vector2=u.position
		if i%3==0:at=current.objects[i%current.objects.size()].position+Vector2(rng.randf_range(-2,2),rng.randf_range(-2,2))
		elif i%3==1:at=current.vehicles[i%current.vehicles.size()].position+Vector2(rng.randf_range(-5,5),rng.randf_range(-5,5))
		u.position=at;u.elevation=current.terrain.height(at);u.stance=i%3;u.walk=0;u.last_clear={}
		u.requested_velocity=Vector2(rng.randf_range(-4,4),rng.randf_range(-4,4))
		fixtures.append(u)
		var direction=Vector3(rng.randf_range(-1,1),rng.randf_range(-.5,.5),rng.randf_range(-1,1)).normalized()
		if i%2==0:
			var vehicle: Dictionary=current.vehicles[i%current.vehicles.size()]
			var target=Vector3(vehicle.position.x,float(vehicle.get("elevation",0))+.7,vehicle.position.y)
			ray_fixtures.append({"origin":target-direction*8,"direction":direction,"length":16.0,"radius":[0.0,.025,.12][i%3]})
		else:ray_fixtures.append({"origin":Vector3(at.x,u.elevation+1.0,at.y),"direction":direction,"length":rng.randf_range(.2,40),"radius":[0.0,.025,.12][i%3]})
	for phase in range(2):
		if phase==1:
			for world in [old,current]:
				for v in world.vehicles:
					v.position+=Vector2(1.4,-1.2);v.angle+=.7;v.turret_angle-=.4;v.elevation=float(v.get("elevation",0))+.3;v.pose_basis=Basis(Vector3.RIGHT,.12)*Basis(Vector3.BACK,.19)
		for f in ray_fixtures:
			var a: Dictionary=old.trace_3d(f.origin,f.direction,f.length,{"radius":f.radius})
			var b: Dictionary=current.trace_3d(f.origin,f.direction,f.length,{"radius":f.radius})
			if a.get("type","")!=b.get("type","") or a.get("target",{}).get("id",-1)!=b.get("target",{}).get("id",-1):
				print("RAY_DIFFERENCE ",phase," ",f," before=",a.get("type",""),"/",a.get("target",{}).get("id",-1),"/",a.get("distance",INF)," after=",b.get("type",""),"/",b.get("target",{}).get("id",-1),"/",b.get("distance",INF))
			check(a.get("type","")==b.get("type","") and a.get("target",{}).get("id",-1)==b.get("target",{}).get("id",-1),"ray target/type, moving and tilted vehicles")
			check(same_float(a.get("distance",INF),b.get("distance",INF)) and a.get("region","")==b.get("region","") and a.get("col",-1)==b.get("col",-1) and a.get("row",-1)==b.get("row",-1),"ray distance/cell/body region")
	for source in fixtures:
		check(same_float(old.ground_height(source.position,.28,source.elevation+.221),current.ground_height(source.position,.28,source.elevation+.221)),"ground support")
		var a=source.duplicate(true);var b=source.duplicate(true)
		old.overlap_budget_usec=1000000;current.overlap_budget_usec=1000000
		old.move_unit(a,Vector2(1.2,-2.5),1.0/30);current.move_unit(b,Vector2(1.2,-2.5),1.0/30)
		check(a.position.is_equal_approx(b.position) and same_float(a.elevation,b.elevation) and a.velocity.is_equal_approx(b.velocity),"movement collision and support")
	var times={"movement":[[],[]],"rays":[[],[]]}
	old.overlap_budget_usec=0;current.overlap_budget_usec=0
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var world=old if mode==0 else current;var begin=Time.get_ticks_usec()
			for source in fixtures:world.move_unit(source.duplicate(true),Vector2(1.2,-2.5),1.0/30)
			times.movement[mode].append((Time.get_ticks_usec()-begin)/1000.0);begin=Time.get_ticks_usec()
			for f in ray_fixtures:world.trace_3d(f.origin,f.direction,f.length,{"radius":f.radius})
			times.rays[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	for key in times:results[key]={"fixtures":fixtures.size(),"before":Summary.summary(times[key][0]),"after":Summary.summary(times[key][1])}

func cases(old,current):
	var before=OldCase.new();var after=Case.new();var first=[];var second=[]
	for i in range(160):
		var u: Dictionary=current.units[i%60];var a=Node3D.new();var b=Node3D.new()
		a.position=Vector3(u.position.x,u.elevation+rng.randf_range(.03,1.5),u.position.y)
		a.rotation=Vector3(rng.randf_range(-PI,PI),rng.randf_range(-PI,PI),rng.randf_range(-PI,PI));a.scale=Vector3(.02,.02,rng.randf_range(.025,.13));b.transform=a.transform
		# Set Euler explicitly on both nodes to retain identical angle representation.
		b.rotation=a.rotation;b.scale=a.scale
		var data={"node":a,"velocity":Vector3(rng.randf_range(-2,2),rng.randf_range(-1,3),rng.randf_range(-2,2)),"spin":Vector3(3.3,4.9,-2.8),"gravity":9.8,"presentation":{"case_shape":"bottleneck"}}
		first.append(data);var copy=data.duplicate();copy.node=b;second.append(Particle.new(copy))
	for frame in range(120):
		before.begin_frame();after.begin_frame()
		for i in range(160):
			var a: Dictionary=first[i];var b: Particle=second[i]
			var old_sound=before.advance(a,1.0/30,old);var new_sound=after.advance_particle(b,1.0/30,current)
			check(a.node.position.is_equal_approx(b.node.position) and a.node.basis.is_equal_approx(b.node.basis),"case ejection/bounce/roll transform")
			check(a.velocity.is_equal_approx(b.velocity) and a.spin.is_equal_approx(b.spin) and a.settled==b.settled and a.rolling==b.rolling and a.bounces==b.bounces,"case motion state")
			check(old_sound==new_sound,"case impact audio remains equal")
	var times=[[],[]]
	# Active-flight workload: reset the same small state, leaving allocations outside
	# the timed loop. Each pair includes identical real-world support/sweep queries.
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var begin=Time.get_ticks_usec()
			for frame in range(12):
				var motion=before if mode==0 else after;motion.begin_frame()
				for i in range(160):
					var p=first[i] if mode==0 else second[i]
					p.node.position=Vector3(current.units[i%60].position.x,2,current.units[i%60].position.y);p.velocity=Vector3(1,-1,2);p.spin=Vector3(3.3,4.9,-2.8);p.settled=false;p.rolling=false;p.gravity=9.8
					if mode==0:before.advance(p,1.0/30,old)
					else:after.advance_particle(p,1.0/30,current)
			times[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	results.active_cases={"cases":160,"steps":12,"before":Summary.summary(times[0]),"after":Summary.summary(times[1])}
	for p in first:p.node.free()
	for p in second:p.node.free()

func canvas():
	var style=StyleBoxFlat.new();style.set_border_width_all(1);style.set_corner_radius_all(5)
	for i in range(50):
		var a=OldCanvas.new();var b=Canvas.new()
		for mesh in [a,b]:
			mesh.style(style,Rect2(5,7,298,103));mesh.arc(Vector2(120,100),28,-PI*.5,TAU*i/49-PI*.5,64,Color.WHITE,2,true)
		check(a.vertices==b.vertices and a.colors==b.colors and a.indices==b.indices and a.uvs==b.uvs,"canvas geometry and colours unchanged")
	var ring=Ring.new();var times=[[],[]]
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var begin=Time.get_ticks_usec()
			for frame in range(120):
				if mode==0:
					var paint=OldCanvas.new();paint.style(style,Rect2(5,7,298,103))
					for slot in range(5):paint.style(style,Rect2(slot*61,130,56,35))
					paint.arc(Vector2(frame,100),28,-PI*.5,TAU-PI*.5,64,Color(.1,.11,.12,.65),3.5,true)
					paint.arc(Vector2(frame,100),28,-PI*.5,TAU*frame/120-PI*.5,64,Color("eee8d8"),2,true);paint.mesh()
				else:ring.refresh(Vector2(frame,100),28,float(frame)/120,true)
			times[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	results.reload_ring_cpu={"updates":120,"before":Summary.summary(times[0]),"after":Summary.summary(times[1]),"note":"CPU geometry/uniform work only; GPU not measured"}
	ring.free()
