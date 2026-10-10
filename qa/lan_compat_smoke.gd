extends SceneTree
## Joins an existing campaign, confirms initial state, then leaves without input.
func _initialize():call_deferred("run_smoke")

func run_smoke():
	var host_ip="192.168.23.181"
	var direct=false
	var linger=0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lan-compat-host="):host_ip=arg.trim_prefix("--lan-compat-host=")
		if arg=="--lan-compat-direct":direct=true
		if arg.begins_with("--lan-compat-linger="):linger=float(arg.trim_prefix("--lan-compat-linger="))
	change_scene_to_file("res://proving_ground.tscn")
	for index in range(4):await process_frame
	var game=current_scene
	if game==null or not game.is_node_ready():
		printerr("LAN_COMPAT scene failed");quit(2);return
	game.lan.status_changed.connect(func(status):print("LAN_COMPAT_STATUS ",status))
	var target={"endpoint":"%s:27829"%host_ip,"version":"unknown"} if direct else {}
	if not direct:
		game.lan.discovery.remember_host(host_ip,false)
		game.home_ui.open_lan()
		for index in range(60):
			for room in game.lan.discovery.room_list():
				if str(room.endpoint).begins_with(host_ip+":"):target=room;break
			if not target.is_empty():break
			await create_timer(.25).timeout
	if target.is_empty():
		printerr("LAN_COMPAT room not discovered");quit(2);return
	if not direct and not game.lan.compatible_version(str(target.version)):
		printerr("LAN_COMPAT room version unsupported ",target.version);quit(2);return
	if not game.lan.join_game(str(target.endpoint)):
		printerr("LAN_COMPAT join did not start");quit(2);return
	for index in range(120):
		if game.lan.is_client():break
		if game.lan.mode=="offline":break
		await create_timer(.25).timeout
	if not game.lan.is_client():
		printerr("LAN_COMPAT handshake failed mode=",game.lan.mode)
		quit(2);return
	print("LAN_COMPAT_JOIN_OK host=",target.endpoint," host_version=",target.version," client_version=",game.BUILD_VERSION," unit=",game.lan.assigned_unit," campaign_time=",game.world.time)
	if linger>0:await create_timer(linger).timeout
	game.lan.stop()
	quit()
