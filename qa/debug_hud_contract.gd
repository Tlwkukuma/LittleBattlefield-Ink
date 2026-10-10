extends SceneTree
## Frozen real scene, UI state changes only. Never advances AI or gameplay.
var checks=0
var failures=0
func check(ok: bool,description: String):
	checks+=1
	if not ok:failures+=1;push_error(description)
func _initialize():run.call_deferred()
func settle(game):
	for i in range(4):await process_frame
	game.hud_batches.refresh()
func run():
	# A failing fixture must produce a terminal result rather than wait forever.
	create_timer(240).timeout.connect(func():push_error("DEBUG_HUD_CONTRACT watchdog expired");quit(2))
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	# Default entry is now home/range. Prepare the existing campaign explicitly,
	# with processing disabled before insertion and no world/input stepping.
	if not game.world.campaign_active():game.start_level01()
	game.home_ui.hide_menu()
	game.armory.hide();game._process(0);await settle(game)
	check(game.world.campaign_active() and game.campaign_ui.hud_summary.has("remaining"),"Campaign fixture supplies force summary")
	if not game.campaign_ui.hud_summary.has("remaining"):
		game.free();quit(1);return
	var drawer=game.debug_ui;var overlay=game.performance_overlay
	check(not game.debug_open(),"Debug starts closed")
	check(drawer.toggle_button.is_visible_in_tree(),"single Debug entry is visible")
	check(not overlay.is_processing() and game.performance_log==null and not game.world.profile_ai,"closed debug has no metric/profiling work")
	for node in [game.hud,game.subtitle,game.notice,game.campaign_ui.title,game.campaign_ui.controls,game.campaign_ui.status,overlay,game.editor.panel]:
		check(drawer.panel.is_ancestor_of(node) and not node.is_visible_in_tree(),"all diagnostics are under the hidden drawer: "+node.name)
	var diagnostic_sources=0
	for item in game.hud_batches.items:
		if drawer.panel.is_ancestor_of(item.node):diagnostic_sources+=1
	check(diagnostic_sources==0,"debug subtree excluded from retained battle glyph/shape batches")
	var before=[overlay.sample_count,drawer.refresh_count,game.hud.text,game.campaign_ui.status.text]
	var frames_before=game.frames
	for i in range(12):game._process(0);overlay._process(1);drawer.refresh(1)
	check(before==[overlay.sample_count,drawer.refresh_count,game.hud.text,game.campaign_ui.status.text],"closed diagnostic samplers and text remain unchanged")
	check(game.frames==frames_before+12,"Lightweight always-on FPS counter remains separate from diagnostic sampling")
	check(game.campaign_ui.hud_summary.remaining==[int(game.plan.deployment.blue.totalForce),int(game.plan.deployment.red.totalForce)],"normal force HUD includes active and reserve forces")
	check(game.combat_hud.visible and not game.hud.is_visible_in_tree(),"health belongs to gameplay HUD, no default stats footer")
	var identity=game.subtitle.text
	drawer.set_open(true);await settle(game);drawer.refresh(1);game.campaign_ui.refresh()
	check(game.debug_open() and overlay.is_processing(),"only opening Debug enables performance sampling")
	check(not game.weapon_shortcut_available() and game.over_ui(),"debug blocks accidental combat input")
	check(not game.trigger_pressed and not game.jump_pressed and game.weapon_input_latched,"opening clears buffered action buttons")
	check(game.performance_log==null,"basic monitor doesn't turn on detailed CPU/GPU profiling")
	overlay.sampled_at=Time.get_ticks_usec()-300000;overlay.previous_frame=Time.get_ticks_usec()-16000;overlay._process(.016)
	check(overlay.sample_count==before[0]+1,"visible monitor reads metrics on demand")
	drawer.recording.button_pressed=true
	check(game.performance_log!=null and game.world.profile_ai,"explicit visible-page profiling can be enabled")
	drawer.tabs.current_tab=1
	check(not overlay.is_processing() and game.performance_log==null and not game.world.profile_ai,"leaving performance page also stops instrumentation")
	drawer.tabs.current_tab=0
	check(overlay.is_processing() and game.performance_log!=null,"returning to performance page starts a fresh profiling session")
	drawer.set_open(false);await settle(game)
	var samples=overlay.sample_count;var updates=drawer.refresh_count
	for i in range(6):game._process(0);overlay._process(1);drawer.refresh(1)
	check(samples==overlay.sample_count and updates==drawer.refresh_count,"close stops sampling and text refresh immediately")
	check(game.performance_log==null and not game.world.profile_ai and overlay.frame_history.is_empty(),"close releases measurements and stale percentile history")
	check(game.subtitle.text==identity,"opening and closing preserves build/start identity")
	# Small and standard viewport layouts, actual Control minimum sizes included.
	for extent in [Vector2i(1280,720),Vector2i(1440,900)]:
		root.size=extent;drawer.set_open(true);await settle(game)
		var bounds=Rect2(Vector2.ZERO,game.get_viewport().get_visible_rect().size)
		check(bounds.encloses(drawer.panel.get_global_rect()),"debug panel fits viewport "+str(extent))
		check(bounds.encloses(drawer.toggle_button.get_global_rect()),"Debug button fits viewport "+str(extent))
		drawer.set_open(false)
	check(game.world.time==0 and game.world.shots==0,"no AI/gameplay simulation in UI contract")
	# Same entry and start identity survive scene/menu changes; no world stepping.
	var launch=game.launch_stamp
	game.start_training();await settle(game)
	check(not game.debug_open() and not game.editing,"scene changes return to a clean gameplay HUD")
	game.toggle_armory()
	check(game.armory.visible and game.vehicle_list.is_visible_in_tree(),"Tab keeps original vehicle and weapon selection")
	game.armory.hide();drawer.set_open(true);drawer.open_editor();await settle(game)
	check(game.editing and drawer.panel.is_ancestor_of(game.editor.panel) and game.editor.panel.is_visible_in_tree(),"scene editor is inside the same Debug drawer")
	drawer.set_open(false);await settle(game)
	check(not game.editing and not game.debug_open() and not game.editor.panel.is_visible_in_tree(),"closing Debug safely leaves scene editing")
	game.start_level01();await settle(game)
	check(game.launch_stamp==launch and game.subtitle.text==identity,"scene round trip preserves version and launch identity")
	check(not game.debug_open() and game.world.time==0 and game.world.shots==0,"scene round trip never plays the game")
	print("DEBUG_HUD_CONTRACT "+JSON.stringify({"version":game.BUILD_VERSION,"checks":checks,"failures":failures,"diagnostic_batch_sources":diagnostic_sources,"samples_after_close":samples,"simulation_time":game.world.time,"shots":game.world.shots}))
	game.queue_free();await process_frame;quit(0 if failures==0 else 1)
