extends SceneTree
var stats_socket=PacketPeerUDP.new()
var server_time=0.0
var server_position=Vector2.ZERO
var server_speed=0.0
func _initialize():call_deferred("run")

func percentile(values: Array,fraction: float) -> float:
	if values.is_empty():return 0.0
	var sorted=values.duplicate();sorted.sort()
	return float(sorted[mini(sorted.size()-1,int(sorted.size()*fraction))])

func run():
	change_scene_to_file("res://proving_ground.tscn")
	for i in range(4):await process_frame
	var game=current_scene
	game.set_physics_process(false)
	game.start_level01();game.world.ai_enabled=false
	if "--latency-host" in OS.get_cmdline_user_args():
		if not game.lan.host_game():quit(2);return
		stats_socket.set_dest_address("127.0.0.1",27832)
		var end=Time.get_ticks_msec()+55000
		var next_stats=0
		var had_peer=false
		while Time.get_ticks_msec()<end:
			await physics_frame
			game.world.step(1.0/60,Vector2.ZERO,game.world.player.position+Vector2.UP*10,false,false)
			if not game.lan.peer_units.is_empty():had_peer=true
			elif had_peer:break
			if Time.get_ticks_msec()>=next_stats and not game.lan.peer_units.is_empty():
				next_stats=Time.get_ticks_msec()+50
				var id=int(game.lan.peer_units.values()[0])
				stats_socket.put_packet(var_to_bytes({"time":game.world.time,"position":game.world.units[id].position,"speed":game.world.units[id].velocity.length()}))
		print("LATENCY_HOST_DONE version=",game.BUILD_VERSION," max_packet=",game.lan.get("maximum_realtime_bytes")," reliable_bytes=",game.lan.get("reliable_bytes")," realtime_bytes=",game.lan.get("realtime_bytes")," coalesced=",game.lan.get("coalesced_snapshots"))
		quit();return
	stats_socket.bind(27832,"127.0.0.1")
	var address="127.0.0.1:27839"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--latency-address="):address=arg.trim_prefix("--latency-address=")
	if not game.lan.join_game(address):quit(2);return
	var timeout=Time.get_ticks_msec()+22000
	while not game.lan.is_client() and Time.get_ticks_msec()<timeout:await process_frame
	if not game.lan.is_client():printerr("LATENCY_JOIN_FAILED");quit(2);return
	game.set_physics_process(false)
	var unit: Dictionary=game.world.player
	for i in range(30):
		await physics_frame
		game.lan.submit_input(game.lan.idle_input(unit))
	var direction=Vector2.RIGHT
	for candidate in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		if not game.world.blocked(unit.position+candidate*3,.32,1.5,-1,unit.elevation):direction=candidate;break
	var Render=load("res://scripts/render_motion.gd")
	var response: Array=[];var staleness: Array=[];var post_outage: Array=[];var errors: Array=[];var speeds: Array=[]
	var started=Time.get_ticks_msec();var phase=-1;var command_at=0;var command_start=Vector3.ZERO;var waiting=false
	while Time.get_ticks_msec()-started<16000:
		await physics_frame
		while stats_socket.get_available_packet_count()>0:
			var stats=bytes_to_var(stats_socket.get_packet());server_time=float(stats.time);server_position=stats.position;server_speed=float(stats.speed)
		var elapsed=Time.get_ticks_msec()-started
		var next_phase=int(elapsed/900)
		var movement=direction*(1 if int(next_phase/2)%2==0 else -1) if next_phase%2==0 else Vector2.ZERO
		if next_phase!=phase:
			phase=next_phase
			if movement!=Vector2.ZERO:
				command_at=Time.get_ticks_msec();command_start=Render.sample(unit,.5,game.world.time);waiting=true
		game.lan.submit_input({"movement":movement,"aim":unit.position+direction*8,"aim_height":unit.elevation+1,"trigger":false,"pressed":false,"aiming":false,"brake":false,"sprint":false,"jump":false,"fire_allowed":false})
		var visual: Vector3=Render.sample(unit,.5,game.world.time)
		if waiting and visual.distance_to(command_start)>.001:
			response.append(Time.get_ticks_msec()-command_at);waiting=false
		var lag=maxf(0,server_time-float(unit.get("net_motion_time",game.world.time)))*1000
		staleness.append(lag)
		if elapsed>10500:post_outage.append(lag)
		errors.append(server_position.distance_to(Vector2(visual.x,visual.z)))
		if movement!=Vector2.ZERO and elapsed%900>400 and elapsed<6000:speeds.append(server_speed)
	game.lan.submit_input(game.lan.idle_input(unit))
	print("LATENCY_RESULT ",JSON.stringify({"version":game.BUILD_VERSION,"responses":response,"response_p50_ms":percentile(response,.5),"response_p95_ms":percentile(response,.95),"server_speed_p50":percentile(speeds,.5),"state_age_p95_ms":percentile(staleness,.95),"post_outage_age_p95_ms":percentile(post_outage,.95),"visual_error_p95_m":percentile(errors,.95),"diagnostics":game.lan.call("diagnostics_text") if game.lan.has_method("diagnostics_text") else "legacy"}))
	quit()
