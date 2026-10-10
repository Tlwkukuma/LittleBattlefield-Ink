extends Node3D
const Art=preload("res://scripts/ink_art.gd")
const Motion=preload("res://scripts/soldier_motion.gd")
const Props=preload("res://scripts/proving_art.gd")
const TerrainEffects=preload("res://scripts/terrain_effects.gd")
const WeaponProfile=preload("res://scripts/weapon_profile.gd")
const Reaction=preload("res://scripts/combat_reaction.gd")
const VehicleFlight=preload("res://scripts/vehicle_impact_motion.gd")
const WeaponEffects=preload("res://scripts/weapon_effects.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
const Magazine=preload("res://scripts/weapon_magazine.gd")
const Ejection=preload("res://scripts/weapon_ejection.gd")
const CaseMotion=preload("res://scripts/spent_case_motion.gd")
const Particle=preload("res://scripts/fx_particle_state.gd")
const MountedCases=preload("res://scripts/mounted_cases.gd")
const Blood=preload("res://scripts/blood_effects.gd")
const Classes=preload("res://scripts/soldier_classes.gd")
var blood
var puffs
var cosmetic_shots: Dictionary={}
var flying_cases: int=0
var case_motion=CaseMotion.new()
var case_sound_cooldown=0.0
var footprints
var vehicle_tracks
var vehicle_destruction
var explosions
var blast_marks
var feedback
var blast_cue_frame=-1
var blast_cues=0
var retained_cases: Dictionary={}
var particles: Array[Particle]=[]
var corpses: Array=[]
var helmets: Array=[]
var delayed: Array=[]
var rng=RandomNumberGenerator.new()
var silent=false
var muted=false
var catalog
var world
var camera: Camera3D
var actor_views: Array=[]
var meshes: Dictionary={}
var materials: Dictionary={}
var last_process_ms=0.0
var last_profile: Dictionary={}
var instance_batches
var support_stamp=0
var support_cursor=0
var support_checks=0
var support_pending=false
var support_scanned=0
var pixel_scale=-1.0
var case_scales: Dictionary={}
var particle_sequence=0
var crowd_batches
var rigid_batches
var corpse_pool: Array=[]
var warmup_handles: Array=[]

func prewarm(units: Array):
	for index in range(18):
		var unit: Dictionary=units[index%units.size()];var view=Art.soldier(self,int(unit.team),false,false)
		Classes.apply(view,str(unit.get("class_id","assault")),int(unit.team));view.root.hide();corpse_pool.append(view)
	var seen={};var handles=[]
	for unit in units:
		if seen.has(unit.weapon_id):continue
		seen[unit.weapon_id]=true
		var profile=Ammo.profile(catalog.weapons[unit.weapon_id])
		var pose=Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
		handles.append(instance_batches.add_case(WeaponEffects.battle_casing_mesh(profile),WeaponEffects.outlined_material(Color.WHITE,true),pose))
		var weapon: Dictionary=catalog.weapons[unit.weapon_id]
		if Magazine.profile(weapon).detachable:
			var magazine=Magazine.build(self,weapon)
			for child in magazine.get_children():
				if child is MeshInstance3D:handles.append(instance_batches.add_magazine(child.mesh,child.material_override,pose,child.transform))
			magazine.free()
	# Submit zero-area instances during startup so real GL shader variants compile
	# before the player's first shot/reload; then release all warm-up slots.
	warmup_handles=handles
	RenderingServer.frame_post_draw.connect(finish_warmup,CONNECT_ONE_SHOT)

func finish_warmup():
	instance_batches.release(warmup_handles)

func _ready():
	rng.seed=937
	instance_batches=preload("res://scripts/fx_instance_batches.gd").new()
	if world!=null:instance_batches.bounds=AABB(Vector3(-world.bounds.x-8,-64,-world.bounds.y-8),Vector3(world.bounds.x*2+16,256,world.bounds.y*2+16))
	add_child(instance_batches)
	puffs=preload("res://scripts/battle_puffs.gd").new()
	if world!=null:puffs.bounds=world.bounds
	add_child(puffs)
	blood=Blood.new();blood.world=world;blood.camera=camera;add_child(blood)
	footprints=preload("res://scripts/terrain_footprints.gd").new();footprints.world=world;add_child(footprints)
	vehicle_tracks=preload("res://scripts/vehicle_ground_effects.gd").new();vehicle_tracks.world=world;add_child(vehicle_tracks)
	vehicle_destruction=preload("res://scripts/vehicle_destruction_fx.gd").new();vehicle_destruction.world=world;add_child(vehicle_destruction)
	explosions=preload("res://scripts/explosion_fx.gd").new();explosions.world=world;explosions.camera=camera;add_child(explosions)
	blast_marks=preload("res://scripts/blast_marks.gd").new();blast_marks.world=world;blast_marks.camera=camera;add_child(blast_marks)
	feedback=preload("res://scripts/combat_feedback.gd").new();feedback.world=world;feedback.camera=camera;add_child(feedback)
	WeaponEffects.casing_mesh()
	# CombatAudio preloads the licensed foley palette; no procedural legacy sounds.

func sound(key: String,pitch: float=1.0,gain: float=1.0):
	if silent or muted or feedback==null:return
	feedback.audio.play(key,Vector3(world.player.position.x,world.player.elevation+1,world.player.position.y),.15,pitch,gain*.45,false,"detail/"+key)

func piece(at: Vector3,size: Vector3,color: Color,velocity: Vector3,life: float=4,round_shape: bool=false,gravity: float=9.8,kind: String="debris",presentation: Dictionary={}) -> Particle:
	if kind in ["smoke","fire","flash","spark"]:
		puffs.emit(at,size,color,velocity,life,gravity,kind);return null
	while particles.size()>=360:remove_particle(0)
	var key="sphere" if round_shape else "cube"
	if not meshes.has(key):
		if round_shape:
			var m=SphereMesh.new();m.radius=.5;m.height=1;m.radial_segments=8;m.rings=4;meshes[key]=m
		else:
			var m=BoxMesh.new();m.size=Vector3.ONE;meshes[key]=m
	var ink="particle_alpha" if color.a<1 else "particle_opaque"
	if not materials.has(ink):
		var material=Art.material(Color.WHITE).duplicate();material.vertex_color_use_as_albedo=true
		if color.a<1:material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		materials[ink]=material
	var node=Node3D.new();add_child(node)
	node.position=at;node.scale=size
	var p:=Particle.new();p.node=node;p.velocity=velocity;p.spin=Vector3(rng.randf_range(-7,7),rng.randf_range(-7,7),rng.randf_range(-7,7))
	p.life=life;p.gravity=gravity;p.size=size;p.kind=kind;p.presentation=presentation
	p.batch=[instance_batches.add_case(WeaponEffects.battle_casing_mesh(presentation),WeaponEffects.outlined_material(Color.WHITE,true),node.transform) if kind=="case" else instance_batches.add(meshes[key],materials[ink],node.transform,Transform3D.IDENTITY,color)]
	particles.append(p)
	particle_sequence+=1;p.motion_age=0.0;p.motion_wait=float(particle_sequence%5)/150.0
	if kind=="case":
		var count=0
		for i in range(particles.size()-1,-1,-1):
			if particles[i].kind!="case":continue
			count+=1
			if count>160:remove_particle(i)
	while particles.size()>360:remove_particle(0)
	return p

func remove_particle(index: int):
	var p: Particle=particles[index]
	instance_batches.release(p.batch);p.node.queue_free();particles.remove_at(index)

func batching_stats() -> Dictionary:
	var result=instance_batches.stats();var resting=0
	for p in particles:
		if p.settled:resting+=1
	result.resting=resting;result.active=particles.size()-resting;result.support_checks=support_checks
	result.support_scanned=support_scanned
	result.craters=blast_marks.entries.size() if blast_marks!=null else 0
	if blast_marks!=null:result.blast_marks=blast_marks.stats()
	if blood!=null:result.blood_stains=blood.stains.size();result.stain_uploads=blood.stain_uploads
	if vehicle_destruction!=null:result.vehicle_destruction=vehicle_destruction.stats()
	if explosions!=null:result.explosions=explosions.stats()
	if feedback!=null:result.audio=feedback.audio.stats()
	return result

func refresh_resting_support():
	# Topology plus vehicle poses cover every mutable supporting surface. Terrain
	# itself is immutable during a round; rebuilding the scene discards this cache.
	var state=[world.topology_revision] if world!=null else [0]
	if world!=null:
		for vehicle in world.vehicles:state.append([vehicle.position,vehicle.angle,vehicle.turret_angle,vehicle.get("elevation",0),vehicle.get("pose_basis",Basis.IDENTITY),vehicle.destroyed])
	var next_stamp=hash(state);var changed=next_stamp!=support_stamp
	support_stamp=next_stamp;support_checks=0;support_scanned=0
	# A completed scan needs no repeat until a support actually changes. Keep the
	# unfinished scan alive across the 16-query budget, even if its stamp is stable.
	if not changed and not support_pending:return
	var scanned=0
	while scanned<particles.size() and support_checks<16:
		support_cursor=posmod(support_cursor,particles.size())
		var p: Particle=particles[support_cursor];support_cursor+=1;scanned+=1
		if not p.settled or p.kind not in ["case","magazine"] or p.support_stamp==support_stamp:continue
		support_checks+=1
		var node: Node3D=p.node
		var floor_height=world.ground_height(Vector2(node.position.x,node.position.z),.025,node.position.y+.04) if world!=null else 0.0
		var old_floor=float(p.floor)
		if floor_height<old_floor-.035:
			p.settled=false;p.rolling=false;p.gravity=9.8
		elif not is_equal_approx(floor_height,old_floor):
			node.position.y+=floor_height-old_floor;instance_batches.sync(p.batch,node.transform)
		p.floor=floor_height;p.support_stamp=support_stamp
	support_scanned=scanned;support_pending=scanned<particles.size()

func attachment(e: Dictionary,socket: String) -> Dictionary:
	if e.has("ejection_node") and is_instance_valid(e.ejection_node):
		return {"position":e.ejection_node.global_position,"basis":e.ejection_node.global_basis}
	if int(e.get("mount",-1))>=0:
		return {"position":e.position,"basis":Basis(Vector3.UP,-float(e.angle)-PI*.5)}
	var u: Dictionary=e.unit
	if u.id>=0 and u.id<actor_views.size():
		var view: Dictionary=actor_views[u.id]
		if view.weapon==e.weapon.get("id","") and is_instance_valid(view.held) and view.held.has_node(socket):
			return {"position":view.held.get_node(socket).global_position,"basis":view.held.global_basis}
	return {"position":e.position,"basis":Basis(Vector3.UP,-float(e.angle)-PI*.5)}

func drop_magazine(e: Dictionary):
	var u: Dictionary=e.unit
	if not u.alive or u.reload<=0 or u.weapon_id!=e.weapon.get("id",""):return
	while particles.size()>=360:remove_particle(0)
	var node=Magazine.build(self,e.weapon);var source=attachment(e,"MagazineSocket")
	node.global_position=source.position;node.global_basis=source.basis
	var bounds=AABB();var first=true
	for mesh in node.get_children():
		if mesh is MeshInstance3D:
			bounds=mesh.mesh.get_aabb() if first else bounds.merge(mesh.mesh.get_aabb());first=false
	var side=Vector3(-sin(e.angle),0,cos(e.angle))
	var p:=Particle.new();p.node=node;p.velocity=side*.55+Vector3(0,-.35,0);p.spin=Vector3(2.1,1.5,3.0)
	p.life=24;p.size=bounds.size;p.bounds=bounds;p.kind="magazine";particles.append(p)
	for mesh in node.get_children():
		if mesh is MeshInstance3D:
			p.batch.append(instance_batches.add_magazine(mesh.mesh,mesh.material_override,node.transform,mesh.transform))
		node.remove_child(mesh);mesh.queue_free()
	var count=0
	for i in range(particles.size()-1,-1,-1):
		if particles[i].kind!="magazine":continue
		count+=1
		if count>32:remove_particle(i)
	while particles.size()>360:remove_particle(0)

func clear_unit_actions(unit_id: int):
	# Unit slots are reused: delayed effects must not follow the next life into its new weapon.
	for i in range(delayed.size()-1,-1,-1):
		if int(delayed[i].get("unit",{}).get("id",-1))==unit_id:delayed.remove_at(i)
	var prefix=str(unit_id)+"/"
	for key in retained_cases.keys():
		if str(key).begins_with(prefix):retained_cases.erase(key)

func handle(e: Dictionary):
	if e.type in ["death","respawn"]:clear_unit_actions(int(e.unit.id))
	feedback.muted=silent or muted;feedback.handle(e)
	match e.type:
		"grenade_throw":sound("throw",1.0,.65)
		"grenade_bounce":
			if Vector2(e.position.x,e.position.z).distance_to(world.player.position)<28:sound("grenade_contact",.73 if e.soft else 1.0,clampf(e.speed/9.0,.10,.72)*(.4 if e.soft else 1.0))
		"terrain_step":
			if e.position.distance_to(world.player.position)>22:return
			var surface=world.terrain.profile_at(e.position)
			if surface.id not in ["terrain.snow","terrain.desert"] or surface.cover<.08:return
			footprints.add_step(e.position,e.forward)
			var snow=surface.id=="terrain.snow";var at=Vector3(e.position.x,world.terrain.height(e.position)+.06,e.position.y)
			var drift=Vector3(-e.forward.x*.30,.18,-e.forward.y*.30)
			var color=Color("e1e7e5") if snow else Color("c6af85")
			piece(at,Vector3(.13,.07,.13)*lerpf(.65,1.25,surface.softness),color,drift,.40 if snow else .62,true,0,"smoke")
			for i in range(2 if snow else 1):piece(at,Vector3.ONE*(.027 if snow else .018),color,drift+Vector3(rng.randf_range(-.3,.3),rng.randf_range(.35,.7),rng.randf_range(-.3,.3)),.55,false,3.8 if snow else 7.5)
		"vehicle_ground":
			var v: Dictionary=e.vehicle
			if v.position.distance_to(world.player.position)>28:return
			for contact in vehicle_tracks.add_vehicle(v):
				var travel_speed: float=v.get("velocity",Vector2.ZERO).length()
				if travel_speed<.6:continue
				var at=Vector3(contact.point.x,world.terrain.height(contact.point)+.07,contact.point.y)
				var drift=Vector3(-contact.forward.x*.4,.23,-contact.forward.y*.4)
				var size=clampf(travel_speed*.035*(1.2 if contact.sliding else 1.0),.09,.28)
				var color=Color("e0e7df") if contact.snow else Color("c8b087") if contact.loose else Color("aeaca4")
				piece(at,Vector3(size,size*.38,size),color,drift,.48 if contact.snow else .65,true,0,"smoke")
		"repair":
			retained_cases.clear();delayed.clear()
			vehicle_destruction.clear()
			explosions.clear()
			blast_marks.clear()
		"land":
			if e.speed<1.2:return
			var u: Dictionary=e.unit
			for i in range(5):piece(Vector3(u.position.x,u.elevation+.06,u.position.y),Vector3(.11,.05,.11),Color("bdb5c4"),Vector3(rng.randf_range(-.5,.5),.12,rng.randf_range(-.5,.5)),.45,true,0,"smoke")
		"shot":
			var w: Dictionary=e.weapon
			if w.kind in ["melee","grenade"]:return
			var at=Vector3(e.position.x,e.height,e.position.y)
			var mount_index=int(e.get("mount",-1))
			if mount_index>=0 and world!=null and world.vehicles[mount_index].emplacement and world.vehicles[mount_index].type=="fieldGun":
				var mount: Dictionary=world.vehicles[mount_index]
				var frame=Basis(Vector3.UP,-mount.angle-PI*.5)
				for side in [-1,1]:
					var spade=Vector3(mount.position.x,.045,mount.position.y)+frame*Vector3(side*.51,0,1.48)
					for i in range(2):piece(spade,Vector3(.19,.06,.17),Color("bdb5c4"),frame*Vector3(side*(.12+i*.10),.05,.24+i*.10),.38,true,0,"smoke")
			var profile=WeaponProfile.get_profile(w)
			var forward: Vector3=e.get("forward",Vector3(cos(e.angle),0,sin(e.angle)))
			# Flash and real tracer already communicate every NPC shot. Decorative
			# muzzle smoke/sparks are reserved for the player and mounted weapons.
			if e.unit.player or mount_index>=0:
				piece(at+forward*.035,Vector3.ONE*(.065 if profile.suppressed else .11),Color("b0a6b6"),forward*.3+Vector3(0,.20,0),.45,true,0,"smoke")
				if not profile.suppressed:
					for i in range(3 if profile.family=="sniper" else 2):
						piece(at,Vector3(.014,.014,.035),Color("ffe8ac"),forward*rng.randf_range(1,3)+Vector3(rng.randf_range(-.4,.4),rng.randf_range(-.2,.5),rng.randf_range(-.4,.4)),.09,false,0,"spark")
			if w.kind=="rocket":
				var rear: Vector3=e.get("backblast",at-forward*.9)
				for i in range(7):
					piece(rear-forward*float(i)*.06,Vector3.ONE*(.07+i*.018),Color("ffe0a3") if i<3 else Color("b2a5aa"),-forward*(2.0+i*.4)+Vector3(0,.13,0),.17 if i<3 else .6,true,0,"flash" if i<3 else "smoke")
			var schedule: Dictionary
			var weapon_mode=""
			if mount_index>=0 and world!=null:
				var mount: Dictionary=world.vehicles[mount_index];weapon_mode=mount.modes[mount.mode]
				schedule=MountedCases.schedule(mount.type,weapon_mode,bool(e.get("eject_cases",true)))
			else:
				var key=str(e.unit.id)+"/"+str(w.get("id",w.kind))
				schedule=Ejection.shot(w,int(retained_cases.get(key,0)));retained_cases[key]=schedule.retained
			var unit_id: int=e.unit.id
			cosmetic_shots[unit_id]=int(cosmetic_shots.get(unit_id,0))+1
			var detailed_ejection: bool=e.unit.player or mount_index>=0
			# Keep exact player/mounted ejection. Nearby NPCs contribute a bounded
			# sample; distant casings are smaller than a pixel in the battle camera.
			var show_cases: bool=detailed_ejection or (e.unit.position.distance_squared_to(world.player.position)<196 and int(cosmetic_shots[unit_id])%3==0 and flying_cases<24)
			for i in range(schedule.count if show_cases else 0):
				delayed.append({"kind":"case","time":schedule.delay+i*.035,"position":e.get("ejection",at-forward*.32),"angle":e.angle,
					"weapon":w,"unit":e.unit,"mount":mount_index,"weapon_mode":weapon_mode,"ejection_node":e.get("ejection_node"),
					"case_presentation":schedule.get("presentation",{}),"reload_phase":float(schedule.get("reload_phase",-1.0))})
		"reload_start":
			var w: Dictionary=e.weapon;var u: Dictionary=e.unit;var at=Vector3(u.position.x,u.elevation+.85,u.position.y)
			var key=str(u.id)+"/"+str(w.get("id",w.kind));var count=Ejection.reload_cases(w,int(retained_cases.get(key,0)))
			retained_cases[key]=0
			for i in range(count):delayed.append({"kind":"case","time":float(w.reload)*.25+i*.045,"position":at,"angle":u.facing.angle(),"weapon":w,"unit":u})
			if Magazine.profile(w).detachable:
				delayed.append({"kind":"magazine","time":float(w.reload)*.24,"position":at,"angle":u.facing.angle(),"weapon":w,"unit":u})
		"damage":blood.queue_hit(e)
		"impact":
			if e.get("material","")!="unit" and feedback.allow_impact(e):TerrainEffects.impact(self,e)
		"fracture":TerrainEffects.fracture(self,e)
		"explosion":
			# Vehicle destruction owns its bounded two-batch visuals; blast damage is unchanged.
			if e.get("weapon",{}).get("vehicle_detonation",false):return
			if not explosions.burst(e):return
			var cue_frame=Engine.get_process_frames()
			if cue_frame!=blast_cue_frame:blast_cue_frame=cue_frame;blast_cues=0
			if blast_cues>=3:return
			blast_cues+=1
			blast_marks.add_blast(e)
		"smoke":
			for i in range(24):piece(Vector3(e.position.x,float(e.get("height",world.terrain.height(e.position)))+.3,e.position.y)+Vector3(rng.randf_range(-2,2),rng.randf_range(0,1),rng.randf_range(-2,2)),Vector3.ONE*1.1,Color("b0acba"),Vector3(0,.03,0),float(e.get("duration",13)),true,0,"smoke")
		"death":death(e.unit,e.get("impulse",Vector3.ZERO))
		"vehicle_damage":vehicle_destruction.damage(e.vehicle)
		"vehicle_destroyed":
			vehicle_destruction.destroyed(e.vehicle)

func death(u: Dictionary,impulse: Vector3):
	var view: Dictionary
	if corpses.size()>=18:view=corpses.pop_front().view
	elif not corpse_pool.is_empty():view=corpse_pool.pop_back()
	else:view=Art.soldier(self,int(u.team),false,false)
	view.root.show()
	Classes.apply(view,str(u.get("class_id","assault")),int(u.team))
	var pose=u.duplicate(true);pose.alive=true;pose.flash=0;pose.velocity=Vector2.ZERO;pose.reload=0
	view.root.position=Vector3(u.position.x,u.elevation,u.position.y)
	Motion.update(view,pose,0,0,2.1);view.muzzle.visible=false;view.rifle.visible=false
	if u.id>=0 and u.id<actor_views.size():
		var living: Dictionary=actor_views[u.id]
		view.helmet.visible=living.helmet.visible
		view.body.transform=living.body.transform;view.model.transform=living.model.transform
		for i in range(view.skeleton.get_bone_count()):view.skeleton.set_bone_pose(i,living.skeleton.get_bone_pose(i))
	for child in view.root.get_children():
		if child is Node3D and child!=view.body:child.hide()
	view.death_entry_pitch=view.body.rotation.x;view.death_entry_roll=view.body.rotation.z
	view.death_entry_pose=[];view.death_stance=u.stance
	for i in range(view.skeleton.get_bone_count()):view.death_entry_pose.append(view.skeleton.get_bone_pose(i))
	var flight: Dictionary=u.get("vehicle_flight",{}).duplicate(true)
	corpses.append({"view":view,"age":0.0,"flight":flight,"impulse":impulse.limit_length(9),"vertical_speed":float(u.vertical_speed),"fall":1 if rng.randf()>.35 else -1,"yaw":view.body.rotation.y,"choice":flight.choice if not flight.is_empty() else Reaction.death_choice(u,impulse)})
	if crowd_batches!=null:crowd_batches.register(view,int(u.team))
	# Death equipment now lives in world.loot and one shared ground-bag batch.
	while corpses.size()>18:corpses.pop_front().view.root.queue_free()

func detach_helmet(view: Dictionary,impulse: Vector3):
	if not view.has("helmet") or not view.helmet.visible:return
	var original: MeshInstance3D=view.helmet
	var node=MeshInstance3D.new();node.mesh=original.mesh;node.material_override=original.material_override;add_child(node);node.global_transform=original.global_transform;original.hide()
	if view.has("render_translation"):node.global_position+=view.render_translation.offset
	for surface in range(original.mesh.get_surface_count()):node.set_surface_override_material(surface,original.get_surface_override_material(surface))
	var class_helmet=original.get_node_or_null("ClassHelmet")
	if class_helmet!=null:node.add_child(class_helmet.duplicate())
	if (crowd_batches==null or not crowd_batches.register_helmet(node,view)) and rigid_batches!=null:rigid_batches.register_tree(node)
	var push=Vector3(impulse.x,0,impulse.z).limit_length(3.5)
	if push.length()<.5:push=Vector3(.8,0,.4)
	helmets.append({"node":node,"velocity":push+Vector3(0,3.7,0),"spin":Vector3(5.2,-3.8,6.0),"age":0.0,"settled":false,"bounces":0})
	while helmets.size()>24:helmets.pop_front().node.queue_free()

func update_helmets(delta: float):
	for i in range(helmets.size()-1,-1,-1):
		var h: Dictionary=helmets[i];h.age+=delta
		if h.age>60:h.node.queue_free();helmets.remove_at(i);continue
		if h.settled:continue
		var node: MeshInstance3D=h.node;h.velocity.y-=9.8*delta
		var next: Vector3=node.position+h.velocity*delta
		if world!=null and world.blocked(Vector2(next.x,next.z),.18,.30,-1,next.y-.15):
			h.velocity.x*=-.42;h.velocity.z*=-.42;next.x=node.position.x;next.z=node.position.z
		node.rotation+=h.spin*delta
		var bounds=node.mesh.get_aabb();var extent=0.0
		for corner in range(8):extent=maxf(extent,-(node.basis*bounds.get_endpoint(corner)).y)
		var floor_height=world.ground_height(Vector2(next.x,next.z),.12,node.position.y-extent+.08) if world!=null else 0.0
		if next.y<floor_height+extent+.012:
			next.y=floor_height+extent+.012;h.bounces+=1
			h.velocity=Vector3(h.velocity.x*.56,absf(h.velocity.y)*.29,h.velocity.z*.56);h.spin*=.48
			if h.velocity.y<.32 or h.bounces>=5:h.velocity=Vector3.ZERO;h.spin=Vector3.ZERO;h.settled=true
		node.position=next

func _process(delta: float):
	var profile_started=Time.get_ticks_usec() if world!=null and world.profile_ai else 0
	case_motion.begin_frame();case_sound_cooldown=maxf(0,case_sound_cooldown-delta)
	if blood!=null:blood.advance(delta)
	if puffs!=null:puffs.advance(delta)
	var after_blood=Time.get_ticks_usec() if profile_started>0 else 0
	update_helmets(delta)
	refresh_resting_support()
	var pixel=camera.size/maxf(1,get_viewport().get_visible_rect().size.y) if camera!=null else .02
	var pixel_changed=not is_equal_approx(pixel_scale,pixel)
	if pixel_changed:pixel_scale=pixel;case_scales.clear()
	for i in range(delayed.size()-1,-1,-1):
		var e: Dictionary=delayed[i]
		if float(e.get("reload_phase",-1.0))>=0:
			# Retain the spent field-gun case until the actual breech-opening phase.
			if world==null or int(e.mount)>=world.vehicles.size():delayed.remove_at(i);continue
			var mount: Dictionary=world.vehicles[e.mount]
			if mount.destroyed:delayed.remove_at(i);continue
			var state: Dictionary=mount.states[e.weapon_mode]
			if state.reload<=0:continue
			var phase=1.0-float(state.reload)/maxf(.05,float(state.reload_duration))
			if phase<float(e.reload_phase):continue
			e.time=0.0
		else:e.time-=delta
		if e.time<=0:
			if e.kind=="magazine":drop_magazine(e)
			else:
				var side=Vector3(-sin(e.angle),0,cos(e.angle));var presentation: Dictionary=e.get("case_presentation",{})
				if presentation.is_empty():presentation=Ammo.profile(e.weapon)
				var source=attachment(e,"EjectionSocket")
				var speed: Vector2=presentation.get("eject_speed",Vector2(1.5,2.25));var lift: Vector2=presentation.get("eject_lift",Vector2(1.5,2.15))
				var velocity=side*rng.randf_range(speed.x,speed.y)+Vector3(0,rng.randf_range(lift.x,lift.y),0)
				var position: Vector3=source.position
				if presentation.get("mounted",false):
					side=(source.basis*Vector3(presentation.eject_axis)).normalized()
					velocity=side*rng.randf_range(presentation.eject_speed.x,presentation.eject_speed.y)+Vector3.UP*rng.randf_range(presentation.eject_lift.x,presentation.eject_lift.y)
					position+=side*minf(.12,presentation.case_size.z*.25)
					if world!=null and int(e.mount)>=0 and int(e.mount)<world.vehicles.size():
						var mount: Dictionary=world.vehicles[e.mount]
						velocity+=Vector3(cos(mount.angle),0,sin(mount.angle))*float(mount.speed)
				if e.weapon.get("id","")=="p90":velocity=side*.4+Vector3.DOWN*.3
				var spent=piece(position,presentation.case_size,presentation.case_color,velocity,float(presentation.get("life",24)),false,9.8,"case",presentation)
				spent.node.basis=source.basis.orthonormalized();spent.node.scale=presentation.case_size
				spent.spin=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))*float(presentation.get("spin",7.0))
			delayed.remove_at(i)
	var before_particles=Time.get_ticks_usec() if profile_started>0 else 0
	flying_cases=0
	for i in range(particles.size()-1,-1,-1):
		var p: Particle=particles[i];var node: Node3D=p.node;p.age+=delta
		if p.age>p.life:remove_particle(i);continue
		if p.kind=="case" and not p.settled:flying_cases+=1
		if p.settled and (not pixel_changed or p.kind!="case"):continue
		var motion_delta: float=delta
		if p.kind in ["case","magazine"] and not p.settled:
			p.motion_age=float(p.motion_age)+delta;p.motion_wait=float(p.motion_wait)-delta
			if p.motion_wait>0:continue
			motion_delta=p.motion_age;p.motion_age=0.0;p.motion_wait=maxf(.001,float(p.motion_wait)+1.0/30.0)
		if p.kind=="case":
			# Enlarge only the drawn mesh; keep ejection timing/gravity independent.
			var key=str(p.presentation.key)
			if not case_scales.has(key):case_scales[key]=Ammo.case_scale(p.presentation,pixel_scale)
			var changed=p.draw_scale!=case_scales[key]
			if changed:node.scale=case_scales[key];p.draw_scale=case_scales[key]
			if p.settled:
				if changed:
					node.position.y=float(p.floor)+CaseMotion.extent(node)+.008
					instance_batches.sync(p.batch,node.transform)
				continue
			var contact=case_motion.advance_particle(p,motion_delta,world)
			if p.settled:p.support_stamp=support_stamp
			instance_batches.sync(p.batch,node.transform)
			if not contact.is_empty() and case_sound_cooldown<=0:
				sound(contact.key,contact.pitch,contact.gain);case_sound_cooldown=.055
			continue
		if p.settled:continue
		p.velocity.y-=p.gravity*motion_delta;node.position+=p.velocity*motion_delta
		if p.kind in ["smoke","fire","flash"]:
			node.scale=p.size*(1+p.age*(.55 if p.kind=="smoke" else 2.5))*clampf((p.life-p.age)/minf(.25,p.life),0,1)
		else:
			var floor_height=world.terrain.height(Vector2(node.position.x,node.position.z)) if world!=null else 0.0;var extent=float(p.size.y)*.5
			if p.kind in ["case","magazine"]:
				var bounds: AABB=p.bounds
				var half=bounds.size*.5
				extent=absf(node.basis.x.y)*half.x+absf(node.basis.y.y)*half.y+absf(node.basis.z.y)*half.z-(node.basis*bounds.get_center()).y
				if world!=null:floor_height=world.ground_height(Vector2(node.position.x,node.position.z),.025,node.position.y+.04)
			var floor_top=floor_height+extent+.008
			if node.position.y>floor_top:node.rotation+=p.spin*motion_delta
			if node.position.y<floor_top:
				node.position.y=floor_top
				if absf(p.velocity.y)>.6:
					var case_data: Dictionary=p.presentation
					p.velocity.y=absf(p.velocity.y)*float(case_data.get("bounce",.28))
					p.velocity.x*=float(case_data.get("ground_drag",.48));p.velocity.z*=float(case_data.get("ground_drag",.48));p.spin*=float(case_data.get("spin_drag",.35))
					if not p.bounced and p.kind in ["case","magazine"]:sound("case",float(case_data.get("sound_pitch",1.0)))
					p.bounced=true
				else:
					p.velocity=Vector3.ZERO;p.gravity=0;p.settled=true;p.floor=floor_height;p.support_stamp=support_stamp
		instance_batches.sync(p.batch,node.transform)
	var before_corpses=Time.get_ticks_usec() if profile_started>0 else 0
	for corpse in corpses:
		corpse.age+=delta
		var flight: Dictionary=corpse.get("flight",{})
		if corpse.get("resting",false) and corpse.get("support_stamp",-1)==support_stamp:
			if flight.is_empty() or not VehicleFlight.separate(world,flight):continue
			corpse.resting=false
		var v: Dictionary=corpse.view;var t=smoothstep(0,.60,corpse.age)
		if v.get("source_rig",false) and not corpse.get("pose_finished",false):
			v.render_pose_revision=int(v.get("render_pose_revision",0))+1
			v.body.rotation.x=lerpf(float(v.death_entry_pitch),0,smoothstep(0,.38,corpse.age));v.body.rotation.z=lerpf(float(v.death_entry_roll),0,smoothstep(0,.38,corpse.age));v.body.rotation.y=lerp_angle(corpse.yaw,float(corpse.choice.yaw),smoothstep(0,.48,corpse.age));v.body.position=Vector3.ZERO;preload("res://scripts/source_rig_motion.gd").death(v,corpse.age,corpse.choice)
			var clip: Dictionary=Reaction.info()[str(corpse.choice.get("clip","fall"))]
			corpse.pose_finished=corpse.age>=maxf(.6,(float(clip.end)-float(clip.start))/24.0/maxf(.01,float(corpse.choice.get("speed",2.2))))
		elif not v.get("source_rig",false):v.body.rotation.x=corpse.fall*PI*.5*t;v.body.position.y=.22*t;v.body.position.z=0
		if not flight.is_empty():
			VehicleFlight.step(world,flight,delta);v.root.position=flight.position
			if corpse.get("pose_finished",false) and flight.settled:corpse.resting=true;corpse.support_stamp=support_stamp
		else:
			var shift=Vector3(corpse.impulse.x,0,corpse.impulse.z)*exp(-corpse.age*4)*delta
			var next=v.root.position+shift
			if world==null or not world.blocked(Vector2(next.x,next.z),.40,.45,-1,next.y):v.root.position=next
			var floor_height=world.ground_height(Vector2(v.root.position.x,v.root.position.z),.16,v.root.position.y+.025) if world!=null else 0.0
			corpse.vertical_speed-=18*delta;v.root.position.y=maxf(floor_height,v.root.position.y+corpse.vertical_speed*delta)
			if v.root.position.y<=floor_height:corpse.vertical_speed=0.0
			if corpse.get("pose_finished",false) and shift.length_squared()<.000000001 and is_zero_approx(corpse.vertical_speed):
				corpse.resting=true;corpse.support_stamp=support_stamp
		if v.get("source_rig",false):continue
		v.skeleton.set_bone_pose_rotation(1,Quaternion.from_euler(Vector3(.18*t,0,-.10*t)))
		v.skeleton.set_bone_pose_rotation(3,Quaternion.from_euler(Vector3(-.08*t,0,.15*t)))
		v.skeleton.set_bone_pose_rotation(8,Quaternion.from_euler(Vector3(.2*t,-.5*t,-.28*t)))
		v.skeleton.set_bone_pose_rotation(10,Quaternion.from_euler(Vector3(-.1*t,.45*t,.18*t)))
	if profile_started>0:
		last_process_ms=(Time.get_ticks_usec()-profile_started)/1000.0
		last_profile={"blood_ms":(after_blood-profile_started)/1000.0,"contacts_emission_ms":(before_particles-after_blood)/1000.0,"particles_ms":(before_corpses-before_particles)/1000.0,"corpses_ms":(Time.get_ticks_usec()-before_corpses)/1000.0,"batches":batching_stats()}
