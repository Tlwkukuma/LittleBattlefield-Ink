extends SceneTree
## Real entry/menu controls only. No player input, world stepping or battle verdict.
const Tactical=preload("res://scripts/tactical_ui.gd")
var checks=0
var failures: Array=[]
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func settle():
	for index in range(4):await process_frame
func run():
	create_timer(240).timeout.connect(func():push_error("TACTICAL_UI_CONTRACT watchdog expired");quit(2))
	var game=load("res://scripts/proving_ground.gd").new()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	while game.home_ui==null or game.get("loading_active")==true:
		var startup_loading=game.get("loading_ui")
		if startup_loading!=null and startup_loading.get("state") in ["failed","cancelled"]:
			push_error("real startup did not complete");quit(2);return
		await process_frame
	await settle()
	var loading=game.get("loading_ui")
	if loading==null:
		loading=load("res://scripts/campaign_loading.gd").new();root.add_child(loading)
	var home=game.home_ui
	check(home!=null and home.main_view.get_child_count()>3,"Home.setup built native menu controls")
	check(Tactical.build_count==1,"one cached theme construction")
	var shared=Tactical.theme_resource()
	check(game.ui.theme==shared and home.theme==shared and game.loot_panel.theme==shared and game.equipment_wheel.theme==shared and game.combat_hud.theme==shared,"all native roots share theme")
	check(game.combat_hud.card_style==Tactical.panel_style(),"HUD retains shared style resource")
	check(not game.debug_open() and game.performance_log==null,"debug instrumentation remains off")
	for control in [game.armory,game.weapon_search,game.weapon_list,game.weapon_filter,game.loot_panel.panel,game.campaign_ui.result_panel,game.campaign_ui.briefing,game.debug_ui.tabs,game.play_notice]:
		check(control.get_theme_default_font()==Tactical.font_resource(),"real native surface inherits shared font: "+control.get_class())
	check(home.recording!=null and home.main_view.is_ancestor_of(home.recording),"recording switch is in ordinary menu")
	check(preload("res://scripts/battle_status_hud.gd").BLUE==Color("628ab0") and preload("res://scripts/battle_status_hud.gd").RED==Color("bd6968"),"team colours unchanged")
	check(game.combat_hud.GOLD==Color("e5bf79") and game.combat_hud.DANGER==Color("e8957d"),"low-ammo and danger semantics unchanged")
	var initial_time=game.world.time;var initial_shots=game.world.shots
	# Exercise the ordinary native menu's signal binding against the integrated logger.
	# This writes session boundaries under the test's isolated user://, never steps play.
	check(not game.play_recording and not home.recording.button_pressed and game.performance_log==null,"recording defaults off in runtime and ordinary menu")
	check(not game.debug_open() and not game.debug_profiling_requested,"recording test starts without Debug profiling")
	var recording_changes: Array=[]
	game.play_recording_changed.connect(func(enabled):recording_changes.append(enabled))
	home.recording.button_pressed=true
	check(game.play_recording and home.recording.button_pressed and game.performance_log!=null,"ordinary menu toggle starts real recording API")
	var recorder=game.performance_log
	if recorder!=null:
		check(recorder.recording and recorder.log_file!=null,"real recording session opens its output")
		var session=recorder.session_id
		var start_reports=recorder.reports_written
		game.set_play_recording(true)
		home.recording.button_pressed=true
		check(game.performance_log==recorder and recorder.session_id==session and recorder.reports_written==start_reports,"repeated enable keeps one session and does not truncate or restart")
		check(recording_changes==[true],"enable emits one state change")
		check(not game.debug_open() and not game.debug_profiling_requested,"recording operates while Debug stays closed")
		home.recording.button_pressed=false
		check(not game.play_recording and not home.recording.button_pressed and game.performance_log==null,"ordinary menu toggle stops real recording API")
		check(not recorder.recording and recorder.log_file==null and not game.world.profile_ai,"stop closes output and releases recording instrumentation")
		var stop_reports=recorder.reports_written
		game.set_play_recording(false)
		home.recording.button_pressed=false
		check(recorder.reports_written==stop_reports and recording_changes==[true,false],"repeated disable is idempotent and emits no duplicate boundary")
		var recorded=FileAccess.get_file_as_string(recorder.log_path)
		check(recorded.count('"session_start"')==1 and recorded.count('"session_stop"')==1,"file has exactly one real session start and stop")
		check(not game.debug_open() and game.performance_log==null,"ordinary recording round trip never opens Debug")
	else:
		# An unavailable output is a failed integration check, not a false pass.
		home.recording.button_pressed=false;game.set_play_recording(false)
	check(game.world.time==initial_time and game.world.shots==initial_shots,"recording UI round trip does not simulate gameplay")
	# Keep the project's default 1440x900 canvas scaling path as well as narrow logical UI.
	for physical in [Vector2i(1280,720),Vector2i(800,600),Vector2i(480,640)]:
		root.size=physical;root.content_scale_size=Vector2i(1440,900)
		await settle()
		var logical_bounds=root.get_visible_rect()
		for menu_page in ["home","campaign","lan"]:
			home.page=menu_page;home.refresh();await settle();home.layout();await settle()
			check(logical_bounds.encloses(home.shell.get_global_rect()),"default canvas logical bounds %s %s"%[physical,menu_page])
			var screen_rect=root.get_final_transform()*home.shell.get_global_rect()
			check(Rect2(Vector2.ZERO,Vector2(physical)).grow(1).encloses(screen_rect),"default canvas physically maps without clipping %s %s"%[physical,menu_page])
	for extent in [Vector2i(1440,900),Vector2i(1280,720),Vector2i(800,600),Vector2i(480,640)]:
		root.size=extent;root.content_scale_size=extent
		await settle()
		for page in ["home","campaign","lan"]:
			home.page=page;home.refresh()
			await settle();home.layout();await settle()
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(home.shell.get_global_rect()),"shell fits %s %s"%[extent,page])
			var view=home.main_view if page=="home" else home.campaign_view if page=="campaign" else home.lan_view
			var controls: Array=[]
			for child in view.get_children():
				if child is Control and child.visible:
					check(child.position.x>=0 and child.position.x+child.size.x<=home.page_canvas.size.x+1,"horizontal bounds %s %s %s"%[extent,page,child.name])
					check(child.position.y+child.size.y<=home.page_canvas.custom_minimum_size.y+1,"reachable via scroll %s %s %s"%[extent,page,child.name])
					controls.append(child)
			for first in range(controls.size()):
				for second in range(first+1,controls.size()):
					check(not controls[first].get_rect().intersects(controls[second].get_rect()),"no overlap %s %s %s / %s"%[extent,page,controls[first].name,controls[second].name])
			if page=="lan":
				var refresh=home.lan_view.get_node("RefreshRooms")
				check(home.room_list.position.y>=refresh.position.y+refresh.size.y+9,"LAN refresh measured height plus gap %s"%extent)
			if page=="campaign":
				home.chapter_start.text="进入第 10 关 · 很长的行动标题与额外任务说明用于窄窗布局验证"
				await settle();home.layout();await settle()
				check(home.chapter_start.size.x<=home.page_canvas.size.x-40,"long chapter title never expands page")
		loading.begin("正在准备包含很长名称的战场与增援区域")
		loading.update_stage("正在整理真实资源与场景引用",3,10)
		await settle()
		check(loading.panel.theme==shared,"loading shares cached theme")
		for control in [loading.title,loading.detail,loading.progress,loading.cancel_button,loading.home_button]:
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(control.get_global_rect()),"real loading control fits %s %s"%[extent,control.name])
		loading.fail("失败原因用于验证窄窗长文字仍可阅读并返回首页或重试")
		await settle()
		check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(loading.retry_button.get_global_rect()),"loading retry reachable %s"%extent)
		loading.hide()
		game.debug_ui.layout();game.campaign_ui.layout_result()
		await settle()
		check(game.armory.size.x<=extent.x,"real loadout panel fits width %s"%extent)
		game.loot_panel.layout_panel()
		await settle()
		check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(game.loot_panel.panel.get_global_rect()),"real loot panel fits viewport %s"%extent)
		check(game.debug_ui.panel.size.x<=extent.x,"real debug panel fits width %s"%extent)
		check(game.campaign_ui.result_panel.size.x<=extent.x,"real result panel fits width %s"%extent)
	check(Tactical.build_count==1 and game.ui.theme==shared,"resize and page switches do not rebuild theme")
	check(game.world.time==initial_time and game.world.shots==initial_shots,"no gameplay simulation")
	print("TACTICAL_UI_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"theme_builds":Tactical.build_count,"simulation_time":game.world.time,"shots":game.world.shots}))
	if loading.get_parent()==root:loading.queue_free()
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
