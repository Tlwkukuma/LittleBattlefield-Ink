extends RefCounted
## Local sensing only: a contact stores an observed position, never a live actor reference.
## Vision families follow campaignPerception.generated.js, converted from 40 units/m.
var world_ref: WeakRef
var sound_cells: Dictionary={}
const MAX_VISUAL_CANDIDATES=4
const MAX_HEARING_RAYS=4
var hearing_frame: int=-1
var hearing_rays: int=0
var hearing_cache: Dictionary={}
var hearing_revision: int=-1
var structure_frame=-1

func configure(world) -> void:world_ref=weakref(world)

static func ensure(unit: Dictionary) -> void:
	if not unit.has("ai_contacts"):unit.ai_contacts={}
	if not unit.has("ai_hearing_contacts"):unit.ai_hearing_contacts={}
	if not unit.has("ai_visible_ids"):unit.ai_visible_ids=[]
	if not unit.has("ai_stress"):unit.ai_stress=0.0

static func profile(weapon: Dictionary) -> Dictionary:
	var family=str(weapon.get("archetype","assault"));var range_m=19.3125;var half_angle=.82;var memory=1.9
	match family:
		"sniper":range_m=41.25;half_angle=.26;memory=2.7
		"antimaterial":range_m=47.8125;half_angle=.22;memory=3.0
		"mortar":range_m=28.125;half_angle=.48;memory=2.1
		"rifle","boltRifle","battleRifle":range_m=23.4375;half_angle=.69;memory=2.1
		"lmg","hmg","minigun":range_m=21.0;half_angle=.72;memory=2.0
		"smg","machinePistol":range_m=14.625;half_angle=.96;memory=1.65
		"shotgun","autoShotgun":range_m=12.1875;half_angle=1.04;memory=1.5
		"rocket","grenadeLauncher":range_m=22.125;half_angle=.64;memory=2.0
		"melee":range_m=9.0;half_angle=1.10;memory=1.35
	return {"range":range_m,"half_angle":half_angle,"memory":memory}

func tick(unit: Dictionary,delta: float) -> void:
	ensure(unit);unit.ai_stress=maxf(0,float(unit.ai_stress)-delta*.16)
	var now=float(world_ref.get_ref().time)
	# Stress responds every AI step; fading remembered contacts needs only 5 Hz.
	if now<float(unit.get("ai_contacts_decay_at",-1)):return
	unit.ai_contacts_decay_at=now+.18+float(unit.id%7)*.008
	for contacts in [unit.ai_contacts,unit.ai_hearing_contacts]:
		for id in contacts.keys():
			var contact: Dictionary=contacts[id]
			var life=6.0 if contact.source=="vision" else 2.8
			var age=now-float(contact.observed_at)
			if age>=life:contacts.erase(id);continue
			contact.confidence=maxf(0,float(contact.get("initial_confidence",1.0))*(1-age/life))

func can_see(unit: Dictionary,target: Dictionary) -> bool:
	var world=world_ref.get_ref()
	if not target.alive or target.team==unit.team:return false
	var rules=profile(world.weapon_for(unit));var offset: Vector2=target.position-unit.position;var distance=offset.length()
	if distance>rules.range+.3:return false
	var allowance=minf(.13,.30/maxf(1.5,distance))
	if absf(wrapf(offset.angle()-unit.facing.angle(),-PI,PI))>rules.half_angle+allowance:return false
	var eye=world.CombatPose.eye(unit)
	# One cached silhouette point for visibility only. It is never the firing aim.
	var head: Vector3=world.CombatPose.head_target(target)
	if world.enclosed(target):head=Vector3(target.position.x,target.elevation+1.1,target.position.y)
	var ray=head-eye
	if world.profile_ai:world.campaign_ai.step_profile.vision_rays=int(world.campaign_ai.step_profile.get("vision_rays",0))+1
	var hit=world.trace_3d(eye,ray.normalized(),ray.length(),{"source":unit.id,"team":unit.team},true)
	return hit.is_empty() or (world.enclosed(target) and hit.type=="vehicle" and hit.target.id==target.mounted)

func confirm(unit: Dictionary,target_id: int) -> Dictionary:
	ensure(unit);var world=world_ref.get_ref()
	if target_id<0 or target_id>=world.units.size():return {}
	var target: Dictionary=world.units[target_id]
	if not can_see(unit,target):
		unit.ai_visible_ids.erase(target_id)
		return {}
	remember_vision(unit,target)
	return target

func refresh(unit: Dictionary) -> Dictionary:
	ensure(unit);var world=world_ref.get_ref();var rules=profile(world.weapon_for(unit))
	unit.ai_visible_ids=[]
	var candidates=[]
	for target in world.units:
		if not target.alive or target.team==unit.team:continue
		var offset: Vector2=target.position-unit.position;var distance=offset.length()
		if distance>rules.range+.3 or absf(wrapf(offset.angle()-unit.facing.angle(),-PI,PI))>rules.half_angle+.13:continue
		candidates.append({"unit":target,"distance":distance})
	candidates.sort_custom(func(a,b):return a.distance<b.distance)
	var chosen: Dictionary={};var score=INF
	var cursor=int(unit.get("ai_scan_cursor",0))
	var selected_indices=scan_indices(candidates,int(unit.get("ai_target",-1)),cursor)
	if observe_structure(unit,rules) and selected_indices.size()>=MAX_VISUAL_CANDIDATES:selected_indices.pop_back()
	unit.ai_scan_cursor=posmod(cursor+1,maxi(1,candidates.size()-2))
	for index in selected_indices:
		var target: Dictionary=candidates[index].unit
		if not can_see(unit,target):continue
		remember_vision(unit,target)
		var candidate=float(candidates[index].distance)
		if int(unit.get("ai_target",-1))==target.id:candidate-=2.0
		for point in world.campaign.points:
			if target.position.distance_squared_to(point.position)<point.radius*point.radius:candidate-=1.5;break
		if candidate<score:score=candidate;chosen=target
	return chosen

func observe_structure(unit: Dictionary,rules: Dictionary) -> bool:
	var world=world_ref.get_ref();var probe: Dictionary=unit.get("ai_structure_probe",{})
	if probe.is_empty() or world.time-float(probe.at)>10 or structure_frame==Engine.get_physics_frames():return false
	var offset: Vector2=probe.position-unit.position
	if offset.length_squared()>12*12 or absf(wrapf(offset.angle()-unit.facing.angle(),-PI,PI))>float(rules.half_angle)+.13:return false
	structure_frame=Engine.get_physics_frames()
	var target=Vector3(probe.position.x,world.terrain.height(probe.position)+.9,probe.position.y)
	var line=target-world.CombatPose.eye(unit)
	var hit=world.trace_3d(world.CombatPose.eye(unit),line.normalized(),line.length(),{},true)
	if not hit.is_empty():return true
	var half=float(probe.wall.size.y)*.5+.65;var normal=Vector2.from_angle(probe.wall.angle).orthogonal()
	if world.campaign_ai.traversable(world,probe.position-normal*half,probe.position+normal*half):
		unit.ai_breach_observed={"position":probe.position,"observed_at":world.time,"wall_id":probe.wall.id,"revision":world.topology_revision,"source":"vision"}
	return true

static func scan_indices(candidates: Array,current_id: int,cursor: int) -> Array:
	var selected_indices=[]
	# Keep the current threat and two nearest candidates; rotate the remaining
	# slots so nearer wall-hidden units cannot permanently mask a visible flank.
	for index in range(candidates.size()):
		if int(candidates[index].unit.id)==current_id:selected_indices.append(index);break
	for index in range(mini(2,candidates.size())):
		if index not in selected_indices:selected_indices.append(index)
	var remaining=maxi(0,candidates.size()-2)
	for index in range(remaining):
		if selected_indices.size()>=MAX_VISUAL_CANDIDATES:break
		var candidate_index=2+posmod(cursor+index,remaining)
		if candidate_index not in selected_indices:selected_indices.append(candidate_index)
	return selected_indices

func remember_vision(unit: Dictionary,target: Dictionary) -> void:
	var world=world_ref.get_ref()
	unit.ai_contacts[target.id]={"id":int(target.id),"position":target.position,"elevation":float(target.elevation),"observed_at":world.time,"confidence":1.0,"initial_confidence":1.0,"source":"vision","stance":target.stance}
	unit.ai_contacts[target.id].spawn_epoch=int(target.get("spawn_epoch",0))
	unit.ai_contacts[target.id].muzzle_height=world.CombatPose.muzzle(target).y-target.elevation
	unit.ai_contacts[target.id].head_height=world.CombatPose.head_target(target).y-target.elevation
	var family=str(world.weapon_for(target).get("archetype","assault"))
	unit.ai_contacts[target.id].penetration_estimate=100.0 if family in ["hmg","minigun","antimaterial"] else 75.0 if family in ["sniper","boltRifle"] else 42.0
	if target.id not in unit.ai_visible_ids:unit.ai_visible_ids.append(target.id)
	unit.ai_memory_at=target.position;unit.ai_memory_until=world.time+float(profile(world.weapon_for(unit)).memory)

func best_contact(unit: Dictionary) -> Dictionary:
	ensure(unit);var best: Dictionary={};var score=-INF
	var now=float(world_ref.get_ref().time)
	for contacts in [unit.ai_contacts,unit.ai_hearing_contacts]:
		for id in contacts:
			var candidate: Dictionary=contacts[id]
			if now-float(candidate.observed_at)>=(6.0 if candidate.source=="vision" else 2.8):continue
			# A sound from the same source must neither replace nor outrank an
			# unexpired visual observation. Its uncertainty remains independent.
			if candidate.source=="hearing" and unit.ai_contacts.has(id) and now-float(unit.ai_contacts[id].observed_at)<6.0:continue
			var value=float(candidate.confidence)*4-unit.position.distance_to(candidate.position)*.04+(1.0 if candidate.source=="vision" else 0.0)
			if value>score:
				score=value;best=candidate.duplicate();best.id=id

	return best

func observe_event(event: Dictionary) -> void:
	var world=world_ref.get_ref();var kind=str(event.get("type",""))
	if kind=="fracture" and str(event.object.get("source_id","")).begins_with("compound-"):
		for unit in world.nearby_units(event.position,12):
			if not unit.alive or unit.player or unit.team!=1 or unit.mounted>=0:continue
			unit.ai_structure_probe={"position":event.position,"wall":event.object,"at":world.time}
			unit.ai_alert_at=Vector2((Vector2(event.position)/2).round())*2;unit.ai_alert_until=world.time+1.5
		return
	if kind=="respawn":
		var unit: Dictionary=event.unit
		for field in unit.keys():
			if str(field).begins_with("ai_") and field not in ["ai_order"]:unit.erase(field)
		ensure(unit);return
	if kind=="damage":
		var unit: Dictionary=event.unit
		if unit.player or not unit.alive:return
		ensure(unit);unit.ai_stress=clampf(float(unit.ai_stress)+.22+float(event.get("amount",0))/maxf(1,unit.max_health)*.75,0,1)
		unit.ai_incoming_at=world.time
		var incoming: Vector3=event.get("incoming",Vector3.ZERO)
		if Vector2(incoming.x,incoming.z).length_squared()>.01:
			unit.ai_alert_at=unit.position-Vector2(incoming.x,incoming.z).normalized()*7
			unit.ai_alert_until=world.time+1.4
		return
	if kind=="explosion":
		var at: Vector2=event.position;var radius=float(event.radius)
		for unit in world.units:
			if not unit.alive or unit.player:continue
			var distance=unit.position.distance_to(at)
			if distance>radius*1.8:continue
			ensure(unit);unit.ai_stress=minf(1,float(unit.ai_stress)+.40*clampf(1-distance/(radius*1.8),0,1))
		emit_sound(at,float(event.get("height",0)),int(event.get("team",-1)),int(event.get("source_id",-1)),minf(55,25+radius*4),.8)
		return
	if kind!="shot":return
	var shooter: Dictionary=event.unit;var weapon: Dictionary=event.weapon
	if weapon.kind=="melee":return
	var at: Vector2=event.position;var cell=Vector2i(at/4)
	var key=str(shooter.team)+":"+str(cell)
	if world.time-float(sound_cells.get(key,-100))<.20:return
	sound_cells[key]=world.time
	if sound_cells.size()>180:
		for old in sound_cells.keys():
			if world.time-float(sound_cells[old])>3:sound_cells.erase(old)
	var family=str(weapon.get("archetype","assault"));var radius=31.25
	if family in ["sniper","antimaterial"]:radius=51.25
	elif family in ["lmg","hmg","minigun"]:radius=37.5
	elif family in ["smg","machinePistol"]:radius=24.5
	elif family=="pistol":radius=20.5
	if bool(world.WeaponProfile.get_profile(weapon).suppressed):radius*=.48
	emit_sound(at,float(event.get("height",shooter.elevation+1.3)),int(shooter.team),int(shooter.id),radius,.65)

func near_segment(projectile: Dictionary,start: Vector3,end: Vector3) -> void:
	var world=world_ref.get_ref()
	if start.distance_squared_to(end)<.000001:return
	var source=int(projectile.get("source",-1));var token=str(source)+":"+str(projectile.get("source_epoch",0))
	var family=str(projectile.weapon.get("archetype","assault"))
	# The existing physical unit index provides a narrow candidate corridor.
	for u in world.unit_ray_candidates(Vector2(start.x,start.z),Vector2(end.x,end.z),1.5):
		if not u.alive or u.player or u.team==projectile.team or world.enclosed(u):continue
		var body=world.CombatPose.chest(u);var nearest=Geometry3D.get_closest_point_to_segment(body,start,end)
		var distance=body.distance_to(nearest)
		if distance>=1.5:continue
		ensure(u)
		if not u.has("ai_pressure_clocks"):u.ai_pressure_clocks={}
		if world.time<float(u.ai_pressure_clocks.get(token,-100))+.12:continue
		if u.ai_pressure_clocks.size()>=16:
			for key in u.ai_pressure_clocks.keys():
				if world.time-float(u.ai_pressure_clocks[key])>1:u.ai_pressure_clocks.erase(key)
			if u.ai_pressure_clocks.size()>=16:u.ai_pressure_clocks.erase(u.ai_pressure_clocks.keys()[0])
		u.ai_pressure_clocks[token]=world.time;u.ai_incoming_at=world.time
		u.ai_stress=minf(1,float(u.ai_stress)+(.09 if family in ["lmg","hmg","minigun"] else .055)*(1-distance/1.5))
		var direction=Vector2(end.x-start.x,end.z-start.z).normalized()
		u.ai_alert_at=u.position-direction*7;u.ai_alert_until=world.time+1.2

func emit_sound(at: Vector2,height: float,team: int,source_id: int,radius: float,loudness: float) -> void:
	var world=world_ref.get_ref();var transmission_cache={};var listeners=[]
	for unit in world.units:
		if not unit.alive or unit.player or unit.team==team or world.enclosed(unit):continue
		var distance=unit.position.distance_to(at)
		if distance<radius:listeners.append({"unit":unit,"distance":distance})
	listeners.sort_custom(func(a,b):return a.distance<b.distance)
	for index in range(mini(18,listeners.size())):
		var unit: Dictionary=listeners[index].unit;var distance=float(listeners[index].distance);var cell=Vector2i(unit.position/4)
		if not transmission_cache.has(cell):
			var origin=Vector3(at.x,height,at.y);var endpoint=Vector3(unit.position.x,unit.elevation+1.3,unit.position.y);var line=endpoint-origin
			transmission_cache[cell]=hearing_transmission(world,origin,endpoint)
		var transmission=float(transmission_cache[cell]);var strength=loudness*pow(maxf(0,1-distance/radius),.72)*transmission
		if strength<.075:continue
		ensure(unit)
		var key=source_id if source_id>=0 else -1000-int(unit.id)
		var error=1.1+distance*.08+(1-strength)*2.0+(1-transmission)*3.0
		var estimate=at+Vector2.from_angle(world.rng.randf()*TAU)*error*world.rng.randf_range(.3,1)
		estimate.x=clampf(estimate.x,-world.bounds.x+.5,world.bounds.x-.5);estimate.y=clampf(estimate.y,-world.bounds.y+.5,world.bounds.y-.5)
		var confidence=clampf(.16+strength*.32,.15,.45)
		unit.ai_hearing_contacts[key]={"position":estimate,"elevation":world.terrain.height(estimate),"observed_at":world.time,"confidence":confidence,"initial_confidence":confidence,"source":"hearing","uncertainty":error}
		unit.ai_alert_at=estimate;unit.ai_alert_until=world.time+1.3

func hearing_transmission(world,origin: Vector3,endpoint: Vector3) -> float:
	# Hearing is deliberately an imprecise sector estimate. It must not perform
	# a fresh accurate wall query for every listener in a simultaneous volley.
	# Real visibility, projectile collision and damage never use this cache.
	var frame: int=Engine.get_process_frames()
	if frame!=hearing_frame:hearing_frame=frame;hearing_rays=0
	if hearing_revision!=world.topology_revision:
		hearing_cache.clear();hearing_revision=world.topology_revision
	var key=Vector4i(floori(origin.x/4),floori(origin.z/4),floori(endpoint.x/4),floori(endpoint.z/4))
	var old: Dictionary=hearing_cache.get(key,{})
	if not old.is_empty() and world.time<old.until and absf(origin.y-old.height)<1 and absf(endpoint.y-old.target_height)<1:return old.value
	# Quiet conservative hearing under load; never turn hearing into clear sight.
	if hearing_rays>=MAX_HEARING_RAYS:return .40
	hearing_rays+=1
	var line=endpoint-origin
	var hit=world.trace_3d(origin,line.normalized(),line.length(),{},true)
	var transmission=.40 if not hit.is_empty() else 1.0
	if hearing_cache.size()>=256:hearing_cache.clear()
	hearing_cache[key]={"until":world.time+.30,"height":origin.y,"target_height":endpoint.y,"value":transmission}
	if world.profile_ai:world.campaign_ai.step_profile.hearing_rays=int(world.campaign_ai.step_profile.get("hearing_rays",0))+1
	return transmission
