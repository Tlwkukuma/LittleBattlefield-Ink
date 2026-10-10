extends Node
## One authoritative campaign simulation. Peers occupy existing blue soldiers,
## so a join never restarts the host's battle or creates a second game mode.
const PORT=27829
## These builds share the same campaign RPCs and snapshot fields.
const LEGACY_LAN_BUILDS=["2026.09.30.45","2026.09.30.46","2026.09.30.47","2026.09.30.48","2026.09.30.49","2026.09.30.50","2026.09.30.51","2026.09.30.52","2026.09.30.53","2026.09.30.54","2026.09.30.55","2026.09.30.56","2026.09.30.57","2026.09.30.58","2026.09.30.59","2026.09.30.60"]
const COMPRESSED_LAN_BUILDS=["2026.09.30.49","2026.09.30.50","2026.09.30.51","2026.09.30.52","2026.09.30.53","2026.09.30.54","2026.09.30.55","2026.09.30.56","2026.09.30.57","2026.09.30.58","2026.09.30.59","2026.09.30.60"]
const REALTIME_LAN_BUILDS=["2026.09.30.53","2026.09.30.54","2026.09.30.55","2026.09.30.56","2026.09.30.57","2026.09.30.58","2026.09.30.59","2026.09.30.60"]
const TRANSPORT_TIMEOUT_MS=8000
const HANDSHAKE_TIMEOUT_MS=20000
const LanDiscovery=preload("res://scripts/lan_discovery.gd")
const VehicleGround=preload("res://scripts/vehicle_grounding.gd")
const VehicleDimensions=preload("res://scripts/vehicle_dimensions.gd")
const SNAPSHOT_INTERVAL=1.0/30.0
const LEGACY_SNAPSHOT_INTERVAL=.10
const MOTION_UNITS_PER_PACKET=16
const MAX_SNAPSHOT_BYTES=4*1024*1024
const UNIT_FIELDS=["position","elevation","velocity","facing","team","health","alive","class_id","walk","flash","hurt","death_age","stance","stance_blend","aiming","mounted","weapon_id","ammo","reserve","reload","cooldown","shot_index","last_shot","aim_height","aim_valid","aim_point","helmet_lost","holstered","equip_remaining","healing","throw_state","melee","reaction","vehicle_flight","grounded","sprinting","vault","ladder","network_peer_id","spawn_epoch"]
const CONTROLLED_FIELDS=["inventory","loadout","quick_slots","quick_tactical","quick_owned","quick_active_slot","medical_stock","medical_selected","throw_low","deployed_mortar"]
const VEHICLE_FIELDS=["position","elevation","angle","turret_angle","aim_target","team","mode","states","health","track_health","speed","velocity","destroyed","flash","driver","driver_id","recoil","shot_time","shot_sequence","ground","airborne","fall_speed","deployed","owner_id","pose_basis","steer_angle","yaw_rate","drive_pitch","drive_roll","handbrake_input"]
const ROUND_FIELDS=["id","origin","position","previous","direction","height","previous_height","start_height","range","remaining","distance","age","speed","team","source","mount","alive","target","velocity","vertical_speed","bounces","radius","slope","flight","arc","motion","fuse","source_epoch","cover_budget","cover_layers","cover_damage_scale","cover_inside"]
const PREDICTION_FIELDS=["position","elevation","velocity","requested_velocity","facing","walk","grounded","vertical_speed","air_speed","jump_cooldown","landing","stance","stance_blend","sprinting","aiming","mounted","alive","vault","ladder","vault_progress","vehicle_flight","reload","throw_state","melee","healing","vehicle_stagger","last_clear"]
signal status_changed(text: String)
var game
var mode="offline"
var peer_units: Dictionary={}
var peer_ready: Dictionary={}
var peer_versions: Dictionary={}
var last_input_ms: Dictionary={}
var assigned_unit=-1
var snapshot_clock=0.0
var legacy_snapshot_clock=0.0
var last_topology=-1
var last_loot_revision=-1
var fx_budget=24
var smoke_fire_logged=false
var discovery
var requested_version=""
var version_retry_count=0
var motion_frames_received=0
var realtime
var prediction
var control_sequence=0
var received_snapshot_serial=0
var snapshot_sequence=0
var pending_snapshot: Dictionary={}
var peer_snapshot_ack: Dictionary={}
var peer_topology: Dictionary={}
var peer_loot: Dictionary={}
var last_server_clock=0.0
var last_motion_usec=0
var motion_gaps: Array=[]
var input_echo_ms: Array=[]
var realtime_bytes=0
var reliable_bytes=0
var coalesced_snapshots=0
var maximum_realtime_bytes=0
var realtime_serial=0
var realtime_fragments: Dictionary={}
var sent_motion: Dictionary={}
var join_phase=""
var join_started_ms=0
var join_address=""
var connect_attempt=0
var preflight_peer: ENetMultiplayerPeer
var ipv4_transport
var queued_owner: Dictionary={}
var owner_states_coalesced=0
var owner_states_applied=0
var network_poll_ms=0.0
var owner_apply_ms=0.0
var snapshot_apply_ms=0.0
var telemetry_age=0.0
var projectile_stream

func compatible_version(version: String) -> bool:
	return version==game.BUILD_VERSION or version in LEGACY_LAN_BUILDS

func supports_packed_snapshot(version: String) -> bool:
	return version==game.BUILD_VERSION or version in COMPRESSED_LAN_BUILDS

func supports_realtime(version: String) -> bool:
	return version==game.BUILD_VERSION or version in REALTIME_LAN_BUILDS

func supports_projectile_stream(version: String) -> bool:
	return version==game.BUILD_VERSION or version in ["2026.09.30.58","2026.09.30.59","2026.09.30.60"]

func connection_log(message: String):
	var path="user://lan-connection.log"
	var file=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file==null:return
	file.seek_end();file.store_line("%s v%s PID %d %s"%[Time.get_datetime_string_from_system(false,true),game.BUILD_VERSION,OS.get_process_id(),message])

func make_client(address: String,port: int) -> ENetMultiplayerPeer:
	var destination=address;var destination_port=port
	if address.is_valid_ip_address() and not address.contains(":") and not address.begins_with("127."):
		ipv4_transport=preload("res://scripts/lan_ipv4_transport.gd").new()
		if ipv4_transport.open(address,port)!=OK:ipv4_transport=null;return null
		destination="127.0.0.1";destination_port=ipv4_transport.local_port()
	var peer=ENetMultiplayerPeer.new()
	if peer.create_client(destination,destination_port)!=OK:
		if ipv4_transport!=null:ipv4_transport.close();ipv4_transport=null
		return null
	return peer

func setup(host):
	game=host
	# This project has one MultiplayerAPI. Receive normalized IPv4 replies before
	# polling ENet, then forward its newly flushed controls in this same frame.
	get_tree().multiplayer_poll=false
	process_priority=-100
	realtime=preload("res://scripts/lan_realtime.gd").new();realtime.name="Realtime";realtime.session=self;add_child(realtime)
	prediction=preload("res://scripts/lan_prediction.gd").new();prediction.session=self
	projectile_stream=preload("res://scripts/lan_projectile_stream.gd").new();projectile_stream.session=self
	discovery=LanDiscovery.new();discovery.name="LanDiscovery";add_child(discovery);discovery.setup(self)
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)

func active() -> bool:return mode in ["host","client","connecting"]
func is_host() -> bool:return mode=="host"
func is_client() -> bool:return mode=="client"

func host_game() -> bool:
	if mode=="host":return true
	if active():stop()
	if not game.world.campaign_active() or bool(game.plan.get("godot3d",{}).get("campaign_offline",false)):game.start_level01()
	var peer=ENetMultiplayerPeer.new()
	var error=peer.create_server(PORT,5)
	if error!=OK:
		status_changed.emit("无法开放局域网房间（端口 %d，错误 %d）"%[PORT,error]);return false
	multiplayer.multiplayer_peer=peer;mode="host";snapshot_clock=0;legacy_snapshot_clock=0;last_topology=-1;last_loot_revision=-1
	if discovery.start_host():status_changed.emit("正在进行的战役已开放 · %s:%d"%[local_addresses(),PORT])
	else:status_changed.emit("战役已开放，但房间发现端口不可用；队友仍可输入 IP 加入")
	return true

func join_game(address: String) -> bool:
	if mode=="connecting":return false
	if active():stop()
	var host_address=address.strip_edges();var port=PORT
	if host_address.contains(":"):
		var parts=host_address.rsplit(":",true,1);host_address=parts[0];port=int(parts[1])
	if host_address.is_empty() or port<1 or port>65535:
		status_changed.emit("请输入局域网主机 IP，例如 192.168.1.8:%d"%PORT);return false
	discovery.remember_host(host_address)
	requested_version=game.BUILD_VERSION;version_retry_count=0
	for room in discovery.room_list():
		if str(room.endpoint)=="%s:%d"%[host_address,port] and compatible_version(str(room.version)):
			requested_version=str(room.version)
			break
	# Keep the current scene responsive until the transport and host accept us.
	# A discovered room does not prove that its separate gameplay port is reachable.
	var peer=make_client(host_address,port)
	if peer==null:
		game.show_lan()
		status_changed.emit("无法建立局域网连接，请检查本机网络接口。");return false
	preflight_peer=peer;mode="connecting"
	connect_attempt+=1;join_phase="probe";join_started_ms=Time.get_ticks_msec();join_address="%s:%d"%[host_address,port]
	multiplayer.multiplayer_peer=peer
	connection_log("CONNECT_START "+join_address)
	status_changed.emit("正在连接 %s:%d…"%[host_address,port]);return true

func prepare_game_connection(attempt: int):
	await get_tree().process_frame
	await get_tree().process_frame
	if mode!="connecting" or attempt!=connect_attempt:return
	var address=join_address;var version=requested_version
	connection_log("GAME_PORT_REACHABLE "+address)
	# Probing uses no gameplay RPC. Close it before the dense loading work, then
	# establish the real session with a ready scene so ENet never stalls loading.
	stop()
	if not game.world.campaign_active() or str(game.plan.get("id",""))!="orchard-level-01" or bool(game.plan.get("godot3d",{}).get("campaign_offline",false)):game.start_level01()
	var parts=address.rsplit(":",true,1)
	var peer=make_client(parts[0],int(parts[1]))
	if peer==null:return_to_lan("游戏端口已连通，但本机无法重建连接，请重试。");return
	requested_version=version;version_retry_count=0;join_address=address
	mode="connecting";join_phase="transport";join_started_ms=Time.get_ticks_msec();connect_attempt+=1
	multiplayer.multiplayer_peer=peer
	status_changed.emit("战役已载入，正在加入房主…")

func stop():
	if mode=="offline":return
	if mode=="host":
		discovery.stop_host()
		for peer_id in peer_units.keys():release_peer(int(peer_id))
	var current_peer=multiplayer.multiplayer_peer
	if current_peer!=null:current_peer.close()
	preflight_peer=null
	# Transfer only the disconnect notification. Never feed replies into a closed
	# local ENet socket while tearing down the transport.
	if ipv4_transport!=null:ipv4_transport.flush_outbound();ipv4_transport.close();ipv4_transport=null
	multiplayer.multiplayer_peer=null;peer_units.clear();peer_ready.clear();peer_versions.clear();last_input_ms.clear();assigned_unit=-1;mode="offline";requested_version="";version_retry_count=0
	pending_snapshot.clear();peer_snapshot_ack.clear();peer_topology.clear();peer_loot.clear();prediction.reset()
	realtime_fragments.clear()
	sent_motion.clear()
	control_sequence=0;received_snapshot_serial=0;last_server_clock=0;motion_gaps.clear();input_echo_ms.clear();last_motion_usec=0
	join_phase="";connect_attempt+=1
	queued_owner.clear();telemetry_age=0
	projectile_stream.reset()
	status_changed.emit("已离开局域网协作")
	connection_log("STOP_FINISHED")

func local_addresses() -> String:
	var addresses=[]
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address.begins_with("169.254."):continue
		if address.begins_with("10.") or address.begins_with("192.168.") or address.begins_with("172."):addresses.append(address)
	return ", ".join(addresses) if not addresses.is_empty() else "本机 IP"

func _connected():
	if mode=="connecting":
		if join_phase=="probe":
			join_phase="preparing"
			status_changed.emit("游戏端口已连通，正在准备战役…")
			prepare_game_connection.call_deferred(connect_attempt)
			return
		join_phase="handshake";join_started_ms=Time.get_ticks_msec()
		connection_log("TRANSPORT_CONNECTED "+join_address)
		status_changed.emit("已连通房主，正在请求当前战役…")
		_request_join.rpc_id(1,requested_version)

func _connection_failed():
	if mode!="connecting":return
	return_to_lan.call_deferred("无法连接游戏端口 %s。房间发现成功不代表游戏端口可达；请房主允许 UDP 27829。"%join_address)

func _server_disconnected():
	if mode not in ["connecting","client"]:return
	return_to_lan.call_deferred("与主机断开连接")

func _peer_connected(_peer_id: int):pass

func _peer_disconnected(peer_id: int):
	if mode!="host":return
	release_peer(peer_id)
	status_changed.emit("队友已离开 · 当前 %d 人"%(peer_units.size()+1))
	game.message("队友已离开战役")

func release_peer(peer_id: int):
	if not peer_units.has(peer_id):return
	var unit_id=int(peer_units[peer_id]);peer_units.erase(peer_id);peer_ready.erase(peer_id);peer_versions.erase(peer_id);last_input_ms.erase(peer_id)
	pending_snapshot.erase(peer_id);peer_snapshot_ack.erase(peer_id);peer_topology.erase(peer_id);peer_loot.erase(peer_id)
	sent_motion.erase(peer_id)
	game.world.network_inputs.erase(unit_id)
	if unit_id>=0 and unit_id<game.world.units.size():
		var unit: Dictionary=game.world.units[unit_id]
		unit.erase("network_peer_id")
		game.world.FireControl.cancel(unit,true)
		if unit.mounted>=0:
			var old=game.world.player;game.world.player=unit;game.world.leave_vehicle(true);game.world.player=old

@rpc("any_peer","call_remote","reliable")
func _request_join(version: String):
	if mode!="host":return
	var peer_id=multiplayer.get_remote_sender_id()
	if not compatible_version(version):
		_join_rejected.rpc_id(peer_id,"项目版本不同：房主 v%s，你是 v%s"%[game.BUILD_VERSION,version]);return
	if not game.world.campaign_active() or game.world.campaign.phase!="playing":
		_join_rejected.rpc_id(peer_id,"当前战役已结束，请房主重新开始");return
	var unit_id=-1;var best=INF
	for unit in game.world.units:
		if not unit.alive or unit.team!=0 or unit.player or unit.mounted>=0 or int(unit.get("network_peer_id",0))>0:continue
		var score=unit.position.distance_squared_to(game.world.player.position)
		if score<best:best=score;unit_id=int(unit.id)
	if unit_id<0:
		var reinforced: Dictionary=game.world.campaign.reinforce(game.world,0,1,true)
		if not reinforced.is_empty():unit_id=int(reinforced.id)
	if unit_id<0:
		_join_rejected.rpc_id(peer_id,"当前没有安全位置可供蓝军队友加入");return
	peer_units[peer_id]=unit_id;peer_ready[peer_id]=false;peer_versions[peer_id]=version;last_input_ms[peer_id]=Time.get_ticks_msec()
	peer_topology[peer_id]=-1;peer_loot[peer_id]=-1;peer_snapshot_ack[peer_id]=0;pending_snapshot[peer_id]=0
	var occupied: Dictionary=game.world.units[unit_id];occupied.network_peer_id=peer_id
	if "--lan-smoke-host" in OS.get_cmdline_user_args():print("LAN_SMOKE_ASSIGNED peer=",peer_id," unit=",unit_id," alive=",occupied.alive," time=",game.world.time)
	game.world.network_inputs[unit_id]=idle_input(occupied)
	var initial=make_snapshot(true,true)
	if "--lan-smoke-host" in OS.get_cmdline_user_args():print("LAN_SMOKE_INITIAL_BYTES ",var_to_bytes(initial).size()," snapshot_time=",initial.time)
	_begin_campaign.rpc_id(peer_id,version,unit_id,pack_snapshot(initial) if supports_packed_snapshot(version) else initial)
	status_changed.emit("队友加入战役 · 当前 %d 人"%(peer_units.size()+1))
	game.message("蓝军队友已进入当前战役 · 当前 %d 人"%(peer_units.size()+1))

@rpc("authority","call_remote","reliable")
func _join_rejected(reason: String):
	if mode!="connecting":return
	if reason.begins_with("项目版本不同：房主 v") and version_retry_count==0:
		var host_version=reason.trim_prefix("项目版本不同：房主 v").get_slice("，",0)
		if compatible_version(host_version) and requested_version!=host_version:
			requested_version=host_version;version_retry_count=1
			status_changed.emit("房主版本 v%s 可兼容，正在重新握手…"%host_version)
			_request_join.rpc_id(1,host_version)
			return
	return_to_lan.call_deferred(reason)

func return_to_lan(reason: String):
	var transport_info=""
	if ipv4_transport!=null:transport_info=" sent=%d received=%d wire=%d last=%s"%[ipv4_transport.sent,ipv4_transport.received,ipv4_transport.wire_received,ipv4_transport.last_sender]
	connection_log("CONNECT_END phase=%s %s%s"%[join_phase,reason,transport_info])
	stop()
	game.show_lan()
	status_changed.emit(reason)

@rpc("authority","call_remote","reliable")
func _begin_campaign(version: String,unit_id: int,state: Dictionary):
	if mode!="connecting" or not compatible_version(version):return
	if join_phase=="loading":return
	join_phase="loading"
	connection_log("HOST_ACCEPTED unit=%d bytes=%d"%[unit_id,var_to_bytes(state).size()])
	status_changed.emit("房主已接受加入，正在载入当前战役…")
	finish_join.call_deferred(version,unit_id,state,connect_attempt)

func finish_join(version: String,unit_id: int,state: Dictionary,attempt: int):
	# Apply the scene outside ENet's polling callback; show the loading status first.
	await get_tree().process_frame
	await get_tree().process_frame
	if mode!="connecting" or attempt!=connect_attempt:return
	var decoded=unpack_snapshot(state)
	if decoded.is_empty():return_to_lan("房主初始战役数据损坏，请重试");return
	if "--lan-smoke-client" in OS.get_cmdline_user_args():print("LAN_SMOKE_BEGIN before=",game.world.time," state_time=",decoded.get("time","missing"))
	assigned_unit=unit_id;mode="client"
	game.begin_network_campaign(unit_id,decoded)
	join_phase="";connection_log("CAMPAIGN_READY unit=%d"%unit_id)
	if "--lan-smoke-client" in OS.get_cmdline_user_args():print("LAN_SMOKE_BEGIN_APPLIED time=",game.world.time," scene=",game.plan.id)
	_client_ready.rpc_id(1)
	if "--lan-smoke-client" in OS.get_cmdline_user_args():print("LAN_SMOKE_READY_SENT")
	status_changed.emit("已加入房主正在进行的第一关 · 蓝军 %d 号"%(unit_id+1))

@rpc("any_peer","call_remote","reliable")
func _client_ready():
	if mode!="host":return
	var peer_id=multiplayer.get_remote_sender_id()
	if not peer_units.has(peer_id):return
	peer_ready[peer_id]=true
	# Include every changed wall and loot bag on the first live update. The
	# initial state was captured before the client finished building its scene.
	last_topology=-1;last_loot_revision=-1
	if "--lan-smoke-host" in OS.get_cmdline_user_args():print("LAN_SMOKE_CLIENT_READY peer=",peer_id," time=",game.world.time)

func idle_input(unit: Dictionary) -> Dictionary:
	return {"movement":Vector2.ZERO,"aim":unit.position+unit.facing*8,"trigger":false,"pressed":false,"aiming":false,"brake":false,"sprint":false,"jump":false,"fire_allowed":false}

func submit_input(control: Dictionary,delta: float=1.0/60.0):
	if mode!="client":return
	control_sequence+=1;control._sequence=control_sequence;control._sent_usec=Time.get_ticks_usec();control._snapshot_ack=received_snapshot_serial
	if supports_realtime(requested_version):realtime.control.rpc_id(1,control)
	else:_receive_control.rpc_id(1,control)
	prediction.submit(control,delta)

@rpc("any_peer","call_remote","unreliable_ordered")
func _receive_control(control: Dictionary):
	if mode!="host":return
	accept_control(multiplayer.get_remote_sender_id(),control)

func accept_control(peer_id: int,control: Dictionary):
	if not peer_units.has(peer_id):return
	peer_snapshot_ack[peer_id]=maxi(int(peer_snapshot_ack.get(peer_id,0)),int(control.get("_snapshot_ack",0)))
	var unit_id=int(peer_units[peer_id]);var unit: Dictionary=game.world.units[unit_id]
	var movement: Vector2=control.get("movement",Vector2.ZERO)
	var target: Vector2=control.get("aim",unit.position+unit.facing*8)
	if not movement.is_finite() or not target.is_finite():return
	control.movement=movement.limit_length(1.0)
	control.aim=target
	if "--lan-smoke-host" in OS.get_cmdline_user_args() and bool(control.get("trigger",false)) and not smoke_fire_logged:
		smoke_fire_logged=true
		print("LAN_SMOKE_FIRE_INPUT unit=",unit_id," alive=",unit.alive," ammo=",unit.ammo," vault=",unit.vault," ladder=",unit.ladder," fire_mode=",unit.get("fire_mode","")," allowed=",control.get("fire_allowed","missing")," busy=",game.world.Equipment.busy(unit)," lock=",unit.get("fire_lock","missing")," time=",game.world.time)
	var aim_height=float(control.get("aim_height",unit.elevation+1.0))
	if is_finite(aim_height):unit.aim_height=clampf(aim_height,-30.0,150.0);unit.aim_valid=true
	game.world.network_inputs[unit_id]=control
	last_input_ms[peer_id]=Time.get_ticks_msec()

func _process(delta: float):
	var poll_started=Time.get_ticks_usec()
	if ipv4_transport!=null:ipv4_transport.pump()
	if active():multiplayer.poll()
	if ipv4_transport!=null:ipv4_transport.flush_outbound()
	network_poll_ms=(Time.get_ticks_usec()-poll_started)/1000.0
	flush_owner_state()
	if mode=="connecting":
		var transport_pending=join_phase in ["probe","transport"]
		var timeout=TRANSPORT_TIMEOUT_MS if transport_pending else HANDSHAKE_TIMEOUT_MS
		if join_phase not in ["loading","preparing"] and Time.get_ticks_msec()-join_started_ms>timeout:
			return_to_lan("游戏连接无回复：%s。请确认房主仍在开房，并已允许游戏 UDP 端口。"%join_address if transport_pending else "房主已连通，但未完成战役握手；请检查双方游戏日志。")
		return
	if mode!="client":return
	telemetry_age+=delta
	if telemetry_age>=5:
		telemetry_age=0
		connection_log("SYNC ping=%.0f gap=%.0f poll=%.2f owner=%.2f snapshot=%.2f echo_p95=%.0f update_p95=%.0f coalesced=%d rounds=%d short=%d finishes=%d"%[ping_ms(),state_gap_ms(),network_poll_ms,owner_apply_ms,snapshot_apply_ms,percentile(input_echo_ms,.95),percentile(motion_gaps,.95),owner_states_coalesced,projectile_stream.rounds.size(),projectile_stream.short_rounds,projectile_stream.played_finishes])
	# Advance visual timers continuously, but freeze after a prolonged network gap.
	var world=game.world
	var elapsed=minf(delta,maxf(0,last_server_clock+.2-world.time))
	world.time+=elapsed
	for unit in world.units:
		unit.flash=maxf(0,unit.flash-elapsed);unit.hurt=maxf(0,unit.hurt-elapsed)
		if not unit.alive:unit.death_age+=elapsed
		elif unit.mounted<0:
			unit.walk+=unit.velocity.length()*elapsed*TAU/(world.Traversal.stride(unit.velocity.length())*(.7 if unit.stance==1 else 1.0))
			unit.stance_blend=move_toward(unit.stance_blend,float(unit.stance),elapsed*(2.4 if unit.stance==2 else 3.0))
	prediction.tick(delta)

func request_action(action: String,value: Variant=null):
	if mode=="client":_action.rpc_id(1,action,value)

@rpc("any_peer","call_remote","reliable")
func _action(action: String,value: Variant):
	if mode!="host":return
	var peer_id=multiplayer.get_remote_sender_id()
	if not peer_units.has(peer_id):return
	var unit_id=int(peer_units[peer_id]);var unit: Dictionary=game.world.units[unit_id]
	if not unit.alive or game.world.campaign.phase!="playing":
		if "--lan-smoke-host" in OS.get_cmdline_user_args():print("LAN_SMOKE_ACTION_REJECT alive=",unit.alive," phase=",game.world.campaign.phase)
		return
	if "--lan-smoke-host" in OS.get_cmdline_user_args():print("LAN_SMOKE_ACTION peer=",peer_id," unit=",unit_id," action=",action," before=",unit.stance)
	var original: Dictionary=game.world.player
	game.world.player=unit
	match action:
		"stance":game.world.set_stance(clampi(int(value),0,2))
		"reload":game.world.reload_weapon()
		"slot":game.world.equip_slot(clampi(int(value),0,4))
		"cycle":game.world.cycle_fire_mode()
		"mount":game.world.interact_vehicle()
		"interact":preload("res://scripts/terrain_ladder.gd").interact(game.world)
		"holster":game.world.holster()
		"medicine":game.world.use_medicine(str(value))
		"cancel_medicine":game.world.cancel_medicine()
		"throw_low":unit.throw_low=bool(value)
		"assign":
			if value is Dictionary and game.catalog.weapons.has(str(value.get("id",""))):game.world.assign_quick_weapon(str(value.id),clampi(int(value.get("slot",0)),0,2))
		"clear_slot":game.world.clear_quick_slot(clampi(int(value),0,2))
		"tactical":
			if str(value) in unit.get("quick_owned",[]):unit.quick_tactical=str(value)
		"loot_take":
			if value is Dictionary:game.world.loot.take(game.world,unit,int(value.get("bag",-1)),str(value.get("key","")))
		"loot_all":game.world.loot.take_all(game.world,unit,int(value))
	game.world.player=original
	if "--lan-smoke-host" in OS.get_cmdline_user_args():print("LAN_SMOKE_ACTION_DONE stance=",unit.stance," time=",game.world.time)

func _physics_process(delta: float):
	if mode!="host" or not game.world.campaign_active():return
	for peer_id in peer_units:
		var occupied_id=int(peer_units[peer_id]);var occupied: Dictionary=game.world.units[occupied_id]
		if not occupied.alive and float(occupied.death_age)>=1.18:
			var substitute: Dictionary={};var nearest=INF
			for candidate in game.world.units:
				if not candidate.alive or candidate.team!=0 or candidate.player or int(candidate.get("network_peer_id",0))>0:continue
				var distance=occupied.position.distance_squared_to(candidate.position)
				if distance<nearest:nearest=distance;substitute=candidate
			if not substitute.is_empty():
				occupied.erase("network_peer_id");game.world.network_inputs.erase(occupied_id)
				substitute.network_peer_id=int(peer_id);peer_units[peer_id]=int(substitute.id)
				game.world.network_inputs[int(substitute.id)]=idle_input(substitute)
				_reassign.rpc_id(int(peer_id),int(substitute.id))
		if Time.get_ticks_msec()-int(last_input_ms.get(peer_id,0))>350:
			var unit_id=int(peer_units[peer_id]);game.world.network_inputs[unit_id]=idle_input(game.world.units[unit_id])
	snapshot_clock-=delta
	legacy_snapshot_clock-=delta
	var new_due=snapshot_clock<=0
	var legacy_due=legacy_snapshot_clock<=0
	if not new_due and not legacy_due:return
	if new_due:snapshot_clock+=SNAPSHOT_INTERVAL
	if legacy_due:legacy_snapshot_clock+=LEGACY_SNAPSHOT_INTERVAL;snapshot_sequence+=1
	fx_budget=8
	for peer_id in peer_units:
		if not bool(peer_ready.get(peer_id,false)):continue
		var modern=supports_realtime(str(peer_versions.get(peer_id,"")))
		if new_due and modern:
			send_motion_frame(int(peer_id))
			if supports_projectile_stream(str(peer_versions.get(peer_id,""))):
				var observer: Dictionary=game.world.units[int(peer_units[peer_id])]
				for bullet_packet in projectile_stream.packets(game.world.projectiles,game.world.time,observer):send_datagram(int(peer_id),bullet_packet)
		if not legacy_due:continue
		# Only one complete reliable snapshot may be in flight. While it awaits
		# receipt, retain the newest world instead of queuing obsolete worlds.
		if modern and int(pending_snapshot.get(peer_id,0))>int(peer_snapshot_ack.get(peer_id,0)):
			coalesced_snapshots+=1;continue
		var topology_changed=game.world.topology_revision!=int(peer_topology.get(peer_id,-1))
		var loot_changed=game.world.loot.revision!=int(peer_loot.get(peer_id,-1))
		var state=make_snapshot(topology_changed,loot_changed,not supports_projectile_stream(str(peer_versions.get(peer_id,""))))
		if modern:state._serial=snapshot_sequence;pending_snapshot[peer_id]=snapshot_sequence
		var packet=pack_snapshot(state) if supports_packed_snapshot(str(peer_versions.get(peer_id,""))) else state
		reliable_bytes+=var_to_bytes(packet).size()
		_snapshot.rpc_id(int(peer_id),packet)
		peer_topology[peer_id]=game.world.topology_revision;peer_loot[peer_id]=game.world.loot.revision

func send_motion_frame(peer_id: int):
	# Keep each unreliable datagram below ENet's MTU. Older peers continue to
	# receive only the unchanged reliable snapshot protocol.
	var data=PackedFloat32Array()
	var occupied: Dictionary=game.world.units[int(peer_units[peer_id])]
	var own=copy_fields(occupied,UNIT_FIELDS)
	for key in PREDICTION_FIELDS:
		if occupied.has(key):own[key]=occupied[key]
	own._ack=int(occupied.get("network_applied_sequence",0));own._echo=int(occupied.get("network_applied_usec",0))
	send_realtime(peer_id,{"type":"owner","time":game.world.time,"data":pack_snapshot(own)})
	for unit in game.world.units:
		if not unit.alive or int(unit.id)==int(occupied.id):continue
		var row=PackedFloat32Array([unit.id,unit.position.x,unit.position.y,unit.elevation,unit.velocity.x,unit.velocity.y,unit.facing.x,unit.facing.y,unit.walk,unit.stance_blend])
		if not motion_changed(peer_id,"u"+str(unit.id),row):continue
		data.append_array(row)
		if data.size()>=MOTION_UNITS_PER_PACKET*10:
			send_realtime(peer_id,{"type":"motion","time":game.world.time,"units":data})
			data=PackedFloat32Array()
	if not data.is_empty():send_realtime(peer_id,{"type":"motion","time":game.world.time,"units":data})
	var vehicles=PackedFloat32Array()
	var vehicle_stride=12 if str(peer_versions.get(peer_id,"")) in [game.BUILD_VERSION,"2026.09.30.57","2026.09.30.58","2026.09.30.59","2026.09.30.60"] else 6
	for vehicle in game.world.vehicles:
		var row=PackedFloat32Array([vehicle.id,vehicle.position.x,vehicle.position.y,vehicle.elevation,vehicle.angle,vehicle.turret_angle])
		if vehicle_stride==12:
			var rotation=VehicleDimensions.body_basis(vehicle).get_rotation_quaternion()
			row.append_array(PackedFloat32Array([rotation.x,rotation.y,rotation.z,rotation.w,vehicle.get("steer_angle",0),vehicle.get("yaw_rate",0)]))
		if not motion_changed(peer_id,"v"+str(vehicle.id),row):continue
		vehicles.append_array(row)
		if vehicles.size()>=12*vehicle_stride:
			send_realtime(peer_id,{"type":"motion","time":game.world.time,"vehicles":vehicles,"vehicle_stride":vehicle_stride})
			vehicles=PackedFloat32Array()
	if not vehicles.is_empty():send_realtime(peer_id,{"type":"motion","time":game.world.time,"vehicles":vehicles,"vehicle_stride":vehicle_stride})

func motion_changed(peer_id: int,key: String,values: PackedFloat32Array) -> bool:
	if not sent_motion.has(peer_id):sent_motion[peer_id]={}
	var previous: Dictionary=sent_motion[peer_id].get(key,{})
	if not previous.is_empty() and previous["values"]==values and game.world.time-float(previous.time)<.25:return false
	sent_motion[peer_id][key]={"values":values,"time":game.world.time}
	return true

func send_realtime(peer_id: int,packet: Dictionary):
	for datagram in realtime_packets(packet):send_datagram(peer_id,datagram)

func realtime_packets(packet: Dictionary) -> Array:
	var raw=var_to_bytes(packet)
	if raw.size()>1100:
		# Rare complex traversal/reaction states also obey the datagram budget.
		# An incomplete frame is discarded; the next owner state replaces it.
		realtime_serial+=1
		var compressed=raw.compress(FileAccess.COMPRESSION_FASTLZ)
		var count=ceili(compressed.size()/700.0)
		var packets: Array=[]
		for index in range(count):
			packets.append({"type":"fragment","serial":realtime_serial,"index":index,"count":count,"size":raw.size(),"data":compressed.slice(index*700,mini(compressed.size(),(index+1)*700))})
		return packets
	return [packet]

func send_datagram(peer_id: int,packet: Dictionary):
	var bytes=var_to_bytes(packet).size()
	maximum_realtime_bytes=maxi(maximum_realtime_bytes,bytes);realtime_bytes+=bytes
	realtime.frame.rpc_id(peer_id,packet)

func receive_realtime(packet: Dictionary):
	if packet.get("type","")=="fragment":
		var count=int(packet.get("count",0));var index=int(packet.get("index",-1));var size=int(packet.get("size",0))
		if count<1 or count>32 or index<0 or index>=count or size<=0 or size>MAX_SNAPSHOT_BYTES:return
		var serial=int(packet.get("serial",-1));var now=Time.get_ticks_msec()
		for id in realtime_fragments.keys():
			if now-int(realtime_fragments[id].started)>250:realtime_fragments.erase(id)
		if not realtime_fragments.has(serial):
			if realtime_fragments.size()>=8:return
			realtime_fragments[serial]={"started":now,"pieces":{},"count":count,"size":size}
		var frame: Dictionary=realtime_fragments[serial]
		if int(frame.count)!=count or int(frame.size)!=size:return
		frame.pieces[index]=packet.get("data",PackedByteArray())
		if frame.pieces.size()!=count:return
		var compressed=PackedByteArray()
		for part in range(count):compressed.append_array(frame.pieces[part])
		realtime_fragments.erase(serial)
		var raw=compressed.decompress(size,FileAccess.COMPRESSION_FASTLZ)
		if raw.size()!=size:return
		var decoded=bytes_to_var(raw)
		if decoded is Dictionary:receive_realtime(decoded)
	elif packet.get("type","")=="motion":
		apply_motion_frame(packet,10)
	elif packet.get("type","")=="rounds":
		if supports_projectile_stream(requested_version):projectile_stream.accept(packet)
	elif packet.get("type","")=="owner":
		var clock=float(packet.get("time",0))
		if assigned_unit<0 or assigned_unit>=game.world.units.size():return
		if clock<=float(game.world.units[assigned_unit].get("net_owner_time",-1)) or clock<=float(queued_owner.get("time",-1)):return
		if not queued_owner.is_empty():owner_states_coalesced+=1
		queued_owner=packet

func flush_owner_state():
	if queued_owner.is_empty():return
	var packet=queued_owner;queued_owner={}
	if not is_client() or assigned_unit<0 or assigned_unit>=game.world.units.size():return
	var started=Time.get_ticks_usec()
	var unit: Dictionary=game.world.units[assigned_unit]
	var clock=float(packet.time)
	if clock<=float(unit.get("net_owner_time",-1)):return
	var own=unpack_snapshot(packet.get("data",{}))
	if own.is_empty():return
	for key in own:
		if not str(key).begins_with("_"):unit[key]=own[key]
	unit.net_owner_time=clock;unit.net_motion_time=clock;unit.net_motion_received_usec=Time.get_ticks_usec();unit.net_motion_max_age=.05
	game.world.index_unit(unit)
	last_server_clock=maxf(last_server_clock,clock);game.world.time=maxf(game.world.time,clock)
	var now=Time.get_ticks_usec()
	if last_motion_usec>0:motion_gaps.append((now-last_motion_usec)/1000.0)
	last_motion_usec=now
	if int(own.get("_echo",0))>0:input_echo_ms.append((now-int(own._echo))/1000.0)
	if motion_gaps.size()>300:motion_gaps.pop_front()
	if input_echo_ms.size()>300:input_echo_ms.pop_front()
	prediction.reconcile(unit,int(own.get("_ack",0)))
	owner_apply_ms=(Time.get_ticks_usec()-started)/1000.0;owner_states_applied+=1

func replicate_event(event: Dictionary):
	if mode!="host":return
	var kind=str(event.get("type",""))
	if kind=="round_finished":
		projectile_stream.capture_finish(event.round,game.world.time);return
	var own_shot=kind=="shot" and event.has("unit") and int(event.unit.get("network_peer_id",0))>0
	if fx_budget<=0 and not own_shot:return
	if kind not in ["shot","reload_start","impact","explosion","smoke","damage","death","vehicle_destroyed"]:return
	var packet={"type":kind}
	for key in ["position","height","angle","mount","forward","ejection","backblast","amount","fatal","impulse","radius","direction","normal","material","source_id","region","point","incoming","explosive"]:
		if event.has(key):packet[key]=event[key]
	if event.has("weapon"):
		var weapon: Dictionary=event.weapon
		packet.weapon_key=str(weapon.get("mounted_fire_key",weapon.get("id","")))
		packet.weapon_id=str(weapon.get("id",""))
	if event.has("unit"):packet.unit_id=int(event.unit.id)
	if event.has("vehicle"):packet.vehicle_id=int(event.vehicle.id)
	var origin: Vector2=packet.get("position",event.unit.position if event.has("unit") else event.vehicle.position if event.has("vehicle") else Vector2.ZERO)
	for peer_id in peer_units:
		if not bool(peer_ready.get(peer_id,false)):continue
		if fx_budget<=0 and (not own_shot or int(peer_units[peer_id])!=int(event.unit.id)):continue
		var occupied: Dictionary=game.world.units[int(peer_units[peer_id])]
		if occupied.position.distance_squared_to(origin)>65*65 and kind not in ["damage","death","vehicle_destroyed"]:continue
		_event.rpc_id(int(peer_id),packet)
	fx_budget=maxi(0,fx_budget-1)

@rpc("authority","call_remote","unreliable_ordered")
func _event(packet: Dictionary):
	if mode!="client":return
	if packet.get("type","")=="motion":
		apply_motion_frame(packet)
		return
	if packet.has("weapon_id"):
		packet.weapon=resolve_weapon(str(packet.weapon_id),str(packet.get("weapon_key","")))
		if packet.weapon.is_empty():return
	if packet.has("unit_id"):
		var id=int(packet.unit_id)
		if id<0 or id>=game.world.units.size():return
		packet.unit=game.world.units[id]
	if packet.has("vehicle_id"):
		var id=int(packet.vehicle_id)
		if id<0 or id>=game.world.vehicles.size():return
		packet.vehicle=game.world.vehicles[id]
	if packet.type=="damage" and int(packet.get("source_id",-1))==assigned_unit and packet.unit.team!=game.world.player.team:
		game.crosshair.hit_time=.18 if packet.get("fatal",false) else .12
		game.crosshair.hit_fatal=bool(packet.get("fatal",false))
	game.fx.handle(packet)

@rpc("authority","call_remote","reliable")
func _snapshot(state: Dictionary):
	if mode!="client":return
	var started=Time.get_ticks_usec()
	var decoded=unpack_snapshot(state)
	if not decoded.is_empty():
		received_snapshot_serial=maxi(received_snapshot_serial,int(decoded.get("_serial",0)))
		apply_snapshot(decoded)
	snapshot_apply_ms=(Time.get_ticks_usec()-started)/1000.0

func apply_motion_frame(packet: Dictionary,stride: int=8):
	var clock=float(packet.get("time",-1))
	if clock<0:return
	motion_frames_received+=1
	var units: PackedFloat32Array=packet.get("units",PackedFloat32Array())
	for index in range(0,units.size()-(stride-1),stride):
		var id=int(units[index])
		if id<0 or id>=game.world.units.size():continue
		var unit: Dictionary=game.world.units[id]
		if clock<=float(unit.get("net_motion_time",-1)):continue
		unit.position=Vector2(units[index+1],units[index+2]);unit.elevation=units[index+3]
		unit.velocity=Vector2(units[index+4],units[index+5]);unit.facing=Vector2(units[index+6],units[index+7])
		if stride==10:unit.walk=units[index+8];unit.stance_blend=units[index+9]
		unit.net_motion_time=clock;unit.net_motion_received_usec=Time.get_ticks_usec();unit.net_motion_max_age=.06
		game.world.index_unit(unit)
	var vehicles: PackedFloat32Array=packet.get("vehicles",PackedFloat32Array())
	var vehicle_stride=int(packet.get("vehicle_stride",6))
	if vehicle_stride not in [6,12]:return
	for index in range(0,vehicles.size()-(vehicle_stride-1),vehicle_stride):
		var id=int(vehicles[index])
		if id<0 or id>=game.world.vehicles.size():continue
		var vehicle: Dictionary=game.world.vehicles[id]
		if clock<=float(vehicle.get("net_motion_time",-1)):continue
		vehicle.position=Vector2(vehicles[index+1],vehicles[index+2]);vehicle.elevation=vehicles[index+3]
		vehicle.angle=vehicles[index+4];vehicle.turret_angle=vehicles[index+5]
		if vehicle_stride==12:
			var rotation=Quaternion(vehicles[index+6],vehicles[index+7],vehicles[index+8],vehicles[index+9])
			if rotation.is_finite() and rotation.length_squared()>.001:vehicle.pose_basis=Basis(rotation.normalized())
			vehicle.steer_angle=vehicles[index+10];vehicle.yaw_rate=vehicles[index+11]
		else:restore_vehicle_pose(vehicle)
		vehicle.net_motion_time=clock;vehicle.net_motion_received_usec=Time.get_ticks_usec();vehicle.net_motion_max_age=.06
		game.world.index_vehicle(vehicle)
	last_server_clock=maxf(last_server_clock,clock);game.world.time=maxf(game.world.time,clock)

func restore_vehicle_pose(vehicle: Dictionary):
	# Older hosts send angle and terrain normal, but omit the cached pose_basis.
	# Do not let the offline scene's initial basis override a new network angle.
	vehicle.pose_basis=VehicleGround.basis(float(vehicle.angle),vehicle.get("ground",{}).get("normal",Vector3.UP))*Basis(Vector3.RIGHT,float(vehicle.get("drive_pitch",0)))*Basis(Vector3.FORWARD,float(vehicle.get("drive_roll",0)))

func pack_snapshot(state: Dictionary) -> Dictionary:
	var raw=var_to_bytes(state)
	return {"_fastlz":raw.compress(FileAccess.COMPRESSION_FASTLZ),"_raw_size":raw.size()}

func unpack_snapshot(state: Dictionary) -> Dictionary:
	if not state.has("_fastlz"):return state
	var expected=int(state.get("_raw_size",0))
	if expected<=0 or expected>MAX_SNAPSHOT_BYTES or not state._fastlz is PackedByteArray:return {}
	var raw: PackedByteArray=state._fastlz.decompress(expected,FileAccess.COMPRESSION_FASTLZ)
	if raw.size()!=expected:return {}
	var decoded=bytes_to_var(raw)
	return decoded if decoded is Dictionary else {}

@rpc("authority","call_remote","reliable")
func _reassign(unit_id: int):
	if mode!="client" or unit_id<0 or unit_id>=game.world.units.size():return
	prediction.reset();queued_owner.clear()
	assigned_unit=unit_id
	game.world.player=game.world.units[unit_id]
	game.player_class=str(game.world.player.get("class_id","assault"))
	game.aim=game.world.player.position+game.world.player.facing*12
	game.update_weapon_details()
	game.message("已接管另一名存活蓝军队友")

func copy_fields(source: Dictionary,keys: Array) -> Dictionary:
	var copy={}
	for key in keys:
		if source.has(key):copy[key]=source[key]
	return copy

func resolve_weapon(weapon_id: String,weapon_key: String) -> Dictionary:
	if game.catalog.weapons.has(weapon_id):return game.catalog.weapons[weapon_id]
	for vehicle in game.world.vehicles:
		if vehicle.emplacement:
			if str(vehicle.profile.get("mounted_fire_key",vehicle.profile.get("id","")))==weapon_key:return vehicle.profile
		else:
			for mode in vehicle.modes:
				var candidate: Dictionary=vehicle.profile.weapons[mode]
				if str(candidate.get("mounted_fire_key",candidate.get("id","")))==weapon_key:return candidate
	return {}

func make_snapshot(include_objects: bool=false,include_loot: bool=false,include_bullets: bool=true) -> Dictionary:
	var world=game.world
	var state={"time":world.time,"units":[],"vehicles":[],"projectiles":[],"campaign":world.campaign.summary(),"topology_revision":world.topology_revision}
	for unit in world.units:
		var unit_data=copy_fields(unit,UNIT_FIELDS)
		if unit.player or int(unit.get("network_peer_id",0))>0:unit_data.merge(copy_fields(unit,CONTROLLED_FIELDS))
		state.units.append(unit_data)
	for vehicle in world.vehicles:
		var copy=copy_fields(vehicle,VEHICLE_FIELDS)
		copy.type=vehicle.type;copy.source_id=vehicle.source_id;copy.emplacement=vehicle.emplacement
		state.vehicles.append(copy)
	for round in world.projectiles:
		if not include_bullets and preload("res://scripts/bullet_flight_visual.gd").supports(round.weapon):continue
		var round_data=copy_fields(round,ROUND_FIELDS)
		var weapon: Dictionary=round.weapon
		round_data.weapon_id=str(weapon.get("id",""))
		round_data.weapon_key=str(weapon.get("mounted_fire_key",weapon.get("id","")))
		state.projectiles.append(round_data)
	if include_objects:
		state.objects=[]
		for object in world.objects:
			if int(object.revision)>0:state.objects.append({"id":object.id,"hp":object.hp,"alive":object.alive,"revision":object.revision})
	if include_loot:state.loot=world.loot.bags.duplicate(true)
	return state

func apply_snapshot(state: Dictionary,static_only: bool=false):
	var world=game.world
	if static_only:
		apply_structural_snapshot(state)
		return
	var state_time=float(state.get("time",world.time))
	last_server_clock=maxf(last_server_clock,state_time)
	world.time=maxf(world.time,state_time);world.topology_revision=maxi(world.topology_revision,int(state.get("topology_revision",world.topology_revision)))
	var units: Array=state.get("units",[])
	for index in range(mini(units.size(),world.units.size())):
		var unit: Dictionary=world.units[index]
		var newer_motion=state_time>float(unit.get("net_motion_time",-1))
		for key in units[index]:
			if state_time<float(unit.get("net_owner_time",-1)) and key not in CONTROLLED_FIELDS:continue
			if not newer_motion and key in ["position","elevation","velocity","facing","walk","stance_blend"]:continue
			unit[key]=units[index][key]
		if newer_motion:
			unit.net_motion_time=state_time;unit.net_motion_received_usec=Time.get_ticks_usec();unit.net_motion_max_age=.11
		unit.player=index==assigned_unit
		world.index_unit(unit)
	if assigned_unit>=0 and assigned_unit<world.units.size():world.player=world.units[assigned_unit]
	var vehicles: Array=state.get("vehicles",[])
	for index in range(vehicles.size()):
		var vehicle_data: Dictionary=vehicles[index]
		if index>=world.vehicles.size():
			var at: Vector2=world.catalog.original_point(vehicle_data.position,world.plan)
			var spec={"id":vehicle_data.source_id,"type":vehicle_data.type,"emplacement":vehicle_data.emplacement,"x":at.x,"y":at.y,"angle":vehicle_data.angle,"team":vehicle_data.team}
			if vehicle_data.type=="portableMortar":
				var profile: Dictionary=world.catalog.weapons["portable-mortar"].duplicate(true)
				profile.merge({"label":"便携迫击炮","health":280.0,"radius":22,"traverse":1.55,"turnRate":1.5,"visionRange":1420,"visionHalfAngle":.75},true)
				world.FireControl.bind_mounted_weapon(profile,"portableMortar/primary")
				spec.profile_override=profile
			var created: Dictionary=world.add_vehicle(spec)
			if not created.is_empty():game.add_network_vehicle_view(created)
		if index>=world.vehicles.size():continue
		var vehicle: Dictionary=world.vehicles[index]
		var newer_motion=state_time>float(vehicle.get("net_motion_time",-1))
		for key in vehicle_data:
			if key in VEHICLE_FIELDS:
				if not newer_motion and key in ["position","elevation","angle","turret_angle","pose_basis","steer_angle","yaw_rate"]:continue
				vehicle[key]=vehicle_data[key]
		if newer_motion:
			vehicle.net_motion_time=state_time;vehicle.net_motion_received_usec=Time.get_ticks_usec();vehicle.net_motion_max_age=.11
		if not vehicle_data.has("pose_basis"):restore_vehicle_pose(vehicle)
		world.index_vehicle(vehicle)
	if state.has("projectiles"):
		var prior: Dictionary={}
		for round in world.projectiles:prior[int(round.id)]=round
		world.projectiles=[]
		for round_data in state.projectiles:
			var round: Dictionary=round_data
			var weapon=resolve_weapon(str(round.get("weapon_id","")),str(round.get("weapon_key","")))
			if weapon.is_empty():continue
			round.weapon=weapon
			var previous: Dictionary=prior.get(int(round.id),{})
			round.net_received_usec=Time.get_ticks_usec()
			round.net_interval=clampf(state_time-float(previous.get("net_state_time",state_time-1.0/60)),1.0/60,.3)
			round.net_state_time=state_time
			if not previous.is_empty():
				var displayed=preload("res://scripts/bullet_flight_visual.gd").head(previous,game.presentation_fraction())
				round.previous=Vector2(displayed.x,displayed.z);round.previous_height=displayed.y
			world.projectiles.append(round)
	var campaign: Dictionary=state.get("campaign",{})
	if not campaign.is_empty():
		world.campaign.phase=campaign.phase;world.campaign.reason=str(campaign.get("reason",""));world.campaign.reserves=campaign.reserves;world.campaign.deployed=campaign.deployed;world.campaign.casualties=campaign.casualties
		for index in range(mini(campaign.points.size(),world.campaign.points.size())):
			for key in ["progress","owner","contested","blue","red"]:world.campaign.points[index][key]=campaign.points[index][key]
	apply_structural_snapshot(state)

func apply_structural_snapshot(state: Dictionary):
	var world=game.world
	world.topology_revision=maxi(world.topology_revision,int(state.get("topology_revision",world.topology_revision)))
	if state.has("objects"):
		var objects_by_id: Dictionary={}
		for object in world.objects:objects_by_id[str(object.id)]=object
		for update in state.objects:
			var object: Dictionary=objects_by_id.get(str(update.id),{})
			if object.is_empty() or int(update.revision)<=int(object.revision):continue
			object.hp=update.hp;object.alive=update.alive;object.revision=update.revision
			game.pending_rebuild[object.id]=object
	if state.has("loot"):
		world.loot.bags=state.loot;world.loot.revision+=1

func diagnostics_text() -> String:
	if not is_client():return ""
	var gap=0.0 if last_motion_usec==0 else (Time.get_ticks_usec()-last_motion_usec)/1000.0
	return "\n局域网：输入回声 P50/P95 %.0f / %.0f ms · 自身更新 P95 %.0f ms · 当前断档 %.0f ms · 预测 %s"%[percentile(input_echo_ms,.5),percentile(input_echo_ms,.95),percentile(motion_gaps,.95),gap,"开启" if prediction.enabled else "旧协议"]

func bullet_presentations() -> Array:
	return projectile_stream.sample() if is_client() and supports_projectile_stream(requested_version) else game.world.projectiles

func state_gap_ms() -> float:
	return (Time.get_ticks_usec()-last_motion_usec)/1000.0 if is_client() and last_motion_usec>0 and supports_realtime(requested_version) else 0.0

func ping_ms() -> float:
	if mode not in ["host","client"]:return -1.0
	var transport=multiplayer.multiplayer_peer
	if not transport is ENetMultiplayerPeer or transport.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return -1.0
	var peers=[1] if is_client() else multiplayer.get_peers()
	var measured=-1.0
	for id in peers:
		var remote=transport.get_peer(int(id))
		if remote!=null and remote.is_active() and remote.get_state()==ENetPacketPeer.STATE_CONNECTED:
			measured=maxf(measured,remote.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return measured

func percentile(values: Array,fraction: float) -> float:
	if values.is_empty():return 0.0
	var sorted=values.duplicate();sorted.sort()
	return float(sorted[mini(sorted.size()-1,int(sorted.size()*fraction))])

func render_vehicle(vehicle: Dictionary) -> Dictionary:
	if not is_client() or not vehicle.has("net_predicted_turret") or int(game.world.player.mounted)!=int(vehicle.id):return vehicle
	var result=vehicle.duplicate(false)
	result.turret_angle=vehicle.net_predicted_turret;result.aim_target=vehicle.net_predicted_aim
	return result
