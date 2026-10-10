extends SceneTree
## Rendered integration check: the real scene receives all combat signals.
var problems: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://main.tscn").instantiate()
	scene.qa_mode=true
	root.add_child(scene)
	await process_frame
	var sim=scene.sim
	for frame in range(60*90):
		if not sim.result.is_empty():
			break
		var aim: Vector2=sim.objective
		var movement=Vector2.ZERO
		var nearest=1.0e10
		for u in sim.units:
			if u.team!=1 or not u.alive:
				continue
			var d=sim.player.position.distance_squared_to(u.position)
			if d<nearest:
				nearest=d
				aim=u.position
		if sim.enemies_alive()==0:
			var path=sim.navigation.get_point_path(sim.nearest_cell(sim.player.position),sim.nearest_cell(sim.objective))
			var next: Vector2=path[1] if path.size()>1 else sim.objective
			if sim.player.position.distance_to(sim.objective)>1.0:
				movement=(next-sim.player.position).normalized()
		sim.step(1.0/60,movement,aim,sim.enemies_alive()>0)
		scene.update_views(1.0/60)
		scene.update_effects(1.0/60)
		if frame%8==0:
			await process_frame
	if sim.result!="victory":
		problems.append("Rendered battle failed to reach victory")
	for obstacle in sim.obstacles:
		if obstacle.destructible and not obstacle.alive and scene.wall_views[obstacle.id].visible:
			problems.append("Destroyed wall remained visible: "+obstacle.id)
	for i in range(15):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/victory.png")
	var summary={"result":sim.result,"kills":sim.kills,"broken":sim.broken,"seconds":sim.elapsed}
	scene.reset_match()
	scene.toggle_inspection()
	if not scene.paused or not scene.hud.inspection:
		problems.append("Character inspection did not pause combat")
	scene.inspection_walk=true
	for i in range(15):
		await process_frame
	# Rest translations must remain intact while the leg rotations animate.
	var skeleton=scene.actor_views[0].skeleton
	if skeleton.get_bone_pose_position(1).distance_to(Vector3(-0.115,0.90,0.03))>0.001:
		problems.append("Hip rest position was lost during animation")
	scene.toggle_inspection()
	if scene.paused or scene.hud.inspection:
		problems.append("Leaving inspection did not restore gameplay")
	if sim.enemies_alive()!=5 or sim.player.ammo!=30 or sim.result!="":
		problems.append("Replay failed to restore the initial match")
	FileAccess.open("res://qa/playthrough-report.json",FileAccess.WRITE).store_string(JSON.stringify({"battle":summary,"problems":problems,"passed":problems.is_empty()},"\t"))
	print("RENDERED_PLAYTHROUGH ",JSON.stringify(summary)," problems=",problems)
	quit(0 if problems.is_empty() else 1)
