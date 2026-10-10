extends SceneTree
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<12:printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	# Imported Skeleton3D/BoneAttachment3D finish their initial deferred setup.
	await process_frame
	var view: Dictionary=game.actors[0];var u: Dictionary=game.world.units[0];var renderer=game.crowd_batches
	var body: MeshInstance3D=view.model.find_child("Source_Body",true,false);var rig: Skeleton3D=view.skeleton
	var entry: Dictionary=renderer.entries[view.root.get_instance_id()]
	var original=body.mesh.surface_get_arrays(0);var merged=renderer.groups.shared.instances.mesh.surface_get_arrays(0)
	check(renderer.groups.size()==2 and renderer.groups.helmets.instances.visible_instance_count==0 and renderer.entries.size()==60,"all original sixty actors share one skin submission; empty detached-helmet pool does not draw")
	check(body.layers==0 and view.helmet.layers==0 and view.shadow.layers==0,"source render surfaces disabled without hiding animation/socket nodes")
	check(renderer.groups.shared.instances.use_colors,"custom-data instances explicitly initialize a neutral color")
	for pose in range(3):
		u.velocity=Vector2(0,-2.8) if pose==1 else Vector2.ZERO;u.stance=2 if pose==2 else 0;u.stance_blend=u.stance;u.walk=.75;u.facing=Vector2.from_angle(.7+pose)
		game.update_views(.033);rig.force_update_all_bone_transforms();renderer.refresh()
		await process_frame
		for index in range(0,original[Mesh.ARRAY_VERTEX].size(),37):
			var expected=Vector3.ZERO
			for influence in range(4):
				var binding=int(original[Mesh.ARRAY_BONES][index*4+influence]);var weight=float(original[Mesh.ARRAY_WEIGHTS][index*4+influence])
				expected+=(rig.get_bone_global_pose(entry.bone_map[binding])*body.skin.get_bind_pose(binding)*original[Mesh.ARRAY_VERTEX][index])*weight
			expected=rig.global_transform*expected
			var actual=Vector3.ZERO
			for influence in range(4):
				var bone=int(merged[Mesh.ARRAY_BONES][index*4+influence]);var weight=float(merged[Mesh.ARRAY_WEIGHTS][index*4+influence]);var row=entry.slot*64+bone
				var a=renderer.palette.get_pixel(0,row);var b=renderer.palette.get_pixel(1,row);var c=renderer.palette.get_pixel(2,row)
				var transform=Transform3D(Basis(Vector3(a.r,b.r,c.r),Vector3(a.g,b.g,c.g),Vector3(a.b,b.b,c.b)),Vector3(a.a,b.a,c.a))
				actual+=(transform*merged[Mesh.ARRAY_VERTEX][index])*weight
			actual=rig.global_transform*actual
			check(actual.distance_to(expected)<.001,"source skin matrices match GPU palette %d/%d error %.6f"%[pose,index,actual.distance_to(expected)])
		check(merged[Mesh.ARRAY_TEX_UV][137].distance_to(original[Mesh.ARRAY_TEX_UV][137])<.00001,"source texture UV preserved")
		var helmet_offset=original[Mesh.ARRAY_VERTEX].size()
		for surface in range(view.helmet.mesh.get_surface_count()):
			var source=view.helmet.mesh.surface_get_arrays(surface)
			var expected_color: Color=view.helmet.get_active_material(surface).get_shader_parameter("solid_color")
			for index in range(0,source[Mesh.ARRAY_VERTEX].size(),23):
				var expected: Vector3=view.helmet.global_transform*source[Mesh.ARRAY_VERTEX][index]
				var actual: Vector3=rig.global_transform*rig.get_bone_global_pose(view.bone_indices.Head)*merged[Mesh.ARRAY_VERTEX][helmet_offset+index]
				check(actual.distance_to(expected)<.001,"helmet keeps original attachment position pose=%d surface=%d index=%d error=%.6f"%[pose,surface,index,actual.distance_to(expected)])
				var color: Color=merged[Mesh.ARRAY_COLOR][helmet_offset+index]
				check(absf(color.r-expected_color.r)<.005 and absf(color.g-expected_color.g)<.005 and absf(color.b-expected_color.b)<.005,"helmet surface keeps original shell/band/rim pigment")
			helmet_offset+=source[Mesh.ARRAY_VERTEX].size()
	check(game.world.time==0 and game.world.shots==0,"resource checks never advance battle")
	for role in renderer.Classes.IDS:
		renderer.Classes.apply(view,role,int(u.team));renderer.register(view,int(u.team));renderer.refresh()
		check(renderer.entries.size()==60 and renderer.groups.shared.entries.size()==60,"class switch retains dense skin slots: "+role)
		check(renderer.entries[view.root.get_instance_id()].role==role,"all five original professions registered: "+role)
		for part in renderer.parts(view):check(part.node.layers==0,"new kit renders only in shared mesh")
	var saved_camera=renderer.camera;renderer.camera=null;renderer.refresh()
	check(renderer.groups.shared.instances.visible_instance_count==60,"all original actors retained when viewport culling is disabled")
	view.root.hide();renderer.refresh()
	check(renderer.groups.shared.instances.visible_instance_count==59,"hidden actor removed from GPU draw count")
	var occupied={}
	for current in renderer.entries.values():
		if current.draw_index>=0:occupied[current.draw_index]=true
	check(occupied.size()==59 and occupied.has(0) and occupied.has(58),"visible GPU slots stay dense after hiding an actor")
	view.root.show();renderer.refresh()
	check(renderer.groups.shared.instances.visible_instance_count==60,"returning actor restores original mesh without a new batch")
	renderer.camera=saved_camera
	print("CROWD_BATCH_CONTRACT checks=%d failures=%d"%[checks,failures]);game.free();quit(0 if failures==0 else 1)
