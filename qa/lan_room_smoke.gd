extends SceneTree
## Run host and client in separate headless Godot processes.
func _initialize():call_deferred("run_smoke")

func run_smoke():
	change_scene_to_file("res://proving_ground.tscn")
	for index in range(4):await process_frame
	var game=current_scene
	if game==null or not game.is_node_ready():
		printerr("LAN_ROOM scene did not load");quit(2);return
	if "--lan-room-host" in OS.get_cmdline_user_args():
		if not game.lan.discovery.start_host():printerr("LAN_ROOM discovery host failed");quit(2);return
		print("LAN_ROOM_HOST_READY version=",game.BUILD_VERSION)
		await create_timer(30).timeout
		quit()
	else:
		var expected_ip=""
		var expected_version=game.BUILD_VERSION
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--lan-room-known="):expected_ip=arg.trim_prefix("--lan-room-known=")
			if arg.begins_with("--lan-room-expect-version="):expected_version=arg.trim_prefix("--lan-room-expect-version=")
		if not expected_ip.is_empty() and not game.lan.discovery.remember_host(expected_ip,false):
			printerr("LAN_ROOM invalid known host ",expected_ip);quit(2);return
		var targets: PackedStringArray=game.lan.discovery.broadcast_targets()
		for address in IP.get_local_addresses():
			var octets=address.split(".")
			if octets.size()==4 and address.begins_with("192.168."):
				var directed="%s.%s.%s.255"%[octets[0],octets[1],octets[2]]
				if not targets.has(directed):printerr("LAN_ROOM missing directed broadcast ",directed);quit(2);return
		game.home_ui.open_lan()
		var found=false
		for index in range(160):
			for candidate in game.lan.discovery.room_list():
				if expected_ip.is_empty() or str(candidate.endpoint).begins_with(expected_ip+":"):found=true;break
			if found:break
			await create_timer(.25).timeout
		if not found:printerr("LAN_ROOM discovery timed out");quit(2);return
		var room: Dictionary=game.lan.discovery.room_list()[0]
		var room_index=0
		if not expected_ip.is_empty():
			for index in range(game.lan.discovery.room_list().size()):
				if str(game.lan.discovery.room_list()[index].endpoint).begins_with(expected_ip+":"):
					room=game.lan.discovery.room_list()[index];room_index=index;break
		if str(room.version)!=expected_version or not str(room.endpoint).ends_with(":27829"):
			printerr("LAN_ROOM wrong room ",room);quit(2);return
		game.home_ui.room_list.select(room_index)
		game.home_ui.update_room_selection()
		if game.home_ui.join_room_button.disabled==game.lan.compatible_version(expected_version) or game.home_ui.room_list.item_count<1:
			printerr("LAN_ROOM room list mismatch rows=",game.home_ui.room_list.item_count);quit(2);return
		print("LAN_ROOM_CLIENT_OK room=",room.endpoint," rows=",game.home_ui.room_list.item_count," client_version=",game.BUILD_VERSION," host_version=",expected_version," targets=",targets)
		quit()
