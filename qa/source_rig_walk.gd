extends SceneTree
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
	view.root.queue_free()
	# A native rendered six-frame contact sheet of the actual walking clip.
	var viewport=SubViewport.new();viewport.size=Vector2i(1800,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var floor_root=Node3D.new();viewport.add_child(floor_root);Game.Art.box(floor_root,Vector3(0,-.06,0),Vector3(30,.1,30),Color("c6c4d8"),false)
	var environment=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("c6c4d8");environment.environment=env;floor_root.add_child(environment)
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.7;floor_root.add_child(camera);camera.position=Vector3(0,2.2,8);camera.look_at(Vector3(0,1,0));camera.current=true
	for i in range(6):
		var actor=Game.Art.soldier(floor_root,0,false,true);actor.root.position.x=-2.5+i;actor.body.rotation.y=PI*.8
		var t=float(info.clips.walk.start)/24+float(info.clips.walk.duration)*i/6
		Motion.sample(actor,"Rifle_walk",t);Game.Art.Style.update_shadow(actor)
		var label=Label.new();label.text="步态 %d / 6"%(i+1);label.add_theme_font_size_override("font_size",20);label.modulate=Color("686479");viewport.add_child(label);label.position=Vector2(camera.unproject_position(actor.root.position).x-52,715)
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw;viewport.get_texture().get_image().save_png("res://qa/source-walk-sequence.png")
	viewport.queue_free();stage.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
