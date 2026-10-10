extends SceneTree
## Frozen original scene: instance transforms, font resources and local CPU work.
## No battle stepping, decisions, firing, movement input or screenshot acceptance.
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<10:push_error(message)
func _initialize():run.call_deferred()
func refresh(game):
	game.crowd_batches.refresh();game.weapon_batches.refresh();game.rigid_batches.refresh();game.vehicle_part_batches.refresh();game.flash_batches.refresh()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 首关实例资源检查（自动关闭）")
	game.armory.hide();game._process(0)
	for i in range(8):await process_frame;game.hud_batches.refresh()
	var gpu=DisplayServer.get_name()!="headless"
	var offset=Vector3(.23,.06,-.17)
	var sources=[]
	for batch in [game.weapon_batches,game.rigid_batches]:
		for entry in batch.entries.values():
			if entry.translation!=null:sources.append(entry.source)
	for entry in game.vehicle_part_batches.entries:
		if entry.translation!=null:sources.append(entry.source)
	for view in game.actors:view.muzzle.show()
	var references={};var crowd_reference={}
	for view in game.actors:view.root.position+=offset
	for source in sources:references[source.get_instance_id()]=source.global_transform
	for view in game.actors:crowd_reference[view.root.get_instance_id()]=[view.skeleton.global_transform,view.shadow.global_transform]
	var flashes={}
	for entry in game.flash_batches.entries.values():
		if entry.translation!=null:
			for piece in entry.pieces:flashes[piece.node.get_instance_id()]=piece.node.global_transform*Transform3D(piece.handle.local)
	for view in game.actors:view.root.position-=offset;view.render_translation.offset=game.stage.global_basis*offset
	refresh(game)
	for batch in [game.weapon_batches,game.rigid_batches]:
		for entry in batch.entries.values():
			if entry.translation==null or not entry.source.is_visible_in_tree():continue
			for handle in entry.handles:
				if batch==game.weapon_batches and handle.index<0:continue
				check(handle.pose.is_equal_approx(references[entry.source.get_instance_id()]),"weapon/rigid translation matches original hierarchy")
	for entry in game.vehicle_part_batches.entries:
		if entry.translation!=null and entry.source.is_visible_in_tree():check(entry.pose.is_equal_approx(references[entry.source.get_instance_id()]),"rigid part palette preserves translated sockets")
	for entry in game.crowd_batches.entries.values():
		if entry.has("helmet") or entry.draw_index<0:continue
		check(entry.transform.is_equal_approx(crowd_reference[entry.view.root.get_instance_id()][0]),"crowd original skin transform")
		if gpu:check(game.crowd_batches.shadows.get_instance_transform(entry.slot).is_equal_approx(crowd_reference[entry.view.root.get_instance_id()][1]),"shadow follows the same translation")
	for entry in game.flash_batches.entries.values():
		if entry.translation!=null and entry.visible:
			for piece in entry.pieces:check(piece.handle.pose.is_equal_approx(flashes[piece.node.get_instance_id()]),"muzzle flash follows same interpolation")
	for view in game.actors:view.render_translation.offset=Vector3.ZERO
	refresh(game)
	# Original and retained HUD geometry use the same shaped glyph rectangles.
	var hud=game.hud_batches;var canvas=hud.glyph_canvas
	var quad=canvas.instances.mesh.surface_get_arrays(0)
	if gpu:
		for item in hud.items:
			var slots: Array=item.get("glyph_slots",[])
			for i in range(slots.size()):
				var transform=canvas.instances.get_instance_transform_2d(slots[i]);var custom=canvas.instances.get_instance_custom_data(slots[i])
				for corner in range(4):
					var at=Vector2(quad[Mesh.ARRAY_VERTEX][corner].x,quad[Mesh.ARRAY_VERTEX][corner].y)
					check((transform*at).distance_to(item.geometry.vertices[i*4+corner])<.001,"GPU canvas quad keeps original pixel position")
					check((Vector2(custom.r,custom.g)+quad[Mesh.ARRAY_TEX_UV][corner]*Vector2(custom.b,custom.a)).distance_to(item.geometry.uvs[i*4+corner])<.0001,"GPU glyph UV orientation and atlas coordinates")
	var writes: int=canvas.writes
	for i in range(60):hud.refresh()
	check(canvas.writes==writes,"unchanged HUD has no glyph uploads")
	game.hud.text="HP 123 | 命中 42 | 75 FPS";hud.dirty=true;hud.refresh()
	check(canvas.writes-writes<100,"counter changes upload one label, not whole HUD")
	var times=[]
	for repeat in range(10):
		var start=Time.get_ticks_usec()
		for i in range(120):game.hud.text="HP %d | 命中 42 | 75 FPS"%(100+i%100);hud.dirty=true;hud.refresh()
		times.append((Time.get_ticks_usec()-start)/1000.0)
	check(game.world.time==0 and game.world.shots==0,"no automated gameplay")
	print("V41_RESOURCE "+JSON.stringify({"checks":checks,"failures":failures,"gpu":gpu,"title":root.title,"hud_120_changes":preload("res://scripts/runtime_performance.gd").summary(times),"simulation_time":game.world.time,"shots":game.world.shots}))
	game.free();quit(0 if failures==0 else 1)
