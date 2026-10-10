extends SceneTree
var problems: Array=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://main.tscn").instantiate()
	scene.qa_mode=true
	scene.benchmark=true
	root.add_child(scene)
	scene.enter_room_preview()
	scene.camera.size=9
	scene.camera.position=Vector3(scene.sim.player.position.x,32.75,scene.sim.player.position.y+32)
	scene.camera.look_at(Vector3(scene.sim.player.position.x,.75,scene.sim.player.position.y))
	for i in range(15): await process_frame
	scene.update_roofs(1.0)
	if scene.houses[0].roof.visible or not scene.houses[0].inside:problems.append("Roof did not cut on entry")
	scene.hud.perf="室内显示验证 · 非性能采样"
	scene.perf_clock=-100
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/interior-cutaway.png")
	scene.roof_mode=2
	scene.update_roofs(1.0)
	if absf(scene.houses[0].fade-.12)>.001:problems.append("Dither roof fade not applied")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/interior-fade.png")
	scene.sim.player.position=Vector2(0,10)
	scene.roof_mode=0
	scene.update_roofs(1.0)
	if not scene.houses[0].roof.visible or scene.houses[0].inside:problems.append("Roof did not restore after exit")
	scene.roof_mode=1
	scene.update_roofs(1.0)
	if scene.houses.any(func(h):return h.roof.visible):problems.append("Always-off roof mode failed")
	scene.reset_match()
	scene.toggle_inspection()
	scene.sim.player.position=Vector2(0,4)
	scene.sim.player.facing=Vector2(.45,.9).normalized()
	scene.camera.size=5.5
	scene.camera.position=Vector3(0,32.75,36)
	scene.camera.look_at(Vector3(0,.75,4))
	scene.sim.player.ammo=15
	scene.sim.start_reload(scene.sim.player)
	for phase in [.28,.60,.84]:
		scene.sim.player.reload=float(scene.weapon.reload)*(1-phase)
		scene.update_views(.1)
		for i in range(2): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/reload-%d.png" % int(phase*100))
	var rig=scene.actor_views[scene.sim.player.id].skeleton
	if rig.get_bone_count()!=13:problems.append("Expected 13 bone rig including prone neck")
	for i in range(rig.get_bone_count()):
		if not rig.get_bone_global_pose(i).is_finite():problems.append("Invalid bone transform")
	print("VISUAL_FEATURES ",JSON.stringify({"passed":problems.is_empty(),"problems":problems}))
	quit(0 if problems.is_empty() else 1)
