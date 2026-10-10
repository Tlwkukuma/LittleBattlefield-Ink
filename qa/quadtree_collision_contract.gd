extends SceneTree
## Pure spatial fixtures and frozen collision queries. No game steps/AI/move/fire.
const Quad=preload("res://scripts/collision_quadtree.gd")
const World=preload("res://scripts/proving_world.gd")
const Before=preload("res://qa/performance/quadtree-before/proving_world.gd")
var checks=0
var failures=0
var random=RandomNumberGenerator.new()
var results={}
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<=12:push_error(label)
func _initialize():run.call_deferred()
func same(a: float,b: float) -> bool:return a==b or is_equal_approx(a,b)
func run():
	random.seed=100861
	tree_fixtures()
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var plan=preload("res://scripts/orchard_level.gd").plan(catalog)
	var world=World.new();world.setup(plan,catalog)
	var old=Before.new();old.setup(plan,catalog)
	world.unit_ray_index.begin(world.units);old.unit_ray_index.begin(old.units)
	var rays=[];var points=[];var ranges=[]
	for i in range(1600):
		var at=world.objects[i%world.objects.size()].position if i%3==0 else world.units[i%60].position if i%3==1 else Vector2(random.randf_range(-40,40),random.randf_range(-27,27))
		at+=Vector2(random.randf_range(-1,1),random.randf_range(-1,1))
		var radius=float([.28,.31,.60,1.8][i%4]);var elevation=world.terrain.height(at)+float([0.0,.4,2.2][i%3])
		points.append({"at":at,"r":radius,"height":float([1.95,1.5,.84][i%3]),"elevation":elevation})
		var flat=Vector2.from_angle(random.randf_range(-PI,PI));var dir=Vector3(flat.x,random.randf_range(-.2,.2),flat.y).normalized()
		rays.append({"at":Vector3(at.x,elevation+.9,at.y),"dir":dir,"length":float([.15,4.0,18.0,40.0][i%4]),"radius":float([0.0,.025,.20,.9][i%4])})
		ranges.append({"at":at,"r":float([1.2,5.0,12.0,28.0][i%4])})
	var old_candidates=0;var new_candidates=0
	for ray in rays:
		var a: Dictionary=old.trace_3d(ray.at,ray.dir,ray.length,{"radius":ray.radius})
		var b: Dictionary=world.trace_3d(ray.at,ray.dir,ray.length,{"radius":ray.radius})
		if a.get("type","")!=b.get("type","") or a.get("target",{}).get("id",-1)!=b.get("target",{}).get("id",-1):print("RAY_DIFF ",a.get("type")," ",a.get("target",{}).get("id")," ",a.get("distance")," -> ",b.get("type")," ",b.get("target",{}).get("id")," ",b.get("distance"))
		check(a.get("type","")==b.get("type","") and a.get("target",{}).get("id",-1)==b.get("target",{}).get("id",-1) and same(float(a.get("distance",INF)),float(b.get("distance",INF))),"ray target/height/distance remain identical: "+str(ray))
		var start=Vector2(ray.at.x,ray.at.z);var end=start+Vector2(ray.dir.x,ray.dir.z)*ray.length
		old_candidates+=old.ray_candidates(start,end,maxf(.02,ray.radius)).size();new_candidates+=world.ray_candidates(start,end,maxf(.02,ray.radius)).size()
	for p in points:
		check(same(old.collision_depth(p.at,p.r,p.height,-1,p.elevation),world.collision_depth(p.at,p.r,p.height,-1,p.elevation)),"body collision depth unchanged")
		check(same(old.ground_height(p.at,p.r,p.elevation+.221),world.ground_height(p.at,p.r,p.elevation+.221)),"floor and terrain support unchanged")
	var route=world.campaign_ai.vehicle_ai.routes["vehicle-001"]
	for at in route:
		var a=old.vehicles[0].duplicate();var b=world.vehicles[0].duplicate();a.position=at;b.position=at
		check(old.VehicleCollision.blocked(old,a,null,false)==world.VehicleCollision.blocked(world,b,null,false),"full vehicle shape still meets surviving walls")
	bench(world,old,rays,points,ranges)
	var detail={}
	for length in [.15,4.0,18.0,40.0]:
		var row={}
		for mode in [0,1]:
			var instance=old if mode==0 else world;var sr=Time.get_ticks_usec()
			for ray in rays:
				if ray.length==length:instance.ray_candidates(Vector2(ray.at.x,ray.at.z),Vector2(ray.at.x,ray.at.z)+Vector2(ray.dir.x,ray.dir.z)*ray.length,maxf(.02,ray.radius))
			var objects_ms=(Time.get_ticks_usec()-sr)/1000.0;sr=Time.get_ticks_usec()
			for ray in rays:
				if ray.length==length:instance.unit_ray_candidates(Vector2(ray.at.x,ray.at.z),Vector2(ray.at.x,ray.at.z)+Vector2(ray.dir.x,ray.dir.z)*ray.length,ray.radius)
			row[str(mode)]={"objects_ms":objects_ms,"units_ms":(Time.get_ticks_usec()-sr)/1000.0}
		detail[str(length)]=row
	results.detail=detail
	dynamic_fixtures(catalog,world,old)
	blast_fixtures(world,old)
	results.obstacle_candidates={"before":old_candidates,"after":new_candidates};results.tree=world.obstacle_tree.diagnostics()
	check(world.time==0 and old.time==0 and world.shots==0 and old.shots==0,"no battle advancement")
	results.checks=checks;results.failures=failures
	FileAccess.open("res://qa/performance/quadtree-collision.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("QUADTREE_COLLISION "+JSON.stringify(results));quit(0 if failures==0 else 1)

func tree_fixtures():
	var tree=Quad.new();tree.reset(Rect2(-64,-64,128,128),2.0)
	for i in range(256):
		var at=Vector2(random.randf_range(-60,60),random.randf_range(-60,60))
		var half=Vector2(random.randf_range(.05,4),random.randf_range(.05,4))
		tree.update(i,Rect2(at-half,half*2),{"id":i},.25)
	tree.update(900,Rect2(-50,-.05,100,.1),{"id":900})
	for i in range(900):
		var a=Vector2(random.randf_range(-70,70),random.randf_range(-70,70));var b=Vector2(random.randf_range(-70,70),random.randf_range(-70,70))
		if i%9==0:b=a
		var pad=float([0,.31,2.0][i%3]);var query=Rect2(a,b-a).abs().grow(pad)
		var found=tree.query(query,true);var ray=tree.segment(a,b,pad)
		var expected_box=[];var expected_ray=[]
		for id in tree.entries:
			if Quad.overlaps(tree.entries[id].bounds,query):expected_box.append(id)
			if Quad.segment_intersects(tree.entries[id].bounds,a,b,pad):expected_ray.append(id)
		expected_box.sort();expected_ray.sort()
		var box_ids=[];var ray_ids=[]
		for entry in found:box_ids.append(entry.id)
		for entry in ray:ray_ids.append(entry.id)
		check(box_ids==expected_box and ray_ids==expected_ray,"quadrant crossing, negative coordinates and zero-length query")
	var value=tree.entries[0].value
	var reinserts=tree.reinserts;var box: Rect2=tree.entries[0].bounds
	tree.update(0,Rect2(box.position+Vector2.ONE*.1,box.size-Vector2.ONE*.2),value)
	check(tree.reinserts==reinserts,"contained movement does not reinsert")
	tree.update(0,Rect2(180,180,2,2),value)
	check(tree.query(Rect2(179,179,4,4)).has(value),"teleport beyond root cannot lose an entry")
	tree.remove(0);check(not tree.query(Rect2(179,179,4,4)).has(value),"removed body cannot remain in tree")
	check(tree.entries.size()==256,"single owner means no duplicate entry slots")

func median(values: Array) -> float:
	var sorted=values.duplicate();sorted.sort();return float(sorted[sorted.size()/2])
func bench(world,old,rays: Array,points: Array,ranges: Array):
	var timings={"rays":[[],[]],"bodies":[[],[]],"nearby":[[],[]]}
	old.build_unit_index();world.build_unit_index()
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var instance=old if mode==0 else world;var started=Time.get_ticks_usec()
			for ray in rays:instance.trace_3d(ray.at,ray.dir,ray.length,{"radius":ray.radius})
			if repeat>0:timings.rays[mode].append((Time.get_ticks_usec()-started)/1000.0)
			started=Time.get_ticks_usec()
			for point in points:instance.collision_depth(point.at,point.r,point.height,-1,point.elevation)
			if repeat>0:timings.bodies[mode].append((Time.get_ticks_usec()-started)/1000.0)
			started=Time.get_ticks_usec()
			for query in ranges:instance.nearby_units(query.at,query.r)
			if repeat>0:timings.nearby[mode].append((Time.get_ticks_usec()-started)/1000.0)
	for key in timings:results[key]={"queries":rays.size(),"before_ms":median(timings[key][0]),"after_ms":median(timings[key][1])}

func same_hit(a: Dictionary,b: Dictionary) -> bool:
	return a.get("type","")==b.get("type","") and a.get("target",{}).get("id",-1)==b.get("target",{}).get("id",-1) and same(float(a.get("distance",INF)),float(b.get("distance",INF)))

func dynamic_fixtures(catalog,world,old):
	var u: Dictionary=world.units[7];var original: Vector2=u.position
	var clone=u.duplicate(true);clone.position=Vector2(300,300);world.index_unit(clone)
	check(world.unit_ray_index.nearby(Vector2(300,300),1).is_empty(),"LAN prediction clone cannot replace authority in spatial index")
	for at in [Vector2(-4,-4),Vector2(4,4),Vector2(130,130)]:
		u.position=at;world.index_unit(u)
		check(world.unit_ray_index.nearby(at,.1).has(u),"live root crossing/teleport updates loose tree")
	u.alive=false;world.index_unit(u);check(not world.unit_ray_index.nearby(u.position,1).has(u),"death removes the spatial entry")
	u.alive=true;u.position=original;world.index_unit(u)
	check(world.unit_ray_index.nearby(original,1).has(u),"respawn reuses original ID without stale entry")
	# Mutate only fixture HP. Exact current geometry must observe live holes
	# without rebuilding the static broad phase or simulating damage.
	for i in range(world.objects.size()):
		var a: Dictionary=world.objects[i];var b: Dictionary=old.objects[i]
		for cell in range(0,a.hp.size(),3):a.hp[cell]=0;b.hp[cell]=0
	for i in range(300):
		var o: Dictionary=world.objects[i%world.objects.size()];var at: Vector2=o.position+Vector2.from_angle(float(i))*.6
		var origin=Vector3(at.x,o.elevation+.8,at.y);var dir=Vector3(cos(i),.03,sin(i)).normalized()
		check(same_hit(old.trace_3d(origin,dir,12,{"radius":.04},true),world.trace_3d(origin,dir,12,{"radius":.04},true)),"live breach hit is unchanged")
		check(same(old.collision_depth(at,.31,1.95,-1,o.elevation),world.collision_depth(at,.31,1.95,-1,o.elevation)),"broken wall remains passable")
	var range_world=World.new();range_world.setup(catalog.range_plan(),catalog)
	var range_old=Before.new();range_old.setup(catalog.range_plan(),catalog)
	var probes=[];var old_probes=[]
	for i in range(420):
		var index=i%range_world.vehicles.size();var v: Dictionary=range_world.vehicles[index];var before: Dictionary=range_old.vehicles[index]
		if i%21==0:
			var displacement=Vector2(2.5,-1.8);v.position+=displacement;before.position+=displacement
			v.angle+=.37;before.angle=v.angle;v.turret_angle-=.49;before.turret_angle=v.turret_angle
			v.pose_basis=Basis(Vector3.UP,-v.angle-PI*.5)*Basis(Vector3.RIGHT,.23)*Basis(Vector3.FORWARD,-.17);before.pose_basis=v.pose_basis
			v.destroyed=i%42==0;before.destroyed=v.destroyed;range_world.index_vehicle(v)
		var at: Vector2=v.position+Vector2.from_angle(float(i))*float([.1,1.5,3.5][i%3])
		var elevation: float=range_world.terrain.height(at);var origin=Vector3(at.x,elevation+1.5,at.y);var dir=Vector3(cos(i),-.03,sin(i)).normalized()
		var old_hit: Dictionary=range_old.trace_3d(origin,dir,16,{"radius":.04},true);var new_hit: Dictionary=range_world.trace_3d(origin,dir,16,{"radius":.04},true)
		if not same_hit(old_hit,new_hit):print("VEHICLE_DIFF i=",i," at=",origin," dir=",dir," old=",old_hit.get("type"),"/",old_hit.get("target",{}).get("id"),"/",old_hit.get("distance")," new=",new_hit.get("type"),"/",new_hit.get("target",{}).get("id"),"/",new_hit.get("distance"))
		check(same_hit(old_hit,new_hit),"multiple/tilted/destroyed vehicles stay hittable")
		check(same(range_old.collision_depth(at,.31,1.95,-1,elevation),range_world.collision_depth(at,.31,1.95,-1,elevation)),"dynamic vehicle-person contact unchanged")
		check(same(range_old.ground_height(at,.31,elevation+3),range_world.ground_height(at,.31,elevation+3)),"tilted vehicle roof support unchanged")
		# Fixed mounts update their authored boxes in place. Independent fixture
		# poses must not share those caches with the stationary original mount.
		var probe=v.duplicate(true);var old_probe=before.duplicate(true);probe.position=at;old_probe.position=at
		check(range_old.VehicleCollision.blocked(range_old,old_probe,null,false)==range_world.VehicleCollision.blocked(range_world,probe,null,false),"vehicle hull-vs-hull/scene collision unchanged")
		var old_contact={};var new_contact={}
		var old_blocked: bool=range_old.VehicleCollision.blocked(range_old,old_probe,old_contact,false);var new_blocked: bool=range_world.VehicleCollision.blocked(range_world,probe,new_contact,false)
		check(old_blocked==new_blocked and old_contact.get("kind","")==new_contact.get("kind","") and old_contact.get("target",{}).get("id",-1)==new_contact.get("target",{}).get("id",-1) and old_contact.get("normal",Vector2.ZERO).is_equal_approx(new_contact.get("normal",Vector2.ZERO)) and same(float(old_contact.get("depth",0)),float(new_contact.get("depth",0))),"first real impact target/depth/normal remain unchanged")
		probes.append(probe);old_probes.append(old_probe)
	var legacy=[];var current=[]
	for repeat in range(7):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var instance=range_old if mode==0 else range_world;var list=old_probes if mode==0 else probes;var started=Time.get_ticks_usec()
			for probe in list:instance.VehicleCollision.blocked(instance,probe,null,false)
			if repeat>0:(legacy if mode==0 else current).append((Time.get_ticks_usec()-started)/1000.0)
	results.vehicles={"queries":probes.size(),"vehicles":range_world.vehicles.size(),"before_ms":median(legacy),"after_ms":median(current)}
	check(range_world.time==0 and range_world.shots==0 and range_old.time==0 and range_old.shots==0,"range fixtures do not advance combat")

func blast_fixtures(world,old):
	var fixtures=[];var full_rays=0;var culled_rays=0
	var edge: Dictionary=world.units[8];var edge_at: Vector2=edge.position+Vector2(3,0);var edge_height: float=edge.elevation+world.stance_height(edge.stance)*.55
	check(world.blast_units(edge_at,3.0,edge_height).has(edge) and not world.blast_units(edge_at,2.99999,edge_height).has(edge),"explosion radius boundary uses the original 3D length rule")
	for i in range(240):
		var at: Vector2=world.units[i%world.units.size()].position+Vector2.from_angle(float(i))*.7
		var radius=float([2.0,3.5,6.0,12.0][i%4]);var height=world.terrain.height(at)+.6
		var found=world.blast_units(at,radius,height);var expected=[]
		for u in world.units:
			if not u.alive or world.enclosed(u):continue
			var offset=Vector3(u.position.x-at.x,u.elevation+world.stance_height(u.stance)*.55-height,u.position.y-at.y)
			if offset.length()<=radius:expected.append(u)
		check(found==expected,"explosion spatial cull retains all actual victims in original order")
		for u in found:
			var offset=Vector3(u.position.x-at.x,u.elevation+world.stance_height(u.stance)*.55-height,u.position.y-at.y)
			check(same_hit(old.trace_3d(Vector3(at.x,height,at.y),offset.normalized(),offset.length(),{},true),world.trace_3d(Vector3(at.x,height,at.y),offset.normalized(),offset.length(),{},true)),"explosion shielding remains before destruction")
		full_rays+=world.units.size();culled_rays+=found.size();fixtures.append({"at":at,"radius":radius,"height":height})
	var legacy=[];var current=[]
	for repeat in range(6):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var instance=old if mode==0 else world;var started=Time.get_ticks_usec()
			for f in fixtures:
				var selected: Array=instance.units if mode==0 else instance.blast_units(f.at,f.radius,f.height)
				for u in selected:
					var offset=Vector3(u.position.x-f.at.x,u.elevation+instance.stance_height(u.stance)*.55-f.height,u.position.y-f.at.y)
					instance.trace_3d(Vector3(f.at.x,f.height,f.at.y),offset.normalized(),offset.length(),{},true)
			if repeat>0:(legacy if mode==0 else current).append((Time.get_ticks_usec()-started)/1000.0)
	results.blast_shielding={"queries":fixtures.size(),"before_rays":full_rays,"after_rays":culled_rays,"before_ms":median(legacy),"after_ms":median(current)}
