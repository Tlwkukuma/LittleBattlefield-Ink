extends SceneTree
## Measures and checks repeated wall-state application without gameplay input.
func _initialize():call_deferred("run_probe")

func run_probe():
	change_scene_to_file("res://proving_ground.tscn")
	for index in range(4):await process_frame
	var game=current_scene
	if game==null or not game.is_node_ready():
		printerr("LAN_SNAPSHOT scene failed");quit(2);return
	game.start_level01()
	var marked=0
	for object in game.world.objects:
		if not object.has("hp") or marked>=100:continue
		object.revision=1
		marked+=1
	var state=game.lan.make_snapshot(true,true)
	var bytes=var_to_bytes(state).size()
	var base_bytes=var_to_bytes(game.lan.make_snapshot(false,false)).size()
	var encoded=var_to_bytes(state)
	var started_compress=Time.get_ticks_usec()
	var compressed=encoded.compress(FileAccess.COMPRESSION_FASTLZ)
	var compress_us=Time.get_ticks_usec()-started_compress
	var restored=compressed.decompress(encoded.size(),FileAccess.COMPRESSION_FASTLZ)
	if restored!=encoded:printerr("LAN_SNAPSHOT compression roundtrip failed");quit(2);return
	var wrapper=game.lan.pack_snapshot(state)
	var unpacked=game.lan.unpack_snapshot(wrapper)
	if unpacked.is_empty() or var_to_bytes(unpacked)!=encoded:printerr("LAN_SNAPSHOT RPC wrapper roundtrip failed");quit(2);return
	print("LAN_SNAPSHOT_SIZE bytes=",bytes," base_bytes=",base_bytes," fastlz_bytes=",compressed.size()," compress_us=",compress_us," units=",state.units.size()," objects=",state.objects.size()," total_objects=",game.world.objects.size())
	game.lan.apply_snapshot(state)
	game.pending_rebuild.clear()
	var started=Time.get_ticks_usec()
	game.lan.apply_snapshot(state)
	var elapsed=Time.get_ticks_usec()-started
	print("LAN_SNAPSHOT_REPEAT elapsed_us=",elapsed," redundant_rebuilds=",game.pending_rebuild.size())
	if game.pending_rebuild.size()!=0:printerr("LAN_SNAPSHOT repeated objects rebuilt");quit(2);return
	quit()
