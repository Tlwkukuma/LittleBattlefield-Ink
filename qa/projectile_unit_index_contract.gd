extends SceneTree
## Geometry only: no simulation steps, AI decisions, inputs, firing or damage.
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const Geometry=preload("res://scripts/aim_geometry.gd")
var checks=0
var failures=0
var exact_hits=0

func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<=12:printerr("FAIL "+label)

func _initialize():run.call_deferred()

func reference(world):
	# Preserve the old all-unit loop and filters, while sharing all other CURRENT
	# geometry code, including concurrent vehicle work, with the indexed version.
	var source=FileAccess.get_file_as_string("res://scripts/proving_world.gd").replace("\r\n","\n")
	source=source.replace("\tvar source_id=int(p.get(\"source\",-1));var team_id=int(p.get(\"team\",-99));var already_hit: Array=p.get(\"hit\",[])\n", "")
	source=source.replace("for u in unit_ray_candidates(start,start+travel*limit,radius):", "for u in units:")
	source=source.replace("for u: Dictionary in unit_ray_candidates(start,start+travel*limit,radius):", "for u: Dictionary in units:")
	check("for u: Dictionary in units:" in source or "for u in units:" in source,"reference uses full unit scan")
	source=source.replace("if not u.alive or u.id==source_id or u.team==team_id or u.id in already_hit or enclosed(u):continue", "if not u.alive or enclosed(u) or u.id==int(p.get(\"source\",-1)) or u.team==int(p.get(\"team\",-99)) or u.id in p.get(\"hit\",[]):continue")
	var script=GDScript.new();script.source_code=source
	if script.reload()!=OK:check(false,"reference compile");return null
	var ref=script.new()
	for key in ["objects","units","vehicles","bounds","terrain","catalog","player"]:ref.set(key,world.get(key))
	ref.build_index()
	return ref

func compare(world,ref,origin: Vector3,line: Vector3,query: Dictionary={},walls_only: bool=false):
	var direction=line.normalized();var distance=line.length()
	var a=world.trace_3d(origin,direction,distance,query,walls_only)
	var b=ref.trace_3d(origin,direction,distance,query,walls_only)
	var same=a.is_empty() and b.is_empty()
	if not a.is_empty() and not b.is_empty():
		same=a.type==b.type and absf(a.distance-b.distance)<.00001 and a.get("region","")==b.get("region","") and a.get("target",{}).get("id",-1)==b.get("target",{}).get("id",-1)
		if a.type=="unit":exact_hits+=1
	check(same,"exact ray %s %s %s"%[origin,line,query])

func capsule(unit: Dictionary):
	var base=Vector3(unit.position.x,unit.elevation,unit.position.y)
	var height=[1.80,1.31,.46][unit.stance]
	var head=base+Vector3.UP*height+Vector3(0,0,.75 if unit.stance==2 else 0.0)
	unit.hit_shapes=[{"a":head,"b":head,"radius":.25,"region":"head"},{"a":base+Vector3.UP*.2,"b":head-Vector3.UP*.35,"radius":.28,"region":"body"}]

func bench(world,ref) -> Array:
	var records=[]
	for length in [.12,8.0,25.0]:
		for count in [5,35,80]:
			var rays=[]
			for i in range(count):
				var unit=world.units[(i*17)%world.units.size()]
				var flat=Vector2.from_angle(float(i)*2.3999632297)
				rays.append([Vector3(unit.position.x,unit.elevation+1.3,unit.position.y),Vector3(flat.x,-.08 if i%3==0 else 0.0,flat.y).normalized(),{"source":unit.id,"team":unit.team}])
			var old=[];var indexed=[];var builds=[]
			for repeat in range(27):
				for mode in ([0,1] if repeat%2==0 else [1,0]):
					var began=Time.get_ticks_usec()
					if mode==1:world.unit_ray_index.begin(world.units)
					var built=Time.get_ticks_usec()
					for ray in rays:
						if mode==1:world.trace_3d(ray[0],ray[1],length,ray[2])
						else:ref.trace_3d(ray[0],ray[1],length,ray[2])
					var elapsed=(Time.get_ticks_usec()-began)/1000.0
					world.unit_ray_index.active=false
					if repeat<2:continue
					if mode==0:old.append(elapsed)
					else:indexed.append(elapsed);builds.append((built-began)/1000.0)
			world.unit_ray_index.begin(world.units,true);world.profile_ai=true
			for ray in rays:world.trace_3d(ray[0],ray[1],length,ray[2])
			var counts=world.unit_ray_index.diagnostics();world.profile_ai=false;world.unit_ray_index.active=false
			old.sort();indexed.sort();builds.sort()
			records.append({"length_m":length,"rays":count,"samples":old.size(),"full_scan_p50_ms":old[old.size()/2],"indexed_with_build_p50_ms":indexed[indexed.size()/2],"build_p50_ms":builds[builds.size()/2],"index_counts":counts})
	return records

func run():
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	for unit in world.units:capsule(unit)
	var ref=reference(world)
	if ref==null:quit(1);return
	world.unit_ray_phase=true
	check(world.unit_ray_index.active and world.unit_ray_index.tree.entries.size()==world.units.size(),"setup prepares persistent spatial index")
	world.unit_ray_candidates(Vector2.ZERO,Vector2.ONE,0)
	check(world.unit_ray_index.active,"first unit ray uses prepared index")
	world.unit_ray_phase=false;world.unit_ray_index.active=false
	check(world.unit_ray_candidates(Vector2.ZERO,Vector2.ONE,0).size()<world.units.size() and world.unit_ray_index.active,"outside projectile scope synchronizes live spatial candidates")
	var random=RandomNumberGenerator.new();random.seed=92834
	world.unit_ray_index.begin(world.units)
	for i in range(2400):
		var unit: Dictionary=world.units[i%world.units.size()]
		var at=Vector3(unit.position.x,unit.elevation+[.3,1.1,1.8][i%3],unit.position.y)
		var offset=Vector3(random.randf_range(-16,16),random.randf_range(-.2,2),random.randf_range(-16,16))
		if i%7==0:offset=Vector3(0,4,0)
		elif i%7==1:offset=Vector3(8,0,0)
		elif i%7==2:offset=Vector3(0,0,-8)
		var query={"radius":[0,.04,.16,.6,.8,4.2][i%6]}
		if i%4==1:query.team=unit.team
		elif i%4==2:query.source=unit.id;query.hit=[world.units[(i+3)%world.units.size()].id]
		if i%5==0:query.camera_pick=true
		compare(world,ref,at-offset,offset*1.3,query,i%13==0)
	# Conservative candidate coverage against the exact pre-existing coarse box.
	for i in range(1100):
		var a=Vector3(random.randf_range(-48,48),1.1,random.randf_range(-30,30))
		var line=Vector3(random.randf_range(-32,32),0,random.randf_range(-32,32))
		if i%5==0:a=Vector3((i%12-6)*4,1.1,(i%8-4)*4);line=Vector3(-16,0,-16)
		if i%5==1:line=Vector3(0,2,0)
		if i%5==2:line=Vector3(-.0000001,0,20)
		var radius=[0,.04,.6,.8,4.2][i%5];var pad=Vector3.ONE*radius
		var ids={}
		for unit in world.unit_ray_index.query(Vector2(a.x,a.z),Vector2(a.x+line.x,a.z+line.z),radius):ids[unit.id]=true
		for unit in world.units:
			var base=Vector3(unit.position.x,unit.elevation,unit.position.y)
			var intersects=Geometry.box_hit(a,line.normalized(),base-Vector3(1.6,.1,1.6)-pad,base+Vector3(1.6,2.2,1.6)+pad,line.length())<INF
			check(not intersects or ids.has(unit.id),"conservative candidate %d/%d"%[i,unit.id])
	# Position/state changes inside a query batch, plus inactive live fallback.
	var unit: Dictionary=world.units[7]
	for point in [Vector2(-4,-4),Vector2(0,0),Vector2(4,4),Vector2(27,-22)]:
		unit.position=point;unit.elevation=2;capsule(unit);world.index_unit(unit)
		compare(world,ref,Vector3(point.x-3,3,point.y),Vector3(6,0,0))
	unit.alive=false;world.index_unit(unit)
	compare(world,ref,Vector3(24,3,-22),Vector3(6,0,0))
	unit.alive=true;unit.camera_hidden=true;unit.stance=2;capsule(unit);world.index_unit(unit)
	compare(world,ref,Vector3(24,2.46,-21.25),Vector3(6,0,0),{"camera_pick":true})
	compare(world,ref,Vector3(24,2.46,-21.25),Vector3(6,0,0))
	unit.mounted=0
	compare(world,ref,Vector3(24,2.46,-21.25),Vector3(6,0,0))
	unit.mounted=-1;world.unit_ray_index.active=false;unit.position=Vector2(22,22);capsule(unit)
	compare(world,ref,Vector3(19,2.46,22.75),Vector3(6,0,0))
	# Equal-distance tie and penetration's existing hit exclusion order.
	var isolated=World.new();isolated.units=[world.units[7].duplicate(true),world.units[8].duplicate(true)];isolated.vehicles=[]
	for u in isolated.units:u.position=Vector2(-4,-4);u.elevation=2;u.stance=0;u.mounted=-1;u.alive=true;capsule(u)
	var isolated_ref=reference(isolated);isolated.unit_ray_index.begin(isolated.units)
	var origin=Vector3(-7,3,-4);var line=Vector3(6,0,0)
	compare(isolated,isolated_ref,origin,line)
	var first=isolated.trace_3d(origin,line.normalized(),line.length())
	check(first.get("target",{}).get("id",-1)==isolated.units[1].id,"original equal-distance last unit wins")
	compare(isolated,isolated_ref,origin,line,{"hit":[isolated.units[1].id]})
	check(isolated.trace_3d(origin,line.normalized(),line.length(),{"hit":[isolated.units[1].id]}).get("target",{}).get("id",-1)==isolated.units[0].id,"penetration skips prior hit")
	for u in isolated.units:u.hit_shapes=[]
	compare(isolated,isolated_ref,origin,line)
	check(not isolated.trace_3d(origin,line.normalized(),line.length()).is_empty(),"fallback hit capsules retained")
	# Fixed-weapon operator remains hittable; enclosed driver does not.
	isolated.units[1].alive=false;isolated.units[0].mounted=0
	isolated.vehicles=[{"emplacement":true}]
	check(not isolated.enclosed(isolated.units[0]),"fixed weapon operator exposed")
	isolated.vehicles[0].emplacement=false
	check(isolated.enclosed(isolated.units[0]),"enclosed driver filtered")
	# Synthetic timer accounting only; does not invoke any physics/game callback.
	var timing=preload("res://scripts/runtime_performance.gd").new()
	timing.last_presented_usec=Time.get_ticks_usec()-10000;timing.report_started_usec=Time.get_ticks_usec()
	world.last_step_profile={"unit_rays":{"queries":2,"candidates":10,"full_scan_candidates":120,"build_ms":.2},"ai_detail":{"vision_rays":4,"perception_ms":1.2}}
	for i in range(3):timing.record_physics(Time.get_ticks_usec()-1000,world)
	timing.record_frame(Time.get_ticks_usec(),.016,world,false)
	check(timing.physics_steps_per_frame==[3] and timing.physics_per_frame[0]>=3.0,"multiple physics ticks attributed to one frame")
	check(timing.pending_physics_steps==0 and timing.pending_physics_ms==0,"frame consumes physics counters once")
	check(timing.unit_ray_totals.queries==6 and timing.unit_ray_totals.candidates==30,"ray counters aggregate all ticks")
	check(timing.ai_query_totals.vision_rays==12 and not timing.physics_stages.has("ai_vision_rays"),"AI query counts are not mislabeled milliseconds")
	# Recreate untouched level geometry for interleaved same-process timings.
	var bench_world=World.new();bench_world.setup(Orchard.plan(catalog),catalog)
	for u in bench_world.units:capsule(u)
	var records=bench(bench_world,reference(bench_world))
	check(exact_hits>100,"meaningful positive hit coverage")
	check(world.time==0 and world.shots==0 and bench_world.time==0 and bench_world.shots==0,"no battle advancement")
	var result={"checks":checks,"failures":failures,"exact_unit_hits":exact_hits,"units":bench_world.units.size(),"simulation_time":world.time,"shots":world.shots,"benchmark":records}
	var output=FileAccess.open("res://qa/performance/projectile-unit-index.json",FileAccess.WRITE);output.store_string(JSON.stringify(result,"\t"));output.close()
	print("PROJECTILE_UNIT_INDEX "+JSON.stringify(result));quit(0 if failures==0 else 1)
