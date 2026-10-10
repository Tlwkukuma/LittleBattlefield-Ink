extends RefCounted
## Bounded local execution of the commander's mission; every candidate is body-clear.
var world_ref: WeakRef
var navigation_ref: WeakRef
var work_frame=-1
var cover_work=0
var recovery_work=0
var standpoints: Dictionary={}
const Cover=preload("res://scripts/campaign_cover.gd")

func take_budget(cover: bool) -> bool:
	if world_ref.get_ref().ai_budget_usec<=0:return false
	var frame=Engine.get_physics_frames()
	if frame!=work_frame:work_frame=frame;cover_work=0;recovery_work=0
	if cover:
		if cover_work>=1:return false
		cover_work+=1
	else:
		if recovery_work>=1:return false
		recovery_work+=1
	return true

func configure(world,navigation) -> void:world_ref=weakref(world);navigation_ref=weakref(navigation);standpoints.clear()

func position_available(point: Vector2,unit_id: int) -> bool:
	var world=world_ref.get_ref()
	for id in standpoints:
		if int(id)==unit_id:continue
		var claim: Dictionary=standpoints[id];var owner: Dictionary=world.units[int(id)]
		if not owner.alive or int(owner.get("spawn_epoch",0))!=int(claim.epoch) or world.time>=float(claim.until):continue
		if point.distance_squared_to(claim.point)<.75*.75:return false
	return true

func reserve_position(unit_id: int,point: Vector2,seconds: float) -> bool:
	if not position_available(point,unit_id):return false
	var world=world_ref.get_ref()
	standpoints[unit_id]={"point":point,"epoch":int(world.units[unit_id].get("spawn_epoch",0)),"until":world.time+seconds}
	return true

func decide(unit: Dictionary,goal: Vector2,contact: Dictionary,visible: bool) -> Dictionary:
	var world=world_ref.get_ref();var task=str(unit.get("ai_task","attack"));var order: Dictionary=unit.get("ai_order",{})
	var stress=float(unit.get("ai_stress",0));var assault=task=="attack";var distance=unit.position.distance_to(goal)
	var result={"goal":goal,"state":"advance","stance":0,"hold":false}
	unit.ai_support_ready=false;unit.ai_support_checked_at=world.time
	unit.ai_fire_clear=false
	if order.get("breach_thrower",false) and float(unit.get("ai_stress",0))<.62:
		result.goal=order.goal;result.hold=unit.position.distance_to(order.goal)<.5;result.state="breach-stage"
		return result
	if contact.is_empty():
		if distance<.85:result.state="hold" if task in ["hold","reserve"] else "screen" if task=="control" else "support" if task=="support" else "capture";result.hold=true
		return result
	var old=world.time-float(contact.get("observed_at",0))>2.6
	if old or float(contact.get("confidence",0))<.24:return result
	var weapon: Dictionary=world.weapon_for(unit)
	unit.ai_fire_clear=Cover.muzzle_clear(world,unit,contact,weapon) and not Cover.friendly_masked(world,unit,contact.position)
	preload("res://scripts/campaign_directional_aim.gd").cache_fire_context(unit,contact,weapon)
	var role=str(order.get("bound_role",""));var phase=str(order.get("bound_phase","idle"))
	var safety=stress>.62 or (unit.health/unit.max_health<.32 and stress>.32)
	if role=="cover" and phase in ["bound","handoff"]:
		# The accepted support member must stay in its actual firing position for
		# this short commitment. A fresh cover search must not move it mid-crossing.
		result.goal=unit.position;result.hold=true;result.state="bound-overwatch"
		result.stance=Cover.pose(world,unit,contact,weapon,safety or unit.reload>0,true)
		mark_support(unit,result,world);return result
	if role in ["wait","move"] and phase=="deploy":
		prepare_bound(unit,goal,contact)
		result.goal=unit.position;result.hold=true;result.state="bound-ready"
		result.stance=Cover.pose(world,unit,contact,weapon,safety,false) if safety else int(unit.stance)
		return result
	if role=="move" and phase in ["bound","handoff"]:
		var endpoint: Vector2=order.get("bound_goal",goal)
		if navigation_ref.get_ref().traversable(world,unit.position,endpoint) or unit.position.distance_to(endpoint)>.8:
			result.goal=endpoint;result.hold=unit.position.distance_to(endpoint)<.5;result.state="bound-arrive" if result.hold else "bound-move"
			if result.hold:result.stance=Cover.pose(world,unit,contact,weapon,safety,true)
			if safety:result.stance=2 if world.terrain.grade(unit.position)<.45 else 1
			mark_support(unit,result,world)
			return result
		result.state="bound-blocked";unit.ai_bound_candidate_at=-100.0;return result
	# Order semantics win over the global support/bounding style. Only half of an
	# assault squad briefly covers the other, and capture-entry urgency cancels it.
	var near_point=false
	for point in world.campaign.points:
		if preload("res://scripts/capture_zone.gd").contains(point,unit.position,unit.elevation):near_point=true;break
	var support=(task=="support" and (visible or distance<4)) or role=="cover"
	if safety or support or (task in ["hold","control","reserve"] and distance<3.5):
		var cover=choose_cover(unit,contact,goal,not safety and assault)
		if not cover.is_empty():
			result.goal=cover.position;result.stance=int(unit.stance)
			result.state="cover" if safety else "support" if support else "hold" if task=="hold" else "screen"
			result.hold=unit.position.distance_to(result.goal)<.40
			if result.hold:
				result.stance=Cover.pose(world,unit,contact,weapon,safety or unit.reload>0,support)
				if not safety and unit.reload<=0 and not unit.ai_fire_clear and cover.has("peek"):
					result.goal=cover.peek;result.stance=0;result.hold=unit.position.distance_to(result.goal)<.35;result.state="peek"
			mark_support(unit,result,world)
			return result
		if support and visible:
			result.goal=unit.position;result.hold=true;result.state="support";result.stance=Cover.pose(world,unit,contact,weapon,safety or unit.reload>0,true)
			mark_support(unit,result,world);return result
		if safety and unit.grounded:
			var stance=2 if world.terrain.grade(unit.position)<.45 else 1
			if not world.blocked(unit.position,.31,world.stance_height(stance),-1,unit.elevation):result.stance=stance;result.state="low-displacement"
	# A moving assault may use cover only when it also closes on its task. This
	# prevents every contact from turning an attack into a permanent firing line.
	if assault and not near_point and stress>.30 and not order.get("capture_commit",false):
		var cover=choose_cover(unit,contact,goal,true)
		if not cover.is_empty() and unit.position.distance_to(cover.position)>.8:result.goal=cover.position;result.state="advance-cover"
	return result

func mark_support(unit: Dictionary,result: Dictionary,world) -> void:
	unit.ai_support_ready=bool(result.hold) and bool(unit.get("ai_fire_clear",false)) and unit.reload<=0 and unit.ammo>0 and float(unit.get("ai_stress",0))<.62 and absf(float(unit.stance_blend)-float(result.stance))<.08
	unit.ai_support_checked_at=world.time

func prepare_bound(unit: Dictionary,goal: Vector2,contact: Dictionary) -> void:
	var world=world_ref.get_ref();var ai=navigation_ref.get_ref()
	var cover=choose_cover(unit,contact,goal,true)
	var endpoint: Vector2=cover.get("position",Vector2.INF);var protected=not cover.is_empty()
	if not endpoint.is_finite():
		# Reuse the unit's existing path instead of issuing a coordinator A* query.
		for p in unit.path:
			if unit.position.distance_to(p)>.7 and unit.position.distance_to(p)<=3.0 and ai.traversable(world,unit.position,p):endpoint=p
	if endpoint.is_finite() and reserve_position(unit.id,endpoint,1.2):unit.ai_bound_candidate=endpoint;unit.ai_bound_candidate_at=world.time;unit.ai_bound_protected=protected
	else:unit.ai_bound_candidate_at=-100.0

static func cover_key(unit: Dictionary,contact: Dictionary,goal: Vector2,advance: bool,revision: int) -> String:
	# Reuse local searches, but not across floors, new lives or a materially
	# different observed weapon. Quantized pose height avoids animation jitter.
	return str(Vector2i(goal))+":"+str(Vector2i(contact.position))+":"+str(advance)+":"+str(revision)+":"+str(int(contact.get("id",-1)))+":"+str(int(contact.get("spawn_epoch",0)))+":"+str(snappedf(float(unit.get("elevation",0)),.25))+":"+str(snappedf(float(contact.get("elevation",0)),.25))+":"+str(snappedf(float(contact.get("muzzle_height",1.33)),.25))+":"+str(snappedf(float(contact.get("head_height",1.7)),.25))+":"+str(float(contact.get("penetration_estimate",75)))

func choose_cover(unit: Dictionary,contact: Dictionary,goal: Vector2,advance: bool) -> Dictionary:
	var world=world_ref.get_ref();var ai=navigation_ref.get_ref()
	var key=cover_key(unit,contact,goal,advance,int(world.topology_revision))
	if unit.get("ai_cover_key","")==key and world.time<float(unit.get("ai_cover_until",0)) and unit.position.distance_to(unit.get("ai_cover_origin",unit.position))<2:return unit.get("ai_cover",{})
	if not take_budget(true):return {}
	var started=Time.get_ticks_usec()
	var search: Dictionary=unit.get("ai_cover_search",{})
	if search.get("key","")!=key or Vector2(search.get("origin",unit.position)).distance_to(unit.position)>2:
		var angle=(goal-unit.position).angle();var samples=[unit.position]
		for radius in [1.5,3.0]:
			for offset in [0.0,-.65,.65,-1.25,1.25]:samples.append(unit.position+Vector2.from_angle(angle+offset)*radius)
		search={"key":key,"origin":unit.position,"samples":samples,"next":0,"best":{},"score":-INF}
	var baseline=unit.position.distance_to(goal);var best: Dictionary=search.best;var score=float(search.score)
	for index in range(int(search.next),search.samples.size()):
		if Time.get_ticks_usec()-started>=650:break
		var point: Vector2=search.samples[index];search.next=index+1
		if not position_available(point,unit.id):continue
		var keep_foothold=false;var preserves_zone=true
		if str(unit.get("ai_task","")) in ["attack","hold"]:
			for objective in world.campaign.points:
				if preload("res://scripts/capture_zone.gd").contains(objective,unit.position,unit.elevation):
					keep_foothold=true;preserves_zone=preload("res://scripts/capture_zone.gd").contains(objective,point,world.terrain.height(point));break
		if keep_foothold and not preserves_zone:continue
		if world.terrain.grade(point)>.75 or world.blocked(point,.31,1.95,-1,world.terrain.height(point)):continue
		if not ai.traversable(world,unit.position,point):continue
		var progress=baseline-point.distance_to(goal)
		if advance and progress<.65:continue
		var elevation=world.terrain.height(point);var threat=Vector3(contact.position.x,float(contact.get("elevation",0))+float(contact.get("muzzle_height",world.CombatPose.MUZZLE_HEIGHT[0])),contact.position.y)
		var standing=world.CombatPose.candidate_head(point,elevation,0);var crouching=world.CombatPose.candidate_head(point,elevation,1)
		var estimate=float(contact.get("penetration_estimate",75))
		var standing_cover=Cover.stopped(world,threat,standing,estimate);var crouch_cover=Cover.stopped(world,threat,crouching,estimate)
		if not crouch_cover:continue
		var crowd=0.0
		for friend in world.nearby_units(point,1.3):
			if friend.alive and friend.team==unit.team and friend.id!=unit.id:crowd+=maxf(0,1.3-friend.position.distance_to(point))
		var value=progress*(1.8 if advance else .25)+(3.2 if standing_cover else 2.3)-point.distance_to(unit.position)*.18-crowd*2.2
		if value>score:score=value;best={"position":point,"elevation":elevation,"standing_cover":standing_cover,"crouch_cover":crouch_cover}
	var complete=int(search.next)>=search.samples.size()
	search.best=best;search.score=score;unit.ai_cover_search=search
	if not best.is_empty() and complete:
		var toward: Vector2=(contact.position-best.position).normalized();var side=toward.orthogonal()
		for sign_value in [1.0,-1.0]:
			var peek: Vector2=best.position+side*sign_value*.9+toward*.15
			if not ai.traversable(world,best.position,peek):continue
			var muzzle=Vector3(peek.x,world.terrain.height(peek)+world.CombatPose.MUZZLE_HEIGHT[0],peek.y)
			var target=Vector3(contact.position.x,float(contact.get("elevation",0))+float(contact.get("head_height",world.CombatPose.HEAD_CENTER[0])),contact.position.y)
			if not obstructed(world,muzzle,target):best.peek=peek;break
	unit.ai_cover_key=key;unit.ai_cover=best;unit.ai_cover_until=world.time+(.05 if not complete else 1.6 if not best.is_empty() else .55);unit.ai_cover_origin=unit.position
	world.ai_budget_usec-=Time.get_ticks_usec()-started
	if complete:unit.erase("ai_cover_search")
	return best

static func obstructed(world,origin: Vector3,target: Vector3) -> bool:
	var line=target-origin
	return not world.trace_3d(origin,line.normalized(),line.length(),{},true).is_empty()

func recover(unit: Dictionary,goal: Vector2) -> Vector2:
	var world=world_ref.get_ref();var ai=navigation_ref.get_ref()
	var search: Dictionary=unit.get("ai_recovery_search",{})
	if search.is_empty() or Vector2(search.origin).distance_squared_to(unit.position)>.0625 or Vector2(search.goal).distance_squared_to(goal)>.25 or search.revision!=world.topology_revision:
		search={"origin":unit.position,"goal":goal,"revision":world.topology_revision,"facing":(goal-unit.position).angle(),"next":0,"best":unit.position,"score":-INF}
	unit.ai_recovery_search=search
	if not take_budget(false):return unit.position
	var started=Time.get_ticks_usec();var budget=mini(650,int(world.ai_budget_usec))
	while int(search.next)<16 and Time.get_ticks_usec()-started<budget:
		var index=int(search.next);search.next=index+1
		var radius=.8 if index<8 else 1.5;var offset=float([0.0,.7,-.7,1.4,-1.4,2.1,-2.1,PI][index%8])
		var point: Vector2=search.origin+Vector2.from_angle(search.facing+offset)*radius
		if not ai.traversable(world,unit.position,point):continue
		var node=ai.graph.get_closest_point(point)
		if node<0:continue
		var connected: Vector2=ai.graph.get_point_position(node)
		if connected.distance_to(point)>1.5 or not ai.traversable(world,point,connected):continue
		var crowd=0.0
		for friend in world.nearby_units(point,1.0):
			if friend.alive and friend.id!=unit.id:crowd+=maxf(0,1.0-friend.position.distance_to(point))
		var value=unit.position.distance_to(goal)-point.distance_to(goal)-crowd*2-absf(offset)*.14
		if value>float(search.score):search.best=point;search.score=value
	world.ai_budget_usec-=Time.get_ticks_usec()-started
	if int(search.next)<16:return unit.position
	unit.erase("ai_recovery_search")
	return search.best if ai.traversable(world,unit.position,search.best) else unit.position

func steer(unit: Dictionary,velocity: Vector2) -> Vector2:
	var world=world_ref.get_ref();var separation:=Vector2.ZERO;var forward:=velocity.normalized();var side:=forward.orthogonal()
	var position: Vector2=unit.position;var id: int=unit.id
	var boarding=int(world.campaign_ai.vehicle_ai.reservations.get(unit.id,{}).get("vehicle",-1))
	for v in world.vehicles:
		if v.id==boarding or v.emplacement or v.destroyed or not v.get("ai_controlled",false):continue
		var towards: Vector2=v.position-position;var along=towards.dot(forward)
		var radius: float=v.dimensions.half.length()+.75
		if along>0 and along<radius+1.2 and absf(towards.dot(side))<v.dimensions.half.y+.7:
			separation+=side*(-1.0 if towards.dot(side)>0 else 1.0)*1.6
	for other: Dictionary in world.nearby_units(position,1.6):
		if not other.alive or other.id==id or other.mounted>=0:continue
		var away: Vector2=position-Vector2(other.position);var distance: float=away.length()
		if distance<.72 and distance>.001:separation+=away/distance*(.72-distance)*3.0
		var ahead: float=(-away).dot(forward)
		if ahead>.1 and ahead<1.5 and absf(away.dot(side))<.55:
			# Opposite traffic uses deterministic right-hand passing, avoiding coin flips.
			separation+=side*(1-ahead/1.5)*.8
	return velocity+separation.limit_length(.95)
