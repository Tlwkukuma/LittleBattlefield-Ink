extends SceneTree
func _initialize():call_deferred("run")
func run():
	change_scene_to_file("res://proving_ground.tscn")
	for i in range(4):await process_frame
	var game=current_scene
	game.set_physics_process(false);game.set_process(false)
	game.start_level01();game.world.ai_enabled=false
	var world=game.world
	var local: Dictionary=world.player
	var remote: Dictionary={}
	for unit in world.units:
		if unit.alive and unit.team==local.team and not unit.player and unit.mounted<0:remote=unit;break
	if remote.is_empty():printerr("CONTRACT no remote unit");quit(2);return
	var origin=local.position
	var direction=Vector2.RIGHT
	for candidate in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		if not world.blocked(origin+candidate*3.5,.3,1.5,-1,local.elevation):direction=candidate;break
	for unit in [local,remote]:
		world.Traversal.reset(unit);unit.position=origin;unit.elevation=world.terrain.height(origin);unit.velocity=Vector2.ZERO;unit.requested_velocity=Vector2.ZERO
		unit.stance=0;unit.stance_blend=0;unit.simulation_pending=0;unit.healing={};unit.throw_state={};unit.melee={}
	remote.network_peer_id=123
	var control={"movement":direction,"aim":origin+direction*10,"trigger":false,"pressed":false,"aiming":false,"sprint":false,"jump":false,"fire_allowed":false}
	world.network_inputs[int(remote.id)]=control
	for i in range(60):world.step(1.0/60,direction,origin+direction*10,false,false)
	var local_distance=local.position.distance_to(origin)
	var remote_distance=remote.position.distance_to(origin)
	print("LAN_SCHEDULE_RESULT version=",game.BUILD_VERSION," local_m=",local_distance," remote_m=",remote_distance," ratio=",remote_distance/maxf(.0001,local_distance))
	if game.lan.get("prediction")==null:quit();return
	if absf(local_distance-remote_distance)>.02:printerr("CONTRACT host/client movement differs");quit(2);return
	world.network_inputs.clear();remote.erase("network_peer_id")
	game.lan.mode="client";game.lan.assigned_unit=int(local.id)
	var wall_found=false
	for object in world.objects:
		if not object.alive or not object.collision or not str(object.component_id).begins_with("wall.") or object.height<1.4:continue
		var approach=Vector2.DOWN.rotated(object.angle)
		var start: Vector2=object.position-approach*(object.size.y*.5+.31)
		var height=world.ground_height(start,.28,object.elevation+.2)
		if world.blocked(start,.28,1.5,-1,height) or not world.blocked(start+approach*.2,.28,1.5,-1,height):continue
		world.Traversal.reset(local);local.position=start;local.elevation=height;local.requested_velocity=Vector2.ZERO;local.velocity=Vector2.ZERO;local.mounted=-1
		game.lan.prediction.reset();game.lan.prediction.reconcile(local,0)
		for i in range(60):game.lan.prediction.submit({"_sequence":i+1,"movement":approach,"aim":start+approach*10},1.0/60)
		var predicted: Dictionary=game.lan.prediction.unit
		if local.position!=start or world.blocked(predicted.position,.28,world.collision_height(predicted),-1,predicted.elevation):
			printerr("CONTRACT prediction crossed wall or changed authority");quit(2);return
		wall_found=true;break
	if not wall_found:printerr("CONTRACT no wall fixture");quit(2);return
	var mounted_tested=false
	for vehicle in world.vehicles:
		if not vehicle.emplacement or vehicle.destroyed:continue
		local.mounted=int(vehicle.id);game.lan.prediction.reconcile(local,60)
		var actual=float(vehicle.turret_angle)
		for i in range(12):game.lan.prediction.submit({"_sequence":61+i,"aim":vehicle.position+Vector2.from_angle(vehicle.angle+.3)*12},1.0/60)
		if float(vehicle.turret_angle)!=actual or absf(float(game.lan.render_vehicle(vehicle).turret_angle)-actual)<.001:
			printerr("CONTRACT turret prediction changed authority or failed to respond");quit(2);return
		mounted_tested=true;break
	if not mounted_tested:printerr("CONTRACT no mounted fixture");quit(2);return
	var flight=load("res://scripts/bullet_flight_visual.gd")
	var round={"previous":Vector2.ZERO,"position":Vector2(1,0),"previous_height":1.0,"height":1.0,"net_interval":.1}
	var previous=-1.0
	for age in [.01,.03,.05,.08,.1]:
		round.net_received_usec=Time.get_ticks_usec()-int(age*1000000)
		var current=float(flight.head(round,.05).x)
		if current<previous:printerr("CONTRACT bullet presentation restarted");quit(2);return
		previous=current
	var payload=PackedByteArray();var random=RandomNumberGenerator.new();random.seed=53
	for i in range(3000):payload.append(random.randi()%256)
	var own={"health":199.0,"_ack":100,"diagnostic_payload":payload}
	var packets=game.lan.realtime_packets({"type":"owner","time":world.time+.1,"data":game.lan.pack_snapshot(own)})
	if packets.size()<2:printerr("CONTRACT fragmented fixture too small");quit(2);return
	for packet in packets:
		if var_to_bytes(packet).size()>1100:printerr("CONTRACT oversized fragment");quit(2);return
	for i in range(packets.size()-1,0,-1):game.lan.receive_realtime(packets[i])
	if local.health==199:printerr("CONTRACT incomplete fragment was applied");quit(2);return
	game.lan.receive_realtime(packets[0])
	game.lan.flush_owner_state()
	if local.health!=199:printerr("CONTRACT reordered fragments did not reconstruct");quit(2);return
	var applications=game.lan.owner_states_applied
	var burst_clock=world.time
	for index in range(100):
		game.lan.receive_realtime({"type":"owner","time":burst_clock+.01*(index+1),"data":game.lan.pack_snapshot({"health":100.0+index,"_ack":101+index})})
	if game.lan.owner_states_applied!=applications:printerr("CONTRACT burst applied inside polling");quit(2);return
	game.lan.flush_owner_state()
	if game.lan.owner_states_applied!=applications+1 or local.health!=199 or game.lan.prediction.last_ack!=200:
		printerr("CONTRACT burst did not retain only latest authority");quit(2);return
	print("LAN_OWNER_BURST_OK queued=100 applied=1 coalesced=",game.lan.owner_states_coalesced)
	var mobile: Dictionary={}
	for vehicle in world.vehicles:
		if not vehicle.emplacement:mobile=vehicle;break
	if mobile.is_empty():printerr("CONTRACT no mobile vehicle");quit(2);return
	var turn=float(mobile.angle)+PI*.5
	var turn_clock=world.time+.1
	game.lan.apply_motion_frame({"time":turn_clock,"vehicles":PackedFloat32Array([mobile.id,mobile.position.x,mobile.position.y,mobile.elevation,turn,turn+.2])})
	var expected_basis=game.lan.VehicleGround.basis(turn,mobile.ground.get("normal",Vector3.UP))
	if not game.VehicleRenderMotion.sample(mobile,.5).body.is_equal_approx(expected_basis):printerr("CONTRACT legacy vehicle yaw stayed frozen");quit(2);return
	var stale_vehicle_snapshot=game.lan.make_snapshot()
	var slope_pose=game.lan.VehicleGround.basis(turn+.3,Vector3(.1,1,.2).normalized())*Basis(Vector3.RIGHT,.025)*Basis(Vector3.FORWARD,-.02)
	var quaternion=slope_pose.get_rotation_quaternion()
	game.lan.apply_motion_frame({"time":turn_clock+.1,"vehicle_stride":12,"vehicles":PackedFloat32Array([mobile.id,mobile.position.x,mobile.position.y,mobile.elevation,turn+.3,turn+.6,quaternion.x,quaternion.y,quaternion.z,quaternion.w,.24,.4])})
	game.lan.apply_snapshot(stale_vehicle_snapshot)
	if not game.VehicleRenderMotion.sample(mobile,.5).body.is_equal_approx(slope_pose) or absf(float(mobile.steer_angle)-.24)>.0001:
		printerr("CONTRACT vehicle tilt/steer overwritten by stale snapshot");quit(2);return
	print("LAN_VEHICLE_POSE_OK legacy_yaw=true quaternion_tilt=true steer=true stale_snapshot_guard=true")
	print("LAN_RUNTIME_CONTRACT_OK prediction_wall=true turret_authority=true bullet_monotonic=true fragments=",packets.size())
	quit()
