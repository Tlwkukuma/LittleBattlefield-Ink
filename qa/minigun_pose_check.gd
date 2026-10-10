extends SceneTree
## Offline original-skeleton sampling, without game inputs or gameplay simulation.
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Props=preload("res://scripts/proving_art.gd")
const Heavy=preload("res://scripts/minigun_motion.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
var checks=0
var failures=[]
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func contact_error(view: Dictionary,side: String) -> float:
	var rig: Skeleton3D=view.skeleton;var hand=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(side+"_Hand"))
	var profile=Profile.get_profile(view.weapon_profile)
	return (hand.origin+hand.basis*Vector3(0,.035,0)).distance_to(view.held.to_global(profile.support if side=="L" else profile.grip))
func _initialize():run.call_deferred()
func run():
	var world=World.new();world.catalog=Catalog.new();world.player=world.add_unit(Vector2.ZERO,true)
	world.equip("minigun");var u: Dictionary=world.player;u.equip_remaining=0;u.facing=Vector2.UP;u.aim_point=Vector2(0,-12);u.aim_height=1;u.aim_valid=true
	var stage=Node3D.new();root.add_child(stage)
	var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
	view.weapon_profile=world.weapon_for(u);view.held=Props.weapon(view.rifle,view.weapon_profile)
	view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
	var worst=0.0;var aim_error=0.0
	for stance in range(3):
		for heading in range(8):
			for distance in [2.0,8.0]:
				for height in [0.0,.7,2.5]:
					u.stance=stance;u.stance_blend=float(stance);u.facing=Vector2.from_angle(heading*TAU/8)
					u.aim_point=u.facing*distance;u.aim_height=height;u.aiming=true;view.body_yaw=atan2(-u.facing.x,-u.facing.y)
					Motion.update(view,u,0,20,float(view.weapon_profile.reload))
					var left=contact_error(view,"L");var right=contact_error(view,"R");worst=maxf(worst,maxf(left,right))
					check(maxf(left,right)<.012,"Both grips reachable stance%d yaw%d distance%.0f height%.1f errors%.3f/%.3f"%[stance,heading,distance,height,left,right])
					var direction=(Vector3(u.aim_point.x,height,u.aim_point.y)-view.muzzle_socket.global_position).normalized()
					var error=(-view.muzzle_socket.global_basis.z.normalized()).angle_to(direction);aim_error=maxf(aim_error,error)
					check(error<.035,"Physical muzzle preserves height aiming; error "+str(error))
	# Stand/walk/run all use original lower-body clips, with gun held below chest.
	for speed in [0.0,2.0,5.0]:
		u.stance=0;u.stance_blend=0.0;u.facing=Vector2.UP;u.velocity=Vector2.UP*speed;u.aim_point=Vector2(0,-12);u.aim_height=1.0;view.body_yaw=0.0
		Motion.update(view,u,.016,20,float(view.weapon_profile.reload))
		check(str(view.source_clip).begins_with("Armature|"),"Keeps source locomotion without baked rifle arms")
		var chest=view.skeleton.to_global(view.skeleton.get_bone_global_pose(view.bone_indices.Spine02).origin)
		check(view.held.global_position.y<chest.y-.04,"Weapon supported below chest")
		check(maxf(contact_error(view,"L"),contact_error(view,"R"))<.012,"Walking does not break grip contact")
		var legs={}
		for side in ["L","R"]:
			for part in ["Thigh","Calf","Foot","ToeBase"]:
				var bone=view.skeleton.find_bone(side+"_"+part);legs[bone]=view.skeleton.get_bone_pose(bone)
		Heavy.pose(view,u,20,Motion)
		for bone in legs:check(legs[bone].is_equal_approx(view.skeleton.get_bone_pose(bone)),"Heavy upper layer preserves original leg/foot transforms")
	u.velocity=Vector2.ZERO
	for phase in [.05,.25,.50,.70,.95]:
		u.reload=float(view.weapon_profile.reload)*(1-phase);u.reload_duration=view.weapon_profile.reload
		Motion.update(view,u,.016,20,float(view.weapon_profile.reload))
		check(contact_error(view,"R")<.012,"Right hand supports gun during side-box reload")
	u.reload=0;u.holstered=true;Motion.update(view,u,.016,20,float(view.weapon_profile.reload))
	check(not view.muzzle.visible,"Holstering retains empty-hands branch")
	stage.free();print("MINIGUN_POSE_CHECK ",checks-failures.size(),"/",checks," passed; worst_grip_m=",worst," max_aim_radians=",aim_error)
	quit(0 if failures.is_empty() else 1)
