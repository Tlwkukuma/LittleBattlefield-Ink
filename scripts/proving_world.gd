extends RefCounted
## Data-driven planar simulation with height-aware shots and local wall destruction.
const Traversal=preload("res://scripts/soldier_traversal.gd")
const WeaponProfile=preload("res://scripts/weapon_profile.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const FireControl=preload("res://scripts/weapon_fire_control.gd")
const VehicleRenderMotion=preload("res://scripts/vehicle_render_motion.gd")
const Equipment=preload("res://scripts/quick_equipment.gd")
const Grenade=preload("res://scripts/grenade_ballistics.gd")
const ThrowControl=preload("res://scripts/grenade_throw_control.gd")
const CampaignRules=preload("res://scripts/campaign_rules.gd")
const CampaignAI=preload("res://scripts/campaign_ai.gd")
const CampaignDirector=preload("res://scripts/campaign_director.gd")
var campaign=CampaignRules.new()
var campaign_ai=CampaignAI.new()
var campaign_director=CampaignDirector.new()
const Melee=preload("res://scripts/melee_action.gd")
const Reaction=preload("res://scripts/combat_reaction.gd")
const AimGeometry=preload("res://scripts/aim_geometry.gd")
const CombatPose=preload("res://scripts/combat_pose.gd")
const CoverRules=preload("res://scripts/cover_rules.gd")
const Penetration=preload("res://scripts/cover_penetration.gd")
const HouseGeometry=preload("res://scripts/house_geometry.gd")
const NatureGeometry=preload("res://scripts/nature_geometry.gd")
const HouseSupport=preload("res://scripts/house_structure.gd")
var housing_support=HouseSupport.new()
var houses: Array=[]
const TerrainStructure=preload("res://scripts/terrain_structure.gd")
const VehicleDimensions=preload("res://scripts/vehicle_dimensions.gd")
const VehicleLivery=preload("res://scripts/vehicle_livery.gd")
const VehicleDynamics=preload("res://scripts/vehicle_dynamics.gd")
const VehicleGround=preload("res://scripts/vehicle_grounding.gd")
const VehicleCollision=preload("res://scripts/vehicle_collision.gd")
const VehiclePersonContact=preload("res://scripts/vehicle_person_contact.gd")
const VehicleRunover=preload("res://scripts/vehicle_runover.gd")
const Emplacement=preload("res://scripts/emplacement_profile.gd")
const PortableMortar=preload("res://scripts/portable_mortar.gd")
const SCALE=40.0
signal event(data: Dictionary)
var terrain=preload("res://scripts/terrain_surface.gd").new()
var loot=preload("res://scripts/loot_bags.gd").new()
var catalog
var plan: Dictionary
var objects: Array=[]
var vehicles: Array=[]
var units: Array=[]
var projectiles: Array=[]
var player: Dictionary
var bounds:=Vector2(50,35)
var time=0.0
var sequence=0
var rng=RandomNumberGenerator.new()
var invulnerable=true
var auto_targets=true
var ai_enabled=false
var shots=0
var hits=0
var kills=0
var broken=0
var damage_total=0.0
var topology_revision=0
var obstacle_grid: Dictionary={}
var obstacle_query_cache: Dictionary={}
var body_grid: Dictionary={}
var obstacle_marks=PackedInt32Array()
var obstacle_query_serial=0
var unit_grid: Dictionary={}
var unit_grid_active=false
var unit_ray_index=preload("res://scripts/unit_ray_index.gd").new()
var unit_ray_phase=false
var projectile_query_profile: Dictionary={}
var navigation=AStarGrid2D.new()
var navigation_dirty=true
var nav_time=0.0
var support_dirty: Dictionary={}
var target_respawn_delay=4.0
var muzzle_provider: Callable
var throw_origin_provider: Callable
var profile_ai=false
var last_step_profile: Dictionary={}
var overlap_budget_usec=2000
var ai_budget_usec=2000
var ai_budget_frame: int=-1
var simulation_tick=0
var offline_ai_order=true
var ai_order_tick=0
var ai_unit_order: Array=[]
## Host-side controls for blue soldiers occupied by LAN peers. The host remains
## the only authority that advances the campaign, damage and projectiles.
var network_inputs: Dictionary={}
const UnitSchedule=preload("res://scripts/unit_step_schedule.gd")
const RenderMotion=preload("res://scripts/render_motion.gd")
const Quad=preload("res://scripts/collision_quadtree.gd")
var obstacle_tree=Quad.new()
var vehicle_tree=Quad.new()
var vehicle_tree_count=-1

func setup(source_plan: Dictionary,source_catalog) -> Dictionary:
	loot.clear()
	campaign_director.cancel()
	if not event.is_connected(_observe_campaign_event):event.connect(_observe_campaign_event)
	catalog=source_catalog;plan=source_plan.duplicate(true)
	var compiled=catalog.compile(plan)
	objects=compiled.objects;bounds=compiled.bounds
	terrain.configure(compiled,catalog,plan)
	preload("res://scripts/terrain_landforms.gd").ground_objects(compiled,terrain)
	campaign=CampaignRules.new();campaign_ai=CampaignAI.new();campaign_director=CampaignDirector.new()
	invulnerable=not bool(plan.get("godot3d",{}).get("campaign",false));auto_targets=invulnerable;ai_enabled=not invulnerable
	houses=compiled.houses;housing_support.revision=-1
	vehicles=[];units=[];projectiles=[];support_dirty={};time=0;sequence=0;shots=0;hits=0;kills=0;broken=0;damage_total=0;topology_revision=0
	network_inputs.clear()
	unit_grid.clear();unit_grid_active=false;unit_ray_index=preload("res://scripts/unit_ray_index.gd").new()
	ai_budget_frame=-1
	ai_order_tick=0;ai_unit_order.clear()
	rng.seed=int(plan.world.get("seed",260925))
	# Seat snow/desert props into the solid relief, keeping each building's foundation level.
	var grounded_owners={};var foundation={}
	for o in objects:
		if o.output=="natural" or o.get("terrain_grounded",false):continue
		if terrain.material_at(o.position) in ["terrain.snow","terrain.desert"]:grounded_owners[o.owner]=true
	for o in objects:
		if not grounded_owners.has(o.owner):continue
		var bottom=terrain.height(o.position)
		if o.output!="tree":
			for x in [-.5,0,.5]:
				for z in [-.5,0,.5]:bottom=minf(bottom,terrain.height(o.position+Vector2(o.size.x*x,o.size.y*z).rotated(o.angle)))
		foundation[o.owner]=minf(float(foundation.get(o.owner,INF)),bottom)
	for house in houses:house.base+=float(foundation.get(house.id,0))
	for roof in compiled.roofs:
		var base=float(foundation.get(roof.id,0));roof.height+=base;roof.elevation+=base
	for o in objects:
		o.surface=terrain.material_at(o.position)
		if not o.get("terrain_grounded",false):o.elevation+=terrain.height(o.position) if o.output=="natural" else float(foundation.get(o.owner,0))
		NatureGeometry.prepare(o)
		HouseGeometry.prepare(o)
		var material: Dictionary=catalog.data.materials.get(o.kind,catalog.data.materials.concrete)
		o.columns=maxi(1,int(ceil(o.size.x/.55)))
		o.rows=maxi(1,int(ceil(o.height/(.27 if o.kind=="sandbag" else .50))))
		o.whole=not o.component_id.begins_with("wall.")
		if o.whole:o.columns=1;o.rows=1
		o.cell_width=o.size.x/o.columns;o.cell_height=o.height/o.rows
		o.max_hp=float(material.get("cellHealth",58))*float(o.health_scale)
		o.hp=[]
		for i in range(o.columns*o.rows):o.hp.append(o.max_hp)
		o.alive=true;o.revision=0;o.blast_scale=float(material.get("blast",1));o.transmission=float(material.get("blastTransmission",.1))
		if o.output=="tree":o.size=Vector2(.35,.35);o.columns=1;o.rows=1;o.cell_width=.35;o.cell_height=o.height;o.hp=[o.max_hp];o.whole=true
		TerrainStructure.prepare(o)
		preload("res://scripts/metal_fence.gd").prepare(o)
		CoverRules.annotate(o)
	build_index()
	for spec in compiled.vehicles:add_vehicle(spec)
	if bool(plan.get("godot3d",{}).get("campaign",false)):
		campaign.configure(self);campaign_ai.configure(self)
	else:
		player=add_unit(catalog.position(plan.deployment.get("player",{"x":plan.world.w*.5,"y":plan.world.h*.65}),plan),true)
		for target in compiled.targets:
			var unit=add_unit(catalog.position(target,plan),false);unit.class_id=str(target.get("class_id","assault"))
			unit.team=clampi(int(target.get("team",1)),0,1)
	navigation_dirty=true;nav_time=0
	unit_ray_index.begin(units)
	if campaign_active():
		rebuild_navigation()
		campaign_director.configure(self)
	return compiled

func _observe_campaign_event(data: Dictionary):
	if data.get("type","") in ["respawn","death"]:index_unit(data.unit)
	if campaign_active() and campaign_ai.has_method("observe_event"):campaign_ai.observe_event(data)

func add_unit(at: Vector2,controlled: bool) -> Dictionary:
	var u={"id":units.size(),"position":at,"spawn":at,"team":0 if controlled else 1,"player":controlled,"health":200.0,"max_health":200.0,"alive":true,
		"facing":Vector2(0,-1) if controlled else Vector2(0,1),"class_id":"assault","velocity":Vector2.ZERO,"requested_velocity":Vector2.ZERO,"walk":rng.randf()*TAU,"flash":0.0,"hurt":0.0,"death_age":0.0,
		"stance":0,"stance_blend":0.0,"aiming":false,"mounted":-1,"weapon_id":"m416","ammo":30,"reserve":180,"reload":0.0,"reload_duration":2.1,"cooldown":0.0,"shot_index":0,
		"last_shot":-100.0,"aim_height":-1.0,"aim_valid":false,"helmet_lost":false,"brain":rng.randf(),"path":[],"repath":0.0,"inventory":{},"death_velocity":Vector3.ZERO,"death_position":Vector3.ZERO,"death_roll":0.0}
	units.append(u)
	Traversal.reset(u);u.elevation=terrain.height(u.position);Handling.reset(u);FireControl.reset(u,weapon_for(u));u.reaction={};u.last_impact={}
	Equipment.initialize(u,catalog.weapons,[u.weapon_id],controlled and not campaign_active())
	return u

func add_vehicle(spec: Dictionary) -> Dictionary:
	var emplacement=bool(spec.get("emplacement",false))
	var profile: Dictionary=spec.get("profile_override",(catalog.data.emplacements if emplacement else catalog.data.vehicles).get(spec.type,{}))
	if profile.is_empty():return {}
	var modes: Array=["primary"] if emplacement else profile.weaponOrder.duplicate()
	var v={"id":vehicles.size(),"source_id":spec.id,"type":spec.type,"profile":profile,"position":catalog.position(spec,plan),"spawn":catalog.position(spec,plan),"angle":float(spec.get("angle",-PI*.5)),"turret_angle":float(spec.get("angle",-PI*.5)),
		"emplacement":emplacement,"team":VehicleLivery.team_id(spec.get("team","neutral")),"modes":modes,"mode":0,"states":{},"health":float(profile.health),"max_health":float(profile.health),"track_health":float(profile.get("trackHealth",0)),"max_track":float(profile.get("trackHealth",0)),
		"speed":0.0,"destroyed":false,"flash":0.0,"driver":false,"radius":float(profile.get("radius",35))/SCALE,"recoil":0.0,"destroy_time":0.0,"shot_time":-100.0,"shot_sequence":0}
	v.dimensions=VehicleDimensions.for_vehicle(v)
	v.driver_id=-1;v.ai_controlled=bool(spec.get("aiControlled",false))
	v.navigation_position=v.position;v.navigation_angle=v.angle
	if not emplacement:v.radius=maxf(v.dimensions.half.x/1.4,v.dimensions.half.y/.9)
	VehicleDynamics.reset(v);VehicleGround.initialize(terrain,v,self)
	for mode in modes:
		var w: Dictionary=profile if emplacement else profile.weapons[mode]
		v.states[mode]={"ammo":int(w.mag),"reserve":int(w.reserve),"reload":0.0,"reload_duration":float(w.reload),"cooldown":0.0}
		FireControl.reset(v.states[mode],w)
	vehicles.append(v);return v

func weapon_for(u: Dictionary) -> Dictionary:return catalog.weapons[u.weapon_id]
func mounted_weapon(v: Dictionary) -> Dictionary:return v.profile if v.emplacement else v.profile.weapons[v.modes[v.mode]]
func active_weapon() -> Dictionary:return mounted_weapon(vehicles[player.mounted]) if player.mounted>=0 else weapon_for(player)

func enclosed(u: Dictionary) -> bool:
	return u.mounted>=0 and not vehicles[u.mounted].emplacement
func active_state() -> Dictionary:
	if player.mounted>=0:
		var v: Dictionary=vehicles[player.mounted]
		return v.states[v.modes[v.mode]]
	return player

func equip(id: String) -> bool:
	if not catalog.weapons.has(id) or not Equipment.available(player):return false
	if id=="portable-mortar" and int(player.get("deployed_mortar",-1))>=0:
		event.emit({"type":"notice","text":"迫击炮已部署，请靠近炮位按 F 操作"});return false
	if campaign_active() and (id not in player.get("loadout",[]) or campaign.phase!="playing"):return false
	if id==player.weapon_id and not player.get("holstered",false) and player.get("healing",{}).is_empty():return true
	if not campaign_active() and (id not in player.quick_owned or (not Equipment.tactical(catalog.weapons[id]) and id not in player.quick_slots)):
		Equipment.assign(player,catalog.weapons[id])
	cancel_firing()
	player.inventory[player.weapon_id]={"ammo":player.ammo,"reserve":player.reserve,"fire_mode":FireControl.selected(player,weapon_for(player)),"cooldown_until":time+maxf(0,player.cooldown)}
	player.weapon_id=id
	var w: Dictionary=weapon_for(player)
	var stored: Dictionary=player.inventory.get(id,{"ammo":int(w.mag),"reserve":int(w.reserve)})
	player.ammo=stored.ammo;player.reserve=stored.reserve;player.reload=0.0;player.cooldown=maxf(0,float(stored.get("cooldown_until",time))-time)
	player.holstered=false;player.healing={};player.flash=0.0
	player.equip_duration=Equipment.draw_time(w);player.equip_remaining=player.equip_duration
	if Equipment.tactical(w):player.quick_tactical=id
	elif id in player.quick_slots:player.quick_active_slot=player.quick_slots.find(id)
	player.fire_mode=str(stored.get("fire_mode",FireControl.default_mode(w)))
	Handling.reset(player);FireControl.reset(player,w);FireControl.cancel(player,true)
	event.emit({"type":"equip","unit":player,"weapon":w})
	return true

func assign_quick_weapon(id: String,slot: int) -> bool:
	if not catalog.weapons.has(id) or not Equipment.available(player):return false
	if id=="portable-mortar" and int(player.get("deployed_mortar",-1))>=0:return false
	if campaign_active() and (campaign.phase!="playing" or id not in player.get("loadout",[])):return false
	Equipment.assign(player,catalog.weapons[id],slot)
	return equip(id)

func clear_quick_slot(slot: int) -> bool:
	if not Equipment.available(player) or slot<0 or slot>2:return false
	if campaign_active() and campaign.phase!="playing":return false
	if player.weapon_id==player.quick_slots[slot]:holster()
	player.quick_slots[slot]="";return true

func holster() -> bool:
	if not Equipment.available(player):return false
	if campaign_active() and campaign.phase!="playing":return false
	cancel_firing();player.reload=0.0;player.healing={};player.holstered=true;player.flash=0.0;player.aiming=false
	return true

func use_medicine(id: String) -> bool:
	if campaign_active() and campaign.phase!="playing":return false
	if not Equipment.begin_heal(player,id):return false
	cancel_firing();player.reload=0.0;player.flash=0.0;player.aiming=false;return true

func cancel_medicine() -> bool:
	if player.get("healing",{}).is_empty():return false
	player.healing={};cancel_firing();return true

func campaign_active() -> bool:return campaign.active

func equip_slot(index: int) -> bool:
	if not Equipment.selection_available(player,vehicles):return false
	if campaign_active() and campaign.phase!="playing":return false
	if player.mounted>=0:
		var v: Dictionary=vehicles[player.mounted]
		if index<0 or index>=v.modes.size():return false
		if index==int(v.mode):return true
		cancel_firing();v.mode=index;FireControl.cancel(active_state(),true)
		return true
	var id=Equipment.slot_weapon(player,index)
	return not id.is_empty() and equip(id)

func equipment_entries() -> Array:
	return Equipment.entries(player,catalog.weapons,vehicles)

func next_equipment_slot(direction: int) -> int:
	return Equipment.next_slot(equipment_entries(),direction)

func reload_weapon() -> bool:
	if not player.alive or not player.vault.is_empty() or not player.ladder.is_empty() or (player.mounted<0 and Equipment.busy(player)):return false
	var state=active_state();var w=active_weapon()
	if not FireControl.begin_reload(state,w):return false
	if player.mounted<0:event.emit({"type":"reload_start","unit":player,"weapon":w})
	return true

func cancel_firing() -> void:
	if player.is_empty():return
	FireControl.cancel(player,true)
	ThrowControl.cancel(player)
	Melee.cancel(player)
	if player.mounted>=0:FireControl.cancel(active_state(),true)

func cycle_fire_mode() -> void:
	if not player.alive or not player.vault.is_empty() or not player.ladder.is_empty():return
	var state=active_state();var w=active_weapon()
	var changed=FireControl.cycle(state,w)
	event.emit({"type":"notice","text":("射击模式：" if changed else "该武器仅支持：")+FireControl.label(state,w)})

func auto_reload(state: Dictionary,w: Dictionary) -> void:
	if not FireControl.needs_reload(state,w):return
	if FireControl.begin_reload(state,w) and state.has("id"):event.emit({"type":"reload_start","unit":state,"weapon":w})

func refill() -> void:
	if campaign_active():return
	for u in units:
		if not u.alive:u.position=u.spawn;u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;Traversal.reset(u);u.elevation=terrain.height(u.position)
		var w=weapon_for(u);u.ammo=int(w.mag);u.reserve=int(w.reserve);u.reload=0.0;u.cooldown=0.0;u.health=u.max_health;u.alive=true;u.inventory={};u.helmet_lost=false
		Handling.reset(u);FireControl.reset(u,w);FireControl.cancel(u,true);ThrowControl.cancel(u);Melee.cancel(u);u.reaction={};u.last_impact={}
		u.holstered=false;u.equip_remaining=0.0;u.healing={};u.medical_feedback={};u.medical_stock={"bandage":3,"first-aid":1}
		u.loot_dropped=false
		index_unit(u)
	for v in vehicles:
		v.health=v.max_health;v.track_health=v.max_track;v.destroyed=false
		VehicleDynamics.reset(v);VehicleGround.initialize(terrain,v,self)
		v.shot_time=-100.0;v.flash=0.0;v.recoil=0.0
		for mode in v.modes:
			var w: Dictionary=v.profile if v.emplacement else v.profile.weapons[mode]
			v.states[mode]={"ammo":int(w.mag),"reserve":int(w.reserve),"reload":0.0,"reload_duration":float(w.reload),"cooldown":0.0}
			FireControl.reset(v.states[mode],w);FireControl.cancel(v.states[mode],true)
	event.emit({"type":"repair"})

func set_stance(stance: int) -> void:
	if player.mounted>=0 or not player.grounded or not player.vault.is_empty():return
	stance=clampi(stance,0,2)
	Traversal.recover_overlap(self,player)
	# A tall obstruction cannot be stood up into after crawling through a breach.
	if stance<player.stance and blocked(player.position,Traversal.RADIUS,stance_height(stance),-1,player.elevation):
		var posture="卧倒" if player.stance==2 else "蹲伏"
		event.emit({"type":"notice","text":"上方仍有障碍，请保持%s，用 WASD 移出缺口后再起身"%posture});return
	player.stance=stance

static func stance_height(stance: int) -> float:return [1.95,1.50,.84][stance]
static func collision_height(u: Dictionary) -> float:
	if not u.get("vehicle_flight",{}).is_empty():return preload("res://scripts/vehicle_impact_motion.gd").height(u.vehicle_flight)
	# Lower the collider with the animation; reserve the full volume before rising.
	var blend=clampf(float(u.get("stance_blend",u.stance)),0,2)
	var animated=lerpf(stance_height(0),stance_height(1),blend) if blend<=1 else lerpf(stance_height(1),stance_height(2),blend-1)
	return maxf(stance_height(u.stance),animated)

static func head_center(u: Dictionary) -> Vector3:
	return CombatPose.head(u)

static func head_intersection(origin: Vector3,direction: Vector3,center: Vector3,radius: float) -> float:
	var relative=origin-center;var a=direction.length_squared();var b=relative.dot(direction);var c=relative.length_squared()-radius*radius;var discriminant=b*b-a*c
	if discriminant<0:return INF
	var t=(-b-sqrt(discriminant))/a
	return maxf(0,t) if (-b+sqrt(discriminant))/a>=0 else INF
static func muzzle_height(u: Dictionary) -> float:
	return CombatPose.muzzle(u).y

func step(delta: float,movement: Vector2,aim: Vector2,trigger: bool,pressed: bool,aiming: bool=false,brake: bool=false,sprint: bool=false,jump: bool=false,fire_allowed: bool=true) -> void:
	if campaign_active() and campaign.phase!="playing":return
	var local_control={"movement":movement,"aim":aim,"trigger":trigger,"pressed":pressed,"aiming":aiming,"brake":brake,"sprint":sprint,"jump":jump,"fire_allowed":fire_allowed}
	VehicleRenderMotion.before_step(vehicles)
	var profile_start=Time.get_ticks_usec() if profile_ai else 0
	simulation_tick+=1
	var staggered=campaign_active() and delta<.025
	overlap_budget_usec=1000 if staggered else 2000
	# Catch-up physics ticks share one decision allowance per rendered frame.
	# Movement, cooldowns, firing and real hits still execute at their own rates.
	var decision_frame: int=Engine.get_process_frames()
	if decision_frame!=ai_budget_frame:
		ai_budget_frame=decision_frame;ai_budget_usec=1000 if staggered else 2000
	if profile_ai:campaign_ai.step_profile.clear()
	time+=delta
	loot.tick(self,delta)
	if campaign_active():campaign_director.tick(delta)
	if campaign_active() and ai_enabled:campaign_ai.vehicle_ai.tick()
	var profile_director=Time.get_ticks_usec() if profile_ai else 0
	build_unit_index()
	var fair_order=UnitSchedule.use_offline_order(campaign_active(),offline_ai_order,network_inputs)
	if fair_order:
		ai_order_tick+=1
		UnitSchedule.fill_offline_order(units,ai_order_tick,ai_unit_order)
	for unit_index in range(units.size()):
		var u: Dictionary=units[int(ai_unit_order[unit_index]) if fair_order else unit_index]
		var control: Dictionary=local_control if u.player else network_inputs.get(int(u.id),{})
		var human=not control.is_empty()
		var unit_delta=UnitSchedule.elapsed(u,delta,simulation_tick,staggered)
		if unit_delta<=0:continue
		RenderMotion.before_unit(u)
		u.flash=maxf(0,u.flash-unit_delta);u.hurt=maxf(0,u.hurt-unit_delta)
		Equipment.tick(u,unit_delta)
		if human:u.aiming=bool(control.get("aiming",false))
		if not u.get("reaction",{}).is_empty():
			u.reaction.age+=unit_delta
			if u.reaction.age>=u.reaction.duration:u.reaction={}
		tick_state(u,weapon_for(u),unit_delta)
		u.stance_blend=move_toward(u.stance_blend,float(u.stance),unit_delta*(2.4 if u.stance==2 else 3.0))
		if not u.alive:
			ThrowControl.cancel(u)
			Melee.cancel(u)
			u.death_age+=unit_delta
			if not u.player and auto_targets and u.death_age>target_respawn_delay:
				u.loot_dropped=false
				u.alive=true;u.health=u.max_health;u.position=u.spawn;u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;u.death_age=0;u.helmet_lost=false
				Traversal.reset(u);u.elevation=terrain.height(u.position)
				Handling.reset(u);FireControl.reset(u,weapon_for(u));u.reaction={};u.last_impact={}
				event.emit({"type":"respawn","unit":u})
				index_unit(u)
			continue
		if not u.get("vehicle_flight",{}).is_empty():
			FireControl.cancel(u,true)
			VehicleRunover.tick_unit(self,u,unit_delta)
			RenderMotion.after_unit(u,time,unit_delta)
			continue
		if human:
			var unit_aim: Vector2=control.get("aim",u.position+u.facing*8)
			var unit_movement: Vector2=control.get("movement",Vector2.ZERO)
			var unit_trigger: bool=bool(control.get("trigger",false))
			var unit_pressed: bool=bool(control.get("pressed",false))
			var unit_allowed: bool=bool(control.get("fire_allowed",false))
			u.aiming=bool(control.get("aiming",false))
			if u.mounted<0:
				var look=unit_aim;var throw_state: Dictionary=u.get("throw_state",{})
				if not throw_state.is_empty() and throw_state.phase=="windup":look=Vector2(throw_state.target.x,throw_state.target.z)
				if not u.get("melee",{}).is_empty():look=u.position+Vector2.from_angle(u.melee.angle)*4
				if u.position.distance_squared_to(look)>.12:
					u.facing=Vector2.from_angle(rotate_toward(u.facing.angle(),(look-u.position).angle(),delta*18.0))
				u.aim_point=look
				Traversal.move(self,u,unit_movement,delta,bool(control.get("sprint",false)) and not u.aiming and not unit_trigger and not unit_pressed and u.reload<=0 and throw_state.is_empty() and u.get("melee",{}).is_empty() and u.get("healing",{}).is_empty(),bool(control.get("jump",false)))
				var allowed=unit_allowed and u.vault.is_empty() and u.ladder.is_empty() and not Equipment.busy(u)
				var w=weapon_for(u)
				if w.kind=="grenade":
					if ThrowControl.update(u,w,delta,unit_trigger,unit_pressed,Vector3(unit_aim.x,u.aim_height,unit_aim.y),allowed):throw_grenade(u,w,u.throw_state.target,u.throw_state.low)
				elif w.kind=="mortar":
					if unit_pressed and allowed:PortableMortar.deploy(self,u,w)
				elif FireControl.wants_shot(u,w,unit_trigger,unit_pressed,allowed):fire(u,w,u,u.position,u.facing.angle(),muzzle_height(u),unit_aim,-1)
		else:
			if ai_enabled:
				if campaign_active():campaign_ai.update(u,unit_delta)
				else:update_ai(u,unit_delta)
			else:u.velocity=Vector2.ZERO;FireControl.cancel(u)
			if u.mounted<0:Traversal.vertical_step(self,u,unit_delta)
		VehicleRunover.tick_unit(self,u,unit_delta)
		update_melee(u,unit_delta,not human or bool(control.get("fire_allowed",false)))
		if human and control.has("_sequence"):
			u.network_applied_sequence=int(control._sequence);u.network_applied_usec=int(control.get("_sent_usec",0))
		RenderMotion.after_unit(u,time,unit_delta)
		# Vaults/ladders can set the authoritative root directly, without move_unit.
		index_unit(u)
	var profile_units=Time.get_ticks_usec() if profile_ai else 0
	unit_grid_active=false
	for v in vehicles:
		v.flash=maxf(0,v.flash-delta);v.recoil=move_toward(v.recoil,0,delta*2)
		if v.destroyed:
			if not v.emplacement and (v.get("airborne",false) or absf(float(v.get("fall_speed",0)))>.001):
				var support=VehicleGround.sample(terrain,v,v.position,v.angle,true,self)
				v.ground=preload("res://scripts/vehicle_vertical_motion.gd").settle(self,v,support,delta)
			continue
		for mode in v.modes:
			var gun_state: Dictionary=v.states[mode]
			var driver_id=int(v.get("driver_id",-1))
			gun_state.aiming=driver_id>=0 and driver_id<units.size() and units[driver_id].get("aiming",false)
			gun_state.velocity=Vector2.ZERO if v.emplacement else Vector2(v.get("velocity",Vector2.ZERO))
			if v.type==PortableMortar.KIND and not v.driver:v.states[mode].cooldown=maxf(0,float(v.states[mode].cooldown)-delta)
			else:tick_state(v.states[mode],v.profile if v.emplacement else v.profile.weapons[mode],delta)
		var driver_id: int=int(v.get("driver_id",-1))
		var operator: Dictionary=units[driver_id] if driver_id>=0 and driver_id<units.size() else {}
		var vehicle_control: Dictionary=local_control if operator==player else network_inputs.get(driver_id,{})
		if not operator.is_empty() and not vehicle_control.is_empty():
			var vehicle_movement: Vector2=vehicle_control.get("movement",Vector2.ZERO)
			var vehicle_aim: Vector2=vehicle_control.get("aim",v.position+Vector2.from_angle(v.turret_angle)*8)
			drive(v,-vehicle_movement.y,vehicle_movement.x,delta,bool(vehicle_control.get("brake",false)),bool(vehicle_control.get("sprint",false)))
			var turret_origin=v.position if v.emplacement else VehicleDimensions.turret_position(v)
			var angle=(vehicle_aim-turret_origin).angle()
			v.aim_target=Vector3(vehicle_aim.x,float(operator.aim_height) if operator.get("aim_valid",false) or operator.aim_height>=0 else 0.0,vehicle_aim.y)
			if not v.emplacement:
				var mount=Vector3(v.position.x,v.elevation,v.position.y)+VehicleDimensions.body_basis(v)*VehicleDimensions.turret_offset(v)
				var tangent: Vector3=(v.aim_target-mount).slide(VehicleDimensions.body_basis(v).y.normalized())
				if tangent.length_squared()>.0001:angle=atan2(tangent.z,tangent.x)
			if v.emplacement:angle=v.angle+clampf(wrapf(angle-v.angle,-PI,PI),-float(v.profile.traverse),float(v.profile.traverse))
			var next_angle=rotate_toward(v.turret_angle,angle,float(v.profile.get("turretTurnRate",v.profile.get("turnRate",1)))*delta)
			if not v.emplacement:v.turret_angle=next_angle
			else:
				var next_operator=Emplacement.operator_position(v,next_angle)
				var next_height: float=PortableMortar.operator_height(self,v,next_operator)
				if absf(next_height-float(v.get("elevation",0)))<=.35 and not blocked(next_operator,Traversal.RADIUS,stance_height(1 if v.type==PortableMortar.KIND else 0),v.id,next_height):v.turret_angle=next_angle
			operator.position=Emplacement.operator_position(v) if v.emplacement else v.position;operator.facing=Vector2.from_angle(v.turret_angle)
			operator.elevation=PortableMortar.operator_height(self,v,operator.position) if v.emplacement else v.elevation
			if v.type==PortableMortar.KIND:operator.stance=1;operator.stance_blend=1.0
			var w=mounted_weapon(v)
			if FireControl.wants_shot(v.states[v.modes[v.mode]],w,bool(vehicle_control.get("trigger",false)),bool(vehicle_control.get("pressed",false)),bool(vehicle_control.get("fire_allowed",false)) and operator.alive):fire(operator,w,v.states[v.modes[v.mode]],v.position,v.turret_angle,1.5 if not v.emplacement else 1.1,vehicle_aim,int(v.id))
		elif campaign_active() and ai_enabled and int(v.get("driver_id",-1))>=0:campaign_ai.vehicle_ai.update(v,delta)
		elif not v.emplacement and (v.get("velocity",Vector2.ZERO).length_squared()>.000001 or absf(v.get("yaw_rate",0))>.001 or v.get("airborne",false) or absf(float(v.get("fall_speed",0)))>.001 or v.get("ground",{}).get("rock_contacts",0)>0):drive(v,0,0,delta,false,false,true)
		if not operator.is_empty():index_unit(operator)
	update_projectiles(delta)
	VehicleRenderMotion.after_step(vehicles)
	if player.mounted>=0:RenderMotion.after_unit(player,time,delta)
	var profile_projectiles=Time.get_ticks_usec() if profile_ai else 0
	resolve_support()
	housing_support.resolve(self)
	var profile_support=Time.get_ticks_usec() if profile_ai else 0
	nav_time-=delta
	if navigation_dirty and nav_time<=0 and ai_enabled:rebuild_navigation()
	var profile_navigation=Time.get_ticks_usec() if profile_ai else 0
	if campaign_active():
		campaign.tick(delta)
		if campaign.phase!="playing":campaign_director.cancel()
	if profile_ai:last_step_profile={"director_ms":(profile_director-profile_start)/1000.0,"units_ms":(profile_units-profile_director)/1000.0,"projectiles_vehicles_ms":(profile_projectiles-profile_units)/1000.0,"support_ms":(profile_support-profile_projectiles)/1000.0,"navigation_ms":(profile_navigation-profile_support)/1000.0,"rules_ms":(Time.get_ticks_usec()-profile_navigation)/1000.0}
	if profile_ai:last_step_profile.ai_detail=campaign_ai.step_profile.duplicate()
	if profile_ai:last_step_profile.unit_rays=projectile_query_profile

func tick_state(state: Dictionary,w: Dictionary,delta: float) -> void:
	Handling.tick(state,w,delta)
	FireControl.tick_clock(state,delta)
	if not state.get("alive",true):FireControl.cancel(state,true);return
	if not state.get("vault",{}).is_empty() or not state.get("ladder",{}).is_empty():FireControl.cancel(state,true);return
	if int(state.get("mounted",-1))>=0:return
	if Equipment.busy(state):return
	if state.reload>0:
		state.reload=maxf(0,state.reload-delta)
		if state.reload==0:
			FireControl.finish_reload(state,w)
	auto_reload(state,w)

func fire(u: Dictionary,w: Dictionary,state: Dictionary,origin: Vector2,angle: float,height: float,target: Vector2,mount_id: int=-1) -> bool:
	if mount_id<0 and Equipment.busy(u):return false
	if w.kind=="mortar":
		if mount_id<0:
			PortableMortar.deploy(self,u,w);return false
		if int(u.mounted)!=mount_id or u.stance!=1:return false
		var distance=origin.distance_to(target)
		if distance<float(w.get("minRange",220))/SCALE or distance>float(w.range)/SCALE or absf(wrapf((target-origin).angle()-angle,-PI,PI))>.12:
			FireControl.cancel(state);return false
	if not u.alive or not u.vault.is_empty() or not u.ladder.is_empty() or state.cooldown>0 or state.reload>0 or (state.ammo<=0 and w.kind!="melee"):return false
	if w.kind=="grenade":return throw_grenade(u,w,Vector3(target.x,float(u.aim_height),target.y),int(u.stance)==2)
	if w.kind=="melee":
		if not u.get("melee",{}).is_empty():return false
		FireControl.committed(state,w);u.last_shot=time;u.shot_index+=1;u.aim_point=target;shots+=1
		Melee.begin(u,w,target);return true
	FireControl.committed(state,w)
	if w.kind!="melee":state.ammo-=1
	var profile=WeaponProfile.get_profile(w)
	u.flash=profile.flash_time;u.last_shot=time;u.shot_index+=1;u.aim_point=target;shots+=1
	if mount_id>=0:
		vehicles[mount_id].flash=profile.flash_time;vehicles[mount_id].recoil=.20
		vehicles[mount_id].shot_time=time;vehicles[mount_id].shot_sequence+=1
		state.shot_time=time
	var muzzle=origin+Vector2.from_angle(angle)*((1.53 if u.stance==2 else .95) if mount_id<0 else vehicles[mount_id].radius*1.25)
	var breech_height=height;var resolved: Dictionary={}
	if muzzle_provider.is_valid():resolved=muzzle_provider.call(u,w,mount_id)
	if resolved.has("position"):
		var point: Vector3=resolved.position;muzzle=Vector2(point.x,point.z);height=point.y
		var forward: Vector3=resolved.forward
		if Vector2(forward.x,forward.z).length_squared()>.001:angle=Vector2(forward.x,forward.z).angle()
	var spread=Handling.aim_spread(w,state,u)
	var recoil=Handling.offset(w,state,time)
	var forward3=Vector3(cos(angle),0,sin(angle))
	if resolved.has("forward"):forward3=resolved.forward
	else:
		forward3.y=(float(u.get("aim_height",-1))-height)/maxf(.5,muzzle.distance_to(target)) if u.get("aim_valid",false) or float(u.get("aim_height",-1))>=0 else 0.0
		forward3=(Basis.looking_at(forward3.normalized(),Vector3.UP)*Basis(Vector3.UP,-recoil.x)*Basis(Vector3.RIGHT,recoil.y)*Vector3.FORWARD).normalized()
	# Pitched weapon assemblies already include their angular kick at the muzzle.
	if mount_id>=0 and not resolved.get("posed_recoil",false):forward3=(Basis.looking_at(forward3,Vector3.UP)*Basis(Vector3.UP,-recoil.x)*Basis(Vector3.RIGHT,recoil.y)*Vector3.FORWARD).normalized()
	var shot={"type":"shot","unit":u,"weapon":w,"position":muzzle,"height":height,"angle":angle,"mount":mount_id,"profile":profile}
	shot.merge(resolved,false);event.emit(shot)
	var pellets=int(w.get("pellets",1))
	var shot_axis=Handling.shot_direction(forward3,spread,rng.randf()*TAU,rng.randf())
	var pellet_spread=float(Handling.profile(w).pellet);var pellet_rotation=rng.randf()*TAU
	for i in range(pellets):
		sequence+=1
		# One aim error per trigger pull; pellets spread around that shared shell axis.
		var azimuth=pellet_rotation+float(i)*2.399963+rng.randf_range(-.16,.16)
		var flight=Handling.cone_direction(shot_axis,pellet_spread,azimuth,(float(i)+rng.randf())/pellets) if pellets>1 else shot_axis
		var direction=Vector2(flight.x,flight.z).normalized()
		var range_m=float(w.get("range",1300))/SCALE
		var speed=float(profile.speed)
		var p={"id":sequence,"weapon":w,"origin":muzzle,"position":muzzle,"previous":muzzle,"direction":direction,"height":height,"previous_height":height,"start_height":height,
			"range":range_m,"remaining":range_m,"distance":0.0,"age":0.0,"speed":speed,"team":u.team,"source":u.id,"mount":mount_id,"alive":true,"hit":[],"penetration":int(w.get("penetration",0)),
			"target":muzzle+(target-muzzle).limit_length(range_m),"velocity":direction*speed,"vertical_speed":6.75,"bounces":0,"radius":profile.collision_radius,"newborn":true}
		p.slope=flight.y/maxf(.1,Vector2(flight.x,flight.z).length())
		p.source_epoch=int(u.get("spawn_epoch",0))
		if w.kind in ["mortar","vehicleMortar"]:
			var offset: Vector2=(target-muzzle).limit_length(range_m)
			offset+=Vector2(cos(azimuth),sin(azimuth))*tan(spread)*offset.length()*rng.randf()
			if offset.length()<float(w.get("minRange",0))/SCALE:offset=direction*float(w.get("minRange",0))/SCALE
			p.target=muzzle+offset;p.flight=clampf(offset.length()/float(profile.get("mortar_speed",float(w.get("flightSpeed",900))/SCALE)),.85,4.0);p.arc=float(w.get("arcHeight",340))/SCALE
		# A long barrel cannot bypass a wall between the body and the socket.
		var barrel_origin=origin
		if resolved.has("breech"):
			barrel_origin=Vector2(resolved.breech.x,resolved.breech.z);breech_height=resolved.breech.y
		var barrel=muzzle-barrel_origin;var barrel_ray={"source":u.id,"team":u.team,"mount":mount_id,"slope":(height-breech_height)/maxf(.001,barrel.length()),"radius":profile.collision_radius}
		var obstruction=ray(barrel_origin,barrel.normalized(),barrel.length(),breech_height,barrel_ray,true) if barrel.length()>.001 and w.kind not in ["grenade","melee"] else {}
		if not obstruction.is_empty():
			# Penetration cannot legalize a barrel/socket embedded through a solid wall.
			p.cover_budget=0.0
			p.position=barrel_origin;p.height=breech_height;p.direction=barrel.normalized();p.slope=barrel_ray.slope
			advance_round(p,barrel.length());continue
		# Includes former hitscan sniper rifles: all rounds now have travel time.
		projectiles.append(p)
	Handling.fired(state,w,u,rng.randf_range(-1,1))
	auto_reload(state,w)
	return true

func update_melee(u: Dictionary,delta: float,allowed: bool):
	var w=weapon_for(u)
	if not Melee.advance(u,w,delta,allowed and u.alive and u.mounted<0 and u.vault.is_empty() and u.ladder.is_empty()):return
	var a: Dictionary=u.melee;var direction=Vector2.from_angle(a.angle)
	var height=clampf(float(a.height),u.elevation+.18,u.elevation+stance_height(u.stance)-.12)
	var origin=Vector3(u.position.x,height,u.position.y)
	if not a.swish:event.emit({"type":"melee_swing","weapon":w,"point":origin});a.swish=true
	for victim in units:
		if victim.team==u.team or not victim.alive or victim.id in a.hit or not Melee.within(u,victim,w):continue
		var victim_y=clampf(height,victim.elevation+.12,victim.elevation+stance_height(victim.stance)-.12)
		if absf(height-victim_y)>.30:continue
		var point=Vector3(victim.position.x,victim_y,victim.position.y);var travel=point-origin
		if not trace_3d(origin,travel.normalized(),travel.length(),{"source":u.id,"radius":.035},true).is_empty():continue
		a.hit.append(victim.id)
		damage_unit(victim,float(w.damage),Vector3(direction.x,0,direction.y)*(1.4 if w.id=="army-knife" else 2.8),w,false,false,victim_y,"body",point,travel,u.id)
		event.emit({"type":"melee_contact","point":point})
	# One solid contact per attack. Use the same damaged wall cells as bullets.
	if "solid" not in a.hit:
		var hit=trace_3d(origin,Vector3(direction.x,0,direction.y),float(w.range)/SCALE,{"source":u.id,"radius":.035},true)
		if not hit.is_empty() and hit.type in ["object","vehicle"]:
			a.hit.append("solid");var at=u.position+direction*float(hit.distance)
			if hit.type=="object":damage_object(hit.target,at,height,float(w.damage),false,int(hit.get("col",-1)),int(hit.get("row",-1)),w)
			event.emit({"type":"impact","position":at,"height":height,"material":hit.target.get("material",hit.type),"angle":a.angle,"weapon":w,"source_id":u.id});event.emit({"type":"melee_contact","point":Vector3(at.x,height,at.y)})

func grenade_solution(u: Dictionary,w: Dictionary,target: Vector3,low: bool,origin: Vector3) -> Dictionary:
	var torso=Vector3(u.position.x,u.elevation+(.36 if u.stance==2 else .85 if u.stance==1 else 1.20),u.position.y)
	var exit_hit=Grenade.sweep(self,torso,origin)
	if not exit_hit.is_empty():origin=exit_hit.point+exit_hit.normal*.012
	# If range limiting moves the requested target, use that location's support height.
	var offset=Vector2(target.x-origin.x,target.z-origin.z);var limit=Grenade.max_range(w,u.stance,low or u.stance==2)
	var requested=offset.length()
	if requested>limit:
		var at=Vector2(origin.x,origin.z)+offset.normalized()*limit
		target=Vector3(at.x,ground_height(at,.06,maxf(origin.y,target.y)+.3),at.y)
	var result=Grenade.solve(origin,target,w,u.stance,low,u.facing);result.limited=result.limited or requested>limit+.05
	return result

func throw_grenade(u: Dictionary,w: Dictionary,target: Vector3,low: bool) -> bool:
	if not u.alive or u.ammo<=0 or u.reload>0 or u.cooldown>0 or not u.vault.is_empty() or not u.ladder.is_empty():ThrowControl.cancel(u);return false
	var origin=Vector3(u.position.x,u.elevation+(.45 if u.stance==2 else 1.30),u.position.y)+Vector3(u.facing.x,0,u.facing.y)*.40
	if throw_origin_provider.is_valid():origin=throw_origin_provider.call(u,w)
	var solution=grenade_solution(u,w,target,low,origin)
	FireControl.committed(u,w);u.ammo-=1;u.last_shot=time;u.shot_index+=1;shots+=1;sequence+=1
	var at: Vector3=solution.origin;var velocity: Vector3=solution.velocity
	var p={"id":sequence,"weapon":w,"origin":Vector2(at.x,at.z),"position":Vector2(at.x,at.z),"previous":Vector2(at.x,at.z),
		"height":at.y,"previous_height":at.y,"start_height":at.y,"direction":Vector2(velocity.x,velocity.z).normalized(),"age":0.0,
		"team":u.team,"source":u.id,"mount":-1,"alive":true,"radius":Grenade.RADIUS,"newborn":true,"motion":Grenade.motion(solution),
		"fuse":ThrowControl.fuse(w),"bounce_sounds":0,"last_bounce_sound":-1.0}
	projectiles.append(p);ThrowControl.released(u)
	event.emit({"type":"grenade_throw","unit":u,"weapon":w,"position":at,"power":solution.power})
	auto_reload(u,w)
	return true

func update_projectiles(delta: float) -> void:
	# The spatial tree persists outside this phase. The active flag delimits
	# diagnostic accounting batches, not the validity of authoritative entries.
	if profile_ai:projectile_query_profile={}
	unit_ray_phase=projectiles.size()>=4 and units.size()>=12
	for p in projectiles:
		# Spawn at the end of this physics tick, so the first rendered position is the socket.
		if p.get("newborn",false):p.newborn=false;continue
		p.previous=p.position;p.previous_height=p.height;p.age+=delta
		var w: Dictionary=p.weapon
		if w.kind in ["mortar","vehicleMortar"]:
			var t=clampf(p.age/p.flight,0,1);p.position=p.origin.lerp(p.target,t);p.height=sin(t*PI)*p.arc+lerpf(p.start_height,terrain.height(p.target)+.025,t)
			var origin=Vector3(p.previous.x,p.previous_height,p.previous.y);var flight=Vector3(p.position.x,p.height,p.position.y)-origin
			var hit=trace_3d(origin,flight.normalized(),flight.length(),p,true)
			if not hit.is_empty():
				var at=origin+flight.normalized()*hit.distance;p.position=Vector2(at.x,at.z);p.height=at.y;p.contact_normal=hit.get("normal",Vector3.ZERO);p.contact_material=hit.get("target",{}).get("material",hit.type);detonate(p)
			if t>=1:detonate(p)
		elif w.kind=="grenade":
			var contacts=Grenade.advance(p.motion,self,delta)
			p.position=Vector2(p.motion.at.x,p.motion.at.z);p.height=p.motion.at.y
			for contact in contacts:
				if p.bounce_sounds<3 and p.age-p.last_bounce_sound>.18:
					event.emit({"type":"grenade_bounce","position":contact.position,"soft":contact.soft,"speed":contact.speed});p.bounce_sounds+=1;p.last_bounce_sound=p.age
			if p.age>=p.fuse:detonate(p)
		else:advance_round(p,minf(p.remaining,p.speed*delta))
		if p.age>8:p.alive=false
	projectiles=projectiles.filter(func(p):return p.alive)
	if profile_ai and unit_ray_index.active:projectile_query_profile=unit_ray_index.diagnostics()
	unit_ray_index.active=false
	unit_ray_phase=false

func advance_round(p: Dictionary,distance: float) -> void:
	var budget=distance
	var loops=0
	var explosive=p.weapon.kind in ["rocket","shell","grenadeProjectile","vehicleGrenade"]
	while budget>.0001 and p.alive and loops<12:
		loops+=1
		for key in p.get("cover_inside",{}).keys():
			if float(p.cover_inside[key])<=float(p.distance)+.00001:p.cover_inside.erase(key)
		# Resume geometry queries at each solid's exit, including later pieces of
		# the same house. Skipping an object across a whole frame would skip rooms.
		var segment=Penetration.segment_limit(p.get("cover_inside",{}),float(p.distance),budget)
		var hit=ray(p.position,p.direction,segment,p.height,p)
		var travel=float(hit.get("distance",segment))
		if campaign_active() and not explosive and travel>.001:
			var clear_from=float(p.distance)
			for expires in p.get("cover_inside",{}).values():clear_from=maxf(clear_from,float(expires))
			var hidden=minf(travel,maxf(0,clear_from-float(p.distance)))
			if hidden<travel:
				var start=Vector3(p.position.x,p.height,p.position.y);var along=Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y)
				campaign_ai.perception.near_segment(p,start+along*hidden,start+along*travel)
		p.position+=p.direction*travel;p.height+=float(p.get("slope",0))*travel;p.distance+=travel;p.remaining-=travel;budget-=travel
		if not hit.is_empty():
			if explosive:
				p.contact_normal=hit.get("normal",Vector3.UP if hit.type=="terrain" else Vector3(-p.direction.x,-float(p.get("slope",0)),-p.direction.y).normalized())
				p.contact_material=hit.get("target",{}).get("material",hit.type);detonate(p);break
			var damage=float(p.weapon.damage)*falloff(p.weapon,p.distance)*float(p.get("cover_damage_scale",1.0))
			if hit.type=="unit":
				p.hit.append(hit.target.id)
				var push=float(p.weapon.get("presentation",{}).get("fx",{}).get("deathPush",65))/SCALE
				damage_unit(hit.target,damage,Vector3(p.direction.x,0,p.direction.y)*push,p.weapon,false,hit.get("region","")=="head",p.height,str(hit.get("region","")),Vector3(p.position.x,p.height,p.position.y),Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y),int(p.get("source",-1)),int(p.get("source_epoch",-1)))
				if p.penetration>0:p.penetration-=1
				else:p.alive=false
			elif hit.type=="terrain":p.alive=false
			elif hit.type=="vehicle":damage_vehicle(hit.target,damage,p.position,p.weapon,false);p.alive=false
			else:
				var incoming_ray=Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y)
				var material_budget=float(p.get("cover_budget",p.weapon.get("cover_ammo",{}).get("penetration",0)))
				var pass_result=Penetration.response(p.weapon,hit,incoming_ray,material_budget)
				var incoming=Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y).normalized()
				var incidence=absf(incoming.dot(hit.get("normal",-incoming)))
				damage_object(hit.target,p.position,p.height,damage,false,int(hit.get("col",-1)),int(hit.get("row",-1)),p.weapon,p.distance,incidence,float(p.get("cover_damage_scale",1)))
				if bool(pass_result.get("pass",false)) and int(p.get("cover_layers",0))<Penetration.MAX_LAYERS:
					p.cover_budget=float(pass_result.remaining);p.cover_layers=int(p.get("cover_layers",0))+1
					p.cover_damage_scale=float(p.get("cover_damage_scale",1))*float(pass_result.damage_scale)
					if not p.has("cover_inside"):p.cover_inside={}
					p.cover_inside[Penetration.key(hit)]=float(p.distance)+float(hit.exit_distance)-travel
				else:p.alive=false
			event.emit({"type":"impact","position":p.position,"height":p.height,"material":hit.target.get("material",hit.type),"angle":p.direction.angle(),"normal":hit.get("normal",Vector3.ZERO),"weapon":p.weapon,"source_id":int(p.get("source",-1))})
			if float(p.weapon.get("impactBlastRadius",0))>0:
				blast(p.position,float(p.weapon.impactBlastRadius)/SCALE,float(p.weapon.get("impactBlastDamage",16)),p.weapon,p.height,int(p.get("source",-1)),p.direction);p.alive=false
			if p.alive:
				var separation=minf(.001,maxf(0,budget))
				p.position+=p.direction*separation;p.height+=float(p.get("slope",0))*separation
				p.distance+=separation;budget-=separation;p.remaining-=separation
		elif budget<=.0001:break
	if p.remaining<=.001:
		if explosive:detonate(p)
		else:p.alive=false
	if not p.alive and p.weapon.kind in ["bullet","hitscan","autocannon","canister"] and not p.get("visual_finished",false):
		p.visual_finished=true
		event.emit({"type":"round_finished","round":p})

static func falloff(w: Dictionary,distance_m: float) -> float:
	var distance=distance_m*SCALE
	var maximum=float(w.get("range",1200));var effective=float(w.get("effectiveRange",maximum*.72));var terminal=float(w.get("terminalDamageMultiplier",.6))
	return lerpf(1,terminal,smoothstep(effective,maximum,distance))

func ray(origin: Vector2,direction: Vector2,distance: float,height: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
	return trace_3d(Vector3(origin.x,height,origin.y),Vector3(direction.x,float(p.get("slope",0)),direction.y),distance,p,walls_only)

func trace_3d(origin: Vector3,direction: Vector3,distance: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
	var best: Dictionary=terrain.ray(origin,direction,distance);var limit: float=float(best.get("distance",distance));var radius: float=float(p.get("radius",0))
	var start: Vector2=Vector2(origin.x,origin.z);var travel: Vector2=Vector2(direction.x,direction.z)
	var pad: Vector3=Vector3.ONE*radius
	var segment_bounds:=AABB(origin,direction*limit).abs().grow(radius*1.732051+.0001)
	var query_end=start+travel*limit;var query_pad=maxf(.02,radius)
	for o: Dictionary in ray_candidates(start,query_end,query_pad):
		if not o.alive or not o.ballistic:continue
		if float(p.get("cover_inside",{}).get("object:"+str(o.id),-1))>float(p.get("distance",0)):continue
		if p.get("camera_pick",false) and o.get("camera_hidden",false):continue
		if o.has("trace_bounds") and not AABB(o.trace_bounds).intersects(segment_bounds):continue
		var at: Vector2=(start-Vector2(o.position)).rotated(-float(o.angle));var along: Vector2=travel.rotated(-o.angle)
		var local: Vector3=Vector3(at.x,origin.y-o.elevation,at.y);var dir: Vector3=Vector3(along.x,direction.y,along.y)
		var visible_height: float=minf(o.height,float(o.get("aim_cut_height",INF))) if p.get("camera_pick",false) else float(o.height)
		var low: Vector3=Vector3(-o.size.x*.5,0,-o.size.y*.5);var high: Vector3=Vector3(o.size.x*.5,visible_height,o.size.y*.5)
		var span: Vector2=AimGeometry.box_span(local,dir,low-pad,high+pad,limit)
		if span.x==INF:continue
		if o.has("nature_solids"):
			var natural_hit: Dictionary=NatureGeometry.ray(o,local,dir,limit,radius,p.get("cover_inside",{}),float(p.get("distance",0)))
			if not natural_hit.is_empty():
				if natural_hit.distance==limit and best.get("type","")=="object" and not later_object_tie(best.target,o,start,query_end,query_pad):continue
				limit=natural_hit.distance;var normal_2d: Vector2=Vector2(natural_hit.normal.x,natural_hit.normal.z).rotated(o.angle)
				best={"type":"object","target":o,"distance":limit,"exit_distance":natural_hit.exit_distance,"piece":natural_hit.piece,"col":0,"row":0,"normal":Vector3(normal_2d.x,natural_hit.normal.y,normal_2d.y)}
			continue
		if o.has("solid_parts"):
			var part_hit: Dictionary=HouseGeometry.hit(o,local,dir,limit,radius,p.has("weapon"),p.get("cover_inside",{}),float(p.get("distance",0)))
			if not part_hit.is_empty():
				if part_hit.distance==limit and best.get("type","")=="object" and not later_object_tie(best.target,o,start,query_end,query_pad):continue
				limit=part_hit.distance;best=part_hit;best.type="object";best.target=o
				if part_hit.has("normal"):
					var flat: Vector2=Vector2(part_hit.normal.x,part_hit.normal.z).rotated(o.angle);best.normal=Vector3(flat.x,part_hit.normal.y,flat.y)
			continue
		var segment_start: Vector3=local+dir*span.x;var segment_end: Vector3=local+dir*span.y
		var c0: int=clampi(floori((minf(segment_start.x,segment_end.x)-radius-.00001+o.size.x*.5)/o.cell_width),0,o.columns-1)
		var c1: int=clampi(floori((maxf(segment_start.x,segment_end.x)+radius+.00001+o.size.x*.5)/o.cell_width),0,o.columns-1)
		var r0: int=clampi(floori((minf(segment_start.y,segment_end.y)-radius-.00001)/o.cell_height),0,o.rows-1)
		var r1: int=clampi(floori((maxf(segment_start.y,segment_end.y)+radius+.00001)/o.cell_height),0,o.rows-1)
		for col in range(c0,c1+1):
			for row in range(r0,r1+1):
				if o.hp[row*o.columns+col]<=0 or row*o.cell_height>=visible_height:continue
				if float(p.get("cover_inside",{}).get(str(o.id)+":"+str(col)+","+str(row),-1))>float(p.get("distance",0)):continue
				low=Vector3(-o.size.x*.5+col*o.cell_width,row*o.cell_height,-o.size.y*.5)
				high=Vector3(low.x+o.cell_width,minf((row+1)*o.cell_height,visible_height),o.size.y*.5)
				var t: float=AimGeometry.box_hit(local,dir,low-pad,high+pad,limit)
				if t<=limit:
					if t==limit and best.get("type","")=="object" and not later_object_tie(best.target,o,start,query_end,query_pad):continue
					limit=t;best={"type":"object","target":o,"distance":t,"col":col,"row":row}
					if p.has("weapon"):
						best.exit_distance=AimGeometry.box_span(local,dir,low-pad,high+pad,INF).y
						var normal: Vector3=AimGeometry.box_normal(local+dir*t,low-pad,high+pad);var flat: Vector2=Vector2(normal.x,normal.z).rotated(o.angle)
						best.normal=Vector3(flat.x,normal.y,flat.y)
	for vehicle: Dictionary in vehicle_ray_candidates(start,start+travel*limit,radius*1.732051+.0001):
		if vehicle.id==int(p.get("mount",-1)):continue
		# Reject the whole ray segment against the rotation-invariant solid radius
		# before validating detailed body/turret boxes for every distant vehicle.
		var closest: Vector2=Geometry2D.get_closest_point_to_segment(vehicle.position,start,start+travel*limit)
		if not VehicleDimensions.might_contain(vehicle,closest,radius*1.732051+.0001):continue
		if not VehicleDimensions.planar_bounds(vehicle).grow(radius+.0001).intersects(Rect2(start,travel*limit).abs().grow(.0001)):continue
		for box: Dictionary in VehicleDimensions.hit_boxes(vehicle):
			var t: float=VehicleDimensions.ray(box,origin,direction,limit,pad)
			if t<=limit:limit=t;best={"type":"vehicle","target":vehicle,"distance":t}
	if walls_only:return best
	var source_id: int=int(p.get("source",-1));var team_id: int=int(p.get("team",-99));var already_hit: Array=p.get("hit",[])
	for u: Dictionary in unit_ray_candidates(start,start+travel*limit,radius):
		if not u.alive or u.id==source_id or u.team==team_id or u.id in already_hit or enclosed(u):continue
		if p.get("camera_pick",false) and u.get("camera_hidden",false):continue
		var base: Vector3=Vector3(u.position.x,u.elevation,u.position.y)
		if AimGeometry.box_hit(origin,direction,base-Vector3(1.6,.1,1.6)-pad,base+Vector3(1.6,2.2,1.6)+pad,limit)==INF:continue
		var shapes: Array=u.get("hit_shapes",[])
		var shape_origin: Vector3=origin-CombatPose.shape_translation(u) if not shapes.is_empty() else origin
		if shapes.is_empty():
			var head: Vector3=head_center(u)
			shapes=[{"a":head,"b":head,"radius":.27,"region":"head"},{"a":base+Vector3.UP*.18,"b":head-Vector3.UP*.35,"radius":.28,"region":"body"}]
		for shape: Dictionary in shapes:
			var t: float=AimGeometry.capsule_hit(shape_origin,direction,shape.a,shape.b,float(shape.radius)+radius)
			if t<=limit:limit=t;best={"type":"unit","target":u,"distance":t,"region":shape.region}
	return best

func later_object_tie(previous: Dictionary,current: Dictionary,a: Vector2,b: Vector2,pad: float) -> bool:
	if is_same(previous,current):return true
	# Only identical-distance contacts need the old first-cell insertion order.
	# Derive it from cached spans; normal rays never traverse this legacy grid.
	var delta=b-a;var cell=Vector2i(floori(a.x/4),floori(a.y/4));var end=Vector2i(floori(b.x/4),floori(b.y/4))
	var sx=1 if delta.x>=0 else -1;var sy=1 if delta.y>=0 else -1
	var dx=4/absf(delta.x) if absf(delta.x)>.000001 else INF;var dy=4/absf(delta.y) if absf(delta.y)>.000001 else INF
	var tx=((cell.x+(1 if sx>0 else 0))*4-a.x)/delta.x if dx<INF else INF
	var ty=((cell.y+(1 if sy>0 else 0))*4-a.y)/delta.y if dy<INF else INF
	var margin=ceili(maxf(0,pad-.6)/4);var serial=0;var previous_order=-1;var current_order=-1
	var pspan: Vector4i=previous.ray_index_span;var cspan: Vector4i=current.ray_index_span
	for _step in range(absi(end.x-cell.x)+absi(end.y-cell.y)+3):
		for x in range(cell.x-margin,cell.x+margin+1):
			for y in range(cell.y-margin,cell.y+margin+1):
				if previous_order<0 and x>=pspan.x and x<=pspan.y and y>=pspan.z and y<=pspan.w:previous_order=serial
				if current_order<0 and x>=cspan.x and x<=cspan.y and y>=cspan.z and y<=cspan.w:current_order=serial
				if previous_order>=0 and current_order>=0:return current_order>previous_order or (current_order==previous_order and current.collision_rank>previous.collision_rank)
				serial+=1
		if cell==end:break
		if tx<ty:cell.x+=sx;tx+=dx
		else:cell.y+=sy;ty+=dy
	return current.collision_rank>previous.collision_rank

func unit_ray_candidates(start: Vector2,end: Vector2,radius: float) -> Array:
	if not unit_ray_index.active:unit_ray_index.begin(units,profile_ai)
	return unit_ray_index.query(start,end,radius,profile_ai)

func detonate(p: Dictionary) -> void:
	if not p.alive:return
	p.alive=false
	if p.weapon.get("payload","")=="smoke":
		event.emit({"type":"smoke","position":p.position,"height":p.height,"radius":float(p.weapon.get("areaRadius",230))/SCALE,"duration":float(p.weapon.get("areaDuration",13))});return
	blast(p.position,float(p.weapon.get("blastRadius",150))/SCALE,float(p.weapon.damage),p.weapon,p.height,int(p.get("source",-1)),p.direction,p.get("contact_normal",Vector3.ZERO),str(p.get("contact_material","")))

func blast(at: Vector2,radius: float,damage: float,w: Dictionary,blast_height: float=.6,source_id: int=-1,incoming_direction: Vector2=Vector2.ZERO,contact_normal: Vector3=Vector3.ZERO,contact_material: String="") -> void:
	event.emit({"type":"explosion","position":at,"radius":radius,"weapon":w,"height":blast_height,"source_id":source_id,"direction":incoming_direction,"normal":contact_normal,"material":contact_material})
	# Sample shielding before topology changes, so targets behind a wall get cover for this blast.
	var exposure: Dictionary={}
	var affected=blast_units(at,radius,blast_height)
	for u in affected:
		var offset=Vector3(u.position.x-at.x,u.elevation+stance_height(u.stance)*.55-blast_height,u.position.y-at.y)
		var hit=trace_3d(Vector3(at.x,blast_height,at.y),offset.normalized(),offset.length(),{},true)
		exposure[u.id]=float(hit.target.get("transmission",.2)) if not hit.is_empty() else 1.0
	for u in affected:
		if not u.alive or enclosed(u):continue
		var distance=Vector3(u.position.x-at.x,u.elevation+stance_height(u.stance)*.55-blast_height,u.position.y-at.y).length()
		if distance>radius:continue
		var fall=clampf(1-distance/radius,.08,1)
		var direction=(u.position-at).normalized()
		damage_unit(u,damage*fall*exposure[u.id],Vector3(direction.x,1.4,direction.y)*minf(8,damage/45.0)*fall,w,true,false,-1,"",Vector3.INF,Vector3.ZERO,source_id)
	for vehicle in vehicle_candidates(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2)):
		var distance=INF
		for shape in VehicleDimensions.hit_boxes(vehicle):distance=minf(distance,VehicleDimensions.distance_to_shape(shape,Vector3(at.x,blast_height,at.y)))
		if distance<radius:damage_vehicle(vehicle,damage*clampf(1-distance/radius,.05,1),at,w,true)
	for o in candidates(at-Vector2.ONE*radius,at+Vector2.ONE*radius,1.0):
		if not o.alive or not o.destructible:continue
		var local=(at-o.position).rotated(-o.angle)
		if o.has("nature_solids"):
			var distance=NatureGeometry.distance_to_solid(o,Vector3(local.x,blast_height-o.elevation,local.y))
			if distance<radius:damage_cell(o,0,0,damage*clampf(1-distance/radius,.03,1)*o.blast_scale,at,true)
			continue
		for col in range(o.columns):
			var x=-o.size.x*.5+(col+.5)*o.cell_width
			var planar=Vector2(x,clampf(local.y,-o.size.y*.5,o.size.y*.5)).distance_to(local)
			for row in range(o.rows):
				var height=o.elevation+(row+.5)*o.cell_height
				var distance=sqrt(planar*planar+pow(height-blast_height,2))
				if distance<radius:damage_cell(o,col,row,damage*clampf(1-distance/radius,.03,1)*o.blast_scale,at,true)

func blast_units(at: Vector2,radius: float,height: float) -> Array:
	# Cull BEFORE shielding rays. Formerly every explosion cast a ray to every
	# soldier, including dead, enclosed and out-of-radius units that cannot be hurt.
	if not unit_ray_index.active:unit_ray_index.begin(units,profile_ai)
	var affected: Array=[]
	for u: Dictionary in unit_ray_index.tree.query(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2),true,profile_ai):
		if not u.alive or enclosed(u):continue
		var offset=Vector3(u.position.x-at.x,u.elevation+stance_height(u.stance)*.55-height,u.position.y-at.y)
		if offset.length()<=radius:affected.append(u)
	return affected

func damage_unit(u: Dictionary,amount: float,impulse: Vector3,w: Dictionary,explosive: bool,headshot: bool=false,hit_height: float=-1.0,hit_region: String="",hit_position: Vector3=Vector3.INF,hit_direction: Vector3=Vector3.ZERO,source_id: int=-1,source_epoch: int=-1) -> void:
	if not u.alive or (u.player and invulnerable):return
	if headshot and not explosive:
		amount*=2.0
		if not u.get("helmet_lost",false):
			u.helmet_lost=true
			event.emit({"type":"headshot","unit":u,"impulse":impulse})
	hits+=1;damage_total+=minf(u.health,amount);u.health=maxf(0,u.health-amount);u.hurt=.18
	if amount>0:u.healing={}
	var region="head" if headshot else "stomach" if (hit_position.is_finite() or hit_height>=0) and hit_height-u.elevation<[1.0,.70,.28][u.stance] else "body"
	if hit_region in ["leg","foot"]:region=hit_region
	Reaction.register_hit(u,impulse,region,amount,explosive)
	var incoming=hit_direction.normalized() if hit_direction.length_squared()>.0001 else impulse.normalized()
	if incoming.length_squared()<.0001:incoming=Vector3(-u.facing.x,0,-u.facing.y)
	var point=hit_position if hit_position.is_finite() else Vector3(u.position.x,hit_height if hit_height>=0 else u.elevation+stance_height(u.stance)*.55,u.position.y)
	event.emit({"type":"damage","unit":u,"amount":amount,"region":region,"direction":u.last_impact.get("direction","front"),"point":point,"incoming":incoming,"fatal":u.health<=0,"explosive":explosive,"weapon":w,"source_id":source_id,"source_epoch":source_epoch})
	if u.health<=0:
		if u.mounted>=0:
			var mount: Dictionary=vehicles[u.mounted];mount.driver=false;mount.driver_id=-1;u.mounted=-1
			if campaign_active():campaign_ai.vehicle_ai.navigation_changed(mount)
		u.alive=false;u.death_age=0;u.death_velocity=impulse;u.death_position=Vector3(u.position.x,u.elevation,u.position.y);u.death_roll=rng.randf_range(-.45,.45)
		if campaign_active():campaign.casualties[u.team]+=1
		if u.team!=player.team:kills+=1
		loot.drop_unit(self,u)
		event.emit({"type":"death","unit":u,"impulse":impulse,"explosive":explosive,"weapon":w})

func damage_object(o: Dictionary,at: Vector2,height: float,amount: float,explosive: bool,hit_col: int=-1,hit_row: int=-1,weapon: Dictionary={},distance_m: float=0,incidence: float=1,energy_scale: float=1) -> void:
	if not o.destructible or not o.alive:return
	var local=(at-o.position).rotated(-o.angle)
	var col=hit_col if hit_col>=0 else clampi(int((local.x+o.size.x*.5)/o.cell_width),0,o.columns-1)
	var row=hit_row if hit_row>=0 else clampi(int((height-o.elevation)/o.cell_height),0,o.rows-1)
	var marked=not explosive and o.hp[row*o.columns+col]>0 and TerrainStructure.mark_impact(o,col,row,local,height)
	if not explosive and not weapon.is_empty():
		if not o.whole or not CoverRules.kinetic_allowed(o,weapon,incidence):
			var structural=CoverRules.kinetic_damage(o,weapon,row*o.columns+col,distance_m,incidence)*energy_scale if not o.whole else 0.0
			if structural>0:damage_cell(o,col,row,structural,at,false)
			elif marked:
				# Cosmetic dents do not remove structure or invalidate navigation/support.
				o.revision+=1;event.emit({"type":"object_changed","object":o})
			return
	# Non-wall whole props and mechanical impacts retain their positive legacy damage
	# until their per-part durability is authored; material prohibitions above still apply.
	var multipliers={"door":2.25,"sandbag":1.65,"barrier":1.40,"bridgeRail":1.45,"ruin":1.28,"wreck":1.18,"jungle":1.22,"tree":1.42,"concrete":.52,"compound":.42,"building":.28,"bunker":.14,"ridge":.34}
	damage_cell(o,col,row,amount*(o.blast_scale if explosive else float(multipliers.get(o.kind,.36))),at,explosive)

func damage_cell(o: Dictionary,col: int,row: int,amount: float,origin: Vector2,explosive: bool) -> void:
	var index=row*o.columns+col
	if not o.alive or not o.destructible or o.hp[index]<=0 or amount<=0:return
	var previous=float(o.hp[index]);o.hp[index]=maxf(0,previous-amount)
	if o.hp[index]<float(o.max_hp)*.000001:o.hp[index]=0.0
	o.revision+=1
	event.emit({"type":"object_changed","object":o})
	if o.hp[index]<=0:
		broken+=1;topology_revision+=1;navigation_dirty=true
		if campaign_active():campaign_ai.invalidate_object(o,col)
		if not o.whole:support_dirty[o.id]={"object":o,"origin":origin}
		var local=Vector2(-o.size.x*.5+(col+.5)*o.cell_width,0)
		var at: Vector2=o.position+local.rotated(o.angle)
		event.emit({"type":"fracture","object":o,"position":at,"height":o.elevation+(row+.5)*o.cell_height,"size":Vector3(o.cell_width,o.cell_height,o.size.y),"origin":origin,"explosive":explosive})
		o.alive=o.hp.any(func(h):return h>0)
		if not o.alive and o.component_id=="prop.barrel":
			# Mark destroyed before chain blast; prevents recursive re-detonation.
			blast(o.position,3.5,180,{"kind":"shell","name":"燃料桶","blastStyle":"fuel"})

func resolve_support() -> void:
	# Grid connectivity preserves supported lintels and drops detached wall islands.
	var dirty=support_dirty.values();support_dirty.clear()
	for entry in dirty:
		var o: Dictionary=entry.object
		if not o.alive or not o.destructible:continue
		var connected: Dictionary={};var queue: Array=[]
		for col in range(o.columns):
			var foot: Vector2=o.position+Vector2(-o.size.x*.5+(col+.5)*o.cell_width,0).rotated(o.angle)
			var supported=not o.get("house",false) or o.get("storey",0)==0 or HouseSupport.supported(self,o,foot)
			if o.hp[col]>0 and supported:connected[col]=true;queue.append(col)
		var cursor=0
		while cursor<queue.size():
			var index=int(queue[cursor]);cursor+=1;var col=index%o.columns;var row=int(index/o.columns)
			for neighbor in [Vector2i(col-1,row),Vector2i(col+1,row),Vector2i(col,row-1),Vector2i(col,row+1)]:
				if neighbor.x<0 or neighbor.x>=o.columns or neighbor.y<0 or neighbor.y>=o.rows:continue
				var at=neighbor.y*o.columns+neighbor.x
				if o.hp[at]>0 and not connected.has(at):connected[at]=true;queue.append(at)
		for index in range(o.hp.size()):
			if o.hp[index]>0 and not connected.has(index):damage_cell(o,index%o.columns,int(index/o.columns),o.max_hp+1,entry.origin,false)
		support_dirty.erase(o.id)

func damage_vehicle(v: Dictionary,amount: float,source: Vector2,w: Dictionary,explosive: bool) -> void:
	if v.destroyed:return
	var relative=wrapf((source-v.position).angle()-v.angle,-PI,PI)
	var sector="front" if absf(relative)<PI*.25 else ("rear" if absf(relative)>PI*.75 else "side")
	var armored=not v.emplacement and v.type!="armedJeep"
	var anti_tank=w.get("name","") in ["Anti-Tank Launcher","RPG"]
	var applied=amount
	if not explosive and w.kind not in ["autocannon","canister"]:applied=minf(applied,v.max_health*.28/maxi(1,int(w.get("pellets",1))))
	if anti_tank:applied*=3.5*((.72 if sector=="front" else 1.2 if sector=="rear" else 1.0) if armored else 1.0)
	elif not v.emplacement:
		applied*=float(v.profile.armor.get(sector,.72))
		if armored and not explosive:
			if w.kind=="autocannon":applied*=.62 if v.type=="lightTank" else .44 if v.type in ["tank","heavyTank"] else .72 if v.type=="ifv" else .92
			elif amount>=90:applied*=.46 if v.type=="lightTank" else .32 if v.type in ["tank","heavyTank"] else .58
			else:applied*=float(v.profile.get("smallArmsMultiplier",.28))
	if v.max_track>0 and (explosive or amount>=65 or w.kind=="autocannon"):
		if rng.randf()<(.72 if sector=="side" else .38 if sector=="rear" else .18):v.track_health=maxf(0,v.track_health-amount*(.42 if explosive else .20))
	v.health=maxf(0,v.health-applied)
	event.emit({"type":"vehicle_damage","vehicle":v,"amount":applied})
	if v.health<=0:
		v.destroyed=true;v.speed=0;v.destroy_time=time
		if not v.emplacement:
			var falling=float(v.get("fall_speed",0));var airborne=bool(v.get("airborne",false));var descending=bool(v.get("descending",false))
			VehicleDynamics.reset(v);v.fall_speed=falling;v.airborne=airborne;v.descending=descending
		if player.mounted==v.id:leave_vehicle(true)
		if campaign_active():campaign_ai.vehicle_ai.destroyed(v)
		event.emit({"type":"vehicle_destroyed","vehicle":v})
		blast(v.position,float(v.profile.get("effects",{}).get("radius",160))/SCALE,145,{"kind":"shell","name":"载具殉爆","vehicle_detonation":true},float(v.get("elevation",0))+.6)

func build_index() -> void:
	obstacle_grid.clear();obstacle_query_cache.clear();body_grid.clear()
	var extent=Rect2(-bounds,bounds*2)
	for o in objects:
		var half=Vector2(absf(cos(o.angle))*o.size.x+absf(sin(o.angle))*o.size.y,absf(sin(o.angle))*o.size.x+absf(cos(o.angle))*o.size.y)*.5
		extent=extent.merge(Rect2(o.position-half,half*2))
	obstacle_tree.reset(extent);vehicle_tree.reset(extent,2.0);vehicle_tree_count=-1
	obstacle_marks.resize(objects.size());obstacle_marks.fill(0);obstacle_query_serial=0
	var rank=0
	for o in objects:
		var half=Vector2(absf(cos(o.angle))*o.size.x+absf(sin(o.angle))*o.size.y,absf(sin(o.angle))*o.size.x+absf(cos(o.angle))*o.size.y)*.5+Vector2.ONE*.6
		var unpadded: Vector2=half-Vector2.ONE*.6
		o.collision_rank=rank;o.ray_index_span=Vector4i(floori((o.position.x-half.x)/4),floori((o.position.x+half.x)/4),floori((o.position.y-half.y)/4),floori((o.position.y+half.y)/4))
		o.trace_bounds=AABB(Vector3(o.position.x-unpadded.x,o.elevation,o.position.y-unpadded.y),Vector3(unpadded.x*2,o.height,unpadded.y*2))
		obstacle_tree.update(rank,Rect2(o.position-unpadded,unpadded*2),o);rank+=1
		# Radius <= .6 queries use one 1 m cell; bounds include that radius.
		for x in range(floori(o.position.x-half.x),floori(o.position.x+half.x)+1):
			for y in range(floori(o.position.y-half.y),floori(o.position.y+half.y)+1):
				var cell=Vector2i(x,y)
				if not body_grid.has(cell):body_grid[cell]=[]
				body_grid[cell].append(o)
		# Tight bullet segments retain the bounded grid fast path. Wide/long rays,
		# blasts and vehicle queries use the tree, rather than expanding this grid.
		var span: Vector4i=o.ray_index_span
		for x in range(span.x,span.y+1):
			for y in range(span.z,span.w+1):
				var cell=Vector2i(x,y)
				if not obstacle_grid.has(cell):obstacle_grid[cell]=[]
				obstacle_grid[cell].append(o)

func body_candidates(point: Vector2,radius: float) -> Array:
	if radius<=.6:return body_grid.get(Vector2i(floori(point.x),floori(point.y)),[])
	return candidates(point,point,radius)

func build_unit_index():
	unit_grid_active=true
	unit_ray_index.begin(units,profile_ai)
	for unit in units:
		index_unit(unit)

func index_unit(unit: Dictionary):
	# Client prediction works on a cloned unit; only authority belongs in the tree.
	if int(unit.id)<0 or int(unit.id)>=units.size() or not is_same(units[int(unit.id)],unit):return
	if unit_ray_index.entries.size()!=units.size():unit_ray_index.begin(units,profile_ai)
	unit_ray_index.update(unit)
	if not unit_grid_active:return
	var cell=Vector2i(floori(unit.position.x/2),floori(unit.position.y/2))
	if unit.get("steering_cell",Vector2i(2147483647,2147483647))==cell:return
	if unit.has("steering_cell"):
		var previous: Array=unit_grid.get(unit.steering_cell,[]);previous.erase(unit)
	unit.steering_cell=cell
	if not unit_grid.has(cell):unit_grid[cell]=[]
	unit_grid[cell].append(unit)

func nearby_units(point: Vector2,radius: float) -> Array:
	if not unit_grid_active or radius>2:
		return unit_ray_index.nearby(point,radius) if not unit_ray_index.tree.nodes.is_empty() else units
	var found: Array=[]
	for x in range(floori((point.x-radius)/2),floori((point.x+radius)/2)+1):
		for y in range(floori((point.y-radius)/2),floori((point.y+radius)/2)+1):
			found.append_array(unit_grid.get(Vector2i(x,y),[]))
	return found

func candidates(a: Vector2,b: Vector2,pad: float) -> Array:
	# Static geometry shares conservative 1 m query tiles. HP remains live in
	# the returned object references; destruction does not require rebuilding.
	var low=a.min(b)-Vector2.ONE*(pad+.0001);var high=a.max(b)+Vector2.ONE*(pad+.0001)
	var key=Vector4i(floori(low.x),floori(high.x),floori(low.y),floori(high.y))
	if obstacle_query_cache.has(key):return obstacle_query_cache[key]
	var found=obstacle_tree.query(Rect2(key.x,key.z,key.y-key.x+1,key.w-key.z+1),true,profile_ai)
	if obstacle_query_cache.size()>=1024:obstacle_query_cache.clear()
	obstacle_query_cache[key]=found
	return found

func ray_candidates(a: Vector2,b: Vector2,pad: float) -> Array:
	if pad*1.732051<=.6:
		var cell=Vector2i(floori(a.x),floori(a.y))
		if cell==Vector2i(floori(b.x),floori(b.y)):return body_grid.get(cell,[])
	if pad*1.732051<=.6 and a.distance_squared_to(b)<=576:return short_obstacle_ray(a,b)
	return obstacle_tree.segment(a,b,pad*1.732051+.0001,true,profile_ai)

func short_obstacle_ray(a: Vector2,b: Vector2) -> Array:
	obstacle_query_serial+=1
	if obstacle_query_serial>=2147483647:obstacle_marks.fill(0);obstacle_query_serial=1
	var result: Array=[];var delta=b-a
	var cell=Vector2i(floori(a.x/4),floori(a.y/4));var end=Vector2i(floori(b.x/4),floori(b.y/4))
	var sx=1 if delta.x>=0 else -1;var sy=1 if delta.y>=0 else -1
	var dx=4/absf(delta.x) if absf(delta.x)>.000001 else INF;var dy=4/absf(delta.y) if absf(delta.y)>.000001 else INF
	var tx=((cell.x+(1 if sx>0 else 0))*4-a.x)/delta.x if dx<INF else INF
	var ty=((cell.y+(1 if sy>0 else 0))*4-a.y)/delta.y if dy<INF else INF
	for _step in range(absi(end.x-cell.x)+absi(end.y-cell.y)+3):
		for o: Dictionary in obstacle_grid.get(cell,[]):
			var rank: int=o.collision_rank
			if obstacle_marks[rank]!=obstacle_query_serial:obstacle_marks[rank]=obstacle_query_serial;result.append(o)
		if cell==end:break
		if tx<ty:cell.x+=sx;tx+=dx
		else:cell.y+=sy;ty+=dy
	return result

func sync_vehicle_index():
	if vehicle_tree.nodes.is_empty():vehicle_tree.reset(Rect2(-bounds-Vector2.ONE*8,bounds*2+Vector2.ONE*16),2.0)
	if vehicle_tree_count!=vehicles.size():
		vehicle_tree.reset(Rect2(-bounds-Vector2.ONE*8,bounds*2+Vector2.ONE*16),2.0);vehicle_tree_count=vehicles.size()
		for v in vehicles:index_vehicle(v)

func index_vehicle(v: Dictionary):
	if vehicles.size()<=4:return
	if int(v.id)<0 or int(v.id)>=vehicles.size() or not is_same(vehicles[int(v.id)],v):return
	if vehicle_tree_count!=vehicles.size():sync_vehicle_index();return
	VehicleDimensions.might_contain(v,v.position,0)
	var radius=float(v.body_query_radius)
	vehicle_tree.update(v.id,Rect2(v.position-Vector2.ONE*radius,Vector2.ONE*radius*2),v,.3)

func vehicle_candidates(bounds_rect: Rect2) -> Array:
	if vehicles.size()<=4:return vehicles
	sync_vehicle_index();return vehicle_tree.query(bounds_rect,true,profile_ai)

func vehicle_ray_candidates(a: Vector2,b: Vector2,pad: float) -> Array:
	if vehicles.size()<=4:return vehicles
	sync_vehicle_index();return vehicle_tree.segment(a,b,pad,true,profile_ai)

func blocked(point: Vector2,radius: float=.3,height: float=1.8,ignore_vehicle: int=-1,base_height: float=0) -> bool:
	return collision_depth(point,radius,height,ignore_vehicle,base_height,true)>Traversal.COLLISION_SKIN

static func circle_rect_depth(point: Vector2,left: float,right: float,half_depth: float,radius: float) -> float:
	var closest: Vector2=Vector2(clampf(point.x,left,right),clampf(point.y,-half_depth,half_depth))
	var distance: float=point.distance_to(closest)
	if distance>0:return maxf(0,radius-distance)
	return radius+minf(minf(point.x-left,right-point.x),half_depth-absf(point.y))

func collision_depth(point: Vector2,radius: float,height: float,ignore_vehicle: int=-1,base_height: float=0,first_only: bool=false) -> float:
	var depth: float=maxf(maxf(0,terrain.height(point)-base_height-.002),maxf(absf(point.x)+radius-bounds.x,absf(point.y)+radius-bounds.y))
	if first_only and depth>Traversal.COLLISION_SKIN:return depth
	for o: Dictionary in body_candidates(point,radius):
		if not o.alive or not o.collision or o.elevation>=base_height+height-.001 or o.elevation+o.height<=base_height+.001:continue
		var local: Vector2=(point-Vector2(o.position)).rotated(-float(o.angle))
		var half: Vector2=Vector2(o.size)*.5
		if absf(local.y)>half.y+radius or absf(local.x)>half.x+radius:continue
		if o.has("nature_solids"):
			var overlap=NatureGeometry.depth(o,local,radius,base_height-o.elevation,height)
			if first_only and overlap>Traversal.COLLISION_SKIN:return overlap
			depth=maxf(depth,overlap);continue
		if o.has("solid_parts"):
			var overlap=HouseGeometry.depth(o,local,radius,base_height-o.elevation,height)
			if first_only and overlap>Traversal.COLLISION_SKIN:return overlap
			depth=maxf(depth,overlap);continue
		var columns: int=o.columns;var width: float=o.cell_width;var cell_height: float=o.cell_height
		var elevation: float=o.elevation;var hp: Array=o.hp
		var c0:=clampi(int((local.x-radius+half.x)/width),0,columns-1)
		var c1:=clampi(int((local.x+radius+half.x)/width),0,columns-1)
		var first_row:=maxi(0,floori((base_height-elevation+.001)/cell_height))
		var last_row:=mini(o.rows,ceili((base_height+height-elevation-.001)/cell_height))
		for col: int in range(c0,c1+1):
			var left: float=-half.x+col*width
			var overlap: float=circle_rect_depth(local,left,left+width,half.y,radius)
			if overlap<=Traversal.COLLISION_SKIN:continue
			for row: int in range(first_row,last_row):
				if hp[row*columns+col]>0:
					if first_only:return overlap
					depth=maxf(depth,overlap);break
	for vehicle: Dictionary in vehicle_candidates(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2)):
		if vehicle.id==ignore_vehicle:continue
		# -2 is used only by the infantry navigation graph. Physical collision and
		# rays still see the vehicle; mobile AI uses bounded local avoidance.
		if ignore_vehicle==-2 and vehicle.get("ai_controlled",false) and vehicle.driver and not vehicle.emplacement and not vehicle.destroyed:continue
		var contact: Dictionary=VehiclePersonContact.contact(vehicle,point,radius,base_height,height,first_only)
		if contact.is_empty():continue
		if first_only:return contact.depth
		depth=maxf(depth,contact.depth)
	return depth

func ground_height(point: Vector2,radius: float,below: float,support_filter: Callable=Callable()) -> float:
	var top: float=terrain.height(point)
	for o: Dictionary in body_candidates(point,radius):
		if not o.alive or not o.collision or o.get("campaign_water",false):continue
		if support_filter.is_valid() and not support_filter.call(o):continue
		var local: Vector2=(point-Vector2(o.position)).rotated(-float(o.angle))
		if absf(local.y)>o.size.y*.5+radius or absf(local.x)>o.size.x*.5+radius:continue
		if o.has("nature_solids"):
			var support: float=NatureGeometry.support(o,local,radius,below-o.elevation)
			if support>-INF:top=maxf(top,o.elevation+support)
			continue
		if o.has("solid_parts"):
			var support: float=HouseGeometry.support(o,local,radius,below-o.elevation)
			if support>-INF:top=maxf(top,o.elevation+support)
			continue
		var half: Vector2=Vector2(o.size)*.5
		var width: float=o.cell_width;var height: float=o.cell_height;var elevation: float=o.elevation
		var columns: int=o.columns;var rows: int=o.rows;var hp: Array=o.hp
		var c0:=clampi(int((local.x-radius+half.x)/width),0,columns-1)
		var c1:=clampi(int((local.x+radius+half.x)/width),0,columns-1)
		for col: int in range(c0,c1+1):
			var left: float=-half.x+col*width
			if circle_rect_depth(local,left,left+width,half.y,radius)<=Traversal.COLLISION_SKIN:continue
			for row: int in range(rows):
				var cell_top: float=elevation+(row+1)*height
				if hp[row*columns+col]>0 and cell_top<=below:top=maxf(top,cell_top)
	if support_filter.is_valid():return top
	for v: Dictionary in vehicle_candidates(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2)):
		if not VehicleDimensions.might_contain(v,point,radius+.0001):continue
		if not VehicleDimensions.planar_bounds(v).grow(radius+.0001).has_point(point):continue
		for box: Dictionary in VehicleDimensions.hit_boxes(v):
			var local: Vector2=(point-Vector2(box.center)).rotated(-float(box.angle));var half: Vector2=box.half
			if circle_rect_depth(local,-half.x,half.x,half.y,radius)<=Traversal.COLLISION_SKIN:continue
			var span=VehicleDimensions.vertical_span(box,point,radius)
			if span.x<=span.y and below>=span.y-.001:top=maxf(top,span.y)
	return top

func terrain_only_motion(a: Vector2,b: Vector2,radius: float) -> bool:
	# The 1 m body grid already expands every object by .6 m. Cover the entire
	# axis-separated sweep, including intermediate corners; any solid falls back
	# to the original detailed queries. No cached vehicle pose or height sampling.
	if radius>.6:return false
	for x in range(floori(minf(a.x,b.x)),floori(maxf(a.x,b.x))+1):
		for y in range(floori(minf(a.y,b.y)),floori(maxf(a.y,b.y))+1):
			for o in body_grid.get(Vector2i(x,y),[]):
				if o.alive and o.collision:return false
	var middle=(a+b)*.5;var padding=a.distance_to(b)*.5+radius+.0001
	for v in vehicle_candidates(Rect2(a,b-a).abs().grow(radius+.0001)):
		if VehicleDimensions.might_contain(v,middle,padding):return false
	return true

func move_unit(u: Dictionary,velocity: Vector2,delta: float,acceleration: float=8) -> void:
	if float(u.get("vehicle_stagger",0))>0:velocity*=.35
	var height: float=collision_height(u)
	var requested: Vector2=Vector2(u.requested_velocity).move_toward(velocity,delta*(acceleration if velocity.length_squared()>.01 else 13))
	var terrain_only: bool=terrain_only_motion(u.position,Vector2(u.position)+requested*delta,Traversal.RADIUS)
	var position: Vector2=u.position;var elevation: float=u.elevation
	var ground: float=terrain.height(position)
	var clear: bool=not blocked(position,Traversal.RADIUS,height,-1,elevation) if not terrain_only else maxf(maxf(0,ground-elevation-.002),maxf(absf(position.x)+Traversal.RADIUS-bounds.x,absf(position.y)+Traversal.RADIUS-bounds.y))<=Traversal.COLLISION_SKIN
	if not clear:Traversal.recover_overlap(self,u)
	# Recovery can change both origin and requested speed; preserve that exact order.
	if not clear:
		position=u.position;elevation=u.elevation;ground=terrain.height(position)
		requested=Vector2(u.requested_velocity).move_toward(velocity,delta*(acceleration if velocity.length_squared()>.01 else 13))
		terrain_only=terrain_only_motion(position,position+requested*delta,Traversal.RADIUS)
	u.requested_velocity=requested
	var p: Vector2=u.position
	var step: Vector2=requested*delta
	var steps: int=maxi(1,ceili(step.length()/.10));step/=steps
	var grounded: bool=u.grounded
	for i: int in range(steps):
		for axis: int in range(2):
			var offset:=Vector2(step.x,0) if axis==0 else Vector2(0,step.y)
			if offset==Vector2.ZERO:continue
			var next: Vector2=position+offset;var base: float=elevation
			var terrain_top: float=terrain.height(next)
			if grounded:
				var support: float=terrain_top if terrain_only else ground_height(next,Traversal.RADIUS,base+.221)
				var on_surface: bool=absf(base-ground)<.03
				if on_surface and support<=terrain_top+.01 and not terrain.walkable_with_heights(position,next,ground,terrain_top):continue
				if absf(support-base)<=.221:base=support
			var obstructed: bool
			if terrain_only:
				obstructed=maxf(maxf(0,terrain_top-base-.002),maxf(absf(next.x)+Traversal.RADIUS-bounds.x,absf(next.y)+Traversal.RADIUS-bounds.y))>Traversal.COLLISION_SKIN
			else:obstructed=blocked(next,Traversal.RADIUS,height,-1,base)
			if not obstructed:position=next;elevation=base;ground=terrain_top;clear=true
	u.position=position;u.elevation=elevation
	u.velocity=(position-p)/maxf(delta,.0001)
	if grounded:
		var previous_step=floori(u.walk/PI)
		u.walk+=u.velocity.length()*delta*TAU/(Traversal.stride(u.velocity.length())*(.7 if u.stance==1 else 1.0))
		if floori(u.walk/PI)!=previous_step and u.stance<2 and absf(elevation-ground)<.08:
			var forward: Vector2=u.velocity.normalized();var side=Vector2(-forward.y,forward.x)
			event.emit({"type":"terrain_step","unit":u,"position":u.position+side*(.13 if floori(u.walk/PI)%2==0 else -.13),"forward":forward})
	if clear:u.last_clear={"position":u.position,"elevation":u.elevation}
	else:Traversal.remember_clear(self,u)
	index_unit(u)

func enter_vehicle(index: int) -> bool:
	if index<0 or index>=vehicles.size() or vehicles[index].driver:return false
	if player.mounted>=0:leave_vehicle(true)
	cancel_firing()
	return mount_unit(player,index)

func mount_unit(unit: Dictionary,index: int) -> bool:
	if index<0 or index>=vehicles.size() or vehicles[index].destroyed:return false
	if vehicles[index].driver or unit.mounted>=0 or not unit.alive or not unit.grounded or not unit.vault.is_empty() or not unit.ladder.is_empty():return false
	var destination: Vector2=Emplacement.operator_position(vehicles[index]) if vehicles[index].emplacement else vehicles[index].position
	var mortar=vehicles[index].type==PortableMortar.KIND
	var destination_height: float=PortableMortar.operator_height(self,vehicles[index],destination) if vehicles[index].emplacement else float(vehicles[index].get("elevation",0))
	if mortar:
		if unit.position.distance_to(vehicles[index].position)>2.2 or absf(float(unit.elevation)-destination_height)>.35:return false
		var start=Vector3(unit.position.x,unit.elevation+.7,unit.position.y);var line=Vector3(destination.x,destination_height+.7,destination.y)-start
		if not trace_3d(start,line.normalized(),line.length(),{"mount":index},true).is_empty():return false
		for i in range(1,9):
			var t=float(i)/8
			if blocked(unit.position.lerp(destination,t),Traversal.RADIUS,stance_height(1),index,lerpf(unit.elevation,destination_height,t)):return false
	if vehicles[index].emplacement and (absf(destination_height-float(vehicles[index].get("elevation",0)))>.35 or blocked(destination,Traversal.RADIUS,stance_height(1 if mortar else 0),index,destination_height)):return false
	Traversal.reset(unit);unit.mounted=index;vehicles[index].driver=true;vehicles[index].driver_id=unit.id
	vehicles[index].ai_mounted_at=time
	if campaign_active():campaign_ai.vehicle_ai.navigation_changed(vehicles[index])
	unit.position=destination;unit.velocity=Vector2.ZERO;unit.requested_velocity=Vector2.ZERO;unit.stance=0;unit.stance_blend=0.0;unit.elevation=destination_height
	if mortar:unit.stance=1;unit.stance_blend=1.0
	unit.path=[];unit.aim_valid=false;unit.healing={};ThrowControl.cancel(unit);Melee.cancel(unit);FireControl.cancel(unit,true)
	FireControl.cancel(vehicles[index].states[vehicles[index].modes[vehicles[index].mode]],true)
	index_unit(unit)
	if unit.player:event.emit({"type":"mount","vehicle":vehicles[index]})
	return true

func nearest_vehicle() -> int:
	var index=-1;var nearest=3.5
	for v in vehicles:
		var distance=player.position.distance_to(v.position)
		if v.type==PortableMortar.KIND and (distance>2.2 or absf(float(player.elevation)-float(v.elevation))>.35):continue
		if not v.destroyed and not v.driver and distance<nearest:nearest=distance;index=v.id
	return index

func interact_vehicle() -> void:
	if not player.alive:return
	if player.mounted>=0:leave_vehicle();return
	if not player.grounded or not player.vault.is_empty():return
	var index=nearest_vehicle()
	if index>=0:enter_vehicle(index)
	else:event.emit({"type":"notice","text":"靠近载具按 F；也可在载具列表中选择“试驾”"})

func leave_vehicle(force: bool=false) -> bool:
	if player.mounted<0:return true
	cancel_firing()
	var v: Dictionary=vehicles[player.mounted]
	if v.type==PortableMortar.KIND and not blocked(player.position,Traversal.RADIUS,stance_height(1),-1,player.elevation):
		var height: float=player.elevation
		player.mounted=-1;v.driver=false;v.driver_id=-1;player.stance=1;player.stance_blend=1.0
		Traversal.reset(player);player.elevation=height;index_unit(player);event.emit({"type":"dismount"});return true
	if v.emplacement and not blocked(player.position,Traversal.RADIUS,stance_height(0),-1,player.elevation):
		player.mounted=-1;v.driver=false;v.driver_id=-1;player.stance=0;player.stance_blend=0.0
		if campaign_active():campaign_ai.vehicle_ai.navigation_changed(v)
		Traversal.reset(player);index_unit(player);event.emit({"type":"dismount"});return true
	for i in range(16):
		var direction=Vector2.from_angle(v.angle+PI*.5+float(i)*TAU/16)
		var point=VehicleDimensions.exit_point(v,direction,Traversal.RADIUS+.28)
		var ground=ground_height(point,Traversal.RADIUS,float(v.get("elevation",0))+.65)
		if terrain.grade(point)<.80 and not blocked(point,Traversal.RADIUS,stance_height(0),-1,ground):
			player.position=point;player.mounted=-1;v.driver=false;v.driver_id=-1;player.stance=0;player.stance_blend=0.0
			if campaign_active():campaign_ai.vehicle_ai.navigation_changed(v)
			Traversal.reset(player);player.elevation=ground;index_unit(player);event.emit({"type":"dismount"});return true
	if force:
		player.position=player.spawn;player.mounted=-1;v.driver=false;v.driver_id=-1;player.stance=0;player.stance_blend=0.0
		if campaign_active():campaign_ai.vehicle_ai.navigation_changed(v)
		Traversal.reset(player);player.elevation=terrain.height(player.position);index_unit(player);return true
	event.emit({"type":"notice","text":"两侧被挡住，移动载具后再下车"});return false

func drive(v: Dictionary,throttle: float,steer: float,delta: float,brake: bool=false,boost: bool=false,parking: bool=false) -> void:
	VehicleDynamics.update(self,v,throttle,steer,delta,brake,boost,parking)
	index_vehicle(v)

func vehicle_blocked(v: Dictionary,position: Vector2) -> bool:
	if position==v.position:return VehicleCollision.blocked(self,v)
	var probe=v.duplicate();probe.position=position
	VehicleGround.initialize(terrain,probe,self)
	return VehicleCollision.blocked(self,probe)

func rebuild_navigation() -> void:
	if campaign_active():
		campaign_ai.rebuild(6);navigation_dirty=not campaign_ai.dirty_cells.is_empty() or not campaign_ai.refresh_edges.is_empty();nav_time=0.0 if navigation_dirty else .6;return
	navigation=AStarGrid2D.new()
	var dims=Vector2i(ceili(bounds.x),ceili(bounds.y))
	navigation.region=Rect2i(-dims,dims*2+Vector2i.ONE)
	navigation.cell_size=Vector2.ONE
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(-dims.x,dims.x+1):
		for y in range(-dims.y,dims.y+1):
			if terrain.grade(Vector2(x,y))>.82 or blocked(Vector2(x,y),.28,1.95,-1,terrain.height(Vector2(x,y))):navigation.set_point_solid(Vector2i(x,y))
	navigation_dirty=false;nav_time=.3

func update_ai(u: Dictionary,delta: float) -> void:
	# Friendly showcase soldiers hold their station when the user enables red retaliation.
	if u.team==player.team:u.velocity=Vector2.ZERO;FireControl.cancel(u);return
	u.brain-=delta;u.repath-=delta
	var direction: Vector2=player.position-u.position
	u.facing=direction.normalized()
	u.aim_valid=true;u.aim_height=player.elevation+stance_height(player.stance)*.65
	var request=false
	if u.brain<=0:
		u.brain=.6+rng.randf()*.3
		request=true;u.ai_fire_time=.18
	u.ai_fire_time=maxf(0,float(u.get("ai_fire_time",0))-delta)
	var allowed=direction.length()<28 and player.alive and u.vault.is_empty() and u.ladder.is_empty()
	if FireControl.wants_shot(u,weapon_for(u),u.ai_fire_time>0,request,allowed):fire(u,weapon_for(u),u,u.position,u.facing.angle(),muzzle_height(u),player.position)
	if direction.length()>7 and navigation.is_in_boundsv(Vector2i(u.position.round())) and navigation.is_in_boundsv(Vector2i(player.position.round())):
		if u.repath<=0:
			u.repath=1+rng.randf();u.path=Array(navigation.get_point_path(Vector2i(u.position.round()),Vector2i(player.position.round())))
		while not u.path.is_empty() and u.position.distance_to(u.path[0])<.35:u.path.pop_front()
		if not u.path.is_empty():move_unit(u,(u.path[0]-u.position).normalized()*1.8,delta)
	else:move_unit(u,Vector2.ZERO,delta)
