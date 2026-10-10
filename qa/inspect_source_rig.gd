extends SceneTree
func _initialize():run.call_deferred()
func run():
	var n=load("res://assets/tripo_source/source-rig-soldier.glb").instantiate();root.add_child(n)
	inspect(n)
	quit()
func inspect(n: Node):
	var extra=""
	if n is Node3D:extra=str(n.transform)
	print(n.get_path()," ",n.get_class()," ",extra)
	if n is Skeleton3D:
		print("BONES ",n.get_bone_count())
		for name in ["Root","Hip","Spine02","Head","L_Foot","R_Foot"]:
			var b=n.find_bone(name);print(name," ",b," ",n.get_bone_global_rest(b))
	if n is AnimationPlayer:
		print("ANIMATIONS ",n.get_animation_list())
		for name in n.get_animation_list():
			if 'walk' in name:
				var a=n.get_animation(name);print(name," ",a.length)
				for i in range(mini(8,a.get_track_count())):print(a.track_get_path(i)," TYPE ",a.track_get_type(i))
				for i in range(a.get_track_count()):
					if str(a.track_get_path(i)).ends_with(":Hip") and a.track_get_type(i)==Animation.TYPE_POSITION_3D:
						for k in range(3):print("KEY ",a.track_get_key_time(i,k)," ",a.track_get_key_value(i,k))
	for child in n.get_children():inspect(child)
