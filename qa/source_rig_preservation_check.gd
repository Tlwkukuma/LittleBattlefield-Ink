extends SceneTree
## Original Blender/GLB resource samples only; excludes the historical render contact sheet.
const Game=preload("res://scripts/proving_ground.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
var failures=[]
var count=0
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	count+=1
	if not ok:failures.append(label);push_error(label)
func run():
	var stage=Node3D.new();root.add_child(stage);var view=Game.Art.soldier(stage,0,false,true);var rig: Skeleton3D=view.skeleton
	var info: Dictionary=view.source_info
	check(rig.get_bone_count()==41,"Original 41 bones retained")
	check(info.source_actions_unchanged and info.skin_weights_unchanged and info.rest_matrices_unchanged,"Original animation, weights and rest matrices unchanged in Blender")
	check(info.lower_body_curves_unchanged.walk and info.lower_body_curves_unchanged.run,"Rifle layers preserve lower-body curves")
	var max_error=0.0;var layer_error=0.0
	for clip in ["idle","walk","run","jump"]:
		var data: Dictionary=info.clips[clip]
		for i in range(0,data.samples.size(),3):
			Motion.sample(view,"Armature|"+clip,(float(data.start)+i)/24.0,false)
			var original={}
			for bone in ["L_Foot","R_Foot","L_ToeBase","R_ToeBase"]:
				var matrix: Array=data.samples[i][bone];var expected=Vector3(matrix[0][3],matrix[1][3],matrix[2][3]);var actual=rig.to_global(rig.get_bone_global_pose(rig.find_bone(bone)).origin)
				if actual.distance_to(expected)>max_error:
					max_error=actual.distance_to(expected)
					if max_error>.001:print("SAMPLE_DIFFERENCE ",clip," frame ",float(data.start)+i," ",bone," actual ",actual," expected ",expected," difference ",actual-expected)
				original[bone]=rig.get_bone_global_pose(rig.find_bone(bone))
			Motion.sample(view,"Rifle_"+clip,(float(data.start)+i)/24.0,false)
			for bone in original:
				var actual=rig.get_bone_global_pose(rig.find_bone(bone));layer_error=maxf(layer_error,actual.origin.distance_to(original[bone].origin));check(actual.basis.is_equal_approx(original[bone].basis),"Rifle layer preserves foot/toe orientation")
	check(max_error<.001,"Godot foot/toe positions match Blender samples within 1 mm: "+str(max_error))
	check(layer_error<.00001,"Rifle layer does not displace feet: "+str(layer_error))
	print("SOURCE RIG: ",count-failures.size(),"/",count," passed; max foot position error m=",max_error,"; layer error=",layer_error,"; failures=",failures)
	stage.free();quit(0 if failures.is_empty() else 1)
