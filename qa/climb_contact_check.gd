extends SceneTree
## Static geometry and sampled source-rig poses only. No input, world.step or rendering.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Props=preload("res://scripts/proving_art.gd")
var catalog=Catalog.new()
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fixture(height: float,angle: float) -> RefCounted:
	var plan=catalog.range_plan();plan.instances=[];plan.trees=[];plan.vehicles=[];plan.emplacements=[];plan.units.red=[]
	var axis=Vector2.RIGHT.rotated(angle)*2.5;var center=Vector2(0,-2)
	plan.deployment.player={"x":2000,"y":1400}
	plan.looseSegments=[{"id":"pose-wall","componentId":"wall.brick","x1":2000+(center.x-axis.x)*40,"y1":1400+(center.y-axis.y)*40,"x2":2000+(center.x+axis.x)*40,"y2":1400+(center.y+axis.y)*40,"thickness":20,"godot3d":{"height":height}}]
	var world=World.new();world.setup(plan,catalog);world.player.facing=Vector2.UP.rotated(angle);world.player.position=center-world.player.facing*.85
	return world
func point(view: Dictionary,name: String) -> Vector3:
	return view.skeleton.to_global(view.skeleton.get_bone_global_pose(view.skeleton.find_bone(name)).origin)
func run():
	var stage=Node3D.new();root.add_child(stage)
	for height in [.65,1.15,1.85]:
		for angle in [0.0,.70,PI*.5]:
			var world=fixture(height,angle);var u: Dictionary=world.player;var path=Traversal.find_vault(world,u,u.facing)
			var label="h=%.2f angle=%.2f"%[height,angle]
			check(not path.is_empty(),"Valid path "+label)
			if path.is_empty():continue
			u.velocity=u.facing*5.8
			var running=Traversal.find_vault(world,u,u.facing)
			check(not running.is_empty() and running.duration<path.duration,"Real approach speed shortens movement "+label)
			u.velocity=Vector2.ZERO
			var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
			view.weapon_profile=catalog.weapons.m416;view.held=Props.weapon(view.rifle,view.weapon_profile);view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
			view.root.position=Vector3(u.position.x,0,u.position.y);u.aim_point=u.position+u.facing*10
			Motion.update(view,u,.016,0,2.1)
			path.lead=u.get("traversal_lead",-1.0);u.vault=path;u.grounded=false
			var finite=true;var clear=true;var legs_clear=true;var min_boot_clearance=INF
			var hand_error=0.0;var locked_hands=0;var foot_error=0.0;var locked_feet=0
			var lengths=[]
			for side in ["L","R"]:lengths.append([point(view,side+"_Upperarm").distance_to(point(view,side+"_Forearm")),point(view,side+"_Forearm").distance_to(point(view,side+"_Hand")),point(view,side+"_Thigh").distance_to(point(view,side+"_Calf")),point(view,side+"_Calf").distance_to(point(view,side+"_Foot"))])
			var length_error=0.0;var worst_boot="";var joints_clear=true;var worst_joint=""
			var previous_feet=[];var previous_root: Vector3=view.root.position;var max_foot_step=0.0;var worst_step="";var worst_contact=""
			for frame in range(101):
				var t=frame/100.0;var sample=Traversal.sample_vault(path,t)
				u.position=sample.position;u.elevation=sample.elevation;u.vault_progress=t;view.root.position=Vector3(u.position.x,u.elevation,u.position.y)
				clear=clear and not Traversal.vault_blocked(world,sample)
				Motion.update(view,u,path.duration/100,t*path.duration,2.1)
				for part in [["Hip",.24],["Spine02",.28],["Head",.39],["L_Calf",.12],["R_Calf",.12]]:
					var at=point(view,part[0]);var radius=float(part[1]);var depth=(Vector2(at.x,at.z)-Vector2(path.hand_point)).dot(path.normal)
					if depth>-radius and depth<path.width+radius and at.y-radius<path.height-.015:
						joints_clear=false;worst_joint="%s t=%.2f depth=%.3f height=%.3f"%[part[0],t,depth,at.y]
				for bone in range(view.skeleton.get_bone_count()):finite=finite and view.skeleton.get_bone_global_pose(bone).is_finite()
				for side in range(2):
					var name="L" if side==0 else "R"
					var foot_at=point(view,name+"_Foot")
					if previous_feet.size()==2:
						# Subtract whole-character travel: the accelerating fall is expected,
						# an ankle jumping across the ledge relative to that motion is not.
						var step=maxf(0,foot_at.distance_to(previous_feet[side])-view.root.position.distance_to(previous_root))
						if step>max_foot_step:max_foot_step=step;worst_step="%s t=%.2f"%[name,t]
					if frame==0:previous_feet.append(foot_at)
					else:previous_feet[side]=foot_at
					var observed=[point(view,name+"_Upperarm").distance_to(point(view,name+"_Forearm")),point(view,name+"_Forearm").distance_to(point(view,name+"_Hand")),point(view,name+"_Thigh").distance_to(point(view,name+"_Calf")),point(view,name+"_Calf").distance_to(point(view,name+"_Foot"))]
					for part in range(4):length_error=maxf(length_error,absf(observed[part]-lengths[side][part]))
					for bone in [name+"_Foot",name+"_ToeBase"]:
						var at=point(view,bone);var depth=(Vector2(at.x,at.z)-Vector2(path.hand_point)).dot(path.normal)
						if depth>-.08 and depth<path.width+.08:
							if at.y-path.height<min_boot_clearance:worst_boot="%s t=%.2f depth=%.3f at=%s"%[bone,t,depth,str(at)]
							min_boot_clearance=minf(min_boot_clearance,at.y-path.height)
							legs_clear=legs_clear and at.y>path.height+.07
				for contact in view.vault_contacts.hands:
					if contact.weight>.98:locked_hands+=1;hand_error=maxf(hand_error,point(view,contact.side+"_Hand").distance_to(contact.target))
				for contact in view.vault_contacts.feet:
					if contact.weight>.99:
						locked_feet+=1;var error=point(view,contact.side+"_Foot").distance_to(contact.target)
						if error>foot_error:worst_contact="%s t=%.2f"%[contact.side,t]
						foot_error=maxf(foot_error,error)
				previous_root=view.root.position
			check(clear,"Whole path keeps physical clearance "+label)
			check(finite and length_error<.003,"Original bone lengths remain finite and unchanged "+label+" error="+str(length_error))
			check(legs_clear,"Boot/toe points clear the ledge "+label+" clearance="+str(min_boot_clearance)+" "+worst_boot)
			check(joints_clear,"Knees, hips, jacket and helmet clear the wall "+label+" "+worst_joint)
			check(max_foot_step<.15,"No sudden boot target snap beyond root travel "+label+" step="+str(max_foot_step)+" "+worst_step)
			check(locked_hands>0 and hand_error<.05,"Actual support hand reaches its fixed ledge contact "+label+" samples="+str(locked_hands)+" error="+str(hand_error))
			check(locked_feet>0 and foot_error<.09,"Planted feet reach their support "+label+" error="+str(foot_error)+" "+worst_contact)
			print("CONTACT_METRICS ",label," hand_samples=",locked_hands," hand_error=",hand_error," foot_error=",foot_error," boot_clearance=",min_boot_clearance," duration=",path.duration)
			u.vault={};u.grounded=true;u.velocity=Vector2.ZERO
			for frame in range(15):Motion.update(view,u,.016,path.duration+.016*frame,2.1)
			check(view.source_clip=="Rifle_idle" and view.vault_exit_age>=.18,"Returns to original locomotion "+label)
			view.root.free()
	# Geometry-only regression checks for the earlier wall-edge trapping issue.
	for gap in [.55,.85,1.35]:
		var world=fixture(1.15,0);world.player.position=Vector2(0,-2)+Vector2.DOWN*gap
		var path=Traversal.find_vault(world,world.player,Vector2.UP)
		check(not path.is_empty(),"Near-wall approach remains available gap="+str(gap))
		if path.is_empty():continue
		check((Vector2(path.approach)-Vector2(path.start)).dot(Vector2.UP)>=-.0001,"Approach does not shuffle backwards gap="+str(gap))
		var clear=true
		for frame in range(151):clear=clear and not Traversal.vault_blocked(world,Traversal.sample_vault(path,frame/150.0))
		check(clear,"Close approach and landing keep live collision clearance gap="+str(gap))
	var too_high=fixture(2.5,0)
	check(Traversal.find_vault(too_high,too_high.player,Vector2.UP).is_empty(),"2.5m obstacle remains unclimbable")
	stage.free()
	print("CLIMB_CONTACT_CHECK ",checks-failures.size(),"/",checks," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
