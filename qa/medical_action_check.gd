extends SceneTree
## State/resource/pose fixtures only. No game inputs, world stepping or screenshots.
const Source=preload("res://scripts/source_rig_character.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Medical=preload("res://scripts/medical_motion.gd")
const Equipment=preload("res://scripts/quick_equipment.gd")
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
	var world=World.new();world.catalog=Catalog.new();world.player=world.add_unit(Vector2.ZERO,true)
	var u: Dictionary=world.player
	check(not world.use_medicine("first-aid") and u.medical_feedback.kind=="full","Full health has explicit graphical feedback without spending stock")
	Equipment.tick(u,1);check(u.medical_feedback.is_empty(),"Feedback expires on simulation clock")
	u.health=70;u.grounded=false
	check(not world.use_medicine("bandage"),"Airborne use rejected before starting")
	u.grounded=true;world.use_medicine("bandage");Equipment.tick(u,.6)
	check(world.cancel_medicine() and u.health==70 and u.medical_stock.bandage==3,"Explicit cancel does not heal or consume")
	check(not world.cancel_medicine(),"Cancel has no effect on idle weapon state")
	for reason in ["damage","death","mount","vault","ladder","air"]:
		u.alive=true;u.mounted=-1;u.vault={};u.ladder={};u.grounded=true;u.health=70
		check(world.use_medicine("first-aid"),"Start before interruption: "+reason)
		match reason:
			"damage":u.health=60
			"death":u.alive=false
			"mount":u.mounted=0
			"vault":u.vault={"mode":"climb"}
			"ladder":u.ladder={"active":true}
			"air":u.grounded=false
		Equipment.tick(u,3.2)
		check(u.healing.is_empty() and u.medical_stock["first-aid"]==1 and u.health<=70,"Cancellation wins over elapsed treatment: "+reason)
	u.alive=true;u.mounted=-1;u.vault={};u.ladder={};u.grounded=true;u.health=190
	world.use_medicine("first-aid");Equipment.tick(u,3.1)
	check(u.health==200 and u.medical_stock["first-aid"]==0 and u.medical_feedback.kind=="complete","Completion capped at max HP, charged once and acknowledged")
	u.health=70;check(not world.use_medicine("first-aid") and u.medical_feedback.kind=="empty","Empty stock produces visual rejection")
	u.medical_stock["first-aid"]=1
	var stage=Node3D.new();root.add_child(stage)
	var reference=Source.soldier(stage,0,true)
	var view=Source.soldier(stage,0,true);view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle)
	view.weapon_profile=world.weapon_for(u);view.held=Props.weapon(view.rifle,view.weapon_profile)
	view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
	u.facing=Vector2(0,-1);u.equip_remaining=0
	for id in Equipment.MEDICAL_IDS:
		for stance in range(3):
			u.healing={};u.stance=stance;u.stance_blend=float(stance);u.velocity=Vector2.ZERO
			for settle in range(20):Motion.update(view,u,1.0/60,9,float(view.weapon_profile.reload))
			world.use_medicine(id)
			var finite=true;var max_step=0.0;var previous: Array=[];var min_separation=INF;var max_frame=0
			for frame in range(121):
				u.healing.remaining=u.healing.duration*(1-float(frame)/120)
				Motion.update(view,u,float(u.healing.duration)/120,10+frame/60.0,float(view.weapon_profile.reload))
				var positions=[]
				for side in ["L","R"]:
					var hand=Medical.wrist(view,side);finite=finite and hand.is_finite();positions.append(hand.origin)
				if frame>1:
					for index in range(2):
						var distance=positions[index].distance_to(previous[index])
						if distance>max_step:max_step=distance;max_frame=frame
				if frame>30 and frame<88:min_separation=minf(min_separation,positions[0].distance_to(positions[1]))
				previous=positions
				if frame==60:
					check(view.medical_visual.root.visible,"Medical prop shown: %s stance%d"%[id,stance])
					check(view.medical_visual.case.visible==(id=="first-aid") and view.medical_visual.roll.visible==(id=="bandage"),"Correct prop per treatment")
					check(not view.muzzle.visible and view.source_clip=="Armature|idle","Gun pose/flash released during treatment")
					if id=="first-aid":check(view.medical_visual.lid.rotation.x<-.8,"First aid lid opens during application")
					if stance==0:
						var data: Dictionary=view.source_info.clips.idle
						Motion.sample(reference,"Armature|idle",float(data.start)/24+fposmod(view.animation_time,float(data.duration)))
						for bone_name in ["L_Thigh","L_Calf","L_Foot","R_Thigh","R_Calf","R_Foot"]:
							var index=view.skeleton.find_bone(bone_name)
							check(view.skeleton.get_bone_pose(index).is_equal_approx(reference.skeleton.get_bone_pose(index)),"Original lower-body pose retained: "+bone_name)
			print("MEDICAL_POSE id=",id," stance=",stance," max_step=",max_step," frame=",max_frame," separation=",min_separation)
			check(finite,"All treatment bones finite: %s stance%d"%[id,stance])
			check(max_step<.085,"No frame-to-frame hand teleport: %s stance%d max%.4f"%[id,stance,max_step])
			check(min_separation>.055,"Hands remain separated: %s stance%d min%.4f"%[id,stance,min_separation])
			world.cancel_medicine();Motion.update(view,u,.2,15,float(view.weapon_profile.reload))
			check(not view.medical_visual.root.visible,"Cancelled props hidden")
	# Moving treatment keeps the original stride. Props are reused, not per-frame meshes.
	u.stance=0;u.stance_blend=0;u.velocity=Vector2(0,-2);u.health=70;world.use_medicine("bandage")
	var resource_id=view.medical_visual.roll.mesh.get_instance_id()
	for frame in range(20):Motion.update(view,u,1.0/60,20,float(view.weapon_profile.reload))
	check(view.source_clip=="Armature|walk","Medical overlay keeps original walk")
	check(view.medical_visual.roll.mesh.get_instance_id()==resource_id and Medical.resource("roll")==view.medical_visual.roll.mesh,"Shared medical meshes reused")
	check(load("res://scripts/combat_hud.gd")!=null and load("res://scripts/loot_panel.gd")!=null and load("res://scripts/proving_ground.gd")!=null,"Integrated UI and entry scene scripts compile")
	stage.free()
	print("MEDICAL_ACTION_CHECK checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
