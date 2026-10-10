extends RefCounted
## Finite forces and signed control-point progress, independent of presentation.
var active=false
var phase="playing"
var points: Array=[]
var reserves: Array=[0,0]
var maximum: Array=[30,30]
var deployed: Array=[0,0]
var casualties: Array=[0,0]
var replacement_cursor: Array=[0,0]
var recruit_anchors: Array=[{},{}]
var wave_clock=0.0
var takeover_wait=0.0
var reason=""
var rules: Dictionary={}
var world_ref: WeakRef
var stage_index=0
var hold_elapsed=0.0
var mission: Dictionary={}

func configure(world) -> void:
	world_ref=weakref(world);active=true;phase="playing";rules=world.plan.get("campaignRules",{})
	stage_index=0;hold_elapsed=0.0;mission=world.plan.get("campaignMission",{})
	build_points(world)
	for team in range(2):
		var key="blue" if team==0 else "red";var deployment: Dictionary=world.plan.deployment[key]
		maximum[team]=maxi(1,int(deployment.get("maxActive",30)))
		var count=mini(maximum[team],int(deployment.get("initialCount",30)))
		var specs: Array=world.plan.get("units",{}).get(key,[])
		for slot in range(count):
			var controlled=team==0 and slot==0
			var spec: Dictionary=world.plan.deployment.player if controlled else specs[(slot-1 if team==0 else slot)%maxi(1,specs.size())] if not specs.is_empty() else deployment.spawnPoints[slot%deployment.spawnPoints.size()]
			var at=world.catalog.position(spec,world.plan)
			at=clear_position(world,at,team,false)
			var unit=world.add_unit(at,controlled);unit.team=team;unit.campaign_slot=slot;unit.campaign_source=spec.duplicate(true)
			unit.spawn_epoch=0;unit.recruit_cohort=-1;unit.recruit_at=0.0
			if controlled:world.player=unit
			apply_loadout(world,unit,spec.get("loadout",["M416","P92","Army Knife","HE Grenade"]))
			unit.facing=Vector2.from_angle(float(spec.get("angle",0))) if int(world.plan.get("godot3d",{}).get("campaign_chapter",1))>1 else Vector2(0,-1) if team==0 else Vector2(0,1)
			unit.guard_until=3.0+float(slot%5)*.65 if team==1 else 0.0
			deployed[team]+=1
		reserves[team]=maxi(0,int(deployment.get("totalForce",120))-deployed[team])

func build_points(world) -> void:
	points.clear()
	for source in world.plan.get("controlPoints",[]):
		var owner_name=str(source.get("initialOwner","neutral"))
		var value=1.0 if owner_name=="blue" else -1.0 if owner_name=="red" else 0.0
		var at: Vector2=world.catalog.position(source,world.plan);var zone=PackedVector2Array()
		for p in source.get("capturePolygon",[]):zone.append(world.catalog.position(p,world.plan))
		points.append({"id":source.get("id","flag"),"label":source.get("shortLabel",source.get("label","B")),"position":world.catalog.position(source,world.plan),
			"name":source.get("label","果园"),"visual_position":world.catalog.position(source.get("visualPosition",source),world.plan),"zone":zone,"elevation":world.terrain.height(at),"capture_height":float(source.get("captureHeight",1.8)),
			"radius":float(source.get("r",180))/40.0,"progress":value,"owner":0 if value>0 else 1 if value<0 else -1,"contested":false,"blue":0,"red":0,
			"capture_time":maxf(3,float(source.get("captureTime",rules.get("captureTime",7))))})

static func weapon_id(world,value) -> String:
	var name=str(value)
	if world.catalog.weapons.has(name):return name
	for id in world.catalog.weapons:
		if str(world.catalog.weapons[id].name)==name:return str(id)
	return ""

static func apply_loadout(world,unit: Dictionary,source: Array) -> void:
	unit.loadout=[];unit.inventory={}
	for value in source:
		var id=weapon_id(world,value)
		if not id.is_empty() and id not in unit.loadout:unit.loadout.append(id)
	if unit.loadout.is_empty():unit.loadout=["m416","p92","army-knife","he-grenade"]
	unit.weapon_id=unit.loadout[0]
	preload("res://scripts/quick_equipment.gd").initialize(unit,world.catalog.weapons,unit.loadout)
	var weapon: Dictionary=world.weapon_for(unit)
	unit.ammo=int(weapon.mag);unit.reserve=int(weapon.reserve);unit.reload=0.0;unit.cooldown=0.0
	unit.class_id="support" if weapon.kind in ["machinegun","lmg"] or unit.weapon_id in ["m249","mg3","rpd"] else "recon" if unit.weapon_id in ["dragunov","kar98k","m24","awm","sks"] else "engineer" if "portable-mortar" in unit.loadout else "medic" if int(unit.id)%5==1 else "assault"
	world.Handling.reset(unit);world.FireControl.reset(unit,weapon);world.FireControl.cancel(unit,true)

func active_counts() -> Array:
	var counts=[0,0];var world=world_ref.get_ref()
	if world==null:return counts
	for unit in world.units:
		if unit.alive:counts[int(unit.team)]+=1
	return counts

func summary() -> Dictionary:
	return {"active":active,"phase":phase,"points":points,"reserves":reserves.duplicate(),"counts":active_counts(),"deployed":deployed.duplicate(),"casualties":casualties.duplicate(),"takeover_wait":takeover_wait,"reason":reason,"stage_index":stage_index,"stage_count":maxi(1,mission.get("stages",[]).size()),"hold_elapsed":hold_elapsed}

func tick(delta: float) -> void:
	if not active or phase!="playing":return
	var world=world_ref.get_ref()
	# A dead player must have an already-living ally. Reserves cannot rescue this state.
	if not world.player.alive:
		var ally=nearest_ally(world)
		if ally.is_empty():
			# A living LAN teammate can still finish the campaign even when the
			# host has no unoccupied soldier left to take over.
			if not world.units.any(func(unit):return unit.alive and unit.team==0 and int(unit.get("network_peer_id",0))>0):finish("lost","无可接管的存活友军");return
			takeover_wait=0.0
		else:
			takeover_wait=maxf(0,float(rules.get("handoffSeconds",1.18))-float(world.player.death_age))
			if takeover_wait<=0:
				var previous: Dictionary=world.player;previous.player=false;ally.player=true;world.player=ally
				ally.velocity=Vector2.ZERO;ally.requested_velocity=Vector2.ZERO;ally.aim_valid=false;ally.aiming=false
				ally.path=[];world.cancel_firing()
				world.event.emit({"type":"player_changed","unit":ally,"previous":previous})
				world.event.emit({"type":"notice","text":"已接管最近友军 · 装备沿用该士兵配装"})
	else:takeover_wait=0.0
	for point in points:
		var presence=[0,0]
		for unit in world.units:
			if unit.alive and preload("res://scripts/capture_zone.gd").contains(point,unit.position,unit.elevation):presence[unit.team]+=1
		advance_point(point,presence[0],presence[1],delta)
	if not mission.is_empty():
		if advance_mission(world,delta):return
	elif not points.is_empty() and points.all(func(point):return point.owner==0):finish("won","已占领全部据点");return
	var counts=active_counts()
	if counts[1]==0 and reserves[1]==0:finish("won","敌军兵力已耗尽");return
	wave_clock+=delta
	if wave_clock<float(rules.get("replacementWaveSeconds",.5)):return
	wave_clock=fmod(wave_clock,maxf(.1,float(rules.get("replacementWaveSeconds",.5))))
	for team in range(2):reinforce(world,team,mini(int(rules.get("replacementWaveSize",5)),maximum[team]-counts[team]))

func current_stage() -> Dictionary:
	var stages: Array=mission.get("stages",[])
	return stages[stage_index] if stage_index>=0 and stage_index<stages.size() else {}

func objective_text() -> String:
	var stage=current_stage()
	if stage.is_empty():return "占领据点，或耗尽敌方兵力"
	var text=str(stage.get("briefing","夺取目标"))
	if str(stage.get("mode","capture"))=="hold":text+=" · %d / %d 秒"%[int(hold_elapsed),int(stage.get("holdSeconds",0))]
	return "%d/%d · %s"%[stage_index+1,mission.stages.size(),text]

func advance_mission(world,delta: float) -> bool:
	var stage=current_stage()
	if stage.is_empty() or points.is_empty():return false
	var secured=points[0].owner==0 and not points[0].contested
	if str(stage.get("mode","capture"))=="hold":
		if secured:hold_elapsed+=delta
		elif points[0].owner==1:hold_elapsed=0.0
		if not secured or hold_elapsed<float(stage.get("holdSeconds",20)):return false
	elif not secured:return false
	var stages: Array=mission.stages
	if stage_index+1>=stages.size():finish("won","全部阶段目标已完成");return true
	stage_index+=1;hold_elapsed=0.0
	preload("res://scripts/campaign_catalog.gd").apply_stage(world.plan,stage_index)
	build_points(world)
	# Public objective relocation invalidates goal caches and orders, not perceptions.
	world.campaign_ai.routes=[[],[]]
	for team in range(2):
		for raw_route in world.plan.godot3d.aiRoutes.get("blue" if team==0 else "red",[]):
			var route=[]
			for point in raw_route:route.append(world.catalog.position(point,world.plan))
			world.campaign_ai.routes[team].append(route)
	world.campaign_ai.refresh_capture_cells()
	world.campaign_ai.vehicle_ai.objective_changed()
	world.campaign_director.objective_changed()
	world.event.emit({"type":"campaign_stage_changed","stage":stage_index,"objective":objective_text()})
	world.event.emit({"type":"notice","text":"阶段完成 · "+objective_text()})
	return false

static func advance_point(point: Dictionary,blue: int,red: int,delta: float) -> void:
	var step=delta/float(point.capture_time)
	if blue>0 and red==0:point.progress=minf(1,point.progress+step*(1.18 if blue>=2 else 1.0))
	elif red>0 and blue==0:point.progress=maxf(-1,point.progress-step*(1.18 if red>=2 else 1.0))
	elif blue>0 and red>0:
		var imbalance=float(absi(blue-red))/float(blue+red)
		point.progress=move_toward(point.progress,0,step*(.48+.32*(1-imbalance)))
	point.blue=blue;point.red=red;point.contested=blue>0 and red>0
	point.owner=0 if point.progress>=.999 else 1 if point.progress<=-.999 else -1

func nearest_ally(world) -> Dictionary:
	var nearest: Dictionary={};var distance=INF
	for unit in world.units:
		if not unit.alive or unit.team!=0 or unit.player or int(unit.get("network_peer_id",0))>0:continue
		var candidate=world.player.position.distance_squared_to(unit.position)
		if candidate<distance:distance=candidate;nearest=unit
	return nearest

func reinforce(world,team: int,budget: int,allow_join_reinforcement: bool=false) -> Dictionary:
	if (reserves[team]<=0 and not allow_join_reinforcement) or budget<=0:return {}
	var key="blue" if team==0 else "red";var deployment: Dictionary=world.plan.deployment[key]
	var first_reinforced: Dictionary={}
	for unit in world.units:
		if budget<=0 or (reserves[team]<=0 and not allow_join_reinforcement):break
		if unit.team!=team or unit.alive or unit.player or int(unit.get("network_peer_id",0))>0 or float(unit.death_age)<.5:continue
		var at=spawn_position(world,team,deployment)
		if not at.is_finite() and allow_join_reinforcement:
			var anchor=world.player.position
			for ally in world.units:
				if ally.alive and ally.team==team:anchor=ally.position;break
			at=clear_position(world,anchor+Vector2.RIGHT*2.0,team,true)
		if not at.is_finite():continue
		unit.spawn_epoch=int(unit.get("spawn_epoch",0))+1
		unit.erase("deployed_mortar")
		unit.recruit_cohort=preload("res://scripts/campaign_roster.gd").cohort(int(replacement_cursor[team]))
		unit.recruit_at=world.time;unit.cohort_route=int(recruit_anchors[team].get("route",0))
		unit.erase("squad_id")
		var sequence: Array=deployment.get("replacementLoadouts",[])
		var loadout: Array=sequence[int(replacement_cursor[team])%sequence.size()] if not sequence.is_empty() else unit.campaign_source.get("loadout",["M416","P92","Army Knife","HE Grenade"])
		unit.position=at;unit.spawn=at;unit.velocity=Vector2.ZERO;unit.requested_velocity=Vector2.ZERO;unit.health=unit.max_health;unit.alive=true;unit.death_age=0.0
		unit.helmet_lost=false;unit.stance=0;unit.stance_blend=0.0;unit.mounted=-1;unit.flash=0.0;unit.hurt=0.0;unit.path=[];unit.repath=0.0;unit.brain=world.rng.randf()*.4
		unit.ai_target=-1;unit.erase("ai_route_index");unit.ai_route_done=false;unit.ai_stuck=0.0;unit.guard_until=0.0;unit.aim_valid=false;unit.aiming=false
		unit.reaction={};unit.last_impact={};unit.hit_shapes=[];unit.death_velocity=Vector3.ZERO;unit.death_position=Vector3.ZERO
		world.Traversal.reset(unit);unit.elevation=world.terrain.height(at);world.ThrowControl.cancel(unit)
		apply_loadout(world,unit,loadout)
		if reserves[team]>0:reserves[team]-=1
		deployed[team]+=1;replacement_cursor[team]+=1;budget-=1
		if first_reinforced.is_empty():first_reinforced=unit
		world.event.emit({"type":"respawn","unit":unit})
	return first_reinforced

func spawn_position(world,team: int,deployment: Dictionary) -> Vector2:
	var spawns: Array=deployment.get("spawnPoints",[])
	if spawns.is_empty():return Vector2.INF
	var cohort=preload("res://scripts/campaign_roster.gd").cohort(int(replacement_cursor[team]))
	var batch: Dictionary=recruit_anchors[team]
	if int(batch.get("id",-1))==cohort:
		var neighbor=clear_position(world,batch.anchor,team,true)
		if spawn_valid(world,team,neighbor):return neighbor
	for i in range(spawns.size()):
		var index=(i+cohort)%spawns.size()
		var at=clear_position(world,world.catalog.position(spawns[index],world.plan),team,true)
		if not spawn_valid(world,team,at):continue
		var route=0;var distance=INF
		for r in range(world.campaign_ai.routes[team].size()):
			var path: Array=world.campaign_ai.routes[team][r]
			if path.is_empty():continue
			var d: float=at.distance_squared_to(path[0])
			if d<distance:distance=d;route=r
		recruit_anchors[team]={"id":cohort,"anchor":at,"route":route}
		return at
	return Vector2.INF

static func spawn_valid(world,team: int,at: Vector2) -> bool:
	if not at.is_finite() or not world.campaign_ai.capture_goal(at).is_finite():return false
	# Spawn protection alone may use authority state; no hidden coordinates enter orders.
	for enemy in world.units:
		if enemy.alive and enemy.team!=team and at.distance_squared_to(enemy.position)<36:return false
	return true

static func clear_position(world,origin: Vector2,_team: int,strict: bool) -> Vector2:
	for attempt in range(49):
		var radius=0.0 if attempt==0 else .72*(1+int((attempt-1)/12))
		var at=origin+Vector2.from_angle(float(attempt%12)*TAU/12)*radius
		var base=world.terrain.height(at)
		if world.terrain.grade(at)>.75 or world.blocked(at,.31,1.95,-1,base):continue
		var occupied=false
		for other in world.units:
			if other.alive and at.distance_squared_to(other.position)<.72*.72:occupied=true;break
		if not occupied:return at
	return Vector2.INF if strict else origin

func finish(result: String,description: String) -> void:
	if phase!="playing":return
	phase=result;reason=description
	var world=world_ref.get_ref();world.cancel_firing()
	for unit in world.units:unit.velocity=Vector2.ZERO;unit.requested_velocity=Vector2.ZERO;world.FireControl.cancel(unit,true)
	world.event.emit({"type":"campaign_finished","phase":phase,"reason":reason,"summary":summary()})
