extends SceneTree
var game
var start=0
var previous=0
var frames: Array=[]
var draws: Array=[]
var particles: Array=[]
var finished=false
func _initialize():run.call_deferred()
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game=load("res://proving_ground.tscn").instantiate();game.qa_mode=true;root.add_child(game);game.set_physics_process(false)
	game.world.player.position=Vector2(-6.5,-3);game.world.equip("minigun");game.zoom=24
	start=Time.get_ticks_usec();previous=start
func _physics_process(delta: float) -> bool:
	if game==null or start==0 or finished:return false
	var time=(Time.get_ticks_usec()-start)/1000000.0
	var target=game.world.units[1+int(time)%6]
	game.aim=target.position;game.world.player.aim_height=1.1
	game.world.step(delta,Vector2(sin(time*.8)*.3,0),game.aim,true,true)
	if game.world.player.reserve<=0:game.world.refill()
	return false
func _process(_delta: float) -> bool:
	if game==null or start==0 or finished:return false
	var now=Time.get_ticks_usec();var elapsed=(now-start)/1000000.0;var duration=(now-previous)/1000.0;previous=now
	if elapsed>2:
		frames.append(duration);draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));particles.append(game.fx.particles.size())
	if elapsed>=10:finish()
	return false
func summary(values: Array) -> Dictionary:
	var sorted=values.duplicate();sorted.sort();var total=0.0
	for x in values:total+=x
	return {"mean":total/values.size(),"p95":sorted[int(sorted.size()*.95)],"max":sorted[-1]}
func finish():
	finished=true;var frame=summary(frames)
	var report={"fps":1000/frame.mean,"frame_ms":frame,"draw_calls":summary(draws),"particles":summary(particles),"viewport":str(root.size),"gpu":RenderingServer.get_video_adapter_name(),"warmup_seconds":2,"sample_seconds":8,"shots":game.world.shots,"kills":game.world.kills,"actors":game.world.units.size(),"vehicles":game.world.vehicles.size(),"corpses":game.fx.corpses.size(),"vsync":false,"sound":false}
	var file=FileAccess.open("res://qa/range-benchmark.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("RANGE_BENCHMARK ",JSON.stringify(report));await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://qa/range-live-fire.png");quit()
