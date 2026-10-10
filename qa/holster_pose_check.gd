extends SceneTree
## Sampled resource/bone fixtures only; no gameplay inputs, rendering or world.step.
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Props=preload("res://scripts/proving_art.gd")
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func point(view: Dictionary,name: String) -> Vector3:
	return view.skeleton.to_global(view.skeleton.get_bone_global_pose(view.skeleton.find_bone(name)).origin)
func _initialize():call_deferred("run")
func run():
	var stage=Node3D.new();root.add_child(stage)
	var expected=Source.soldier(stage,0,true)
	for id in ["p92","m416","mortar"]:
		var world=World.new();world.catalog=Catalog.new();world.player=world.add_unit(Vector2.ZERO,true)
		world.equip(id)
		var u: Dictionary=world.player;u.equip_remaining=0;u.facing=Vector2(0,-1)
		var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
		view.weapon_profile=world.weapon_for(u);view.held=Props.weapon(view.rifle,view.weapon_profile)
		view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
		Motion.update(view,u,.2,10,float(view.weapon_profile.reload))
		check(world.holster(),"Holster accepted: "+id)
		for motion in [{"clip":"idle","speed":0.0},{"clip":"walk","speed":2.0},{"clip":"run","speed":5.0}]:
			u.velocity=Vector2(0,-motion.speed)
			for frame in range(30):Motion.update(view,u,1.0/60,11+frame/60.0,float(view.weapon_profile.reload))
			var clip="Armature|"+motion.clip;var data: Dictionary=view.source_info.clips[motion.clip]
			check(view.animator.current_animation==clip,"Supplied unarmed clip: "+id+" "+motion.clip)
			Motion.sample(expected,clip,float(data.start)/24+fposmod(view.animation_time,float(data.duration)))
			var rig: Skeleton3D=view.skeleton
			var upper_error=0.0;var lower_error=0.0
			for bone in range(rig.get_bone_count()):
				var actual=rig.get_bone_pose(bone);var reference=expected.skeleton.get_bone_pose(bone)
				var name=rig.get_bone_name(bone)
				var error=actual.origin.distance_to(reference.origin)+actual.basis.x.distance_to(reference.basis.x)+actual.basis.y.distance_to(reference.basis.y)+actual.basis.z.distance_to(reference.basis.z)
				if "arm" in name or "Hand" in name or "Clavicle" in name:upper_error=maxf(upper_error,error)
				if "Thigh" in name or "Calf" in name or "Foot" in name or "Toe" in name:lower_error=maxf(lower_error,error)
			check(upper_error<.0001,"Original arms/wrists retained: "+id+" "+motion.clip)
			check(lower_error<.0001,"Original legs/feet retained: "+id+" "+motion.clip)
			check(not view.muzzle.visible,"No holstered muzzle flash: "+id)
			if motion.clip=="idle":
				for side in ["L","R"]:
					var drop=point(view,side+"_Upperarm").y-point(view,side+"_Hand").y
					print("HOLSTER_HAND_DROP weapon=",id," side=",side," metres=",drop)
					check(drop>.25,"Relaxed hand below shoulder: "+id+" "+side)
				check(point(view,"L_Hand").distance_to(point(view,"R_Hand"))>.4,"Hands separated beside body: "+id)
				check(float(view.mortar_deploy)<.001,"Holstered mortar does not force deployment crouch")
		# Same-stride transitions may blend arms but cannot reset source root travel.
		var before_time=float(view.animation_time);var before_hip=point(view,"Hip")
		world.equip(id);u.equip_remaining=0;Motion.update(view,u,0,12,float(view.weapon_profile.reload))
		check(is_equal_approx(view.animation_time,before_time),"Draw preserves stride phase: "+id)
		check(point(view,"Hip").distance_to(before_hip)<.001,"Draw preserves visible pelvis: "+id)
		for frame in range(12):Motion.update(view,u,1.0/60,12+frame/60.0,float(view.weapon_profile.reload))
		before_time=view.animation_time;before_hip=point(view,"Hip")
		world.holster();Motion.update(view,u,0,13,float(view.weapon_profile.reload))
		check(is_equal_approx(view.animation_time,before_time),"Holster preserves stride phase: "+id)
		check(point(view,"Hip").distance_to(before_hip)<.001,"Holster preserves visible pelvis: "+id)
		u.grounded=false;u.vertical_speed=0.0;Motion.update(view,u,.2,14,float(view.weapon_profile.reload))
		check(view.animator.current_animation=="Armature|jump","Jump also releases rifle arms: "+id)
		u.grounded=true;u.velocity=Vector2.ZERO;u.stance=2;u.stance_blend=2.0
		Motion.update(view,u,.2,15,float(view.weapon_profile.reload))
		check(point(view,"L_Hand").is_finite() and point(view,"R_Hand").is_finite(),"Empty prone support stays finite: "+id)
		view.root.free()
	stage.free()
	print("HOLSTER_POSE_CHECK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
