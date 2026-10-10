extends SceneTree
## Frozen state contracts only. This never drives or simulates a battle.
var failures: Array=[]
func check(value: bool,label: String):
	if not value:failures.append(label);push_error(label)

class ProfileWorld:
	extends RefCounted
	var time=0.0
	var ai_budget_usec=2000
	var player={"velocity":Vector2.ZERO}
	var units: Array=[]
	var projectiles: Array=[]
	var last_step_profile={"total_ms":1.0,"unit_rays":{"rays":2,"cache":{"nested":3}},"ai_detail":{"rays":1,"observe_ms":0.5,"budget":{"remaining":9}}}
	func campaign_active():return false

func _initialize():call_deferred("run")
func run():
	var Logger=load("res://scripts/runtime_performance.gd")
	var logger=Logger.new();var profile=ProfileWorld.new()
	var path="user://loading-contract-performance.jsonl"
	check(logger.start_session(path),"new session opens")
	logger.record_physics(Time.get_ticks_usec(),profile)
	logger.record_frame(Time.get_ticks_usec(),0.016,profile)
	logger.boundary("test_pause")
	var first=FileAccess.get_file_as_string(path)
	check(logger.start_session(path),"repeated start succeeds")
	check(FileAccess.get_file_as_string(path)==first,"repeated start does not truncate")
	check(logger.last_presented_usec==0 and logger.pending_physics_steps==0,"boundary clears clocks and catchup")
	var samples=JSON.parse_string(first.split("\n")[1])
	check(samples.data.unit_ray_metadata.cache.nested==3,"nested unit ray metadata retained")
	check(samples.data.ai_query_metadata.budget.remaining==9,"nested AI metadata retained")
	check(samples.data.unit_ray_totals.rays==2,"numeric ray totals")
	check(samples.data.render_gpu.status=="unknown","unsupported GPU is unknown")
	var bounded=[]
	for i in range(6000):Logger._sample(bounded,i)
	check(bounded.size()==Logger.MAX_SAMPLES,"sample memory bounded")
	logger.stop_session()
	check(FileAccess.get_file_as_string(path).contains("session_stop"),"stop flushes")

	var cancelled_startup=load("res://scripts/proving_ground.gd").new()
	cancelled_startup.paused=true;root.add_child(cancelled_startup)
	check(not cancelled_startup.loading_ui.home_button.visible,"startup does not offer a non-existent home")
	cancelled_startup.loading_ui.panel.size=Vector2(480,720);cancelled_startup.loading_ui._layout()
	check(cancelled_startup.loading_ui.content.custom_minimum_size.x<=448,"loading content fits narrow viewport")
	cancelled_startup.loading_ui.cancel_button.pressed.emit()
	while cancelled_startup.loading_active:await process_frame
	check(not cancelled_startup.world_ready and cancelled_startup.loading_ui.state=="cancelled","startup cancel exits without waiting for watchdog")
	check(cancelled_startup.loading_ui.retry_button.text=="重新加载场景","startup retry clearly names reload")
	var stopped_generation=cancelled_startup.loading_generation
	cancelled_startup.loading_ui.home_requested.emit()
	await process_frame
	check(cancelled_startup.loading_generation==stopped_generation and cancelled_startup.loading_ui.state=="cancelled","startup error page remains stable")
	cancelled_startup.queue_free();await process_frame
	var game=load("res://scripts/proving_ground.gd").new()
	game.paused=true
	root.add_child(game)
	# A startup rebuild may yield; no battle may advance during this wait.
	while game.loading_active or game.home_ui==null:
		await process_frame
		if game.loading_ui!=null and game.loading_ui.state in ["failed","cancelled"]:
			check(false,"startup succeeds");break
	check(game.world_ready,"startup world ready")
	game.paused=true
	var old_world=game.world;var old_stage=game.stage
	var old_selected=game.campaign_progress.selected
	game.start_campaign_chapter(1)
	check(game.loading_active and game.loading_ui.visible,"entry immediately shows independent loading canvas")
	check(game.loading_ui.layer>game.ui.get_parent().layer,"loading canvas above menu")
	var generation=game.loading_generation
	game.start_campaign_chapter(1)
	check(game.loading_generation==generation,"duplicate entry ignored")
	var frozen=old_world.time
	game._physics_process(1.0)
	check(old_world.time==frozen,"physics blocked during loading")
	game.loading_ui.cancel_button.pressed.emit()
	while game.loading_active:await process_frame
	check(game.world==old_world and game.stage==old_stage,"cancel restores original world and stage")
	check(game.campaign_progress.selected==old_selected,"cancel does not advance progress")
	check(game.loading_ui.state=="cancelled" and game.loading_ui.retry_button.visible,"cancel offers retry")
	game.loading_ui.hide()
	var original_steps=Engine.max_physics_steps_per_frame
	var original_hz=Engine.physics_ticks_per_second
	var original_jitter=Engine.physics_jitter_fix
	game.editor.panel.show()
	var original_style=game.style_button.visible if game.style_button!=null else false
	game.start_campaign_chapter(1)
	while game.loading_active and (game.world==old_world or Engine.max_physics_steps_per_frame!=2):await process_frame
	check(game.loading_active and game.world!=old_world and Engine.max_physics_steps_per_frame==2,"campaign setup changed physics before injected failure")
	game.loading_ui.failure="injected failure after campaign setup"
	while game.loading_active:await process_frame
	check(game.world==old_world and game.stage==old_stage,"mid-build failure restores training world")
	check(Engine.max_physics_steps_per_frame==original_steps and Engine.physics_ticks_per_second==original_hz and Engine.physics_jitter_fix==original_jitter,"rollback restores all global physics parameters")
	check(game.campaign_ui.training_box.visible and not game.campaign_ui.equipment_box.visible,"rollback rebinds training UI")
	check(game.campaign_ui.objective_views.is_empty(),"rollback removes campaign objective bindings")
	check(game.editor.panel.visible,"rollback restores editor panel visibility")
	check(game.style_button==null or game.style_button.visible==original_style,"rollback restores style button visibility")
	check(game.campaign_progress.selected==old_selected,"mid-build failure does not save chapter")
	game.editor.panel.hide()
	game.loading_ui.hide()
	game._start_loading("failure contract")
	game.loading_ui.failure="injected setup failure";game._finish_loading(false)
	check(game.world==old_world and game.loading_ui.state=="failed","failure rolls back and exposes error")
	game.loading_ui.hide()
	game._start_loading("watchdog contract")
	game.loading_ui.started=Time.get_ticks_msec()-120001
	check(not game._loading_valid(game.loading_generation),"watchdog bounded")
	game._finish_loading(false)
	# Simulate a delayed callback from the just-failed request after a new one begins.
	var stale_generation=game.loading_generation
	game._start_loading("new request after timeout")
	var live_generation=game.loading_generation
	game._finish_loading(false,stale_generation)
	check(game.loading_active and game.loading_generation==live_generation,"stale rollback cannot terminate new request")
	game.loading_ui.cancelled=true;game._finish_loading(false,live_generation)
	game.loading_ui.retry_button.pressed.emit()
	while game.loading_active:await process_frame
	check(game.world_ready and game.loading_ui.state=="ready","retry completes")
	check(game.armory.visible and game.world.time==0,"ready campaign remains in briefing")
	check(game.actors.size()==game.world.units.size(),"all soldiers built")
	check(game.vehicle_views.size()==game.world.vehicles.size(),"all vehicles built")
	check(game.object_views.size()==game.world.objects.size(),"all objects built")
	game.set_play_recording(true)
	var recorder=game.performance_log
	game.set_debug_profiling(false)
	check(game.performance_log==recorder and game.world.profile_ai,"Debug off leaves play recording active")
	game.set_play_recording(true)
	check(game.performance_log==recorder,"repeat recording enable preserves session")
	game.set_play_recording(false)
	check(game.performance_log==null,"explicit stop disables unused profiler")
	print("LOADING_TELEMETRY_CONTRACT "+JSON.stringify({"failures":failures,"drawn":game.loading_ui.drawn,"units":game.world.units.size(),"time":game.world.time}))
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
