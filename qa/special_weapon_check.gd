extends SceneTree
## Isolated state / source-rig / mesh checks. Never loads or drives the game scene.
const Catalog=preload("res://scripts/source_catalog.gd")
const Art=preload("res://scripts/ink_art.gd")
const Props=preload("res://scripts/proving_art.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
const Melee=preload("res://scripts/melee_action.gd")
class ContactFixture extends "res://scripts/proving_world.gd":
	var cover=false
	var dealt=[]
	func trace_3d(_at: Vector3,_direction: Vector3,_distance: float,_options: Dictionary={},_solids: bool=false) -> Dictionary:
		return {"type":"object","distance":.5,"target":{"id":0,"material":"concrete"}} if cover else {}
	func damage_unit(v: Dictionary,_amount: float,_impulse: Vector3,_w: Dictionary,_explosive: bool,_head: bool=false,_height: float=-1,_region: String="",_point: Vector3=Vector3.INF,_direction: Vector3=Vector3.ZERO,_source: int=-1,_source_epoch: int=-1):dealt.append(v.id)
	func damage_object(_object: Dictionary,_at: Vector2,_height: float,_amount: float,_explosive: bool,_col: int=-1,_row: int=-1,_weapon: Dictionary={},_distance: float=0,_incidence: float=1,_energy_scale: float=1):pass
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func unit(id: String) -> Dictionary:
	return {"position":Vector2.ZERO,"elevation":0.0,"facing":Vector2.UP,"velocity":Vector2.ZERO,"weapon_id":id,"walk":0.0,"stance":0,"stance_blend":0.0,"aiming":true,"mounted":-1,"ammo":1,"reserve":5,"reload":0.0,"cooldown":0.0,"shot_index":0,"last_shot":-100.0,"flash":0.0,"hurt":0.0,"aim_point":Vector2(0,-8),"aim_height":1.0,"aim_valid":true,"vault":{},"ladder":{},"alive":true,"grounded":true,"reaction":{}}
func run():
	var catalog=Catalog.new();var stage=Node3D.new();root.add_child(stage)
	var fixture=ContactFixture.new();fixture.catalog=catalog
	var attacker=unit("army-knife");attacker.id=0;attacker.team=0;attacker.aim_height=1.0
	var enemy=unit("army-knife");enemy.id=1;enemy.team=1;enemy.position=Vector2(0,-1)
	fixture.units=[attacker,enemy]
	var knife: Dictionary=catalog.weapons["army-knife"]
	Melee.begin(attacker,knife,Vector2.UP*3)
	fixture.update_melee(attacker,.04,true);check(fixture.dealt.is_empty(),"Contact cannot damage during anticipation")
	for i in range(30):fixture.update_melee(attacker,1.0/60,true)
	check(fixture.dealt==[1],"One victim can only be hit once per attack")
	for reason in ["wall","floor","cancel"]:
		fixture.dealt=[];fixture.cover=reason=="wall";enemy.elevation=3.4 if reason=="floor" else 0.0
		Melee.begin(attacker,knife,Vector2.UP*3)
		for i in range(30):fixture.update_melee(attacker,1.0/60,reason!="cancel")
		check(fixture.dealt.is_empty(),"Melee respects "+reason)
	for id in ["army-knife","fire-axe","katana"]:
		var w: Dictionary=catalog.weapons[id];var u=unit(id)
		Melee.begin(u,w,Vector2.UP*3);var p=Melee.profile(w)
		check(not Melee.advance(u,w,p.duration*.10,true),"No immediate damage before windup: "+id)
		check(Melee.advance(u,w,p.duration*.5,true),"Skipped frames still cross active window: "+id)
		check(Melee.within(u,{"position":Vector2(0,-1)},w) and not Melee.within(u,{"position":Vector2(0,1)},w),"Forward arc excludes behind: "+id)
		check(not Melee.within(u,{"position":Vector2(0,-4)},w),"Melee keeps range limit: "+id)
		Melee.advance(u,w,.016,false);check(u.melee.is_empty(),"Interruption cancels pending hit: "+id)
	for id in ["army-knife","fire-axe","katana","rpg","anti-tank-launcher","grenade-launcher","portable-mortar"]:
		var w: Dictionary=catalog.weapons[id];var view=Art.soldier(stage,0,false,true)
		for child in view.rifle.get_children():view.rifle.remove_child(child);child.free()
		view.held=Props.weapon(view.rifle,w);view.weapon=w.id;view.weapon_profile=w
		view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Effects.flash(view.muzzle_socket,w)
		check(view.skeleton.get_bone_count()==41 and view.animator.has_animation("Armature|slash"),"Original rig and slash retained: "+id)
		var max_grip=0.0
		var melee_left=0.0
		for stance in range(3):
			for heading in [0.0,PI*.5,PI,PI*1.5]:
				for t in [0.0,.16,.38,.55,.8,1.0]:
					var u=unit(id);u.stance=stance;u.stance_blend=stance;u.facing=Vector2.from_angle(heading);u.aim_point=u.facing*8
					view.body_yaw=atan2(-u.facing.x,-u.facing.y)
					view.mortar_deploy=1.0 if w.kind=="mortar" and stance<2 else 0.0
					if w.kind=="melee":Melee.begin(u,w,u.aim_point);u.melee.age=Melee.profile(w).duration*t
					else:u.reload_duration=w.reload;u.reload=float(w.reload)*(1-t)
					Motion.update(view,u,0,1,float(w.reload))
					check(view.held.global_transform.is_finite() and view.muzzle_socket.global_transform.is_finite(),"Finite held / muzzle pose: "+id)
					for side in ["L","R"]:
						var pose=view.skeleton.global_transform*view.skeleton.get_bone_global_pose(view.skeleton.find_bone(side+"_Hand"))
						check(pose.is_finite(),"Finite hand pose: "+id)
						if w.kind=="melee" and id!="army-knife" and side=="L" and stance<2:
							melee_left=maxf(melee_left,(pose.origin+pose.basis*Vector3(0,.035,0)).distance_to(view.held.to_global(Vector3(0,0,.16))))
						if w.kind!="melee" and t==1:
							var actual=pose.origin+pose.basis*Vector3(0,.035,0)
							var target=view.held.to_global(preload("res://scripts/weapon_profile.gd").get_profile(w).grip if side=="R" else preload("res://scripts/weapon_profile.gd").get_profile(w).support)
							max_grip=maxf(max_grip,actual.distance_to(target))
		print("SPECIAL_GRIP ",id," max ready palm error m=",max_grip)
		if w.kind=="melee" and id!="army-knife":check(melee_left<.12,"Second hand stays on melee handle: "+id+" error="+str(melee_left))
		if w.kind!="melee":check(max_grip<.12,"Hands reach actual launcher grips: "+id)
		view.root.free()
	stage.free();print("SPECIAL_WEAPON_CHECK ",checks-failures.size(),"/",checks,"; no gameplay automation");quit(0 if failures.is_empty() else 1)
