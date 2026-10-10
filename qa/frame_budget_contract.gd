extends SceneTree
## Resource and frozen geometry checks only. No inputs, AI or world.step.
const OldWalls=preload("res://qa/performance/frame-budget-v38-source/reference_walls.gd")
const Summary=preload("res://scripts/runtime_performance.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<10:push_error(label)
func _initialize():run.call_deferred()
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	await process_frame
	game.update_camera(0);game.update_views(0)
	var current=game.wall_batches;var old=OldWalls.new();game.stage.add_child(old);old.configure(game.world.objects,game.object_views)
	var objects: Array=[];var cells: int=0
	for object in game.world.objects:
		if current.members.has(object.id) and object.rows>2:
			objects.append(object);cells+=object.hp.size()
			if cells>=240:break
	var timings=[[],[]]
	for repeat in range(10):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var batch=old if mode==0 else current
			var started:=Time.get_ticks_usec()
			for height in [1.15,INF]:
				for object in objects:game.object_views[object.id].cut_height=height;batch.changed(object)
				batch.flush()
			timings[mode].append((Time.get_ticks_usec()-started)/1000.0)
	# Damage selects baked cosmetic states; holes still expose all original faces immediately.
	for state in [.4,0.0,1.0]:
		for object in objects:
			var cell: int=int(object.hp.size()/2);object.hp[cell]=object.max_hp*state
		for height in [1.15,INF,1.15]:
			for object in objects:game.object_views[object.id].cut_height=height;old.changed(object);current.changed(object)
			old.flush();current.flush()
			for object in objects:preload("res://qa/baked_wall_geometry.gd").compare(game,object,check)
	var sources: Array=[]
	for node in game.stage.find_children("*","MeshInstance3D",true,false):
		if node.layers==0 and not node.is_transform_notification_enabled():sources.append(node)
	check(sources.size()>300,"batched sources omit duplicate renderer notifications")
	var source_transforms: Array=[]
	for node in sources:source_transforms.append(node.global_transform)
	var offset:=Vector3(3,.4,-2)
	game.stage.position+=offset
	for i in range(sources.size()):
		var expected: Transform3D=source_transforms[i];expected.origin+=offset
		check(sources[i].global_transform.is_equal_approx(expected),"source global transforms remain current without render notifications")
	game.stage.position-=offset
	check(game.player_occlusion.copies[0].is_transform_notification_enabled(),"visible occlusion copy retains renderer updates")
	game.crowd_batches.refresh();game.weapon_batches.camera=null;game.weapon_batches.refresh()
	var before_vertices: int=0;var after_vertices: int=0;var active_sources: int=0
	for group in game.weapon_batches.groups.values():
		if group.active==0:continue
		before_vertices+=int(group.key.get_slice("/",1))*int(group.active)
		after_vertices+=int(group.draw_count)*int(group.active)
		check(group.instances.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==group.draw_count,"weapon atlas submits exact largest active prefix")
	for entry in game.weapon_batches.entries.values():
		if not entry.source.is_visible_in_tree():continue
		active_sources+=1
		for handle in entry.handles:check(handle.count<=handle.group.draw_count,"weapon geometry never truncated")
	game.weapon_batches.camera=game.camera;game.weapon_batches.refresh()
	var camera: Camera3D=game.camera;var visible_before: int=0
	for group in game.weapon_batches.groups.values():visible_before+=int(group.active)
	check(visible_before>0,"camera culling retains weapons in the initial playable view")
	# Test culling conservativeness against every corner at sampled camera positions.
	var camera_origin:=camera.position
	var tested_corners: int=0;var culled_sources: int=0
	for offset_x in [-24.0,0.0,24.0]:
		camera.position=camera_origin+Vector3(offset_x,0,0);game.weapon_batches.refresh()
		for entry in game.weapon_batches.entries.values():
			var source: MeshInstance3D=entry.source;var bounds: AABB=source.mesh.get_aabb();var pose: Transform3D=source.global_transform
			if not game.weapon_batches.in_view(source,pose):culled_sources+=1
			for corner in range(8):
				var p: Vector3=pose*bounds.get_endpoint(corner)
				if root.get_visible_rect().has_point(camera.unproject_position(p)):
					tested_corners+=1
					check(game.weapon_batches.in_view(source,pose),"culling keeps a weapon with a visible AABB corner")
	camera.position=camera_origin
	check(tested_corners>0 and culled_sources>0,"camera test covers both visible and culled weapons")
	check(game.world.time==0 and game.world.shots==0,"no battle advancement")
	var result={"checks":checks,"failures":failures,"cut_cells":cells,"two_cut_switches":{"before":Summary.summary(timings[0]),"after":Summary.summary(timings[1])},"suppressed_source_notifications":sources.size(),"weapon_submitted_vertices":{"before":before_vertices,"after":after_vertices,"active_sources":active_sources,"onscreen_sources":visible_before,"tested_visible_corners":tested_corners,"tested_culled_sources":culled_sources},"simulation_time":game.world.time,"shots":game.world.shots}
	FileAccess.open("res://qa/performance/frame-budget.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("FRAME_BUDGET_CONTRACT "+JSON.stringify(result))
	game.free();quit(0 if failures==0 else 1)
