extends SceneTree
## Own-process host for joining when every blue AI soldier has fallen.
func _initialize():call_deferred("run_smoke")

func run_smoke():
	change_scene_to_file("res://proving_ground.tscn")
	for index in range(4):await process_frame
	var game=current_scene
	if game==null or not game.is_node_ready():
		printerr("LAN_REINFORCEMENT scene failed");quit(2);return
	game.start_level01()
	var blue_dead=0
	for unit in game.world.units:
		if unit.team!=0 or unit.player:continue
		unit.alive=false;unit.health=0;unit.death_age=2.0
		blue_dead+=1
	game.world.campaign.reserves[0]=0
	if blue_dead<1 or not game.lan.host_game():
		printerr("LAN_REINFORCEMENT host failed blue_dead=",blue_dead);quit(2);return
	print("LAN_REINFORCEMENT_HOST_READY blue_dead=",blue_dead," reserves=",game.world.campaign.reserves[0])
	for index in range(120):
		if game.lan.peer_ready.values().has(true):break
		await create_timer(.25).timeout
	if not game.lan.peer_ready.values().has(true):
		printerr("LAN_REINFORCEMENT client not ready");quit(2);return
	var assigned_id=int(game.lan.peer_units.values()[0])
	var assigned: Dictionary=game.world.units[assigned_id]
	if not assigned.alive or assigned.team!=0 or int(assigned.get("network_peer_id",0))<=0:
		printerr("LAN_REINFORCEMENT invalid assigned unit ",assigned);quit(2);return
	print("LAN_REINFORCEMENT_HOST_OK unit=",assigned_id," health=",assigned.health," reserves=",game.world.campaign.reserves[0])
	await create_timer(6).timeout
	quit()
