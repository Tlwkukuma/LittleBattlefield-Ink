extends RefCounted
## Team tactics over explicit, body-clear and slope-checked navigation edges.
const Perception=preload("res://scripts/campaign_perception.gd")
const Tactics=preload("res://scripts/campaign_tactics.gd")
const DirectionalAim=preload("res://scripts/campaign_directional_aim.gd")
const Suppression=preload("res://scripts/campaign_suppression.gd")
var perception=Perception.new()
var tactics=Tactics.new()
var vehicle_ai=preload("res://scripts/campaign_vehicle_ai.gd").new()
var world_ref: WeakRef
var graph=AStar2D.new()
var cells: Dictionary={}
var revision=-1
var routes: Array=[[],[]]
var paths_this_frame=0
var path_frame=-1
var dimensions=Vector2i.ZERO
var dirty_cells: Dictionary={}
var refresh_edges: Dictionary={}
var graph_ready=false
var last_rebuild_ms=0.0
var last_rebuild_cells=0
var step_profile: Dictionary={}
var connectivity=preload("res://scripts/campaign_connectivity.gd").new()
var capture_cells: Array=[]
var capture_goal_cache: Dictionary={}
var capture_reservations=preload("res://scripts/campaign_goal_reservations.gd").new()

func profile_part(key: String,started: int) -> int:
	if started==0:return 0
	var now=Time.get_ticks_usec()
	step_profile[key]=float(step_profile.get(key,0))+(now-started)/1000.0
	return now

func configure(world) -> void:
	world_ref=weakref(world)
	perception.configure(world);tactics.configure(world,self)
	vehicle_ai.configure(world)
	var source: Dictionary=world.plan.get("godot3d",{}).get("aiRoutes",{})
	for team in range(2):
		for raw_route in source.get("blue" if team==0 else "red",[]):
			var route=[]
			for point in raw_route:route.append(world.catalog.position(point,world.plan))
			routes[team].append(route)

func rebuild(cell_budget: int=0) -> void:
	var started=Time.get_ticks_usec();var world=world_ref.get_ref()
	if graph_ready and (not dirty_cells.is_empty() or not refresh_edges.is_empty()):
		refresh_cells(world,cell_budget);revision=world.topology_revision
		last_rebuild_ms=(Time.get_ticks_usec()-started)/1000.0
		return
	if graph_ready and revision==world.topology_revision:return
	graph.clear();cells.clear();dimensions=Vector2i(ceili(world.bounds.x),ceili(world.bounds.y))
	for x in range(-dimensions.x,dimensions.x+1):
		for z in range(-dimensions.y,dimensions.y+1):
			var cell=Vector2i(x,z);var at=Vector2(cell)
			if world.terrain.grade(at)>.8 or world.blocked(at,.31,1.95,-2,world.terrain.height(at)):continue
			var id=cell_id(cell);cells[cell]=id;graph.add_point(id,at)
	for cell in cells:
		for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
			var next: Vector2i=cell+offset
			if not cells.has(next):continue
			if offset.x!=0 and offset.y!=0 and (not cells.has(cell+Vector2i(offset.x,0)) or not cells.has(cell+Vector2i(0,offset.y))):continue
			if traversable(world,Vector2(cell),Vector2(next),true):graph.connect_points(cells[cell],cells[next])
	revision=world.topology_revision
	for unit in world.units:unit.repath=minf(float(unit.repath),.15+float(unit.id%10)*.05);unit.path=[]
	graph_ready=true;dirty_cells.clear();refresh_edges.clear();last_rebuild_cells=cells.size();last_rebuild_ms=(Time.get_ticks_usec()-started)/1000.0
	connectivity.begin(graph)
	# Initial graph work belongs to loading; subsequent repairs are distributed.
	while not connectivity.ready:connectivity.pump(graph,4096,100000)
	refresh_capture_cells()

func cell_id(cell: Vector2i) -> int:return (cell.x+dimensions.x)*(dimensions.y*2+1)+cell.y+dimensions.y

func invalidate_object(object: Dictionary,column: int=-1) -> void:
	var center: Vector2=object.position;var size: Vector2=object.size
	# Ordinary wall destruction changes only one horizontal column. A collapsing
	# run marks each removed column, merging the affected grid cells automatically.
	if column>=0 and not object.whole and not object.has("solid_parts") and not object.has("nature_solids"):
		size.x=object.cell_width
		center+=Vector2(-object.size.x*.5+(column+.5)*object.cell_width,0).rotated(object.angle)
	var half=Vector2(absf(cos(object.angle))*size.x+absf(sin(object.angle))*size.y,absf(sin(object.angle))*size.x+absf(cos(object.angle))*size.y)*.5
	invalidate_bounds(center-half-Vector2.ONE*1.35,center+half+Vector2.ONE*1.35)

func invalidate_bounds(low: Vector2,high: Vector2) -> void:
	if not graph_ready:return
	connectivity.invalidate()
	for x in range(maxi(-dimensions.x,floori(low.x)),mini(dimensions.x,ceili(high.x))+1):
		for y in range(maxi(-dimensions.y,floori(low.y)),mini(dimensions.y,ceili(high.y))+1):
			var cell=Vector2i(x,y);dirty_cells[cell]=true
			var id=cell_id(cell)
			if graph.has_point(id):graph.set_point_disabled(id,true)

func invalidate_vehicle(vehicle: Dictionary) -> void:
	# Moving support vehicles use local avoidance, not hundreds of grid rebuilds.
	if vehicle.get("ai_controlled",false) and not vehicle.emplacement and not vehicle.destroyed:return
	var previous: Vector2=vehicle.get("navigation_position",vehicle.spawn)
	var angle=float(vehicle.get("navigation_angle",vehicle.angle))
	if previous.distance_squared_to(vehicle.position)<.36 and absf(wrapf(vehicle.angle-angle,-PI,PI))<.22:return
	var radius=float(vehicle.dimensions.half.length())+1.4
	invalidate_bounds(previous-Vector2.ONE*radius,previous+Vector2.ONE*radius)
	invalidate_bounds(vehicle.position-Vector2.ONE*radius,vehicle.position+Vector2.ONE*radius)
	vehicle.navigation_position=vehicle.position;vehicle.navigation_angle=vehicle.angle
	world_ref.get_ref().navigation_dirty=true

func refresh_cells(world,cell_budget: int=0) -> void:
	# Only an object's footprint plus the adjacent grid ring can change after damage.
	# Stable grid IDs preserve every unrelated node and all still-valid paths.
	var changed=dirty_cells.keys()
	if cell_budget>0 and changed.size()>cell_budget:changed.resize(cell_budget)
	for cell in changed:dirty_cells.erase(cell)
	last_rebuild_cells=changed.size()
	for cell in changed:
		refresh_edges[cell]=true
		var id=cell_id(cell)
		if graph.has_point(id):
			for neighbor in graph.get_point_connections(id):graph.disconnect_points(id,neighbor)
		var at=Vector2(cell)
		var clear=world.terrain.grade(at)<=.8 and not world.blocked(at,.31,1.95,-2,world.terrain.height(at))
		if clear:
			cells[cell]=id
			if not graph.has_point(id):graph.add_point(id,at)
			graph.set_point_disabled(id,true)
		else:
			cells.erase(cell)
			if graph.has_point(id):graph.remove_point(id)
	# Complete node occupancy first. Diagonal edges depend on corner nodes, which
	# may belong to a later batch; rebuilding edges early leaves stale diagonals.
	if not dirty_cells.is_empty():return
	var edge_cells=refresh_edges.keys()
	if cell_budget>0 and edge_cells.size()>mini(3,cell_budget):edge_cells.resize(mini(3,cell_budget))
	last_rebuild_cells=maxi(last_rebuild_cells,edge_cells.size())
	for cell in edge_cells:
		refresh_edges.erase(cell)
		if not cells.has(cell):continue
		graph.set_point_disabled(cells[cell],false)
		for offset in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
			var next: Vector2i=cell+offset
			if not cells.has(next) or graph.are_points_connected(cells[cell],cells[next]):continue
			if offset.x!=0 and offset.y!=0 and (not cells.has(cell+Vector2i(offset.x,0)) or not cells.has(cell+Vector2i(0,offset.y))):continue
			if traversable(world,Vector2(cell),Vector2(next),true):graph.connect_points(cells[cell],cells[next])
	for unit in world.units:unit.repath=minf(float(unit.repath),.15+float(unit.id%10)*.05)
	if refresh_edges.is_empty():connectivity.begin(graph);refresh_capture_cells()

func refresh_capture_cells() -> void:
	capture_cells.clear();capture_goal_cache.clear();capture_reservations.claims.clear();var world=world_ref.get_ref()
	for point in world.campaign.points:
		var candidates=[]
		var extent=ceili(float(point.radius)+2)
		var center=Vector2i(point.position.round())
		for x in range(center.x-extent,center.x+extent+1):
			for z in range(center.y-extent,center.y+extent+1):
				var cell=Vector2i(x,z)
				if not cells.has(cell):continue
				var id=int(cells[cell])
				if graph.is_point_disabled(id):continue
				var at=Vector2(cell)
				if preload("res://scripts/capture_zone.gd").contains(point,at,world.terrain.height(at)):candidates.append(id)
		capture_cells.append(candidates)

func tick_connectivity() -> void:
	var world=world_ref.get_ref()
	if not connectivity.building or world.ai_budget_usec<=0:return
	var started=Time.get_ticks_usec();connectivity.pump(graph,1024,mini(450,world.ai_budget_usec))
	world.ai_budget_usec-=Time.get_ticks_usec()-started

func same_component(a: Vector2,b: Vector2) -> bool:
	return connectivity.connected(point_cell(a),point_cell(b))

func capture_goal(origin: Vector2,slot: int=0,objective: int=0,wanted: Vector2=Vector2.INF,owner_id: int=-1,task_key: String="") -> Vector2:
	if not connectivity.ready or objective>=capture_cells.size():return Vector2.INF
	var start=point_cell(origin);var candidates: Array=capture_cells[objective]
	var cache_key=str(objective)+":"+str(slot)+":"+str(connectivity.labels.get(start,-1))
	if wanted.is_finite():cache_key+=":"+str(Vector2i(wanted.round()))
	var world=world_ref.get_ref()
	if owner_id>=0:
		capture_reservations.prune(world.units,world.time)
	if owner_id<0 and capture_goal_cache.has(cache_key):return capture_goal_cache[cache_key]
	var point: Dictionary=world_ref.get_ref().campaign.points[objective]
	var preferred: Vector2=point.position+Vector2.from_angle(float(slot)*2.39996)*minf(2.5,float(point.radius)*.35)
	if wanted.is_finite():preferred=wanted+Vector2.from_angle(float(slot)*2.39996)*.65
	var best=Vector2.INF;var score=INF
	for id in candidates:
		if graph.is_point_disabled(id) or not connectivity.connected(start,id):continue
		var at=graph.get_point_position(id)
		if owner_id>=0 and not capture_reservations.available(at,owner_id):continue
		var value=at.distance_squared_to(preferred)
		if value<score:score=value;best=at
	if owner_id<0:capture_goal_cache[cache_key]=best
	elif best.is_finite():capture_reservations.reserve(world.units[owner_id],best,task_key,world.time)
	return best

func connected_goal(origin: Vector2,wanted: Vector2) -> Vector2:
	var start=point_cell(origin);var id=point_cell(wanted)
	if connectivity.connected(start,id):return graph.get_point_position(id)
	var best=Vector2.INF;var score=INF
	for radius in [1.0,2.0,3.0]:
		for index in range(8):
			id=point_cell(wanted+Vector2.from_angle(index*TAU/8)*radius)
			if not connectivity.connected(start,id):continue
			var at=graph.get_point_position(id);var value=at.distance_squared_to(wanted)
			if value<score:score=value;best=at
		if best.is_finite():break
	return best

static func traversable(world,a: Vector2,b: Vector2,navigation_edge: bool=false) -> bool:
	var steps=maxi(1,ceili(a.distance_to(b)/.18));var previous=a
	for index in range(1,steps+1):
		var at=a.lerp(b,float(index)/steps)
		if not world.terrain.walkable(previous,at):return false
		if world.blocked(at,.30,1.95,-2 if navigation_edge else -1,world.terrain.height(at)):return false
		previous=at
	return true

func cell_near(at: Vector2,world) -> int:
	var center=Vector2i(at.round());var best=-1;var distance=INF
	for radius in range(4):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				if radius>0 and absi(x)!=radius and absi(z)!=radius:continue
				var cell=center+Vector2i(x,z)
				if not cells.has(cell):continue
				if graph.is_point_disabled(cells[cell]):continue
				var candidate=at.distance_squared_to(Vector2(cell))
				if candidate<distance and traversable(world,at,Vector2(cell)):best=cells[cell];distance=candidate
		if best>=0:return best
	return -1

func point_cell(at: Vector2) -> int:
	# Goals can be original author coordinates inside walls; choose a walkable nearby cell.
	var rounded=Vector2i(at.round())
	if cells.has(rounded) and not graph.is_point_disabled(cells[rounded]):return int(cells[rounded])
	return graph.get_closest_point(at) if graph.get_point_count()>0 else -1

func path_between(a: Vector2,b: Vector2) -> Array:
	var world=world_ref.get_ref();var start=cell_near(a,world);var target=point_cell(b)
	if start<0 or target<0:return []
	return Array(graph.get_point_path(start,target,true))

func update(unit: Dictionary,delta: float) -> void:
	if unit.mounted>=0:return
	var world=world_ref.get_ref()
	var profile_time=Time.get_ticks_usec() if world.profile_ai else 0
	perception.tick(unit,delta)
	unit.brain-=delta;unit.repath-=delta
	var order: Dictionary=unit.get("ai_order",{});unit.ai_task=str(order.get("task","attack"));unit.squad_id=str(order.get("squad_id",str(unit.team)+":"+str(int(unit.campaign_slot/5))))
	var decide=unit.brain<=0 and world.ai_budget_usec>0
	var decision_started=Time.get_ticks_usec()
	if decide:
		unit.brain=.30+world.rng.randf()*.22
		var selected=perception.refresh(unit);var target_id=int(selected.get("id",-1))
		if target_id!=int(unit.get("ai_target",-1)) and target_id>=0:unit.ai_reaction=.35+world.rng.randf()*.35
		unit.ai_target=target_id;unit.ai_visible=target_id>=0
		if target_id>=0:select_weapon(world,unit,unit.position.distance_to(selected.position))
		world.ai_budget_usec-=Time.get_ticks_usec()-decision_started
	profile_time=profile_part("perception_ms",profile_time)
	var contact: Dictionary=unit.ai_contacts.get(int(unit.get("ai_target",-1)),{})
	if contact.is_empty():contact=perception.best_contact(unit)
	unit.ai_contact_source=str(contact.get("source",""))
	if bool(order.get("breach_thrower",false)) or (decide and world.weapon_for(unit).kind=="grenade"):
		select_weapon(world,unit,unit.position.distance_to(Vector2(order.get("goal",unit.position))))
	if decide and bool(order.get("breach_thrower",false)):world.campaign_director.plan_executor.prepare_throw(unit)
	var weapon: Dictionary=world.weapon_for(unit)
	var suppressive=Suppression.machinegun(weapon)
	unit.ai_support_capable=weapon.kind in ["bullet","hitscan"]
	unit.ai_reaction=maxf(0,float(unit.get("ai_reaction",0))-delta)
	if suppressive:unit.ai_reaction=minf(float(unit.ai_reaction),.12)
	unit.ai_fire_clock=float(unit.get("ai_fire_clock",float(unit.id%7)*.08))-delta
	unit.ai_fire_time=maxf(0,float(unit.get("ai_fire_time",0))-delta)
	var request=false
	if unit.ai_fire_clock<=0:
		unit.ai_fire_clock=(1.10 if suppressive else .68)+world.rng.randf()*.15
		unit.ai_fire_time=.85 if suppressive else .18
		request=true
	var remembered_cover=str(order.get("bound_role",""))=="cover" and contact.get("source","")=="vision" and world.time-float(contact.get("observed_at",-100))<1.3 and float(contact.get("confidence",0))>=.4
	var visible=(bool(unit.get("ai_visible",false)) and int(unit.get("ai_target",-1))>=0 and DirectionalAim.fresh(contact,world.time)) or remembered_cover or (suppressive and Suppression.known(contact,world.time))
	unit.aiming=visible;unit.aim_valid=visible
	var aligned=false
	if visible:
		if float(unit.get("ai_aim_observed_at",-100))!=float(contact.observed_at) or int(unit.get("ai_aim_contact_id",-2))!=int(contact.get("id",unit.ai_target)) or int(unit.get("ai_aim_contact_epoch",-1))!=int(contact.get("spawn_epoch",0)):
			DirectionalAim.observe(unit,contact,weapon,Vector2(world.rng.randf_range(-1,1),world.rng.randf_range(-1,1)))
		aligned=DirectionalAim.track(unit,delta)
		if suppressive:
			var mark: Vector3=unit.ai_aim_mark;var planar=Vector2(mark.x,mark.z)-Vector2(unit.position)
			var pitch=atan2(mark.y-world.muzzle_height(unit),maxf(.5,planar.length()))
			aligned=Suppression.in_sector(planar.angle()-unit.facing.angle(),pitch-float(unit.get("ai_aim_pitch",0)))
	var allowed=visible and aligned and unit.ai_reaction<=0 and unit.vault.is_empty() and unit.ladder.is_empty() and bool(unit.get("ai_fire_clear",false)) and DirectionalAim.fire_context_matches(unit,contact,weapon) and weapon.kind!="grenade"
	if weapon.kind=="grenade" and bool(order.get("breach_thrower",false)) and unit.get("ai_breach_ready",false) and world.time<float(unit.get("ai_breach_expires",0)):
		unit.ai_breach_ready=false
		unit.facing=(Vector2(unit.ai_breach_target.x,unit.ai_breach_target.z)-Vector2(unit.position)).normalized()
		world.throw_grenade(unit,weapon,unit.ai_breach_target,false)
	var wants=world.FireControl.wants_shot(unit,weapon,unit.ai_fire_time>0,request,allowed)
	if wants:
		# Shoot along the imperfect remembered direction. Real muzzle/barrel and
		# projectile collision remain authoritative; no per-shot target confirmation.
		var distance=unit.position.distance_to(unit.aim_point)
		var legal=distance<=float(weapon.get("range",1200))/40.0
		if weapon.kind=="mortar":legal=legal and distance>=float(weapon.get("minRange",360))/40.0 and blast_clear(world,unit,unit.aim_point,float(weapon.get("blastRadius",180))/40.0)
		if legal:world.fire(unit,weapon,unit,unit.position,unit.facing.angle(),world.muzzle_height(unit),unit.aim_point)
	profile_time=profile_part("fire_ms",profile_time)
	var base_goal=objective_goal(world,unit)
	var signature=str(order.get("revision",0))+":"+str(order.get("bound_role",""))+":"+str(order.get("bound_phase",""))+":"+str(order.get("bound_goal",Vector2.ZERO))+":"+str(order.get("breach_thrower",false))+":"+str(order.get("breach_open",false))+":"+str(order.get("capture_commit",false))
	# A perception decision can exhaust this frame's shared budget before tactics.
	# Retry its unchecked report on a later budgeted tick, rather than perpetually
	# replacing it with the next observation before a lane is ever authorized.
	if tactics_due(unit,contact,weapon,signature,decide,visible,int(world.ai_budget_usec)):
		var started=Time.get_ticks_usec();var before_budget=int(world.ai_budget_usec)
		unit.ai_tactic=tactics.decide(unit,base_goal,contact,visible);unit.ai_tactic_signature=signature
		world.ai_budget_usec-=maxi(0,int(Time.get_ticks_usec()-started)-(before_budget-int(world.ai_budget_usec)))
	if not unit.has("ai_tactic"):unit.ai_tactic={"goal":base_goal,"hold":false,"state":"advance","stance":0}
	var action: Dictionary=unit.ai_tactic;var goal: Vector2=action.goal
	var boarding_goal=vehicle_ai.goal(unit)
	if boarding_goal.is_finite():
		action={"goal":boarding_goal,"hold":false,"state":"board-vehicle","stance":0};goal=boarding_goal
	unit.ai_goal=goal;unit.ai_state=str(action.state)
	var stance=int(action.stance)
	if stance!=unit.stance and (world.time>=float(unit.get("ai_pose_until",0)) or float(unit.get("ai_stress",0))>.62) and not world.blocked(unit.position,.31,world.stance_height(stance),-1,unit.elevation):
		unit.stance=stance;unit.ai_pose_until=world.time+.8
	var moving=not bool(action.hold) and unit.position.distance_to(goal)>(.30 if boarding_goal.is_finite() else .5)
	var velocity=Vector2.ZERO
	var frame=Engine.get_physics_frames()
	if path_frame!=frame:path_frame=frame;paths_this_frame=0
	if moving:
		if unit.get("ai_path_goal",Vector2.INF).distance_to(goal)>1.6:unit.repath=0
		if unit.repath<=0 and paths_this_frame<2 and graph.get_point_count()>0 and world.ai_budget_usec>0:
			var path_started=Time.get_ticks_usec()
			unit.path=path_between(unit.position,goal);unit.ai_path_goal=goal;unit.repath=1.3+world.rng.randf()*.6;paths_this_frame+=1
			world.ai_budget_usec-=Time.get_ticks_usec()-path_started
		while not unit.path.is_empty() and unit.position.distance_to(unit.path[0])<.36:unit.path.pop_front()
		if not unit.path.is_empty():velocity=(unit.path[0]-unit.position).normalized()*2.8
		elif unit.position.distance_to(goal)<1.4 and traversable(world,unit.position,goal):velocity=(goal-unit.position).normalized()*1.8
	if world.time<float(unit.get("ai_recovery_until",0)):
		goal=unit.ai_recovery_goal;velocity=(goal-unit.position).normalized()*1.9;unit.ai_state="recover";moving=true
	profile_time=profile_part("tactics_path_ms",profile_time)
	velocity*=world.terrain.speed_at(unit.position)*[1.0,.60,.62/2.8][clampi(int(unit.stance),0,2)]*(1-float(unit.ai_stress)*.17)
	if not visible and world.time<float(order.get("watch_until",0)):
		unit.ai_alert_at=order.watch_goal;unit.ai_alert_until=world.time+.2
	if velocity.length_squared()>.1 and not visible:
		var look=velocity.angle()
		if world.time<float(unit.get("ai_alert_until",0)) and fmod(world.time+float(unit.id)*.1,1.8)<.5:look=(unit.ai_alert_at-unit.position).angle()
		unit.facing=Vector2.from_angle(rotate_toward(unit.facing.angle(),look,delta*6))
	elif not visible and world.time<float(unit.get("ai_alert_until",0)):
		unit.facing=Vector2.from_angle(rotate_toward(unit.facing.angle(),(unit.ai_alert_at-unit.position).angle(),delta*6))
	world.move_unit(unit,tactics.steer(unit,velocity),delta)
	profile_time=profile_part("movement_ms",profile_time)
	var progress: Dictionary=preload("res://scripts/campaign_member_progress.gd").sample(unit,unit.get("ai_member_progress",{}),base_goal,world.time)
	unit.ai_member_progress=progress;unit.ai_last_progress_at=progress.at
	if moving:
		unit.ai_stuck=maxf(0,world.time-float(progress.at))
		if unit.ai_stuck>1.1 and world.time>=float(unit.get("ai_recover_after",0)):
			var escape=tactics.recover(unit,goal)
			accept_recovery(unit,escape,world.time)
	else:unit.ai_stuck=0.0;progress.at=world.time
	profile_part("recovery_ms",profile_time)
	vehicle_ai.try_board(unit)

static func accept_recovery(unit: Dictionary,escape: Vector2,now: float) -> void:
	var pending=unit.has("ai_recovery_search")
	unit.ai_recover_after=now+(.04 if pending else 1.4)
	# A deferred search has no result yet. Keep the route it may have just
	# consumed the shared budget to find instead of erasing it every retry.
	if pending:return
	unit.repath=0;unit.path=[]
	if escape.distance_to(unit.position)>.3:unit.ai_recovery_goal=escape;unit.ai_recovery_until=now+.65

static func tactics_due(unit: Dictionary,contact: Dictionary,weapon: Dictionary,signature: String,decide: bool,visible: bool,budget_usec: int) -> bool:
	if budget_usec<=0:return false
	var lane_pending=visible and not DirectionalAim.fire_context_matches(unit,contact,weapon)
	return decide or lane_pending or not unit.has("ai_tactic") or signature!=unit.get("ai_tactic_signature","")

func observe_event(event: Dictionary) -> void:
	if world_ref.get_ref().campaign_director.plan_executor.world_ref!=null:world_ref.get_ref().campaign_director.plan_executor.observe_event(event)
	if event.get("type","")=="damage":
		var source=int(event.get("source_id",-1));var world=world_ref.get_ref()
		if source>=0 and source<world.units.size():
			var shooter: Dictionary=world.units[source];var target: Dictionary=event.unit
			var report: Dictionary=shooter.get("ai_contacts",{}).get(int(target.id),{})
			if int(event.get("source_epoch",-1))==int(shooter.get("spawn_epoch",0)) and int(report.get("spawn_epoch",-1))==int(target.get("spawn_epoch",0)) and report.get("source","")=="vision" and world.time-float(report.get("observed_at",-100))<1.3:
				shooter.ai_effect_at=world.time;shooter.ai_effect_position=Vector2(report.position)
	if event.get("type","")=="shot":
		var shooter: Dictionary=event.unit
		if not shooter.get("player",false) and shooter.get("alive",false):
			shooter.ai_last_shot_at=world_ref.get_ref().time
			shooter.ai_last_shot_target=int(shooter.get("ai_target",-1))
			shooter.ai_last_shot_epoch=int(shooter.get("spawn_epoch",0))
			shooter.ai_last_shot_target_epoch=int(shooter.get("ai_contacts",{}).get(int(shooter.get("ai_target",-1)),{}).get("spawn_epoch",-1))
	perception.observe_event(event)
	if event.get("type","") in ["respawn","death"]:
		capture_reservations.claims.erase(event.unit.id);tactics.standpoints.erase(event.unit.id)
	if event.get("type","")=="respawn":event.unit.erase("ai_order")

func objective_goal(world,unit: Dictionary) -> Vector2:
	var order: Dictionary=unit.get("ai_order",{})
	var point: Dictionary=world.campaign.points[0] if not world.campaign.points.is_empty() else {}
	var destination: Vector2=order.get("goal",point.get("position",unit.spawn))
	var task=str(order.get("task","attack"));unit.ai_task=task
	var assigned: Array=routes[int(unit.team)]
	var near=not point.is_empty() and preload("res://scripts/capture_zone.gd").contains(point,unit.position,unit.elevation)
	if task=="reserve" or bool(order.get("direct",false)) or order.get("capture_commit",false) or (near and not bool(order.get("mandatory_route",false))) or assigned.is_empty():unit.ai_route_done=true;return destination
	var selected=posmod(int(order.get("route_index",int(unit.campaign_slot/5))),assigned.size())
	var route: Array=assigned[selected]
	if route.is_empty():unit.ai_route_done=true;return destination
	var changed=int(unit.get("ai_route_selected",-1))!=selected
	if changed or not unit.has("ai_route_index"):
		unit.ai_route_selected=selected;unit.ai_route_done=false
		var index=route.size();var best=INF;var remaining=0.0
		var suffix=[];suffix.resize(route.size())
		for i in range(route.size()-1,-1,-1):
			if i<route.size()-1:remaining+=route[i].distance_to(route[i+1])
			suffix[i]=remaining
		var direct_distance=unit.position.distance_to(destination)
		# Keep the authored final approach/gate sequence. Jumping straight to its
		# final waypoint sends southern arrivals across the exposed courtyard.
		for i in range(mini(2,route.size()) if bool(order.get("mandatory_route",false)) else maxi(1,route.size()-2)):
			var entry_distance=unit.position.distance_to(route[i])
			# Never march back into a deep flank when already closer to the objective.
			if not bool(order.get("mandatory_route",false)) and route[i].distance_to(destination)>direct_distance+3.0:continue
			var score=entry_distance+float(suffix[i])*.16
			if score<best:best=score;index=i
		unit.ai_route_index=index
	var index=int(unit.ai_route_index)
	while index<route.size() and unit.position.distance_to(route[index])<1.6:index+=1
	unit.ai_route_index=index
	if index<route.size() and not unit.get("ai_route_done",false):return route[index]
	unit.ai_route_done=true;return destination

static func select_target(world,unit: Dictionary) -> Dictionary:
	var candidates=[]
	for enemy in world.units:
		if not enemy.alive or enemy.team==unit.team or world.enclosed(enemy):continue
		var distance=unit.position.distance_squared_to(enemy.position)
		if distance<42*42:candidates.append({"unit":enemy,"distance":distance})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	for i in range(mini(5,candidates.size())):
		if line_of_sight(world,unit,candidates[i].unit):return candidates[i].unit
	return {}

static func line_of_sight(world,unit: Dictionary,target: Dictionary) -> bool:
	var origin=Vector3(unit.position.x,world.muzzle_height(unit),unit.position.y)
	var aim=Vector3(target.position.x,target.elevation+world.stance_height(target.stance)*.64,target.position.y)
	var direction=aim-origin
	return world.trace_3d(origin,direction.normalized(),direction.length(),{"source":unit.id,"team":unit.team},true).is_empty()

static func blast_clear(world,unit: Dictionary,at: Vector2,radius: float) -> bool:
	for other in world.units:
		if other.alive and other.team==unit.team and other.position.distance_to(at)<radius+1:return false
	return true

static func select_weapon(world,unit: Dictionary,distance: float) -> void:
	var loadout: Array=unit.get("loadout",[])
	if loadout.is_empty():return
	var chosen=str(loadout[0])
	if "portable-mortar" in loadout and distance>14:chosen="portable-mortar"
	if bool(unit.get("ai_order",{}).get("breach_thrower",false)):
		var grenade=world.campaign_director.plan_executor.grenade_id(unit)
		if not grenade.is_empty():chosen=grenade
	var state: Dictionary=unit if chosen==unit.weapon_id else unit.inventory.get(chosen,{"ammo":1,"reserve":1})
	if int(state.ammo)+int(state.reserve)<=0:
		for id in loadout:
			var weapon: Dictionary=world.catalog.weapons[id]
			var ammo: Dictionary=unit if id==unit.weapon_id else unit.inventory.get(id,{"ammo":int(weapon.mag),"reserve":int(weapon.reserve)})
			if weapon.kind not in ["grenade","mortar"] and (int(ammo.ammo)+int(ammo.reserve)>0 or weapon.kind=="melee"):chosen=id;break
	# A deployed mortar deliberately holsters its former carrier. Selecting the
	# same carried weapon must also draw it; otherwise Equipment.busy blocks fire
	# forever after an AI leaves the mount. Never recreate a deployed inventory item.
	if chosen==unit.weapon_id and not unit.get("holstered",false):return
	if unit.weapon_id in loadout:
		unit.inventory[unit.weapon_id]={"ammo":unit.ammo,"reserve":unit.reserve,"fire_mode":world.FireControl.selected(unit,world.weapon_for(unit))}
	unit.weapon_id=chosen;unit.holstered=false
	var weapon: Dictionary=world.weapon_for(unit);var stored: Dictionary=unit.inventory.get(chosen,{"ammo":int(weapon.mag),"reserve":int(weapon.reserve)})
	unit.ammo=stored.ammo;unit.reserve=stored.reserve;unit.reload=0.0;unit.cooldown=.35;unit.fire_mode=stored.get("fire_mode",world.FireControl.default_mode(weapon))
	world.Handling.reset(unit);world.FireControl.reset(unit,weapon);world.FireControl.cancel(unit,true)
	world.event.emit({"type":"equip","unit":unit,"weapon":weapon})
