extends SceneTree
## Numeric GPU equivalence in the frozen original entry; no screenshots or play.
func _initialize():run.call_deferred()
func capture(game,native: bool,missing: bool=false) -> Image:
	game.wall_batches.visible=not native and not missing;game.weapon_batches.visible=not native and not missing
	for id in game.wall_batches.members:game.object_views[id].mesh.layers=1 if native else 0
	for entry in game.weapon_batches.entries.values():entry.source.layers=1 if native else 0
	for frame in range(4):await process_frame
	return root.get_texture().get_image()
func difference(a: Image,b: Image) -> int:
	var aa=a.get_data();var bb=b.get_data();var channels=aa.size()/(a.get_width()*a.get_height());var error=0
	for at in range(0,aa.size(),channels):
		for channel in range(3):error+=absi(int(aa[at+channel])-int(bb[at+channel]))
	return error
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 第一关 · GPU 网格一致性检查（自动关闭）");print("RESOURCE_WINDOW ",root.title)
	for frame in range(2):await process_frame
	game._process(0);game.ui.hide();game.crowd_batches.refresh();game.vehicle_part_batches.refresh();game.rigid_batches.refresh();game.weapon_batches.refresh()
	game.camera.position+=Vector3(-game.world.player.position.x,0,-game.world.player.position.y);game.camera.size=96
	var failures=0
	var previous_image: Image
	for state in [1.0,0.4,0.0]:
		for object in game.world.objects:
			if not game.wall_batches.members.has(object.id):continue
			var index=int(object.hp.size()/2);object.hp[index]=object.max_hp*state
			game.object_views[object.id].mesh.mesh=preload("res://scripts/terrain_art.gd").wall_mesh(object)
			game.wall_batches.changed(object)
		game.wall_batches.flush()
		var expected=await capture(game,true);var actual=await capture(game,false);var missing=await capture(game,false,true)
		var error=difference(expected,actual);var control=difference(expected,missing)
		var changed=difference(expected,previous_image) if previous_image!=null else 0;previous_image=expected
		print("GPU_RETAINED_MATCH state=",state," error=",error," missing_control=",control," damage_change=",changed)
		if control<1000 or error>control*.04:failures+=1
		if state!=1.0 and changed<1000:failures+=1
	print("GPU_RETAINED_CONTRACT failures=",failures," time=",game.world.time," shots=",game.world.shots)
	game.free();quit(0 if failures==0 else 1)
