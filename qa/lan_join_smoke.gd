extends SceneTree
## Run in two Godot processes with -- --lan-smoke-host / --lan-smoke-client.
func _initialize():call_deferred("run_smoke")

func run_smoke():
	change_scene_to_file("res://proving_ground.tscn")
	for i in range(4):await process_frame
	var game=current_scene
	if game==null or not game.is_node_ready():
		printerr("LAN_SMOKE scene did not load");quit(2);return
	if "--lan-smoke-host" in OS.get_cmdline_user_args():
		game.start_level01()
		game.world.player.position+=Vector2(1.2,0)
		var changed: Dictionary=game.world.objects[0]
		changed.hp[0]=maxf(0,float(changed.hp[0])-8)
		changed.revision+=1;game.world.topology_revision+=1
		if not game.lan.host_game():printerr("LAN_SMOKE host failed");quit(2);return
		print("LAN_SMOKE_HOST_READY version=",game.BUILD_VERSION," unit=",game.world.player.id," time=",game.world.time)
		if "--zero-background-fx" in OS.get_cmdline_user_args():
			physics_frame.connect(func():game.lan.fx_budget=0)
		for i in range(2400):
			await process_frame
			if game.lan.peer_ready.values().has(true):break
		if game.lan.peer_ready.values().has(true):
			changed.hp[0]=maxf(0,float(changed.hp[0])-8)
			changed.revision+=1;game.world.topology_revision+=1
			print("LAN_SMOKE_HOST_LIVE_CHANGE revision=",changed.revision)
		var end=Time.get_ticks_msec()+40000
		while not game.lan.peer_units.is_empty() and Time.get_ticks_msec()<end:await create_timer(.1).timeout
		print("LAN_SMOKE_HOST_DONE peers=",game.lan.peer_units.size()," time=",game.world.time," max_realtime_bytes=",game.lan.maximum_realtime_bytes," coalesced=",game.lan.coalesced_snapshots)
		if game.lan.maximum_realtime_bytes>1100:printerr("LAN_SMOKE datagram exceeds budget");quit(2);return
		quit()
	else:
		var join_address="127.0.0.1"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--smoke-address="):join_address=arg.trim_prefix("--smoke-address=")
		if not game.lan.join_game(join_address):
			printerr("LAN_SMOKE connect failed");quit(2);return
		for i in range(900):
			await process_frame
			if game.lan.is_client():break
		if not game.lan.is_client():printerr("LAN_SMOKE join timed out mode=",game.lan.mode);quit(2);return
		var unit=game.world.player
		var changed=game.world.objects[0]
		if not game.world.campaign_active() or int(unit.id)!=game.lan.assigned_unit or int(unit.id)==0 or int(changed.revision)<1:
			printerr("LAN_SMOKE state mismatch unit=",unit.id," object_revision=",changed.revision);quit(2);return
		var joined_at=game.world.time
		for i in range(900):
			await process_frame
			if game.world.time>joined_at+.5:break
		if game.world.time<=joined_at+.5:
			printerr("LAN_SMOKE snapshots stalled at ",game.world.time);quit(2);return
		game.lan.request_action("stance",1)
		print("LAN_SMOKE_CLIENT_ACTION_SENT path=",game.lan.get_path()," peer=",game.multiplayer.get_unique_id()," status=",game.multiplayer.multiplayer_peer.get_connection_status()," time=",game.world.time)
		# Headless clients may render many frames before the host has processed
		# a reliable RPC. Wait for the network result in real time.
		for i in range(120):
			if int(game.world.player.stance)==1:break
			await create_timer(.05).timeout
		if int(game.world.player.stance)!=1:
			printerr("LAN_SMOKE action failed stance=",game.world.player.stance," phase=",game.world.campaign.phase," alive=",game.world.player.alive," grounded=",game.world.player.grounded," mode=",game.lan.mode," time=",game.world.time);quit(2);return
		var start=Vector2(unit.position)
		var direction=Vector2.RIGHT
		for candidate in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			if not game.world.blocked(start+candidate*1.5,.32,1.5,-1,unit.elevation):direction=candidate;break
		game.set_physics_process(false)
		for i in range(90):
			game.lan.submit_input({"movement":direction,"aim":start+direction*8,"aim_height":unit.elevation+1,"trigger":false,"pressed":false,"aiming":false,"brake":false,"sprint":false,"jump":false,"fire_allowed":false})
			await process_frame
		game.lan.submit_input(game.lan.idle_input(unit))
		for i in range(30):await process_frame
		if unit.position.distance_to(start)<.2 or int(changed.revision)<2:
			printerr("LAN_SMOKE live sync failed moved=",unit.position.distance_to(start)," object_revision=",changed.revision," time=",game.world.time);quit(2);return
		for i in range(12):
			var release=game.lan.idle_input(unit);release.fire_allowed=true
			game.lan.submit_input(release);await process_frame
		var shot_before=int(unit.shot_index)
		var cosmetic_before=int(game.fx.cosmetic_shots.get(int(unit.id),0))
		var ammo_before=int(unit.ammo)
		if game.world.weapon_for(unit).kind not in ["mortar","grenade","melee"]:
			for i in range(150):
				game.lan.submit_input({"movement":Vector2.ZERO,"aim":unit.position+direction*18,"aim_height":unit.elevation+1,"trigger":true,"pressed":i<12,"aiming":false,"brake":false,"sprint":false,"jump":false,"fire_allowed":true})
				await process_frame
			game.lan.submit_input(game.lan.idle_input(unit))
			for i in range(20):await process_frame
			if int(unit.shot_index)<=shot_before:
				printerr("LAN_SMOKE remote fire failed shot_index=",unit.shot_index," weapon=",unit.weapon_id," ammo_before=",ammo_before," ammo_after=",unit.ammo," reload=",unit.reload," cooldown=",unit.cooldown," busy=",game.QuickEquipment.busy(unit)," alive=",unit.alive," assigned=",game.lan.assigned_unit," player=",game.world.player.id," vault=",unit.vault," ladder=",unit.ladder," mode=",unit.get("fire_mode",""));quit(2);return
		if game.lan.requested_version==game.BUILD_VERSION and game.lan.motion_frames_received<=0:
			printerr("LAN_SMOKE fast motion path received no packets");quit(2);return
		if game.lan.requested_version==game.BUILD_VERSION:
			var old_state=game.lan.make_snapshot()
			var expected=unit.position+Vector2(.25,0)
			var newer_time=maxf(float(old_state.time),float(unit.get("net_motion_time",0)))+.1
			game.lan.apply_motion_frame({"type":"motion","time":newer_time,"units":PackedFloat32Array([unit.id,expected.x,expected.y,unit.elevation,unit.velocity.x,unit.velocity.y,unit.facing.x,unit.facing.y])})
			game.lan.apply_snapshot(old_state)
			if unit.position.distance_to(expected)>.01:
				printerr("LAN_SMOKE stale reliable snapshot rolled back newer movement");quit(2);return
		print("LAN_SMOKE_CLIENT_OK version=",game.BUILD_VERSION," unit=",unit.id," time=",game.world.time," object_revision=",changed.revision," stance=",unit.stance," moved=",unit.position.distance_to(start)," shots=",int(unit.shot_index)-shot_before," fast_motion_packets=",game.lan.motion_frames_received)
		print("LAN_SMOKE_PING ms=",game.lan.ping_ms()," hud=",game.network_status_hud.text)
		if "--zero-background-fx" in OS.get_cmdline_user_args():
			var confirmed=int(game.fx.cosmetic_shots.get(int(unit.id),0))-cosmetic_before
			print("LAN_SMOKE_OWN_SHOT_FX confirmed=",confirmed," authority=",int(unit.shot_index)-shot_before," background_budget=0")
			if confirmed<int(unit.shot_index)-shot_before-1:printerr("LAN_SMOKE own firing effects starved by background quota");quit(2);return
		if game.lan.supports_projectile_stream(game.lan.requested_version):
			print("LAN_SMOKE_PROJECTILES received=",game.lan.projectile_stream.received," short=",game.lan.projectile_stream.short_rounds," finished=",game.lan.projectile_stream.played_finishes)
			if game.lan.projectile_stream.received<1 or game.lan.projectile_stream.played_finishes<1:printerr("LAN_SMOKE verified bullet stream missing");quit(2);return
		game.lan.stop()
		for i in range(3):await process_frame
		if game.lan.mode!="offline" or game.lan.ipv4_transport!=null:printerr("LAN_SMOKE stop retained transport");quit(2);return
		print("LAN_SMOKE_STOP_OK")
		quit()
