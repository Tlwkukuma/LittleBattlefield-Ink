extends SceneTree
## Resource/pose and path samples only; no world.step, input injection or rendering.
const Contact=preload("res://qa/climb_contact_check.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Props=preload("res://scripts/proving_art.gd")
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func hip(view: Dictionary) -> Vector3:
	return view.skeleton.to_global(view.skeleton.get_bone_global_pose(view.bone_indices.Hip).origin)
func run():
	var fixture=Contact.new();var stage=Node3D.new();root.add_child(stage)
	var worst_entry=0.0;var worst_exit=0.0;var worst_offset=0.0;var worst_step=0.0
	for height in [.65,1.15,1.85]:
		for angle in [0.0,.70,PI]:
			for speed in [3.4,5.8]:
				for phase in [.1,.45,.85]:
					var world=fixture.fixture(height,angle);var u: Dictionary=world.player
					var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
					view.weapon_profile=fixture.catalog.weapons.m416;view.held=Props.weapon(view.rifle,view.weapon_profile)
					view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
					view.root.position=Vector3(u.position.x,0,u.position.y);u.velocity=u.facing*speed
					Motion.update(view,u,.016,0,2.1)
					var clip="run" if speed>4 else "walk"
					view.animation_time=phase*float(view.source_info.clips[clip].duration)
					Motion.update(view,u,.16,.16,2.1)
					var before=hip(view);var path=Traversal.find_vault(world,u,u.facing)
					var label="h=%.2f yaw=%.2f speed=%.1f phase=%.2f"%[height,angle,speed,phase]
					check(not path.is_empty(),"Running path available "+label)
					if path.is_empty():view.root.free();continue
					u.vault=path;u.grounded=false;u.velocity=Vector2.ZERO;u.vault_progress=0.0
					Motion.update(view,u,0,.16,2.1)
					var entry=hip(view).distance_to(before);worst_entry=maxf(worst_entry,entry)
					check(entry<.05,"Entry preserves visible pelvis "+label+" shift="+str(entry))
					var previous=hip(view);var previous_root: Vector3=view.root.position;var step_max=0.0;var offset_max=0.0;var step_at=0.0
					var count=ceili(path.duration*120)
					for frame in range(1,count+1):
						var t=float(frame)/count;var at=Traversal.sample_vault(path,t)
						u.position=at.position;u.elevation=at.elevation;u.vault_progress=t;view.root.position=Vector3(u.position.x,u.elevation,u.position.y)
						Motion.update(view,u,path.duration/count,.16+t*path.duration,2.1)
						var current=hip(view);var residual=(current-previous)-(view.root.position-previous_root)
						if residual.length()>step_max:step_max=residual.length();step_at=t
						var local=view.root.to_local(current);offset_max=maxf(offset_max,Vector2(local.x,local.z).length())
						previous=current;previous_root=view.root.position
					worst_offset=maxf(worst_offset,offset_max);worst_step=maxf(worst_step,step_max)
					check(offset_max<.45,"Pose remains attached to traversal path "+label+" offset="+str(offset_max))
					check(step_max<.09,"No pelvis snap during traversal "+label+" step="+str(step_max)+" t="+str(step_at))
					before=hip(view);u.vault={};u.grounded=true;u.velocity=u.facing*speed
					Motion.update(view,u,0,path.duration+.16,2.1)
					var exit_shift=hip(view).distance_to(before);worst_exit=maxf(worst_exit,exit_shift)
					check(exit_shift<.05,"Exit preserves visible pelvis "+label+" shift="+str(exit_shift))
					previous=hip(view);var recovery_step=0.0;var recovery_offset=0.0
					for frame in range(1,19):
						Motion.update(view,u,1.0/60,path.duration+.16+frame/60.0,2.1)
						var current=hip(view);recovery_step=maxf(recovery_step,current.distance_to(previous))
						var local=view.root.to_local(current);recovery_offset=maxf(recovery_offset,Vector2(local.x,local.z).length());previous=current
					check(recovery_step<.09 and recovery_offset<.20,"Landing blends back to in-place locomotion "+label+" step="+str(recovery_step)+" offset="+str(recovery_offset))
					view.root.free()
	fixture.free();stage.free()
	print("CLIMB_TRANSITION_CHECK ",checks-failures.size(),"/",checks," worst_entry=",worst_entry," worst_exit=",worst_exit," worst_offset=",worst_offset," worst_step=",worst_step)
	quit(0 if failures.is_empty() else 1)
