extends SceneTree
func _initialize():call_deferred("run")
func run():
	change_scene_to_file("res://proving_ground.tscn")
	for i in range(4):await process_frame
	var game=current_scene
	game.lan.status_changed.connect(func(message):print("CONNECT_STATUS ",Time.get_ticks_msec()," ",message))
	game.lan.multiplayer.connection_failed.connect(func():print("CONNECT_FAILED_RETURNED"))
	game.lan.multiplayer.connected_to_server.connect(func():print("CONNECT_TRANSPORT_CONNECTED"))
	game.show_lan()
	print("CONNECT_JOIN_START")
	var address="192.168.23.181"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trace-address="):address=arg.trim_prefix("--trace-address=")
	game.lan.join_game(address)
	print("CONNECT_JOIN_RETURNED mode=",game.lan.mode)
	var deadline=Time.get_ticks_msec()+65000
	var joined_ms=0
	while Time.get_ticks_msec()<deadline:
		await create_timer(1).timeout
		print("CONNECT_ALIVE mode=",game.lan.mode," time=",game.world.time)
		var bridge=game.lan.get("ipv4_transport")
		if bridge!=null:print("CONNECT_BRIDGE sent=",bridge.sent," received=",bridge.received," wire=",bridge.wire_received," source=",bridge.last_sender," client_port=",bridge.client_port)
		if game.lan.is_client():
			if joined_ms==0:joined_ms=Time.get_ticks_msec();print("CONNECT_JOINED unit=",game.lan.assigned_unit)
			var remote=game.multiplayer.multiplayer_peer.get_peer(1)
			print("CONNECT_METRICS fps=",Engine.get_frames_per_second()," ping=",remote.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)," throttle=",remote.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE),game.lan.diagnostics_text())
			if "--trace-hold" not in OS.get_cmdline_user_args() or Time.get_ticks_msec()-joined_ms>35000:
				print("CONNECT_STOP_BEGIN");game.lan.stop();print("CONNECT_STOP_RETURNED");quit();return
		if game.lan.mode=="offline":quit();return
	quit(2)
