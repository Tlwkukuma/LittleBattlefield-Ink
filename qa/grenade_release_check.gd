extends SceneTree
## Original-rig pose sampling only. No gameplay inputs or automated playthrough.
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Props=preload("res://scripts/proving_art.gd")
const Ball=preload("res://scripts/grenade_ballistics.gd")
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	var world=World.new();world.catalog=Catalog.new();world.player=world.add_unit(Vector2.ZERO,true)
	world.equip("he-grenade");var u: Dictionary=world.player;u.equip_remaining=0
	var stage=Node3D.new();root.add_child(stage)
	var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
	view.weapon_profile=world.weapon_for(u);view.held=Props.weapon(view.rifle,view.weapon_profile)
	view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
	for stance in range(3):
		for low in [false,true]:
			for yaw in [0.0,PI*.5,PI,PI*1.5]:
				u.stance=stance;u.stance_blend=float(stance);u.facing=Vector2.from_angle(yaw);u.throw_state={"phase":"aim","age":1.0,"low":low}
				for frame in range(15):Motion.update(view,u,1.0/60,20,float(view.weapon_profile.reload))
				var palm_before=view.held.global_transform;var bone_before=view.skeleton.get_bone_global_pose(view.skeleton.find_bone("R_Hand"))
				var origin=Motion.grenade_release_origin(view,u,low)
				check(view.held.global_transform==palm_before and bone_before==view.skeleton.get_bone_global_pose(view.skeleton.find_bone("R_Hand")),"Release preview does not mutate the rig")
				u.throw_state.phase="windup";u.throw_state.age=1.0
				Motion.update(view,u,0,20,float(view.weapon_profile.reload))
				var actual: Vector3=view.held.global_position
				check(origin.distance_to(actual)<.004,"Predicted palm matches actual release: stance%d low%s yaw%.2f error%.4f"%[stance,low,yaw,origin.distance_to(actual)])
				var target=Vector3(u.facing.x*8,0,u.facing.y*8)
				var preview=world.grenade_solution(u,view.weapon_profile,target,low,origin)
				var live=world.grenade_solution(u,view.weapon_profile,target,low,actual)
				check(Vector3(preview.velocity).distance_to(live.velocity)<.03,"Preview and flight use matching initial velocities")
	# The same wall exit clipping applies to the read-only prediction and real release.
	check(load("res://scripts/grenade_preview.gd")!=null and load("res://scripts/proving_ground.gd")!=null,"Integration scripts compile")
	stage.free();print("GRENADE_RELEASE_CHECK ",checks-failures.size(),"/",checks," passed")
	quit(0 if failures.is_empty() else 1)
