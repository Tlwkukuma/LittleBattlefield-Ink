extends SceneTree
## Windowed, real GPU benchmark; no headless FPS and no VSync cap.
var game
var start_usec = 0
var previous_usec = 0
var samples: Array = []
var cpu: Array = []
var animation: Array = []
var draws: Array = []
var primitives: Array = []
var live: Array = []
var strict = false
var recorded = false
var seconds = 18.0

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--strict100": strict=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game=load("res://main.tscn").instantiate()
	game.crowd_mode=true
	game.benchmark=true
	game.qa_mode=true
	root.add_child(game)
	game.paused=false
	game.camera.size=30
	game.zoom_goal=30
	start_usec=Time.get_ticks_usec()
	previous_usec=start_usec
	print("BENCHMARK_START strict100=",strict)

func _physics_process(delta: float) -> bool:
	if game==null or start_usec==0 or recorded: return false
	var player: Dictionary=game.sim.player
	var target: Dictionary={}
	var nearest=10000.0
	for u in game.sim.units:
		if u.team!=player.team and u.alive:
			var distance=player.position.distance_squared_to(u.position)
			if distance<nearest:
				nearest=distance
				target=u
	var begin=Time.get_ticks_usec()
	game.sim.step(delta,Vector2(sin(game.sim.elapsed*.6)*.3,0),target.position if not target.is_empty() else Vector2.ZERO,true)
	if strict:
		for u in game.sim.units:
			if not u.alive: game.sim.respawn(u)
	game.simulation_ms=(Time.get_ticks_usec()-begin)/1000.0
	return false

func _process(_delta: float) -> bool:
	if game==null or start_usec==0 or recorded: return false
	var now=Time.get_ticks_usec()
	var elapsed=(now-start_usec)/1000000.0
	var frame=(now-previous_usec)/1000.0
	previous_usec=now
	game.paused=false
	if elapsed>3.0:
		samples.append(frame)
		cpu.append(game.simulation_ms)
		animation.append(game.animation_ms)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		live.append(game.sim.units.filter(func(u):return u.alive).size())
	if elapsed>seconds: finish.call_deferred()
	return false

func stats(values: Array) -> Dictionary:
	var sorted=values.duplicate()
	sorted.sort()
	var total=0.0
	for v in values: total+=v
	return {"mean":total/values.size(),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*.95))],"p99":sorted[mini(sorted.size()-1,int(sorted.size()*.99))],"min":sorted[0],"max":sorted[-1]}

func finish() -> void:
	if recorded:return
	recorded=true
	var frames=stats(samples)
	var report={"mode":"100 continuously alive / instant respawn" if strict else "50 vs 50 / 2 second respawn",
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":"Compatibility/OpenGL",
		"viewport":str(root.size),"vsync":false,"warmup_seconds":3,"sample_seconds":(Time.get_ticks_usec()-start_usec)/1000000.0-3,
		"frames":samples.size(),"fps":1000.0/frames.mean,"frame_ms":frames,"simulation_ms":stats(cpu),"animation_ms":stats(animation),
		"draw_calls":stats(draws),"render_primitives":stats(primitives),"alive":stats(live),"actors":game.sim.units.size(),
		"shots":game.sim.total_shots,"respawns":game.sim.respawns,"result":game.sim.result}
	var name="strict100" if strict else "crowd100"
	var file=FileAccess.open("res://qa/"+name+"-benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("BENCHMARK_RESULT ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/"+name+"-battle.png")
	quit()
