extends SceneTree
## Resource geometry and isolated seat-state checks. Never runs world.step/AI/fire.
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<20:push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var plan=preload("res://scripts/orchard_level.gd").plan(catalog)
	var world=preload("res://scripts/proving_world.gd").new();world.setup(plan,catalog)
	check(world.units.size()==60,"same 30 vs 30 force")
	check(world.vehicles.size()==plan.vehicles.size()+plan.emplacements.size(),"runtime vehicle roster matches authored plan")
	check(plan.trees.size()==140,"tree population preserved")
	check(world.bounds==Vector2(41.25,28.75),"field dimensions")
	check(plan.godot3d.combat_camera_size==25,"fixed campaign camera size")
	var original: Dictionary=catalog.scenes.filter(func(scene):return scene.id=="level-01")[0]
	for gun in plan.emplacements:
		var source: Dictionary=original.emplacements.filter(func(item):return item.id==gun.id)[0]
		check(gun.x==source.x and gun.y==source.y and gun.angle==source.angle,"original gun position and facing "+gun.id)
	for feature in plan.world.groundFeatures:
		check(feature.id not in ["orchard-perimeter-lane","farm-access-road"],"removed roads leave no paint or flattening")
	for id in ["sandbag-001","segment-001","segment-002"]:
		check(plan.looseSegments.filter(func(s):return s.id==id)==original.looseSegments.filter(func(s):return s.id==id),"original gun cover "+id)
	for team in world.campaign_ai.routes:
		for route in team:
			for i in range(1,route.size()):check(not world.campaign_ai.path_between(route[i-1],route[i]).is_empty(),"infantry approach connected "+str(catalog.original_point(route[i-1],plan))+" -> "+str(catalog.original_point(route[i],plan)))
	var houses={}
	for instance in plan.instances:
		if instance.id not in preload("res://scripts/orchard_layout.gd").HOUSE_CENTERS:continue
		var footprint=catalog.prefabs[instance.prefabId].footprint;var rect=Rect2(catalog.v(footprint[0])+catalog.v(instance),Vector2.ZERO)
		for p in footprint:rect=rect.expand(catalog.v(p)+catalog.v(instance))
		houses[instance.id]=rect
	check((houses["orchard-house-b"].position.x-houses["orchard-house-a"].end.x)/40.0>=5.8,"east-west house lane >=5.8m")
	check((houses["orchard-house-c"].position.y-houses["orchard-house-b"].end.y)/40.0>=3.5,"north-south house lane >=3.5m")
	for name in houses:
		for other in houses:
			if name==other:continue
			check(not houses[name].grow(24).intersects(houses[other]),"house walls keep clearance")
	for raw in [[2190,1630],[2140,1350],[2110,1100],[2890,1510],[2890,1180],[2700,1140],[2350,1100],[2620,1060]]:
		var p=catalog.position(raw,plan)
		check(not world.blocked(p,.31,1.95,-1,world.terrain.height(p)),"walkable gate/courtyard "+str(raw))
	var south_walls=world.objects.filter(func(o):return o.get("source_id","")=="compound-bottom")
	check(south_walls.size()==1,"south wall restored as one original continuous span")
	for wall in world.objects:
		if wall.owner!="orchard-compound":continue
		check(wall.height>=2.2 and wall.height<2.3 and not wall.hp.is_empty(),"compound walls are 2.2m tall real destructible solids")
	for x in [2830,2860,2890,2920,2950]:
		var outside=catalog.position([x,1610],plan);var inside=catalog.position([x,1500],plan)
		for height in [.5,1.75,2.05]:
			var ray=world.trace_3d(Vector3(outside.x,height,outside.y),Vector3(0,0,-1),outside.distance_to(inside),{})
			check(not ray.is_empty() and ray.type=="object" and ray.target.get("source_id","")=="compound-bottom","former south gap blocks fire at "+str(x)+" / "+str(height))
		var overhead=world.trace_3d(Vector3(outside.x,2.5,outside.y),Vector3(0,0,-1),outside.distance_to(inside),{})
		check(overhead.is_empty(),"wall top remains real geometry, no invisible barrier above it")
	for v in world.vehicles:
		check(v.ai_controlled,"authored AI access")
		check(not world.vehicle_blocked(v,v.position),"clear initial vehicle "+str(v.source_id))
		var point=world.campaign_ai.vehicle_ai.boarding_point(v)
		check(point.is_finite(),"clear boarding point "+str(v.source_id))
		if point.is_finite():
			var paths=0
			for u in world.units:
				if u.player or (v.team>=0 and u.team!=v.team) or u.position.distance_to(point)>18:continue
				if not world.campaign_ai.path_between(u.position,point).is_empty():paths+=1;break
			check(paths>0,"crew can path to "+str(v.source_id))
		var route: Array=world.campaign_ai.vehicle_ai.routes.get(v.source_id,[])
		for i in range(1,route.size()):
			var a: Vector2=route[i-1];var b: Vector2=route[i]
			var count=ceili(a.distance_to(b)/.45)
			for k in range(count+1):
				var probe=v.duplicate(true);probe.position=a.lerp(b,float(k)/count);probe.angle=(b-a).angle()
				world.VehicleGround.initialize(world.terrain,probe,world)
				check(probe.ground.passable and not world.VehicleCollision.blocked(world,probe),"vehicle route clear "+str(v.source_id)+" "+str(catalog.original_point(probe.position,plan)))
	var u: Dictionary=world.units.filter(func(unit):return not unit.player and unit.team==0)[0]
	var v: Dictionary=world.vehicles[0]
	check(preload("res://scripts/campaign_vehicle_ai.gd").available(v,u),"friendly free seat")
	var enemy_mount: Dictionary=v.duplicate(true);enemy_mount.team=1
	check(not preload("res://scripts/campaign_vehicle_ai.gd").available(enemy_mount,u),"enemy side cannot be claimed")
	check(world.mount_unit(u,v.id),"isolated fixture mounts NPC")
	check(u.mounted==v.id and v.driver_id==u.id and v.driver,"seat has one owner")
	check(not world.mount_unit(u,world.vehicles[2].id),"one soldier cannot occupy two seats")
	check(not world.mount_unit(world.units[2],v.id),"double boarding rejected")
	check(world.campaign_ai.vehicle_ai.leave(u),"isolated fixture dismounts NPC")
	check(u.mounted<0 and v.driver_id<0 and not v.driver,"seat released")
	check(not world.blocked(u.position,.31,1.95,-1,u.elevation),"dismount has solid clearance")
	var intent=preload("res://scripts/campaign_vehicle_ai.gd").steering({"position":Vector2.ZERO,"angle":0.0},Vector2(10,3))
	check(intent.x>0 and intent.y>0,"steering follows target direction")
	var dirty=world.campaign_ai.dirty_cells.size();world.campaign_ai.invalidate_vehicle(v)
	check(world.campaign_ai.dirty_cells.size()==dirty,"AI driving does not rebuild infantry grid")
	check(world.time==0 and world.shots==0,"no gameplay simulation")
	print("ORCHARD_LAYOUT_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"objects":world.objects.size(),"houses":houses.size(),"units":world.units.size(),"vehicles":world.vehicles.size(),"shots":world.shots,"world_time":world.time}))
	quit(0 if failures==0 else 1)
