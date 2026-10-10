extends SceneTree
func _initialize():run.call_deferred()
func run():
	var stage=Node3D.new();root.add_child(stage)
	var view=preload("res://scripts/ink_art.gd").soldier(stage,0,false,true)
	var rig: Skeleton3D=view.skeleton
	for frame in range(1,160,8):
		preload("res://scripts/source_rig_motion.gd").sample(view,"Armature|slash",float(frame)/24.0)
		var hand=rig.to_global(rig.get_bone_global_pose(rig.find_bone("R_Hand")).origin)
		var left=rig.to_global(rig.get_bone_global_pose(rig.find_bone("L_Hand")).origin)
		print("SLASH ",frame," R ",hand," L ",left)
	stage.free();quit()
