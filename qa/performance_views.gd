extends SceneTree
## Frozen client animation and presentation calls, not an automated battle.
var label="baseline"
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	call_deferred("measure")
func measure():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(game);game.update_camera(0)
	for unit in game.world.units:
		unit.velocity=Vector2(0,-2.8);unit.aiming=true;unit.aim_point=unit.position+Vector2(0,-10);unit.aim_height=unit.elevation+1.25
	var values=[]
	for sample in range(16):
		var before=Time.get_ticks_usec();game._process(1.0/60.0)
		if sample>=2:values.append((Time.get_ticks_usec()-before)/1000.0)
	values.sort()
	var result={"battle_steps":0,"simulation_time":game.world.time,"units":game.world.units.size(),"client_update_ms":{"median":values[values.size()/2],"max":values[-1],"min":values[0]}}
	if game.performance_log!=null:result.last_frame=game.performance_log.last_frame
	DirAccess.make_dir_recursive_absolute("res://qa/performance")
	var file=FileAccess.open("res://qa/performance/"+label+"-views.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("FROZEN_VIEWS "+JSON.stringify(result));game.free();quit()
