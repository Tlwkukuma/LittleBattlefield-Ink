extends SceneTree
## Frozen resource/pose samples only. No world.step, AI, inputs, combat or rendering.
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Props=preload("res://scripts/proving_art.gd")
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func points(view: Dictionary) -> Array:
	var result=[]
	for name in ["Hip","L_Thigh","R_Thigh","L_Calf","R_Calf","L_Foot","R_Foot","L_ToeBase","R_ToeBase"]:
		result.append(view.skeleton.to_global(view.skeleton.get_bone_global_pose(view.skeleton.find_bone(name)).origin))
	return result
func error(a: Array,b: Array) -> float:
	var worst=0.0
	for i in range(a.size()):worst=maxf(worst,a[i].distance_to(b[i]))
	return worst
func run():
	var world=World.new();world.catalog=Catalog.new();world.player=world.add_unit(Vector2.ZERO,true)
	world.equip("m416");var u: Dictionary=world.player
	u.equip_remaining=0;u.facing=Vector2.UP;u.aim_point=Vector2(0,-12);u.aim_height=1.0;u.aim_valid=true;u.aiming=true
	var stage=Node3D.new();root.add_child(stage)
	var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
	view.weapon_profile=world.weapon_for(u);view.held=Props.weapon(view.rifle,view.weapon_profile)
	view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
	var worst_entry=0.0;var worst_exit=0.0
	check(view.skeleton.get_bone_count()==41,"Original 41 bones retained")
	for clip in view.source_info.original_actions:check(view.animator.has_animation(clip),"Original clip retained: "+clip)
	for speed in [0.0,3.4,5.8]:
		for cycle in [.1,.45,.85]:
			u.grounded=true;u.velocity=u.facing*speed;view.source_clip="";view.transition_pose=[];view.locomotion_pose=[]
			Motion.update(view,u,.2,20,2.1)
			var name="run" if speed>4 else "walk" if speed>.05 else "idle"
			view.animation_time=cycle*float(view.source_info.clips[name].duration)
			Motion.update(view,u,0,20,2.1)
			var before=points(view)
			u.grounded=false;u.vertical_speed=6.4
			Motion.update(view,u,0,20,2.1)
			var entry=error(before,points(view));worst_entry=maxf(worst_entry,entry)
			check(entry<.001,"Takeoff zero-time continuity speed %.1f phase %.2f: %.5f m"%[speed,cycle,entry])
			check(view.source_clip=="Rifle_jump","Jump participates in clip transition bookkeeping")
			# Sample a prescribed airborne state; do not integrate a trajectory.
			u.vertical_speed=-6.4;Motion.update(view,u,.25,20.25,2.1);before=points(view)
			u.grounded=true;Motion.update(view,u,0,20.25,2.1)
			var landing=error(before,points(view));worst_exit=maxf(worst_exit,landing)
			check(landing<.001,"Landing zero-time continuity speed %.1f phase %.2f: %.5f m"%[speed,cycle,landing])
			check(view.source_clip=="Rifle_"+name,"Landing returns to correct source clip")
			Motion.update(view,u,.2,20.45,2.1)
			check(view.transition>=1,"Transition completes within bounded interval")
	# A run/walk boundary must not keep restarting its legs when speed fluctuates.
	u.grounded=true;u.velocity=u.facing*3.4;Motion.update(view,u,.2,21,2.1)
	view.animation_time=.63*float(view.source_info.clips.walk.duration)
	u.velocity=u.facing*5.8;Motion.update(view,u,0,21,2.1)
	check(absf(view.animation_time/float(view.source_info.clips.run.duration)-.63)<.0001,"Walk/run preserves normalized stride phase")
	var switches=0;var old=str(view.source_clip)
	for speed in [3.99,4.01,3.98,4.02,3.99,4.01]:
		u.velocity=u.facing*speed;Motion.update(view,u,1.0/60,21,2.1)
		if str(view.source_clip)!=old:switches+=1
		old=str(view.source_clip)
	check(switches==0,"Speed noise near run boundary does not restart transitions: "+str(switches))
	# Forward/backward/zero/strafe samples use the original lower-body keys.
	var reference=Source.soldier(stage,0,true)
	var worst_direction_entry=0.0;var worst_muzzle=0.0
	for stance in [0,1]:
		u.stance=stance;u.stance_blend=float(stance);u.holstered=false;u.aiming=true
		var first_direction=true
		for velocity in [Vector2.UP*3.4,Vector2.DOWN*3.4,Vector2.ZERO,Vector2.RIGHT*3.4,Vector2.LEFT*3.4,Vector2(1,1).normalized()*3.4,Vector2.UP*3.4]:
			var before=points(view);u.velocity=velocity
			Motion.update(view,u,0,22,2.1)
			var entry=error(before,points(view))
			if not first_direction:worst_direction_entry=maxf(worst_direction_entry,entry)
			# The first stance change is intentionally an explicit state sample.
			if not first_direction:check(entry<.001,"Direction change preserves zero-time leg pose stance %d velocity %s: %.6f"%[stance,velocity,entry])
			first_direction=false
			for frame in range(15):Motion.update(view,u,1.0/60,22+frame/60.0,2.1)
			check(absf(wrapf(float(view.body_yaw),-PI,PI))<=.8001,"Armed hips remain inside original aim-twist bound")
			if velocity==Vector2.DOWN*3.4:check(view.stride_rate<-.99,"Backpedal reverses original stride")
			if velocity==Vector2.UP*3.4:check(view.stride_rate>.99,"Forward movement restores forward stride")
			if velocity==Vector2.ZERO:check(absf(float(view.body_yaw))<.001,"Stopped reverse movement does not turn hips sideways")
			if velocity==Vector2.RIGHT*3.4:check(float(view.body_yaw)*float(view.stride_rate)<-.7,"Aimed right strafe aligns signed foot travel")
			if velocity==Vector2.LEFT*3.4:check(float(view.body_yaw)*float(view.stride_rate)>.7,"Aimed left strafe aligns signed foot travel")
			var target=Vector3(u.aim_point.x,u.aim_height,u.aim_point.y)
			var aim_error=(-view.muzzle_socket.global_basis.z.normalized()).angle_to((target-view.muzzle_socket.global_position).normalized())
			worst_muzzle=maxf(worst_muzzle,aim_error);check(aim_error<.035,"Actual muzzle remains aimed while hips follow movement")
			for shape in u.hit_shapes:
				check(shape.a.distance_to(view.skeleton.to_global(view.skeleton.get_bone_global_pose(shape.bone_a).origin))<.00001,"Hit capsule begins on actual posed bone")
				check(shape.b.distance_to(view.skeleton.to_global(view.skeleton.get_bone_global_pose(shape.bone_b).origin))<.00001,"Hit capsule ends on actual posed bone")
			if stance==0:
				var name=str(view.source_clip).trim_prefix("Rifle_")
				var data: Dictionary=view.source_info.clips[name]
				Motion.sample(reference,view.source_clip,float(data.start)/24+fposmod(float(view.animation_time),float(data.duration)))
				for side in ["L","R"]:
					for part in ["Thigh","Calf","Foot","ToeBase"]:
						var bone=view.skeleton.find_bone(side+"_"+part)
						check(view.skeleton.get_bone_pose(bone).is_equal_approx(reference.skeleton.get_bone_pose(bone)),"Directional motion preserves original leg/foot keys")
	# Near-sideways direction noise retains the prior reverse/forward choice.
	u.stance=0;u.stance_blend=0.0;u.velocity=Vector2.UP*3.4;Motion.update(view,u,.25,24,2.1)
	for forward in [-.10,.10,-.15,.15]:
		u.velocity=Vector2(sqrt(1-forward*forward),-forward)*3.4;Motion.update(view,u,1.0/60,24,2.1)
		check(not view.stride_reverse,"Pure-strafe directional deadband prevents backwards flips")
	# Reproducible direction/clip interruptions across the existing pose cadences.
	var rng=RandomNumberGenerator.new();rng.seed=20261009
	var saved_position: Vector2=u.position;var saved_elevation=float(u.elevation)
	var saved_health=float(u.health);var saved_ammo=int(u.ammo);var saved_root: Transform3D=view.root.transform
	for i in range(48):
		var before=points(view);var angle=rng.randf_range(-PI,PI)
		u.velocity=Vector2.from_angle(angle)*[3.4,3.98,4.02,5.8][i%4]
		var saved_velocity: Vector2=u.velocity;var saved_facing: Vector2=u.facing
		Motion.update(view,u,0,25,2.1)
		check(error(before,points(view))<.001,"Seeded clip/direction interruption has no zero-time pop: "+str(i))
		var old_rate=float(view.stride_rate);var dt=float([1.0/60,1.0/30,1.0/24,1.0/6][i%4])
		Motion.update(view,u,dt,25+dt,2.1)
		check(absf(float(view.stride_rate)-old_rate)<=dt*12.0+.00001,"Signed playback slew is bounded at each pose cadence")
		check(u.position==saved_position and u.elevation==saved_elevation and u.velocity==saved_velocity and u.facing==saved_facing and u.health==saved_health and u.ammo==saved_ammo and view.root.transform==saved_root,"Pose evaluation leaves authoritative movement/combat state unchanged")
		var finite=true
		for bone in range(view.skeleton.get_bone_count()):finite=finite and view.skeleton.get_bone_global_pose(bone).is_finite()
		check(finite,"All original bone transforms remain finite in seeded reversal sample")
	print("DIRECTIONAL_LOCOMOTION worst_zero_time_entry_m=",worst_direction_entry," worst_muzzle_radians=",worst_muzzle)
	check(world.time==0 and world.shots==0,"No gameplay simulation or shots occurred")
	print("SOURCE_LOCOMOTION_CHECK ",checks-failures.size(),"/",checks," worst_takeoff_m=",worst_entry," worst_landing_m=",worst_exit," failures=",failures.size())
	stage.free();quit(0 if failures.is_empty() else 1)
