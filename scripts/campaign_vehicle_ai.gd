extends RefCounted
## Few authored support routes; shared decision budget, real driving/collision/ammo.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Emplacement=preload("res://scripts/emplacement_profile.gd")
const Mission=preload("res://scripts/campaign_asset_mission.gd")
const Zone=preload("res://scripts/capture_zone.gd")
const Suppression=preload("res://scripts/campaign_suppression.gd")
var world_ref: WeakRef
var reservations: Dictionary={}
var routes: Dictionary={}
var cursor=0
var assign_at=0.0
var mission_jobs: Dictionary={}
var missions: Dictionary={}

func configure(world):
	world_ref=weakref(world);reservations.clear();routes.clear();mission_jobs.clear();missions.clear();cursor=0;assign_at=.8
	for id in world.plan.godot3d.get("vehicleRoutes",{}):
		routes[id]=[]
		for p in world.plan.godot3d.vehicleRoutes[id]:routes[id].append(world.catalog.position(p,world.plan))

func objective_changed() -> void:
	# A public stage transition replaces goals, never actors, ammunition or crew.
	# Replanning remains deferred to the existing two-pose/shared-budget job pump.
	var world=world_ref.get_ref()
	for uid in reservations.keys():cancel_reservation(int(uid),false)
	missions.clear();mission_jobs.clear();routes.clear()
	for id in world.plan.get("godot3d",{}).get("vehicleRoutes",{}):
		routes[id]=[]
		for point in world.plan.godot3d.vehicleRoutes[id]:routes[id].append(world.catalog.position(point,world.plan))
	for v in world.vehicles:
		if not v.get("ai_controlled",false) or v.destroyed:continue
		for key in ["ai_mission","ai_mission_blocked_at","ai_best_post_distance","ai_support_wait_at"]:v.erase(key)
		v.ai_force_replan=true;v.ai_route_index=0;v.ai_stuck=0.0;v.ai_reverse_until=world.time

static func available(v: Dictionary,unit: Dictionary) -> bool:
	return not v.destroyed and not v.driver and int(v.get("driver_id",-1))<0 and (int(v.team)<0 or int(v.team)==int(unit.team))

func boarding_points(v: Dictionary) -> Array:
	var world=world_ref.get_ref()
	var points=[]
	for angle in ([0.0,-.55,.55] if v.emplacement else [PI*.5,-PI*.5,PI,0.0]):
		var at: Vector2=Emplacement.operator_position(v)-Vector2.from_angle(v.turret_angle+angle)*.45 if v.emplacement else Dimensions.exit_point(v,Vector2.from_angle(v.angle+angle),.48)
		var ground: float=world.terrain.height(at)
		if absf(ground-float(v.elevation))<.45 and not world.blocked(at,.31,1.95,-1,ground):points.append(at)
	return points

func boarding_point(v: Dictionary) -> Vector2:
	var points=boarding_points(v);return points[0] if not points.is_empty() else Vector2.INF

static func eligible(u: Dictionary,v: Dictionary,now: float) -> bool:
	if not u.alive or u.player or int(u.get("network_peer_id",0))>0 or u.mounted>=0 or not available(v,u):return false
	if now<float(u.get("ai_vehicle_retry_at",0)) or u.health<u.max_health*.4 or float(u.get("ai_stress",0))>.62 or not u.vault.is_empty() or not u.ladder.is_empty():return false
	var order: Dictionary=u.get("ai_order",{})
	return not order.get("breach_thrower",false) and not order.get("breach_open",false) and str(order.get("bound_role",""))!="cover"

static func crew_cost(u: Dictionary,at: Vector2) -> float:
	var order: Dictionary=u.get("ai_order",{});var task=str(order.get("task","attack"))
	var disruption=7.0 if task=="attack" else 5.5 if task=="hold" else 2.0 if task=="control" else -6.0 if task=="support" else -3.0
	if str(u.get("class_id","")) in ["antitank","sniper","medic"]:disruption+=4.0
	return u.position.distance_to(at)+disruption

func frontage() -> Vector2:
	var world=world_ref.get_ref()
	var metadata: Dictionary=world.plan.get("godot3d",{}).get("campaign_tactics",{})
	if metadata.has("vehicle_frontage"):return world.catalog.position(metadata.vehicle_frontage,world.plan)
	if (bool(world.plan.get("godot3d",{}).get("source_layout",false)) or int(world.plan.get("godot3d",{}).get("campaign_chapter",1))>1) and not world.campaign.points.is_empty():return world.campaign.points[0].position
	return world.catalog.position([2350,1100],world.plan)

func cancel_reservation(id: int,cooldown: bool=true):
	if not reservations.has(id):return
	var world=world_ref.get_ref();var r: Dictionary=reservations[id];var u: Dictionary=world.units[id]
	if cooldown:
		u.ai_vehicle_retry_at=world.time+4.0;world.vehicles[r.vehicle].ai_crew_available_at=world.time+1.5
	reservations.erase(id);u.path=[];u.repath=0;u.erase("ai_tactic")

func reservation_valid(u: Dictionary,r: Dictionary) -> bool:
	var world=world_ref.get_ref();var v: Dictionary=world.vehicles[r.vehicle]
	return eligible(u,v,world.time) and int(u.get("spawn_epoch",0))==int(r.epoch) and world.time<=float(r.expires) and Vector2(v.position).distance_squared_to(r.mount_position)<.25

func prepare_mission(v: Dictionary) -> bool:
	var world=world_ref.get_ref();var key=int(v.id)
	if missions.has(key) and not v.get("ai_force_replan",false):
		# Destruction can remove route obstacles; it must not restart a useful job
		# for every distant broken wall cell. Movement still uses live colliders.
		if not missions[key].result.is_empty() or world.time<float(missions[key].get("retry_at",0)):return not missions[key].result.is_empty()
	if v.emplacement:
		var pending: Dictionary=mission_jobs.get(key,{})
		if pending.get("kind","")=="sector":
			if not pending.done:v.ai_state="checking-sector";return false
			if pending.get("invalidated",false):mission_jobs.erase(key);v.ai_force_replan=true;return false
			var useful=not pending.result.is_empty()
			missions[key]={"revision":world.topology_revision,"retry_at":world.time+5.0,"result":pending.result,"sector_samples":4+int(pending.samples)}
			mission_jobs.erase(key);v.ai_force_replan=false
			v.ai_state="waiting-crew" if useful else "sector-blocked";return useful
		var angle=v.angle+clampf(wrapf((frontage()-Vector2(v.position)).angle()-float(v.angle),-PI,PI),-float(v.profile.traverse)*.7,float(v.profile.traverse)*.7)
		var aim=Vector2.INF
		for bearing in [angle,float(v.angle),float(v.angle)+float(v.profile.traverse)*.5,float(v.angle)-float(v.profile.traverse)*.5]:
			var candidate: Vector2=v.position+Vector2.from_angle(bearing)*6.0
			if Mission.firing_lane(world,v,v.position,candidate):aim=candidate;break
		var useful=aim.is_finite()
		if not useful:
			mission_jobs[key]=Mission.begin_sector(v,frontage());v.ai_state="checking-sector";return false
		missions[key]={"revision":world.topology_revision,"retry_at":world.time+5.0,"result":{"goal":v.position,"route":[],"focus":aim} if useful else {}}
		v.ai_force_replan=false
		v.ai_state="waiting-crew" if useful else "sector-blocked";return useful
	var job: Dictionary=mission_jobs.get(key,{})
	if job.is_empty() or Vector2(job.origin).distance_to(v.position)>1.0:
		job=Mission.begin(world,v,routes.get(v.source_id,[]),frontage());mission_jobs[key]=job
	if not job.done:v.ai_state="checking-route";return false
	missions[key]={"revision":world.topology_revision,"retry_at":world.time+8.0,"result":job.result};mission_jobs.erase(key);v.ai_force_replan=false
	v.ai_state="waiting-crew" if not job.result.is_empty() else "route-blocked"
	return not job.result.is_empty()

func tick():
	var world=world_ref.get_ref()
	if world.vehicles.is_empty():mission_jobs.clear();missions.clear();return
	if world.ai_budget_usec<=0:return
	var started=Time.get_ticks_usec()
	# Route geometry progresses every frame, independently of the 0.75 s asset
	# recruitment cycle. At most one sliced job spends the shared budget.
	for id in mission_jobs.keys():
		if int(id)<0 or int(id)>=world.vehicles.size() or int(world.vehicles[int(id)].id)!=int(id):mission_jobs.erase(id);continue
		var job: Dictionary=mission_jobs[id]
		if job.done:continue
		if job.get("kind","")=="sector":Mission.pump_sector(world,world.vehicles[id],job,mini(350,int(world.ai_budget_usec)))
		else:Mission.pump(world,world.vehicles[id],job,mini(350,int(world.ai_budget_usec)),2)
		break
	if world.time<assign_at:world.ai_budget_usec-=Time.get_ticks_usec()-started;return
	assign_at=world.time+.25
	var v: Dictionary=world.vehicles[cursor%world.vehicles.size()];cursor+=1
	for uid in reservations.keys():
		var r: Dictionary=reservations[uid];var u: Dictionary=world.units[uid]
		if not reservation_valid(u,r):cancel_reservation(uid);continue
		if Vector2(u.position).distance_to(r.progress)>.25:r.progress=u.position;r.progress_at=world.time
		elif world.time-float(r.progress_at)>3.0:cancel_reservation(uid)
	if v.get("ai_controlled",false) and not v.driver and int(v.get("driver_id",-1))<0 and not v.destroyed and world.time>=float(v.get("ai_crew_available_at",0)) and has_ammo(v) and prepare_mission(v):
		var claimed=false
		for r in reservations.values():
			if r.vehicle==v.id:claimed=true;break
		if not claimed:
			assign_crew(v)
	world.ai_budget_usec-=Time.get_ticks_usec()-started

static func has_ammo(v: Dictionary) -> bool:
	for state in v.states.values():
		if int(state.ammo)+int(state.reserve)>0:return true
	return false

func assign_crew(v: Dictionary):
	var world=world_ref.get_ref();var ai=world.campaign_ai;var points=boarding_points(v);var candidates=[];var occupied=[0,0];var living=[0,0]
	for u in world.units:
		if u.alive and not u.player and int(u.get("network_peer_id",0))<=0:
			living[int(u.team)]+=1
			if u.mounted>=0 or reservations.has(u.id):occupied[int(u.team)]+=1
	for u in world.units:
		if reservations.has(u.id) or not eligible(u,v,world.time) or occupied[int(u.team)]>=maxi(1,floori(living[int(u.team)]*.2)):continue
		if not world.campaign.points.is_empty() and Zone.contains(world.campaign.points[0],u.position,u.elevation) and str(u.get("ai_order",{}).get("task","")) in ["attack","hold"]:continue
		if u.position.distance_squared_to(v.position)>30*30:continue
		candidates.append({"unit":u,"cost":crew_cost(u,v.position)})
	candidates.sort_custom(func(a,b):return a.cost<b.cost)
	var frame=Engine.get_physics_frames()
	if ai.path_frame!=frame:ai.path_frame=frame;ai.paths_this_frame=0
	for candidate in candidates.slice(0,6):
		var u: Dictionary=candidate.unit
		for at in points:
			if not ai.same_component(u.position,at):continue
			var target=ai.point_cell(at);var start=ai.point_cell(u.position)
			if target<0 or start<0 or not ai.traversable(world,ai.graph.get_point_position(target),at):continue
			if ai.paths_this_frame>=2 or world.ai_budget_usec<=0:return
			ai.paths_this_frame+=1
			var path=Array(ai.graph.get_point_path(start,target,false))
			if path.is_empty() or not ai.traversable(world,u.position,path[0]):continue
			var length=0.0;var previous: Vector2=u.position
			for p in path:length+=previous.distance_to(p);previous=p
			if length>60:continue
			path.append(at)
			reservations[u.id]={"vehicle":v.id,"goal":at,"epoch":int(u.get("spawn_epoch",0)),"mount_position":v.position,"expires":world.time+clampf(length/2.0+6,8,36),"progress":u.position,"progress_at":world.time}
			u.path=path;u.ai_path_goal=at;u.repath=1.6;u.erase("ai_tactic");return

func goal(unit: Dictionary) -> Vector2:
	if not reservations.has(unit.id):return Vector2.INF
	var world=world_ref.get_ref();var r: Dictionary=reservations[unit.id]
	if not reservation_valid(unit,r):
		cancel_reservation(unit.id);return Vector2.INF
	return r.goal

func try_board(unit: Dictionary):
	if not reservations.has(unit.id):return
	var world=world_ref.get_ref();var r: Dictionary=reservations[unit.id]
	if unit.position.distance_to(r.goal)>.30:return
	var v: Dictionary=world.vehicles[r.vehicle]
	if not reservation_valid(unit,r):cancel_reservation(unit.id);return
	if absf(unit.elevation-world.terrain.height(r.goal))>.2 or not unit.grounded:return
	if v.emplacement:
		var seat=Emplacement.operator_position(v)
		if unit.position.distance_to(seat)>.8:return
		for i in range(1,9):
			var at: Vector2=unit.position.lerp(seat,float(i)/8)
			if world.blocked(at,.31,1.95,v.id,world.terrain.height(at)):return
	if world.mount_unit(unit,v.id):
		v.ai_route_index=0;v.ai_next_scan=world.time+.25;v.ai_contact={};v.ai_progress=v.position;v.ai_stuck=0.0;v.ai_recover_attempts=0
		v.ai_mission=missions.get(int(v.id),{}).get("result",{});v.ai_mission_revision=world.topology_revision
		v.ai_best_post_distance=v.position.distance_to(v.ai_mission.get("goal",v.position))
		reservations.erase(unit.id);unit.ai_state="mounted-support"

static func steering(v: Dictionary,target: Vector2) -> Vector2:
	var offset=target-Vector2(v.position);var error=wrapf(offset.angle()-float(v.angle),-PI,PI)
	var throttle=clampf(offset.length()/3.0,.18,.72)*clampf(1.0-absf(error)/PI,.28,1.0)
	return Vector2(throttle,clampf(error*1.6,-1,1))

func scan(v: Dictionary,u: Dictionary):
	var world=world_ref.get_ref()
	if world.time<float(v.get("ai_next_scan",0)) or world.ai_budget_usec<=0:return
	var started=Time.get_ticks_usec();v.ai_next_scan=world.time+.48+float(v.id%3)*.06
	var previous: Dictionary=v.get("ai_contact",{})
	var candidates=[];var sight=minf(35.0,float(world.mounted_weapon(v).get("range",1200))/40.0)
	for target in world.units:
		if not target.alive or target.team==u.team:continue
		var offset: Vector2=target.position-v.position
		if offset.length_squared()>sight*sight:continue
		if v.emplacement and absf(wrapf(offset.angle()-v.angle,-PI,PI))>float(v.profile.traverse):continue
		var score=offset.length_squared()-(16.0 if int(previous.get("id",-1))==int(target.id) else 0.0)
		candidates.append({"unit":target,"distance":score})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	var suppressive=Suppression.machinegun(world.mounted_weapon(v))
	v.ai_contact=previous if suppressive and Suppression.known(previous,world.time) else {}
	var eye=Vector3(v.position.x,v.elevation+(1.35 if v.emplacement else 1.8),v.position.y)
	if world.muzzle_provider.is_valid():
		var resolved: Dictionary=world.muzzle_provider.call(u,world.mounted_weapon(v),v.id)
		if resolved.has("position"):eye=resolved.position
	var indices=[]
	if not candidates.is_empty():indices.append(0)
	if candidates.size()>1:
		indices.append(1+posmod(int(v.get("ai_scan_cursor",0)),candidates.size()-1));v.ai_scan_cursor=int(v.get("ai_scan_cursor",0))+1
	for i in indices:
		var target: Dictionary=candidates[i].unit
		var mark=Vector3(target.position.x,target.elevation+(.95 if target.stance==0 else .62 if target.stance==1 else .30),target.position.y)
		var ray=mark-eye
		var hit=world.trace_3d(eye,ray.normalized(),ray.length(),{"source":u.id,"team":u.team,"mount":v.id},true)
		if not hit.is_empty() and not (hit.type=="vehicle" and int(target.mounted)==int(hit.target.id)):continue
		# A clear observation is not a continuously tracked body target. Keep its
		# imperfect direction until the next bounded scan, with acquisition delay.
		var same=int(previous.get("id",-1))==int(target.id) and int(previous.get("epoch",-1))==int(target.get("spawn_epoch",0))
		v.ai_contact={"id":target.id,"epoch":int(target.get("spawn_epoch",0)),"source":"vision","mark":mark,"at":world.time,"ready_at":previous.get("ready_at",world.time+.12) if same else world.time+(.12 if suppressive else .35),"fire_clear":false,"yaw_error":world.rng.randf_range(-.06,.06),"height_error":world.rng.randf_range(-.25,.25)}
		break
	if suppressive and (v.ai_contact.is_empty() or world.time-float(v.ai_contact.at)>.7):
		var report=reported_sector(v,u,sight)
		if not report.is_empty() and (v.ai_contact.is_empty() or float(report.at)>float(v.ai_contact.at)):v.ai_contact=report
	if not v.ai_contact.is_empty():v.ai_contact.fire_clear=not friendly_fire_mask(v,u,eye,v.ai_contact.mark,suppressive)
	world.ai_budget_usec-=Time.get_ticks_usec()-started

func reported_sector(v: Dictionary,u: Dictionary,sight: float) -> Dictionary:
	var world=world_ref.get_ref();var best={};var score=INF
	# Local allied visual reports provide a firing direction, not hidden enemy
	# state. Their original observation clock is never refreshed by the relay.
	for ally in world.nearby_units(v.position,12.0):
		if not ally.alive or ally.id==u.id or ally.team!=u.team:continue
		for id in ally.get("ai_contacts",{}):
			var report: Dictionary=ally.ai_contacts[id]
			if not Suppression.known(report,world.time) or world.time-float(report.observed_at)>1.0 or float(report.get("confidence",0))<.4:continue
			var offset: Vector2=report.position-v.position
			if offset.length_squared()>sight*sight or (v.emplacement and absf(wrapf(offset.angle()-v.angle,-PI,PI))>float(v.profile.traverse)):continue
			var cost=offset.length_squared()+20.0*(world.time-float(report.observed_at))
			if cost>=score:continue
			score=cost
			var height=[.95,.62,.30][clampi(int(report.get("stance",0)),0,2)]
			best={"id":id,"epoch":int(report.get("spawn_epoch",0)),"source":"vision","relay":ally.id,"mark":Vector3(report.position.x,float(report.get("elevation",0))+height,report.position.y),"at":float(report.observed_at),"ready_at":world.time+.12,"fire_clear":false,"yaw_error":.05,"height_error":.12}
	return best

func friendly_fire_mask(v: Dictionary,u: Dictionary,eye: Vector3,mark: Vector3,suppressive: bool) -> bool:
	var world=world_ref.get_ref();var planar=Vector2(mark.x,mark.z)-Vector2(eye.x,eye.z);var direction=planar.normalized()
	for ally in world.nearby_units(v.position,minf(8.0,planar.length())):
		if not ally.alive or ally.team!=u.team or ally.id==u.id or ally.mounted==v.id:continue
		var offset: Vector2=ally.position-Vector2(eye.x,eye.z);var along=offset.dot(direction)
		var corridor=.5+(along*tan(Suppression.YAW_CONE) if suppressive else 0.0)
		if along>.25 and along<minf(8.0,planar.length()) and absf(offset.cross(direction))<corridor:
			var height=lerpf(eye.y,mark.y,along/maxf(.1,planar.length()))
			if height>=float(ally.elevation) and height<=float(ally.elevation)+world.stance_height(ally.stance):return true
	return false

func friendly_ahead(v: Dictionary,u: Dictionary) -> bool:
	var world=world_ref.get_ref();var forward=Vector2.from_angle(v.angle)
	for ally in world.units:
		if not ally.alive or ally.id==u.id or ally.team!=u.team or ally.mounted>=0:continue
		var delta: Vector2=ally.position-v.position;var along=delta.dot(forward)
		if along>0 and along<3.4+absf(v.speed)*.45 and absf(delta.cross(forward))<v.dimensions.half.y+.5 and absf(ally.elevation-v.elevation)<1.8:return true
	return false

func infantry_support_hold(v: Dictionary,u: Dictionary,target: Vector2,seen: bool) -> bool:
	var world=world_ref.get_ref();var forward=(target-Vector2(v.position)).normalized()
	var leading=-INF;var found=false
	for ally in world.units:
		if not ally.alive or ally.player or ally.team!=u.team or ally.mounted>=0:continue
		var order: Dictionary=ally.get("ai_order",{})
		if order.get("lane","") not in ["main","defense"]:continue
		var offset: Vector2=ally.position-v.position
		if offset.length_squared()>18*18 or absf(offset.cross(forward))>6:continue
		found=true;leading=maxf(leading,offset.dot(forward))
	if not found:
		if not v.has("ai_support_wait_at"):v.ai_support_wait_at=world.time
		return v.position.distance_to(frontage())<18.0 or (seen and world.time-float(v.ai_support_wait_at)<3.0)
	v.erase("ai_support_wait_at")
	return leading< -4.0

func update(v: Dictionary,delta: float):
	var world=world_ref.get_ref();var uid=int(v.get("driver_id",-1))
	if uid<0 or uid>=world.units.size():return
	var u: Dictionary=world.units[uid]
	if not u.alive or u.player or int(u.get("network_peer_id",0))>0 or u.mounted!=v.id:return
	if v.emplacement:v.ai_state="operate"
	var state: Dictionary=v.states[v.modes[v.mode]]
	if int(state.ammo)+int(state.reserve)<=0:
		for i in range(v.modes.size()):
			var next_state: Dictionary=v.states[v.modes[i]]
			if int(next_state.ammo)+int(next_state.reserve)>0:v.mode=i;state=next_state;break
	if v.health<v.max_health*.2 or not has_ammo(v):
		if leave(u):return
	scan(v,u)
	var contact: Dictionary=v.get("ai_contact",{})
	var suppressive=Suppression.machinegun(world.mounted_weapon(v))
	var seen=Suppression.known(contact,world.time) if suppressive else not contact.is_empty() and world.time-float(contact.at)<.8
	var mission: Dictionary=v.get("ai_mission",{})
	if not v.emplacement and (mission.is_empty() or v.get("ai_force_replan",false)) and world.ai_budget_usec>0:
		var started=Time.get_ticks_usec()
		if prepare_mission(v):v.ai_mission=missions[v.id].result;v.ai_mission_revision=world.topology_revision;v.ai_route_index=0
		elif missions.has(v.id) and mission_jobs.get(v.id,{}).get("done",true):
			if not v.has("ai_mission_blocked_at"):v.ai_mission_blocked_at=world.time
			if world.time-float(v.ai_mission_blocked_at)>3.0 and leave(u):world.ai_budget_usec-=Time.get_ticks_usec()-started;return
		world.ai_budget_usec-=Time.get_ticks_usec()-started
		mission=v.get("ai_mission",{})
	var route: Array=mission.get("route",[]);var route_index=int(v.get("ai_route_index",0))
	while route_index<route.size() and v.position.distance_to(route[route_index])<1.0:route_index+=1
	v.ai_route_index=route_index
	if not v.emplacement:
		var move=route_index<route.size()
		var request=steering(v,route[route_index]) if move else Vector2.ZERO
		if world.time>=float(v.get("ai_next_traffic",0)):
			v.ai_next_traffic=world.time+.2;v.ai_yield=friendly_ahead(v,u)
			v.ai_support_hold=infantry_support_hold(v,u,route[route_index],seen) if move else false
		var checking=mission.is_empty() or bool(v.get("ai_force_replan",false))
		var post_distance: float=v.position.distance_to(mission.get("goal",v.position))
		# Fire from a stable post when contact is useful, then resume the objective
		# approach when observation expires; seeing a rifleman never changes route.
		var combat_hold=seen and post_distance<7.0 and absf(v.speed)<2.0
		var stop=not move or checking or combat_hold or bool(v.get("ai_yield",false)) or bool(v.get("ai_support_hold",false))
		if not stop and v.position.distance_to(v.get("ai_progress",v.position))<.18:v.ai_stuck=float(v.get("ai_stuck",0))+delta
		elif v.position.distance_to(v.get("ai_progress",v.position))>=.18:v.ai_stuck=0.0;v.ai_progress=v.position
		else:v.ai_stuck=0.0
		if post_distance<float(v.get("ai_best_post_distance",INF))-.75:v.ai_best_post_distance=post_distance;v.ai_recover_attempts=0
		if float(v.ai_stuck)>1.6:
			v.ai_reverse_until=world.time+.9;v.ai_stuck=0.0;v.ai_recover_attempts=int(v.get("ai_recover_attempts",0))+1
			if v.ai_recover_attempts>=4 and leave(u):v.ai_crew_available_at=world.time+16.0;return
		if world.time<float(v.get("ai_reverse_until",0)) and not stop:request=Vector2(-.35,-request.y*.6)
		if stop:request=Vector2.ZERO
		if not request.is_zero_approx() or v.velocity.length_squared()>.000001 or v.get("airborne",false):world.drive(v,request.x,request.y,delta,false,false,stop)
		v.ai_state="checking-route" if checking else "yield" if v.get("ai_yield",false) else "engage-post" if combat_hold else "overwatch" if v.get("ai_support_hold",false) else "drive" if move else "screen-gate"
	var wanted=(frontage()-Vector2(v.position)).angle()
	if v.emplacement:
		wanted=(Vector2(mission.get("focus",frontage()))-Vector2(v.position)).angle()
		var center_angle=float(v.angle)+clampf(wrapf(wanted-float(v.angle),-PI,PI),-float(v.profile.traverse)*.6,float(v.profile.traverse)*.6)
		wanted=center_angle+sin(world.time*.55+float(v.id))*.35*float(v.profile.traverse)
	if seen:
		var target: Vector3=contact.mark;var planar=Vector2(target.x,target.z)-Vector2(v.position)
		wanted=planar.angle()+float(contact.yaw_error)+(sin(world.time*3.2+float(v.id))*.07 if suppressive else 0.0)
		var aim=Vector2(v.position)+Vector2.from_angle(wanted)*planar.length()
		v.aim_target=Vector3(aim.x,target.y+float(contact.height_error),aim.y)
	else:
		v.aim_target=Vector3(v.position.x, v.elevation+1.0,v.position.y)+Vector3(cos(wanted),0,sin(wanted))*12
	if v.emplacement:wanted=v.angle+clampf(wrapf(wanted-v.angle,-PI,PI),-float(v.profile.traverse),float(v.profile.traverse))
	var next=rotate_toward(v.turret_angle,wanted,float(v.profile.get("turretTurnRate",v.profile.get("turnRate",1)))*delta)
	if not v.emplacement:v.turret_angle=next
	elif absf(next-v.turret_angle)>.00001:
		var p=Emplacement.operator_position(v,next);var h: float=world.PortableMortar.operator_height(world,v,p)
		if absf(h-v.elevation)<.35 and not world.blocked(p,.31,1.5 if v.type=="portableMortar" else 1.95,v.id,h):v.turret_angle=next
	u.position=Emplacement.operator_position(v) if v.emplacement else v.position
	u.elevation=world.PortableMortar.operator_height(world,v,u.position) if v.emplacement else v.elevation
	if v.type=="portableMortar":u.stance=1;u.stance_blend=1.0
	u.facing=Vector2.from_angle(v.turret_angle);u.velocity=Vector2.ZERO
	u.aim_point=Vector2(v.aim_target.x,v.aim_target.z);u.aim_height=v.aim_target.y;u.aim_valid=seen;u.aiming=seen
	var burst=Suppression.burst(world.time,v.id) if suppressive else fmod(world.time+float(v.id)*.37,1.45)<.55
	var error=wrapf(wanted-float(v.turret_angle),-PI,PI)
	var aligned=seen and (Suppression.in_sector(error) if suppressive else absf(error)<.09)
	var safe=aligned and bool(contact.get("fire_clear",false)) and world.time>=float(contact.get("ready_at",INF)) and world.time-float(v.get("ai_mounted_at",world.time))>.8
	var w=world.mounted_weapon(v)
	if safe and float(w.get("blastRadius",0))>0:
		for ally in world.units:
			if ally.alive and ally.team==u.team and ally.position.distance_to(u.aim_point)<float(w.blastRadius)/40.0+1:safe=false;break
	if world.FireControl.wants_shot(state,w,burst,burst and not bool(v.get("ai_was_burst",false)),safe):world.fire(u,w,state,v.position,v.turret_angle,v.elevation+1.5,u.aim_point,v.id)
	v.ai_was_burst=burst;world.RenderMotion.after_unit(u,world.time,delta)

func leave(u: Dictionary) -> bool:
	var world=world_ref.get_ref();var v: Dictionary=world.vehicles[u.mounted]
	for i in range(8):
		var point=Dimensions.exit_point(v,Vector2.from_angle(v.angle+PI*.5+i*TAU/8),.6)
		var h: float=world.ground_height(point,.31,v.elevation+.65)
		if world.terrain.grade(point)>.8 or world.blocked(point,.31,1.95,-1,h):continue
		v.driver=false;v.driver_id=-1;u.mounted=-1;u.position=point;u.elevation=h;u.path=[];u.repath=0.0
		v.ai_crew_available_at=world.time+8.0;v.erase("ai_mission_blocked_at");missions.erase(int(v.id));mission_jobs.erase(int(v.id))
		navigation_changed(v)
		world.Traversal.reset(u);u.ai_vehicle_retry_at=world.time+18.0
		# Resume the actual carried loadout, retaining the abandoned mount's ammo.
		world.campaign_ai.select_weapon(world,u,0.0)
		world.index_unit(u);return true
	return false

func destroyed(v: Dictionary):
	var world=world_ref.get_ref();var uid=int(v.get("driver_id",-1))
	navigation_changed(v)
	if uid<0 or uid>=world.units.size() or world.units[uid].player:return
	var u: Dictionary=world.units[uid]
	if not leave(u):
		v.driver=false;v.driver_id=-1;u.mounted=-1
		world.damage_unit(u,u.max_health+1,Vector3.UP,{"kind":"shell"},true)

func navigation_changed(v: Dictionary):
	var world=world_ref.get_ref();var radius: float=v.dimensions.half.length()+1.4
	world.campaign_ai.invalidate_bounds(v.position-Vector2.ONE*radius,v.position+Vector2.ONE*radius);world.navigation_dirty=true

func diagnostics() -> Dictionary:
	var result={"reserved":reservations.size(),"mounts":[]};var world=world_ref.get_ref()
	for v in world.vehicles:
		if not v.get("ai_controlled",false):continue
		result.mounts.append({"id":v.source_id,"driver":v.get("driver_id",-1),"state":v.get("ai_state","waiting"),"waypoint":v.get("ai_route_index",0),"position":str(v.position),"destroyed":v.destroyed})
	return result
