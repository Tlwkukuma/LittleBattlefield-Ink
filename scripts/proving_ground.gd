extends Node3D
const BUILD_VERSION="2026.10.10.4"
const MOUNTED_VIEW_SIZES={"armedJeep":30.0,"scoutCar":34.0,"apc":32.0,"ifv":36.0,"lightTank":36.0,"tank":40.0,"heavyTank":42.0,"hmg":32.0,"fieldGun":38.0}
@export var start_in_style_range=false
const StyleRange=preload("res://scripts/style_range.gd")
var graphic_style=true
var style_button: Button
var theme_uses_graphic=false
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Art=preload("res://scripts/ink_art.gd")
const Props=preload("res://scripts/proving_art.gd")
const Batch=preload("res://scripts/mesh_batch.gd")
const Motion=preload("res://scripts/soldier_motion.gd")
const RenderMotion=preload("res://scripts/render_motion.gd")
const VehicleRenderMotion=preload("res://scripts/vehicle_render_motion.gd")
const EmplacementMotion=preload("res://scripts/emplacement_motion.gd")
const VehicleRig=preload("res://scripts/vehicle_weapon_rig.gd")
const VehicleDynamics=preload("res://scripts/vehicle_dynamics.gd")
const VehicleOffroad=preload("res://scripts/vehicle_offroad.gd")
const VehicleLivery=preload("res://scripts/vehicle_livery.gd")
const FX=preload("res://scripts/proving_fx.gd")
const WeaponEffects=preload("res://scripts/weapon_effects.gd")
const BulletFlight=preload("res://scripts/bullet_flight_visual.gd")
const WeaponProfile=preload("res://scripts/weapon_profile.gd")
const Handling=preload("res://scripts/weapon_handling.gd")
const FireControl=preload("res://scripts/weapon_fire_control.gd")
const QuickEquipment=preload("res://scripts/quick_equipment.gd")
const ThrowControl=preload("res://scripts/grenade_throw_control.gd")
const Reticle=preload("res://scripts/weapon_reticle.gd")
const Scope=preload("res://scripts/scope_view.gd")
const Editor=preload("res://scripts/range_editor.gd")
const TerrainGround=preload("res://scripts/terrain_ground.gd")
const TerrainShowcase=preload("res://scripts/terrain_showcase.gd")
const Classes=preload("res://scripts/soldier_classes.gd")
const ClassShowcase=preload("res://scripts/class_showcase.gd")
const Interaction=preload("res://scripts/range_interaction.gd")
# Load the campaign layout on entry; the joint range can start independently.
const ORCHARD_LEVEL_PATH="res://scripts/orchard_level.gd"
const CampaignPresentation=preload("res://scripts/campaign_presentation.gd")
const LanSession=preload("res://scripts/lan_session.gd")
const HomeScreen=preload("res://scripts/home_screen.gd")
const CampaignCatalog=preload("res://scripts/campaign_catalog.gd")
var campaign_progress=preload("res://scripts/campaign_progress.gd").new()
var campaign_result_recorded=false
var campaign_save_attempt_at=-2000
var campaign_ui
var lan
var home_ui
var home_ui_dirty=false
var training_switches: Dictionary={}
var player_class="assault"
var class_list: OptionButton
var biome_list: OptionButton
var class_detail: Label
var vehicle_detail: Label
var class_showcase
var interactions: Array=[]
var interaction_hint: Label
var interaction_age=0.0
var catalog=Catalog.new()
var world
var plan: Dictionary
var compiled: Dictionary
var stage: Node3D
var fx
var camera: Camera3D
var scene_environment: Environment
var camera_follow_position=Vector3.ZERO
var camera_follow_size=20.0
var actors: Array=[]
var crowd_batches
var player_occlusion
var rigid_batches
var weapon_batches
var wall_batches
var vehicle_part_batches
var flash_batches
var hud_batches
var damage_number_batch
var object_views: Dictionary={}
var vehicle_views: Array=[]
var projectile_views: Dictionary={}
var bullet_flight_batch
var feedback_camera_offset=Vector3.ZERO
var feedback_camera_scale=.5
var roof_views: Array=[]
var ui: Control
var armory: PanelContainer
var weapon_list: ItemList
var weapon_search: LineEdit
var weapon_filter: OptionButton
var weapon_assignment: OptionButton
var weapon_detail: Label
var vehicle_list: OptionButton
var hud: Label
var subtitle: Label
var play_notice: Label
var notice: Label
var notice_age=0.0
var editor
var editing=false
var top_down=false
var editor_focus=Vector2.ZERO
var zoom=20.0
var combat_view_before_editor=20.0
var aim=Vector2.ZERO
var trigger_pressed=false
var jump_pressed=false
var roof_mode=0
var crosshair
var grenade_preview
var scope_view
var combat_hud
var network_status_hud
var equipment_wheel
var loot_panel
var loot_visual
var weapon_input_latched=false
var selection_ring: Node3D
var qa_mode=false
var paused=false
var close_view=false
var atlas: Texture2D
var wall_fps_counter=preload("res://scripts/wall_fps_counter.gd").new()
var frames_per_second=0
var capture_path=""
var pending_rebuild: Dictionary={}
var damage_labels: Array=[]
var performance_log
var performance_overlay
var debug_ui
var static_prop_batches
var launch_stamp=""
var launch_time=""
var startup_chapter=0
var pose_cursor=0
var loading_ui
var loading_active=false
var loading_snapshot: Dictionary={}
var loading_generation=0
var loading_chapter=0
var loading_tactic="T01"
var loading_return_home=false
var world_ready=false
signal play_recording_changed(enabled: bool)
var play_recording=false
var debug_profiling_requested=false
const LOADING_FIELDS=["world","stage","plan","compiled","actors","object_views","vehicle_views","projectile_views","roof_views","pending_rebuild","damage_labels","fx","loot_visual","damage_number_batch","bullet_flight_batch","static_prop_batches","wall_batches","crowd_batches","rigid_batches","weapon_batches","vehicle_part_batches","flash_batches","player_occlusion","grenade_preview","crosshair","selection_ring","interactions","class_showcase","player_class","campaign_result_recorded","campaign_save_attempt_at","paused","editing","close_view","roof_mode","zoom","aim","weapon_input_latched"]


func _ready():
	# Official release templates disable command-line scene path overrides.
	# Route the user flag through the application to the dedicated sample scene.
	if "--range2" in OS.get_cmdline_user_args() and not start_in_style_range:
		process_mode=Node.PROCESS_MODE_DISABLED
		get_tree().change_scene_to_file.call_deferred("res://proving_ground_2.tscn")
		return
	if DisplayServer.get_name()=="headless" and "--runtime-cost-contract" in OS.get_cmdline_user_args():
		process_mode=Node.PROCESS_MODE_DISABLED
		var result=load("res://qa/runtime_cost_workload.gd").new().run()
		print("RUNTIME_COST "+JSON.stringify(result));get_tree().quit();return
	if "--movement-probe" in OS.get_cmdline_user_args():
		process_mode=Node.PROCESS_MODE_DISABLED
		print("MOVEMENT_COST "+JSON.stringify(load("res://qa/movement_probe.gd").new().run()))
		get_tree().quit();return
	launch_stamp=Time.get_datetime_string_from_system(false,true)
	launch_time=launch_stamp.get_slice(" ",1)
	set_game_title("小小战地 · 联合演武场")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture_path=arg.trim_prefix("--capture=");qa_mode=true
		if arg=="--qa":qa_mode=true
		if arg.begins_with("--campaign-chapter="):startup_chapter=clampi(int(arg.trim_prefix("--campaign-chapter=")),1,10)
		# Debug profiling and explicit user-play recording are separate opt-ins.
	var environment=WorldEnvironment.new();var setting=Environment.new();setting.background_mode=Environment.BG_COLOR;setting.background_color=Color("c0bbcc");setting.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;setting.ambient_light_color=Color.WHITE;setting.ambient_light_energy=.8;environment.environment=setting;scene_environment=setting;add_child(environment)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=zoom;camera.near=.05;camera.far=300;add_child(camera);camera.current=true
	ui=Control.new();ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var layer=CanvasLayer.new();add_child(layer);layer.add_child(ui);build_theme()
	_ensure_loading_ui();loading_active=true;loading_generation+=1
	loading_ui.begin("正在准备场景")
	# No complete world/menu exists yet. Never disguise a reload as "home".
	loading_ui.home_button.hide();loading_ui.retry_button.text="重新加载场景"
	var startup_generation=loading_generation
	get_tree().create_timer(121.0).timeout.connect(func():
		if loading_active and startup_generation==loading_generation:
			loading_generation+=1;loading_active=false;world_ready=false
			loading_ui.fail("初始化超时，请重试"))
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	if startup_generation!=loading_generation:return
	if not _loading_valid(startup_generation):
		loading_active=false;world_ready=false
		loading_ui.fail(loading_ui.failure if not loading_ui.failure.is_empty() else "初始化已取消，请重试")
		return
	loading_ui.drawn=DisplayServer.get_name()!="headless"
	atlas=load("res://assets/original/weapon_atlas.png")
	plan=CampaignCatalog.plan(catalog,startup_chapter) if startup_chapter>0 else StyleRange.plan(catalog) if start_in_style_range or "--range2" in OS.get_cmdline_user_args() else load(ORCHARD_LEVEL_PATH).plan(catalog) if "--level01" in OS.get_cmdline_user_args() else TerrainShowcase.plan(catalog) if "--terrain" in OS.get_cmdline_user_args() else catalog.range_plan()
	if startup_chapter>0:plan.godot3d.campaign_checkpoint=campaign_progress.can_play(startup_chapter)
	var startup_ok=await rebuild(plan,true)
	if startup_generation!=loading_generation:return
	loading_active=false
	if not startup_ok:
		world_ready=false
		loading_ui.fail(loading_ui.failure if not loading_ui.failure.is_empty() else "初始化已取消，请重试")
		return
	stage.process_mode=Node.PROCESS_MODE_INHERIT;loading_ui.finish()
	build_ui()
	lan=LanSession.new();lan.name="LanSession";add_child(lan);lan.setup(self)
	home_ui=HomeScreen.new();ui.add_child(home_ui);home_ui.setup(self)
	scope_view=Scope.new();scope_view.game=self;ui.add_child(scope_view)
	combat_hud=preload("res://scripts/combat_hud.gd").new();combat_hud.game=self;ui.add_child(combat_hud)
	network_status_hud=preload("res://scripts/network_status_hud.gd").new();network_status_hud.game=self;ui.add_child(network_status_hud)
	equipment_wheel=preload("res://scripts/equipment_wheel.gd").new();equipment_wheel.game=self;ui.add_child(equipment_wheel)
	loot_panel=preload("res://scripts/loot_panel.gd").new();loot_panel.game=self;ui.add_child(loot_panel)
	editor=Editor.new(self);editor.build(ui);debug_ui.attach_editor()
	performance_overlay=preload("res://scripts/performance_overlay.gd").new();performance_overlay.game=self;debug_ui.attach_performance(performance_overlay)
	hud_batches=preload("res://scripts/hud_batches.gd").new();hud_batches.game=self;ui.add_child(hud_batches)
	aim=world.player.position+Vector2(0,-12);editor_focus=world.player.position
	world.event.connect(on_world_event)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapon=") and not world.campaign_active():
			world.equip(arg.trim_prefix("--weapon="));update_weapon_details()
	if is_style_range():
		set_game_title("小小战地 · 演武场2：荒原墨线");zoom=20
		message("演武场2 · F2 原地对比画风，F1 动作近景；Tab 换枪 / 试驾，F5 复原破坏")
	elif startup_chapter>0:
		set_game_title("小小战地 · "+str(plan.title));zoom=25
		message(str(plan.title)+" · 查看任务与战术，按 Tab 开始")
	elif "--level01" in OS.get_cmdline_user_args():
		set_game_title("小小战地 · 第一关：石墙果园");zoom=preload("res://scripts/orchard_layout.gd").CAMERA_SIZE
		message("第一关 · 占领 B 点 / 耗尽敌军；1–4 随身装备，F 就近操作载具，Tab 战况与装备，Esc 暂停")
	elif "--editor" in OS.get_cmdline_user_args():message("点击右上角 Debug → 测试工具 → 场景工坊")
	elif "--armory" in OS.get_cmdline_user_args():toggle_armory()
	elif "--vehicles" in OS.get_cmdline_user_args():visit_vehicle_area()
	elif "--housing-occlusion" in OS.get_cmdline_user_args():visit_house(true)
	elif "--housing" in OS.get_cmdline_user_args():visit_house()
	elif "--ladder" in OS.get_cmdline_user_args():visit_ladder()
	elif "--nature" in OS.get_cmdline_user_args():visit_nature()
	elif "--biomes" in OS.get_cmdline_user_args():visit_biomes(1)
	elif "--terrain" in OS.get_cmdline_user_args():
		set_game_title("小小战地 · 林地前哨（地形验收）")
		zoom=22;message("林地前哨 · 前方四种材质可破坏；Tab 换 RPG，F5 复原，F8 编辑，北侧房屋可进入")
	elif "--traversal" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-8,7.5);aim=world.player.position+Vector2.UP*5;close_view=true;zoom=9
		message("翻越训练 · 朝墙按 W + 空格；Shift 快跑，空旷处空格跳跃。F1 切换视野")
	elif "--climb" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-8,21.6);aim=world.player.position+Vector2.UP*5;close_view=true;zoom=7.0
		message("1.85 m 高墙 · W + 空格攀爬；越过后继续向上是中墙、低墙。Shift 助跑，F1 切换视野")
	elif "--weapons" in OS.get_cmdline_user_args():
		close_view=true;zoom=7.0
		message("枪械细节 · Tab 换枪：S1897 / S686 / DBS / O12；R 装填观察弹壳、弹匣落地，F1 切换视野")
	elif "--scope" in OS.get_cmdline_user_args():
		close_view=false;zoom=20.0
		set_game_title("小小战地 · 右键扩大视野")
		message("固定常规视野 · 右键看见更大范围，狙击先扩展再出现圆镜；松开恢复，Tab 换步枪对比")
	elif "--equipment-wheel" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-3.6);aim=world.player.position+Vector2.UP*5;close_view=false;zoom=20.0
		set_game_title("小小战地 · 联合演武场 / 快捷装备轮盘")
		notice_age=0;notice.hide()
	elif "--combat-hud" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-3.6);aim=world.player.position+Vector2.UP*5;close_view=false;zoom=20.0
		set_game_title("小小战地 · 换弹与聚焦提示")
		notice_age=0;notice.hide()
	elif "--hit-feedback" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-3.6);aim=world.player.position+Vector2.UP*5;close_view=false;zoom=13.0
		message("受击反馈 · 前方靶兵可对比身体 / 头 / 脚部飞溅；Tab 换霰弹或狙击，F1 近景，F5 重置")
	elif "--reticle" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-3.6);aim=world.player.position+Vector2.UP*5;close_view=false;zoom=13.0
		set_game_title("小小战地 · 准心跟随鼠标")
		message("所有准心跟随鼠标 · 霰弹细方框；右键举枪，狙击准心与圆镜同心；Tab 换枪")
	elif "--ammo" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-3.6);aim=world.player.position+Vector2.UP*5;close_view=false;zoom=13.0
		set_game_title("小小战地 · 短光迹与分口径弹壳")
		message("短亮弹芯 / 分口径弹壳 · Tab 切 M416 / S1897 / O12 / AWM；R 看落壳落匣，F1 近景，F5 重置")
	elif "--fire-modes" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-3.6);aim=world.player.position+Vector2.UP*5;close_view=false;zoom=13.0
		set_game_title("小小战地 · 射击模式 / 空仓装填")
		message("B 切单发 / 连发 / 全自动 · 打空自动装填；Tab 可换 M16A4、Mk47、O12、MG3，R 手动装填")
	elif "--special-weapons" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-1,-6.9);aim=world.player.position+Vector2.UP*3;close_view=true;zoom=7.5
		set_game_title("小小战地 · 近战与炮筒动作")
		message("左键近战攻击 · Tab 切军刀 / 消防斧 / 武士刀、RPG / 榴弹发射器 / 迫击炮；R 装填，F1 远近")
	elif "--grenades" in OS.get_cmdline_user_args():
		world.player.position=Vector2(-8,7.5);aim=world.player.position+Vector2.UP*7;close_view=false;zoom=20
		set_game_title("小小战地 · 联合演武场 / 手雷投掷")
		message("手雷 · 按住左键预瞄，松开投出；右键上抛 / 低抛，Esc 取消")
	elif "--classes" in OS.get_cmdline_user_args():equip_class("medic");visit_classes()
	elif "--character" in OS.get_cmdline_user_args():
		world.player.position=Vector2(0,12);world.player.facing=Vector2(.75,.66).normalized();aim=world.player.position+world.player.facing*3;close_view=true;zoom=3.6
		message("线稿小兵 · 原骨骼与走跑动作 / WASD 移动 / Shift 快跑 / H 掉帽 / F5 恢复 / F1 返回演武场")
	else:message("Tab 换枪 · 右键扩大视野，松开恢复 · 狙击圆镜跟随鼠标 · 可直接瞄准脚部和墙根")
	if ("--briefing" in OS.get_cmdline_user_args() or startup_chapter>0) and world.campaign_active():
		armory.show();campaign_ui.refresh();message(str(plan.title)+"已准备 · 查看战况与装备，按 Tab 或“继续战斗”开始")
	update_camera(0)
	if "--character" in OS.get_cmdline_user_args():Input.warp_mouse(camera.unproject_position(Vector3(aim.x,World.muzzle_height(world.player),aim.y)))
	if not capture_path.is_empty():capture.call_deferred()
	if "--startup-watch" in OS.get_cmdline_user_args():
		if world.campaign_active():print("CAMPAIGN_BRIEFING_READY chapter=",int(plan.godot3d.get("campaign_chapter",1))," scene=",plan.id," armory_visible=",armory.visible," simulation_time=",world.time)
		print("BUILD_VERSION_READY version=",BUILD_VERSION," title=",get_window().title," subtitle=",subtitle.text)
		print("BATTLE_HUD_READY debug_open=",debug_open()," monitor_processing=",performance_overlay.is_processing()," detailed_profiling=",world.profile_ai," debug_batched=false")
		get_tree().create_timer(3.0).timeout.connect(func():
			print("RANGE_READY scene=",plan.id," fps=",Engine.get_frames_per_second()," simulation_time=",world.time," window=",DisplayServer.window_get_size())
			if player_occlusion!=null:print("PLAYER_OCCLUSION_READY ",JSON.stringify(player_occlusion.stats())))
	var lan_join_address=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lan-join="):lan_join_address=arg.trim_prefix("--lan-join=").strip_edges()
	if not lan_join_address.is_empty():
		show_home()
		home_ui.open_lan()
		home_ui.address.text=lan_join_address
		# Join after the home screen has finished entering the tree. If the
		# connection fails, the address and LAN status remain visible for retry.
		home_ui.join_campaign.call_deferred()
	elif "--lan-browser" in OS.get_cmdline_user_args():
		show_home()
		home_ui.open_lan()
	elif OS.get_cmdline_user_args().is_empty():show_home()

func set_game_title(scene_title: String):
	get_window().title="v%s · %s%s · 启动 %s · PID %s"%[BUILD_VERSION,scene_title," · Release" if not OS.is_debug_build() else "",launch_stamp,OS.get_process_id()]

func show_home():
	if home_ui==null:return
	if home_ui_dirty or home_ui.page!="home" or not home_ui.overlay.visible:replace_home_page("home")
	home_ui.show_menu("home")

func show_lan():
	if home_ui==null:return
	if home_ui_dirty or home_ui.page!="lan" or not home_ui.overlay.visible:replace_home_page("lan")
	home_ui.show_menu("lan")
	lan.discovery.start_scan()

func replace_home_page(target_page: String):
	# Level rebuilds and hidden-page transitions leave Button/Label canvas items
	# undrawn. Build the active page while it is visible to the renderer.
	var previous=home_ui
	previous.hide()
	previous.queue_free()
	home_ui=HomeScreen.new();home_ui.page=target_page;ui.add_child(home_ui);home_ui.setup(self,true)
	home_ui_dirty=false

func home_open() -> bool:
	return home_ui!=null and home_ui.overlay!=null and home_ui.overlay.visible

func begin_network_campaign(unit_id: int,state: Dictionary):
	paused=false;editing=false;close_view=false;roof_mode=0;zoom=preload("res://scripts/orchard_layout.gd").CAMERA_SIZE
	armory.hide()
	if not world.campaign_active() or str(plan.get("id",""))!="orchard-level-01" or bool(plan.get("godot3d",{}).get("campaign_offline",false)):rebuild(load(ORCHARD_LEVEL_PATH).plan(catalog))
	lan.assigned_unit=unit_id;lan.apply_snapshot(state)
	player_class=str(world.player.get("class_id","assault"))
	aim=world.player.position+world.player.facing*12
	update_camera(0);set_game_title("小小战地 · 第一关：石墙果园 / 局域网协作")
	if campaign_ui!=null:campaign_ui.refresh()
	if home_ui!=null:home_ui.hide_menu()
	message("已进入房主正在进行的第一关 · 接管蓝军队友")

func add_network_vehicle_view(vehicle: Dictionary):
	var view=Props.vehicle(stage,vehicle);vehicle_views.append(view)
	if flash_batches!=null:flash_batches.register_tree(view.root)
	if rigid_batches!=null:rigid_batches.register_tree(view.root)

func build_theme():
	preload("res://scripts/tactical_ui.gd").apply(ui)
	if hud_batches!=null:hud_batches.previous_shapes="";hud_batches.previous="";hud_batches.dirty=true

func make_panel(parent: Control,at: Vector2,size: Vector2,right: bool=false) -> PanelContainer:
	var panel=PanelContainer.new();parent.add_child(panel)
	if right:panel.anchor_left=1;panel.anchor_right=1
	panel.offset_left=at.x;panel.offset_top=at.y;panel.offset_right=at.x+size.x;panel.offset_bottom=at.y+size.y;panel.mouse_filter=Control.MOUSE_FILTER_STOP
	return panel
func label(parent: Node,text: String,font_size: int=15) -> Label:
	var result=Label.new();result.text=text;result.add_theme_font_size_override("font_size",font_size);parent.add_child(result);return result
func button(parent: Node,text: String,callback: Callable) -> Button:
	var result=Button.new();result.text=text;result.tooltip_text=text;result.clip_text=true;result.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;result.focus_mode=Control.FOCUS_ALL;parent.add_child(result);result.pressed.connect(callback);return result

func build_ui():
	campaign_ui=CampaignPresentation.new()
	debug_ui=preload("res://scripts/debug_drawer.gd").new(self);debug_ui.build()
	var row: Container=HFlowContainer.new();debug_ui.tools_box.add_child(row)
	button(row,"第一关",start_level01);button(row,"联合演武场",start_training);button(row,"演武场2",start_style_range)
	button(row,"动作近景  F1",toggle_close_view)
	campaign_ui.armory_button=button(row,"武器 / 载具  Tab",func():debug_ui.set_open(false);toggle_armory())
	campaign_ui.editor_button=button(row,"场景工坊  F8",debug_ui.open_editor)
	campaign_ui.roof_button=button(row,"房顶  F3",cycle_roof);button(row,"重开  F5",reset_range)
	style_button=button(row,"画风对比  F2",toggle_graphic_style);style_button.visible=is_style_range()
	play_notice=label(ui,"",16);play_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;play_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	play_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);play_notice.offset_left=-220;play_notice.offset_right=220;play_notice.offset_top=80;play_notice.offset_bottom=110;play_notice.hide()
	interaction_hint=label(ui,"",18);interaction_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;interaction_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	# Text remains the single interaction source; CombatActionHUD draws its shared style.
	interaction_hint.hide()
	interaction_hint.anchor_left=.5;interaction_hint.anchor_right=.5;interaction_hint.anchor_top=1;interaction_hint.anchor_bottom=1
	interaction_hint.offset_left=-320;interaction_hint.offset_right=320;interaction_hint.offset_top=-123;interaction_hint.offset_bottom=-92
	armory=make_panel(ui,Vector2(-326,58),Vector2(310,710),true)
	armory.anchor_bottom=1;armory.offset_bottom=-24
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;armory.add_child(scroll)
	var contents=VBoxContainer.new();scroll.add_child(contents);contents.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var box=VBoxContainer.new();contents.add_child(box);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",7)
	label(box,"武器库 / ARMORY",20);label(box,"84 项原版装备 · 真实弹药与装填",12)
	label(box,"职业形象",18);class_list=OptionButton.new();class_list.focus_mode=Control.FOCUS_NONE;box.add_child(class_list)
	for id in Classes.IDS:class_list.add_item(Classes.profile(id).name)
	class_list.item_selected.connect(func(i):equip_class(Classes.IDS[i]))
	class_detail=label(box,"",12);class_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;class_detail.custom_minimum_size.x=265
	row=HBoxContainer.new();debug_ui.tools_box.add_child(row);button(row,"前往职业展区",visit_classes);button(row,"样兵转身 90°",func():if is_instance_valid(class_showcase):class_showcase.rotate_figures())
	refresh_class_detail()
	button(debug_ui.tools_box,"前往两层住宅",visit_house)
	row=HBoxContainer.new();debug_ui.tools_box.add_child(row);button(row,"树木预制体区",func():visit_nature(false));button(row,"岩石预制体区",func():visit_nature(true))
	label(debug_ui.tools_box,"北侧地形区",18);biome_list=OptionButton.new();biome_list.focus_mode=Control.FOCUS_NONE;debug_ui.tools_box.add_child(biome_list)
	for title_text in ["红土 / 壕沟 / 梯子","雪地阵地","沙漠地块","山体缓坡"]:biome_list.add_item(title_text)
	button(debug_ui.tools_box,"前往所选地形",func():visit_biomes(biome_list.selected))
	weapon_search=LineEdit.new();weapon_search.placeholder_text="搜索武器名称";box.add_child(weapon_search);weapon_search.text_changed.connect(func(_t):refresh_weapons())
	weapon_filter=OptionButton.new()
	for category in ["全部武器","步枪 / 冲锋枪 / 手枪","狙击 / 精确射手","霰弹枪","机枪","爆炸物 / 特种装备","近战"]:weapon_filter.add_item(category)
	box.add_child(weapon_filter);weapon_filter.item_selected.connect(func(_i):refresh_weapons())
	weapon_assignment=OptionButton.new();weapon_assignment.focus_mode=Control.FOCUS_NONE
	for slot in range(3):weapon_assignment.add_item("装备到武器位 %d"%(slot+1))
	box.add_child(weapon_assignment)
	weapon_assignment.tooltip_text="三个武器位自由配装；投掷物和发射器进入战术区。"
	button(box,"卸下所选武器位",func():world.clear_quick_slot(weapon_assignment.selected);update_weapon_details();get_viewport().gui_release_focus())
	weapon_list=ItemList.new();weapon_list.custom_minimum_size=Vector2(270,220);weapon_list.fixed_icon_size=Vector2i(72,36);box.add_child(weapon_list);weapon_list.item_selected.connect(equip_index)
	weapon_detail=label(box,"",13);weapon_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;weapon_detail.custom_minimum_size.y=70
	button(box,"切换射击模式  B",cycle_fire_mode)
	button(debug_ui.tools_box,"补满弹药 / 修复",func():if not world.campaign_active():world.refill();message("已补给弹药并修复载具"))
	button(box,"返回射击",func():armory.hide();get_viewport().gui_release_focus())
	var medical_row=HBoxContainer.new();box.add_child(medical_row)
	for medical_id in QuickEquipment.MEDICAL_IDS:
		button(medical_row,str(QuickEquipment.MEDICINE[medical_id].name)+"  5",func():
			armory.hide();world.player.medical_selected=medical_id;use_quick_medicine();get_viewport().gui_release_focus())
	button(debug_ui.tools_box,"医疗演练",func():debug_ui.set_open(false);prepare_medical_training())
	label(box,"车辆 / 固定武器",18);vehicle_list=OptionButton.new();box.add_child(vehicle_list);refresh_vehicles()
	vehicle_detail=label(box,"",13);vehicle_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	vehicle_list.item_selected.connect(func(_i):refresh_vehicle_detail());refresh_vehicle_detail()
	row=HBoxContainer.new();box.add_child(row);button(row,"立即试驾 / 操作",trial_vehicle);button(row,"下车  F",func():world.leave_vehicle())
	row=HBoxContainer.new();box.add_child(row);label(row,"重击镜头",14)
	var camera_strength=OptionButton.new();camera_strength.focus_mode=Control.FOCUS_NONE
	for text in ["关闭","轻微","标准"]:camera_strength.add_item(text)
	camera_strength.select(0 if feedback_camera_scale<=0 else 1 if feedback_camera_scale<1 else 2);row.add_child(camera_strength)
	camera_strength.item_selected.connect(func(index):feedback_camera_scale=[0.0,.5,1.0][index])
	button(debug_ui.tools_box,"前往车辆涂装区",visit_vehicle_area)
	row=HBoxContainer.new();debug_ui.tools_box.add_child(row)
	var protect=CheckBox.new();protect.text="玩家无敌";protect.button_pressed=world.invulnerable;row.add_child(protect);protect.toggled.connect(func(value):if not world.campaign_active():world.invulnerable=value)
	var ai=CheckBox.new();ai.text="靶兵反击";ai.button_pressed=world.ai_enabled;row.add_child(ai);ai.toggled.connect(func(value):if not world.campaign_active():world.ai_enabled=value)
	var targets=CheckBox.new();targets.text="靶兵倒地后自动补充";targets.button_pressed=world.auto_targets;debug_ui.tools_box.add_child(targets);targets.toggled.connect(func(value):if not world.campaign_active():world.auto_targets=value)
	training_switches={"invulnerable":protect,"ai_enabled":ai,"auto_targets":targets}
	refresh_weapons();update_weapon_details();armory.hide()
	campaign_ui.build(self,box,contents)

func debug_open() -> bool:
	return debug_ui!=null and debug_ui.panel.visible

func set_debug_profiling(enabled: bool):
	debug_profiling_requested=enabled
	_sync_performance_logging()

func set_play_recording(enabled: bool):
	if play_recording==enabled:return
	play_recording=enabled
	play_recording_changed.emit(enabled)
	_sync_performance_logging()
	if performance_log!=null:
		if enabled:
			if not performance_log.start_session():
				var reason=performance_log.log_error
				set_play_recording(false)
				if notice!=null:message(reason)
		else:performance_log.stop_session()

func _sync_performance_logging():
	var enabled=debug_profiling_requested or play_recording
	if enabled and performance_log==null:
		performance_log=preload("res://scripts/runtime_performance.gd").new()
		performance_log.measure_viewport(get_viewport().get_viewport_rid())
	elif not enabled and performance_log!=null:
		performance_log.stop_session()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),false)
		performance_log=null
	if world!=null:world.profile_ai=enabled

func refresh_class_detail():
	if class_list==null:return
	class_list.select(maxi(0,Classes.IDS.find(player_class)))
	class_detail.text=str(Classes.profile(player_class).description)+"\n本阶段为外观换装，武器自由选择。"

func equip_class(id: String):
	if world.campaign_active():return
	if not Classes.DATA.has(id):return
	if not world.player.alive:refresh_class_detail();message("补给复活后再换装");return
	if not world.player.vault.is_empty():refresh_class_detail();message("翻越结束后再换装");return
	player_class=id;world.player.class_id=id
	Classes.apply(actors[world.player.id],id,int(world.player.team));refresh_class_detail()
	get_viewport().gui_release_focus();message("已换装："+str(Classes.profile(id).name)+" · "+str(Classes.profile(id).description))

func visit_classes():
	if not is_instance_valid(class_showcase):message("当前布局可在 Tab 面板选择职业形象；职业展台位于联合演武场");return
	if world.player.mounted>=0 and not world.leave_vehicle():return
	if not world.player.alive:message("请先补给复活或 F5 重置后查看职业");return
	set_game_title("小小战地 · 职业展区（E 交互 / F 上下车）")
	preload("res://scripts/soldier_traversal.gd").reset(world.player)
	world.player.position=Vector2(5.4,19.2);world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO
	aim=world.player.position+Vector2.UP*5;close_view=false;zoom=18;armory.hide()
	message("五职业形象 · 靠近前方装备包按 E 换装；Tab 可转动样兵、切换职业，F 上下车，F1 近景")

func visit_house(behind: bool=false):
	if world.houses.is_empty():message("两层住宅位于联合演武场，也可在 F8 工坊中放置住宅预制体");return
	if not world.player.alive:return
	if world.player.mounted>=0 and not world.leave_vehicle():return
	var house: Dictionary=world.houses[0];var points: Array=house.points
	var front=(points[2]+points[3])*.5;var outward=(front-(points[0]+points[1])*.5).normalized()
	preload("res://scripts/soldier_traversal.gd").reset(world.player)
	world.player.position=front+outward*2.5;world.player.elevation=world.terrain.height(world.player.position)
	if behind:
		world.player.position=(points[0]+points[1])*.5-outward*1.2
		world.player.elevation=world.terrain.height(world.player.position)
	world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO
	aim=front-outward*4;close_view=false;zoom=23;armory.hide()
	set_game_title("小小战地 · 两层住宅 · U 形楼梯与宽平台")
	message("两层住宅 · 正门进入后左转，U 形内梯经平台折返上二楼；右侧外梯经休息平台到阳台。楼梯直接步行")
	if behind:
		set_game_title("小小战地 · 两层住宅 / 主角遮挡提示")
		message("住宅后侧 · 遮挡时显示自己的淡蓝剪影与脚下环；绕过墙角、走外梯或从正门进入对比")

func visit_biomes(index: int=0):
	if not plan.get("godot3d",{}).get("biome_training",false):message("北侧地形区位于联合演武场，可从 F8 场景列表返回");return
	if not world.player.alive:return
	var destination: Vector2=[Vector2(15,-18),Vector2(-33,-17),Vector2(-9,-17),Vector2(39,-14)][clampi(index,0,3)]
	var vehicle: Dictionary=world.vehicles[world.player.mounted] if world.player.mounted>=0 else {}
	if not vehicle.is_empty() and vehicle.emplacement:
		if not world.leave_vehicle():return
		vehicle={}
	if not vehicle.is_empty():
		var placed=false
		for offset in [Vector2.ZERO,Vector2(3,0),Vector2(-3,0),Vector2(0,3),Vector2(0,6)]:
			if VehicleDynamics.place(world,vehicle,destination+offset,-PI*.5):placed=true;break
		if not placed:message("地形区入口被阻挡，请先清理入口或下车前往");return
		destination=vehicle.position
	preload("res://scripts/soldier_traversal.gd").reset(world.player)
	world.player.position=destination;world.player.elevation=vehicle.elevation if not vehicle.is_empty() else world.terrain.height(destination)
	world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO
	aim=world.player.position+Vector2.UP*5;close_view=false;zoom=24;armory.hide()
	if biome_list!=null:biome_list.select(clampi(index,0,3))
	set_game_title("小小战地 · 联合演武场 / "+["红土壕沟","积雪与雪堆","沙丘与低地","山体缓坡"][clampi(index,0,3)])
	message("已带车进入地形区 · W/S 前后，A/D 转向，Shift 加速，空格手刹漂移" if not vehicle.is_empty() else "北侧地形区 · 西侧雪地 / 沙漠，前方红土壕沟，东侧山体；靠近梯子按 E，W 上 / S 下")

func visit_ladder():
	if world.terrain.ladders.is_empty() or not world.player.alive:return
	if world.player.mounted>=0 and not world.leave_vehicle():return
	var ladder: Dictionary=world.terrain.ladders[0]
	var forward=Vector2(ladder.high.x-ladder.low.x,ladder.high.z-ladder.low.z).normalized()
	preload("res://scripts/soldier_traversal.gd").reset(world.player)
	world.player.position=Vector2(ladder.high.x,ladder.high.z)+forward*.7
	world.player.elevation=world.terrain.height(world.player.position)
	world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO
	aim=Vector2(ladder.low.x,ladder.low.z);close_view=false;zoom=20;armory.hide()
	set_game_title("小小战地 · 联合演武场 / 壕沟梯子")
	message("梯子上端 · E 下梯，S 向下；到沟底后 E 上梯，W 向上；E / 空格松手")

func visit_nature(rocks: bool=false):
	if not plan.get("godot3d",{}).get("nature_training",false):message("树石预制体区位于默认联合演武场，可从 F8 场景列表返回");return
	if not world.player.alive:return
	var vehicle: Dictionary=world.vehicles[world.player.mounted] if world.player.mounted>=0 else {}
	if not vehicle.is_empty() and vehicle.emplacement:vehicle={}
	if vehicle.is_empty():
		if world.player.mounted>=0 and not world.leave_vehicle():return
	else:
		var placed=false
		var entry=Vector2(46,-6) if rocks else Vector2(42.75,24.5)
		var heading=-PI*.5 if rocks else PI*.5
		for offset in [Vector2.ZERO,Vector2(-3,0),Vector2(0,3)]:
			if VehicleDynamics.place(world,vehicle,entry+offset,heading):placed=true;break
		if not placed:message("预制体区入口被阻挡，请清理入口或下车前往");return
	preload("res://scripts/soldier_traversal.gd").reset(world.player)
	world.player.position=vehicle.position if not vehicle.is_empty() else Vector2(42.5,-5) if rocks else Vector2(16,25)
	world.player.elevation=vehicle.elevation if not vehicle.is_empty() else world.terrain.height(world.player.position);world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO
	aim=world.player.position+(Vector2.from_angle(vehicle.angle) if not vehicle.is_empty() else Vector2.UP)*5;zoom=24;close_view=false;armory.hide()
	set_game_title("小小战地 · 联合演武场 / "+("岩石预制体" if rocks else "树木预制体"))
	if not vehicle.is_empty():message(("前方是低矮扁石" if rocks else "前方是倒木主干 · 避开高断枝")+" · 低速接近比较越障；Shift 加速，空格手刹，F 下车")
	else:message("树石预制体 · Tab 切换树木 / 岩石区；F8 可放置单体和组合；树干、岩石可破坏，树冠下与岩拱间隙可通行")

func update_interaction_hint(delta: float):
	if interaction_hint==null:return
	interaction_age-=delta
	if interaction_age>0:return
	interaction_age=.10;interaction_hint.text=""
	if editing or paused or armory.visible or loot_open() or wheel_open() or has_text_focus() or not world.player.alive:return
	if world.player.mounted>=0:
		interaction_hint.text="F  离开迫击炮" if world.vehicles[world.player.mounted].type=="portableMortar" else "F  离开载具 / 固定武器";return
	if not world.loot.nearest(world,world.player).is_empty():interaction_hint.text="Tab  背包";return
	var ladder_hint=preload("res://scripts/terrain_ladder.gd").hint(world)
	if not ladder_hint.is_empty():interaction_hint.text=ladder_hint;return
	var target=Interaction.nearest(world,interactions)
	if not target.is_empty():interaction_hint.text=target.label
	if world.player.grounded and world.player.vault.is_empty() and world.nearest_vehicle()>=0:
		interaction_hint.text+=("    ·    " if not interaction_hint.text.is_empty() else "")+("F  蹲姿操作迫击炮" if world.vehicles[world.nearest_vehicle()].type=="portableMortar" else "F  进入载具 / 操作固定武器")
	elif world.active_weapon().kind=="mortar" and not world.Equipment.busy(world.player):interaction_hint.text="左键  部署迫击炮"

func refresh_weapons():
	weapon_list.clear();var query=weapon_search.text.to_lower();var filter=weapon_filter.selected
	for id in catalog.weapons:
		var w: Dictionary=catalog.weapons[id];var category=str(w.get("archetype","")).to_lower();var name=str(w.name)
		if not query.is_empty() and not name.to_lower().contains(query):continue
		if filter==1 and category not in ["assault","smg","pistol","machinepistol"]:continue
		if filter==2 and category not in ["sniper","battlerifle","antimaterial"]:continue
		if filter==3 and int(w.get("pellets",1))<2 and name!="O12":continue
		if filter==4 and category not in ["lmg","machinegun"] and name!="Minigun":continue
		if filter==5 and w.kind in ["bullet","hitscan","melee"] and name!="Minigun":continue
		if filter==6 and w.kind!="melee":continue
		var icon=preload("res://scripts/weapon_icon.gd").get_texture(w,atlas,catalog.atlas.frames)
		var index=weapon_list.add_item(name+(" *" if w.get("source_disabled",false) else ""),icon);weapon_list.set_item_metadata(index,id)
		if id==world.player.weapon_id:weapon_list.select(index)

func equip_index(index: int):
	if world.campaign_active():return
	if world.player.mounted>=0:world.leave_vehicle()
	world.assign_quick_weapon(weapon_list.get_item_metadata(index),weapon_assignment.selected);update_weapon_details();get_viewport().gui_release_focus()

func update_weapon_details():
	if weapon_detail==null:return
	var w=world.active_weapon();var pellets=int(w.get("pellets",1))
	if w.kind=="melee":
		weapon_detail.text="%s\n伤害 %s · 攻击间隔 %.2f s · 距离 %.2f m\n左键：%s\n挥击阶段命中；每次攻击对同一目标只结算一次"%[w.get("label",w.name),str(w.damage),60.0/float(w.rpm),float(w.range)/40.0,"单手刺击" if w.id=="army-knife" else "双手劈砍" if w.id=="fire-axe" else "双手横斩"]
		return
	weapon_detail.text="%s\n伤害 %s%s  ·  %d RPM\n弹匣 %d  ·  装填 %.2f s  ·  射程 %.1f m"%[w.get("name",w.get("label","武器")),str(w.damage),(" × "+str(pellets)) if pellets>1 else "",int(FireControl.rpm(w,world.active_state())),int(w.mag),float(w.reload),float(w.get("range",0))/40]
	weapon_detail.text+="\n模式："+FireControl.label(world.active_state(),w)+"\n可选："+FireControl.options_label(w)+"\n空仓自动装填 · R 手动装填"
	if w.kind=="grenade":weapon_detail.text+="\n左键按住预瞄、松开投出；鼠标远近控制力度\n右键上抛 / 近距离低抛，Esc 取消；出手后计时 %.1f s"%ThrowControl.fuse(w)
	var handling=Handling.profile(w)
	weapon_detail.text+="\n后坐 %.2f° / 发 · 稳定瞄准误差 %.2f°"%[rad_to_deg(handling.pitch),rad_to_deg(handling.ads)]
	if w.kind in ["bullet","hitscan"]:weapon_detail.text+="\n"+str(WeaponProfile.get_profile(w).ammo_visual.label)
	if handling.scope:weapon_detail.text+="\n按住右键：先扩大视野，再进入圆镜 · 视野范围 %.2f×"%float(handling.scope_zoom)
	elif Scope.hold_view_scale(handling)>1:weapon_detail.text+="\n按住右键：扩大可见范围 · 松开恢复固定视野"
	if w.get("source_disabled",false):weapon_detail.text+="\n* 原版停用装备，演武场开放测试"

func visit_vehicle_area():
	if not plan.get("godot3d",{}).get("range",false):message("车辆涂装区位于联合演武场，可从 F8 场景列表返回");return
	if not world.player.alive:return
	if world.player.mounted>=0 and not world.leave_vehicle():return
	preload("res://scripts/soldier_traversal.gd").reset(world.player)
	world.player.position=Vector2(-32,10);world.player.elevation=world.terrain.height(world.player.position)
	world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO
	aim=world.player.position+Vector2.UP*5;zoom=22;close_view=false;armory.hide()
	set_game_title("小小战地 · 联合演武场 / 载具驾驶与蓝红涂装")
	message("Tab 选车试驾 · W/S 前后，A/D 转向，Shift 加速，空格手刹漂移；可带车前往地形区")

func refresh_vehicles():
	if vehicle_list==null:return
	vehicle_list.clear()
	for v in world.vehicles:
		var title=VehicleLivery.label(int(v.team))+" · "+str(v.profile.get("label",v.type))
		if v.get("deployed",false):continue
		vehicle_list.add_item(title);vehicle_list.set_item_metadata(vehicle_list.item_count-1,v.id)
		var footprint: Vector2=v.dimensions.half*2
		vehicle_list.set_item_tooltip(vehicle_list.item_count-1,"%s\n车体 %.2f × %.2f m"%[title,footprint.x,footprint.y])
	if world.vehicles.is_empty():vehicle_list.add_item("此场景没有载具")
	refresh_vehicle_detail()

func refresh_vehicle_detail():
	if vehicle_detail==null:return
	if world.vehicles.is_empty() or vehicle_list.selected<0:vehicle_detail.text="";return
	var v: Dictionary=world.vehicles[int(vehicle_list.get_item_metadata(vehicle_list.selected))]
	vehicle_detail.text="固定武器 · 操作员就位后控制" if v.emplacement else VehicleOffroad.description(v)+"\n通过能力还取决于接近方向、轮履接触和底盘余量；岩面上自动降低速度。"
	if not v.emplacement:
		vehicle_detail.text="装甲上限 %d  ·  %s上限 %d\n"%[v.max_health,preload("res://scripts/vehicle_durability.gd").gear_name(v),v.max_track]+vehicle_detail.text

func trial_vehicle():
	if world.campaign_active():message("靠近车辆 / 固定武器后按 F 操作");return
	if world.vehicles.is_empty():return
	var index=int(vehicle_list.get_item_metadata(vehicle_list.selected))
	if world.enter_vehicle(index):
		armory.hide();update_weapon_details()
		var v: Dictionary=world.vehicles[index]
		message(("已就位 " if v.emplacement else "已进入 ")+VehicleLivery.label(int(v.team))+" · "+str(v.profile.get("label","载具"))+(" · 鼠标转向，左键开火，R 装填，F 离开" if v.emplacement else " · W/S 前后，A/D 转向，Shift 加速，空格手刹漂移，F 离开"))
	else:message("装备已损毁或操作位置被挡住；请修复或清理周围空间")

func rebuild(source: Dictionary,sliced: bool=false):
	if performance_log!=null:performance_log.boundary("rebuild")
	world_ready=false
	if world==null:world=World.new()
	var generation=loading_generation
	if home_ui!=null:home_ui_dirty=true
	var was_style_range=is_style_range()
	if loot_panel!=null:loot_panel.close()
	if equipment_wheel!=null:equipment_wheel.close(false)
	if scope_view!=null:scope_view.cancel()
	jump_pressed=false;trigger_pressed=false
	plan=source.duplicate(true)
	preload("res://scripts/campaign_background.gd").apply(scene_environment,plan)
	campaign_result_recorded=false;campaign_save_attempt_at=-2000
	RenderingServer.global_shader_parameter_set("range2_enabled",is_style_range() and graphic_style)
	if ui!=null:build_theme()
	rigid_batches=null;player_occlusion=null;weapon_batches=null
	flash_batches=null;vehicle_part_batches=null
	if stage!=null and not sliced:remove_child(stage);stage.queue_free()
	stage=Node3D.new();add_child(stage);actors=[];object_views={};vehicle_views=[];projectile_views={};roof_views=[];pending_rebuild={};damage_labels=[]
	if sliced:
		stage.process_mode=Node.PROCESS_MODE_DISABLED
		loading_ui.update_stage("初始化地形与世界（整段作业）",0,0)
		await get_tree().process_frame
		if not _loading_valid(generation):return false
	compiled=world.setup(plan,catalog)
	if sliced and world.campaign.phase=="placement_failed":
		loading_ui.failure=str(world.campaign.reason)
		return false
	if sliced and not _loading_valid(generation):return false
	if is_style_range():
		for object in world.objects:object.range2_family=preload("res://scripts/range2_materials.gd").family(object)
	var batched=world.campaign_active() or is_style_range()
	# NPCs retain their 30 Hz cadence in two alternating groups. Player/projectiles
	# update at 60 Hz so a whole troop tick cannot consume a single rendered frame.
	Engine.physics_ticks_per_second=60
	Engine.physics_jitter_fix=0.0
	Engine.max_physics_steps_per_frame=2 if world.campaign_active() else 8
	if world.campaign_active():player_class=str(world.player.get("class_id","assault"))
	else:world.player.class_id=player_class
	interactions=[];class_showcase=null
	world.muzzle_provider=resolve_muzzle
	world.throw_origin_provider=resolve_throw_origin
	fx=FX.new();fx.catalog=catalog;fx.world=world;fx.camera=camera;stage.add_child(fx);fx.silent=qa_mode
	loot_visual=preload("res://scripts/loot_bag_visual.gd").new();loot_visual.world=world;stage.add_child(loot_visual)
	damage_number_batch=preload("res://scripts/damage_number_batch.gd").new();damage_number_batch.game=self;stage.add_child(damage_number_batch)
	bullet_flight_batch=preload("res://scripts/bullet_flight_batch.gd").new()
	bullet_flight_batch.bounds=AABB(Vector3(-world.bounds.x-8,-64,-world.bounds.y-8),Vector3(world.bounds.x*2+16,256,world.bounds.y*2+16));stage.add_child(bullet_flight_batch)
	if sliced:
		loading_ui.update_stage("构建地形网格（整段作业）",0,0)
		await get_tree().process_frame
		if not _loading_valid(generation):return false
	build_ground()
	var built=0
	for o in world.objects:
		object_views[o.id]=Props.object(stage,o);built+=1
		if sliced:
			loading_ui.update_stage("构建物件",built,world.objects.size())
			if loading_ui.should_yield():
				await get_tree().process_frame
				if not _loading_valid(generation):return false
				loading_ui.slice_started=Time.get_ticks_usec()
	static_prop_batches=preload("res://scripts/static_prop_batches.gd").new();stage.add_child(static_prop_batches)
	if not batched:static_prop_batches.configure(world.objects,object_views)
	wall_batches=null
	if batched:
		wall_batches=preload("res://scripts/wall_batches.gd").new();stage.add_child(wall_batches);wall_batches.configure(world.objects,object_views)
	if "--startup-watch" in OS.get_cmdline_user_args():print("STATIC_PROP_BATCHES "+JSON.stringify(static_prop_batches.stats()))
	built=0
	for v in world.vehicles:
		vehicle_views.append(Props.vehicle(stage,v));built+=1
		if sliced:
			loading_ui.update_stage("构建载具",built,world.vehicles.size())
			if loading_ui.should_yield():
				await get_tree().process_frame
				if not _loading_valid(generation):return false
				loading_ui.slice_started=Time.get_ticks_usec()
	built=0
	for u in world.units:
		var view=Art.soldier(stage,u.team,u.player and not world.campaign_active(),u.player)
		if batched:
			view.render_translation=preload("res://scripts/batch_render_translation.gd").new();view.root.set_meta("batch_render_translation",view.render_translation)
		actors.append(view);replace_weapon(view,world.weapon_for(u))
		view.ground_markers=[]
		for child in view.root.get_children():
			if child is Node3D and child!=view.body:view.ground_markers.append({"node":child,"height":child.position.y})
		built+=1
		if sliced:
			loading_ui.update_stage("构建人员",built,world.units.size())
			if loading_ui.should_yield():
				await get_tree().process_frame
				if not _loading_valid(generation):return false
				loading_ui.slice_started=Time.get_ticks_usec()
	if sliced:
		loading_ui.update_stage("配置批次与效果（整段作业）",0,0)
		await get_tree().process_frame
		if not _loading_valid(generation):return false
	fx.actor_views=actors
	crowd_batches=null
	if batched:
		crowd_batches=preload("res://scripts/crowd_batches.gd").new();stage.add_child(crowd_batches)
		crowd_batches.camera=camera
		crowd_batches.bounds=AABB(Vector3(-world.bounds.x-8,-64,-world.bounds.y-8),Vector3(world.bounds.x*2+16,256,world.bounds.y*2+16))
		crowd_batches.configure(actors,world.units);fx.crowd_batches=crowd_batches
		rigid_batches=preload("res://scripts/rigid_batches.gd").new();stage.add_child(rigid_batches);rigid_batches.bounds=crowd_batches.bounds;fx.rigid_batches=rigid_batches
		vehicle_part_batches=preload("res://scripts/palette_mesh_batches.gd").new();stage.add_child(vehicle_part_batches);vehicle_part_batches.bounds=crowd_batches.bounds
		var vehicle_roots=[]
		for vehicle in vehicle_views:vehicle_roots.append(vehicle.root)
		for actor in actors:vehicle_roots.append(actor.held)
		flash_batches=preload("res://scripts/flash_batches.gd").new();stage.add_child(flash_batches)
		for flash_root in vehicle_roots:flash_batches.register_tree(flash_root)
		flash_batches.refresh()
		weapon_batches=preload("res://scripts/weapon_instance_batches.gd").new();weapon_batches.camera=camera;stage.add_child(weapon_batches);weapon_batches.bounds=crowd_batches.bounds;weapon_batches.prepare(catalog)
		for actor in actors:weapon_batches.register_tree(actor.held)
		weapon_batches.refresh()
		var fixed_roots=[]
		for object in world.objects:
			if object.whole and not object.has("house_role") and object_views[object.id].mesh==null:fixed_roots.append(object_views[object.id].root)
		vehicle_part_batches.configure(vehicle_roots,fixed_roots)
		for actor in actors:rigid_batches.register_tree(actor.held)
		for vehicle in vehicle_views:rigid_batches.register_tree(vehicle.root)
		fx.prewarm(world.units)
	player_occlusion=preload("res://scripts/player_occlusion.gd").new();player_occlusion.configure(actors[world.player.id],stage)
	grenade_preview=preload("res://scripts/grenade_preview.gd").new();grenade_preview.game=self;stage.add_child(grenade_preview)
	if plan.get("godot3d",{}).get("range",false) and not plan.get("godot3d",{}).get("terrain_review",false):
		class_showcase=ClassShowcase.new();class_showcase.game=self;stage.add_child(class_showcase);interactions=class_showcase.interactions
	for roof in compiled.roofs:build_roof(roof)
	crosshair=Reticle.new();crosshair.game=self;stage.add_child(crosshair)
	selection_ring=Node3D.new();stage.add_child(selection_ring);Art.ring(selection_ring,Vector3.ZERO,.6,Art.BLUE.lightened(.3),.045,32);selection_ring.hide()
	if vehicle_list!=null:refresh_vehicles();update_weapon_details()
	refresh_class_detail()
	if campaign_ui!=null:campaign_ui.sync_mode();campaign_ui.rebuild_world()
	if style_button!=null:style_button.visible=is_style_range()
	if was_style_range or is_style_range():set_game_title("小小战地 · "+str(plan.get("title","联合演武场")))
	for key in training_switches:training_switches[key].set_pressed_no_signal(bool(world.get(key)))
	if sliced and not _loading_valid(generation):return false
	world.profile_ai=performance_log!=null
	world_ready=true
	return true

func replace_weapon(view: Dictionary,w: Dictionary):
	for child in view.rifle.get_children():
		if flash_batches!=null:flash_batches.unregister_tree(child)
		view.rifle.remove_child(child);child.queue_free()
	view.held=Props.weapon(view.rifle,w);view.weapon=w.id;view.weapon_profile=w
	view.muzzle_socket=view.held.get_node("MuzzleSocket")
	view.ejection_socket=view.held.get_node("EjectionSocket")
	view.backblast_socket=view.held.get_node("BackblastSocket")
	view.muzzle=WeaponEffects.flash(view.muzzle_socket,w)
	# Flash dimensions are in world metres even for compact weapon meshes.
	view.muzzle_socket.scale=Vector3.ONE/view.held.scale
	if flash_batches!=null:flash_batches.register_tree(view.held)
	if weapon_batches!=null:weapon_batches.register_tree(view.held)
	if rigid_batches!=null:rigid_batches.register_tree(view.held)

func resolve_throw_origin(u: Dictionary,w: Dictionary) -> Vector3:
	var view: Dictionary=actors[u.id];view.root.position=Vector3(u.position.x,u.elevation,u.position.y)
	if view.weapon!=w.id:replace_weapon(view,w)
	Motion.update(view,u,0,world.time,float(w.reload))
	return view.held.global_position

func resolve_muzzle(u: Dictionary,w: Dictionary,mount: int) -> Dictionary:
	var socket: Node3D
	var result: Dictionary={}
	if mount>=0 and mount<vehicle_views.size():
		var view: Dictionary=vehicle_views[mount];var v: Dictionary=world.vehicles[mount]
		if v.emplacement:
			EmplacementMotion.update_weapon(view,v,world.time)
			result.ejection=view.ejection_socket.global_position
			result.ejection_node=view.ejection_socket
			if v.type=="hmg":
				result.posed_recoil=true;result.breech=view.elevation.global_position
		else:
			return VehicleRig.resolve(view,v,world.time)
		socket=view.muzzle_socket
	elif u.id>=0 and u.id<actors.size():
		var view: Dictionary=actors[u.id];view.root.position=Vector3(u.position.x,u.elevation,u.position.y)
		if view.weapon!=w.id:replace_weapon(view,w)
		# Evaluate the current aim/stance before asking the weapon for its world-space socket.
		if view.held.has_meta("secondary_muzzle"):
			view.muzzle_socket.position=view.held.get_meta("secondary_muzzle" if int(u.shot_index)%2==0 else "primary_muzzle")
		var pose_started=Time.get_ticks_usec() if world.profile_ai else 0
		Motion.update(view,u,0,world.time,float(w.reload));socket=view.muzzle_socket
		if world.profile_ai:
			var timings: Dictionary=world.campaign_ai.step_profile
			timings.muzzle_pose_ms=float(timings.get("muzzle_pose_ms",0))+(Time.get_ticks_usec()-pose_started)/1000.0
			timings.muzzle_pose_calls=int(timings.get("muzzle_pose_calls",0))+1
		result.ejection=view.ejection_socket.global_position;result.backblast=view.backblast_socket.global_position
	else:return result
	result.position=socket.global_position;result.forward=-socket.global_basis.z.normalized();return result

func build_ground():
	var ground=Node3D.new();stage.add_child(ground)
	TerrainGround.build(self,ground)
	if is_style_range():StyleRange.decorate(ground)
	preload("res://scripts/terrain_ladder.gd").build(world,ground)
	if plan.get("godot3d",{}).get("nature_training",false):
		for sample in preload("res://scripts/nature_library.gd").samples():ground_label(sample.label,Vector3(sample.point.x,world.terrain.height(sample.point)+.035,sample.point.y+2.35),3.4)
	if plan.get("godot3d",{}).get("biome_training",false):
		for item in preload("res://scripts/terrain_biomes.gd").labels():ground_label(item[0],Vector3(item[1].x,world.terrain.height(item[1])+.035,item[1].y),3.8)
	if plan.get("godot3d",{}).get("range",false):
		for i in range(6):
			var x=-6.5+i*2.75
			Art.box(ground,Vector3(x,.017,-9),Vector3(1.1,.015,3.5),Color("c8c1d0"),false)
			Art.line(ground,Vector3(x-1,.03,8),Vector3(x+1,.03,8),Color("e9dce7"))
		ground_label("01  射击与姿态",Vector3(-5,.04,12),2.8)
		ground_label("02  材质破坏",Vector3(-10,.04,2.4),2.1)
		var material_names={"wall.wood-fence":"木墙","wall.brick":"砖墙","wall.concrete":"混凝土","wall.sandbag":"沙袋","wall.metal-fence":"金属围栏","prop.barrel":"金属油桶","prop.crate":"木箱"}
		# Static sample captions share the actual placement; no per-frame tracking.
		for sample in world.objects:
			if not str(sample.id).begins_with("destruction-"):continue
			var caption: String=material_names.get(sample.component_id,"")
			if caption.is_empty():continue
			var point: Vector2=sample.position+Vector2(0,sample.size.y*.5+.65)
			ground_label(caption,Vector3(point.x,world.terrain.height(point)+.04,point.y),caption.length()*.48)
		ground_label("03  车辆试验 · 蓝 / 红涂装",Vector3(-32,.04,-10),7.5)
		ground_label("我方 · 蓝",Vector3(-36,.04,-8),3.4)
		ground_label("敌方 · 红",Vector3(-28,.04,-8),3.4)
		ground_label("04  两层住宅 · 内外楼梯",Vector3(20,.04,2.5),5.0)
		ground_label("05  翻越训练 · 空格",Vector3(-8,.04,10.3),3.8)
		ground_label("0.65 m · 跨越",Vector3(-8,.04,4.8),3.2)
		ground_label("1.15 m · 撑越",Vector3(-8,.04,11.8),3.2)
		ground_label("1.85 m · 攀爬",Vector3(-8,.04,18.8),3.2)
		ground_label("2.5 m · 无法攀爬",Vector3(-8,.04,25.8),3.6)
	if plan.get("godot3d",{}).get("terrain_review",false):
		for i in range(4):ground_label(["砖墙 · 局部破口","混凝土 · 重火力","木墙 · 易击穿","沙袋 · 低掩体"][i],Vector3(-9+i*6,.032,7.2),3.3)
	# Relief already is one mesh and uses its own slope/snow/sand shader.
	Batch.collapse(ground,[ground.get_node("TerrainRelief")] if ground.has_node("TerrainRelief") else [])

func ground_label(text: String,at: Vector3,width: float):
	var node=Label3D.new();node.text=text;node.font_size=42;node.pixel_size=width/(text.length()*42);node.modulate=Color("666078");node.outline_size=0;stage.add_child(node);node.position=at;node.rotation_degrees.x=-90

func polygon(parent: Node3D,points: Array,height: float,color: Color) -> MeshInstance3D:
	var p=PackedVector2Array(points);var triangles=Geometry2D.triangulate_polygon(p);var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	for i in triangles:v.append(Vector3(p[i].x,height,p[i].y));n.append(Vector3.UP);c.append(color)
	var mesh=Art.mesh_node(parent,Props.mesh_from(v,n,c),Vector3.ZERO,color);mesh.material_override=Art.ink_material(Color.WHITE,true,.14);return mesh

func build_roof(roof: Dictionary):
	if roof.get("house",false):roof_views.append({"data":roof});return
	if not roof.enabled or roof.points.size()<3:return
	var node=Art.mesh_node(stage,TerrainGround.roof_mesh(roof),Vector3.ZERO,Color.WHITE)
	if is_style_range():node.mesh=preload("res://scripts/range2_materials.gd").tag_mesh(node.mesh,3)
	node.material_override=Art.ink_material(Color.WHITE,true,.10).duplicate();var material: ShaderMaterial=node.material_override
	var members: Array=[]
	for object in world.objects:
		if object.owner==roof.id:members.append(object)
	roof_views.append({"root":node,"material":material,"data":roof,"opacity":1.0,"members":members,"revision":-1,"collapse":false})

func ground_mouse(height: float=0) -> Vector2:
	var mouse=get_viewport().get_mouse_position();var origin=camera.project_ray_origin(mouse)-feedback_camera_offset;var direction=camera.project_ray_normal(mouse)
	var hit=world.terrain.ray(origin,direction,300)
	if not hit.is_empty():
		var terrain_point=origin+direction*hit.distance;return Vector2(terrain_point.x,terrain_point.z)
	if absf(direction.y)<.001:return world.player.position
	var point=origin+direction*((height-origin.y)/direction.y);return Vector2(point.x,point.z)

func aim_mouse() -> Vector2:
	var mouse: Vector2=get_viewport().get_mouse_position()
	var origin=camera.project_ray_origin(mouse)-feedback_camera_offset;var direction=camera.project_ray_normal(mouse)
	var hit=world.trace_3d(origin,direction,300,{"source":world.player.id,"mount":world.player.mounted,"camera_pick":true})
	var point=origin+direction*float(hit.get("distance",300.0))
	# Select the actual surface/limb height first. No chest/head screen-space snapping.
	world.player.aim_height=point.y;world.player.aim_valid=true
	world.player.aim_surface={"head":"头部","body":"身体","leg":"腿部","foot":"脚部","object":"掩体","vehicle":"载具"}.get(str(hit.get("region",hit.get("type",""))),"地面")
	return Vector2(point.x,point.z)

func has_text_focus() -> bool:
	var control=get_viewport().gui_get_focus_owner();return control is LineEdit or control is TextEdit
func wheel_open() -> bool:
	return equipment_wheel!=null and equipment_wheel.active
func loot_open() -> bool:
	return loot_panel!=null and loot_panel.visible
func over_ui() -> bool:
	if debug_open() and not editing:return true
	var control=get_viewport().gui_get_hovered_control();return control!=null and control!=ui

func _physics_process(delta: float):
	if loading_active or not world_ready:return
	if lan!=null and lan.mode=="connecting":return
	if not is_node_ready() or editing or (paused and (lan==null or not lan.active())) or (world.campaign_active() and world.campaign.phase!="playing") or (armory.visible and (lan==null or not lan.active())) or (home_open() and (lan==null or not lan.active())):
		world.cancel_firing();jump_pressed=false;trigger_pressed=false;return
	var started=Time.get_ticks_usec() if performance_log!=null else 0
	var move=Vector2.ZERO
	var movement_allowed=not home_open() and not debug_open() and get_window().has_focus() and not armory.visible and not has_text_focus() and not wheel_open() and not loot_open()
	if movement_allowed:move=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if scope_view!=null:scope_view.sync_input()
	aim=aim_mouse() if not qa_mode and not wheel_open() and not debug_open() else aim
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):weapon_input_latched=false
	var fire_allowed=not home_open() and not debug_open() and not armory.visible and not loot_open() and not wheel_open() and not weapon_input_latched and not over_ui() and not has_text_focus() and get_window().has_focus()
	var fire=Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var aiming=not home_open() and not debug_open() and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or (scope_view!=null and scope_view.active)) and not over_ui() and not has_text_focus() and not wheel_open() and not loot_open() and not QuickEquipment.busy(world.player)
	if world.player.mounted<0 and world.active_weapon().kind=="mortar":aiming=false
	if lan!=null and lan.is_client():
		lan.submit_input({"movement":move,"aim":aim,"aim_height":world.player.aim_height,"trigger":fire and fire_allowed,"pressed":trigger_pressed and fire_allowed,"aiming":aiming,"brake":Input.is_physical_key_pressed(KEY_SPACE) and movement_allowed,"sprint":Input.is_physical_key_pressed(KEY_SHIFT) and movement_allowed,"jump":jump_pressed and movement_allowed,"fire_allowed":fire_allowed},delta)
		trigger_pressed=false;jump_pressed=false;return
	world.offline_ai_order=(lan==null or not lan.active())
	world.step(delta,move,aim,fire and fire_allowed,trigger_pressed and fire_allowed,aiming,Input.is_physical_key_pressed(KEY_SPACE) and movement_allowed,Input.is_physical_key_pressed(KEY_SHIFT) and movement_allowed,jump_pressed and movement_allowed,fire_allowed)
	trigger_pressed=false;jump_pressed=false
	if performance_log!=null:performance_log.record_physics(started,world)

func _process(delta: float):
	if loading_active or not world_ready:return
	if not is_node_ready():return
	var started=Time.get_ticks_usec() if performance_log!=null else 0
	frames_per_second=wall_fps_counter.sample(Time.get_ticks_usec())
	if scope_view!=null:scope_view.sync_input()
	update_camera(delta)
	var before_views=Time.get_ticks_usec() if performance_log!=null else 0
	update_views(delta)
	var before_roofs=Time.get_ticks_usec() if performance_log!=null else 0
	update_roofs(delta)
	var before_occlusion=Time.get_ticks_usec() if performance_log!=null else 0
	if player_occlusion!=null:player_occlusion.refresh(self,delta)
	var before_projectiles=Time.get_ticks_usec() if performance_log!=null else 0
	update_projectiles(delta)
	if loot_visual!=null:loot_visual.refresh()
	var before_hud=Time.get_ticks_usec() if performance_log!=null else 0
	if performance_log!=null:performance_log.last_frame={"actors_ms":(before_roofs-before_views)/1000.0,"roofs_ms":(before_occlusion-before_roofs)/1000.0,"player_occlusion_ms":(before_projectiles-before_occlusion)/1000.0,"projectile_views_ms":(Time.get_ticks_usec()-before_projectiles)/1000.0,"fx_ms":fx.last_process_ms,"fx_detail":fx.last_profile}
	if grenade_preview!=null:grenade_preview.refresh(delta)
	update_interaction_hint(delta)
	crosshair.refresh(delta)
	if scope_view!=null:scope_view.refresh(delta)
	if combat_hud!=null:combat_hud.refresh()
	if campaign_ui!=null:campaign_ui.refresh(delta)
	if debug_ui!=null:debug_ui.refresh(delta)
	play_notice.visible=not home_open() and not debug_open() and not armory.visible and (paused or not world.player.alive)
	if play_notice.visible:play_notice.text="已暂停 · Esc 继续" if paused else "倒地 · 正在接管队友"
	var mouse_mode=Input.MOUSE_MODE_HIDDEN if crosshair.visible and not qa_mode and not debug_open() and not home_open() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode!=mouse_mode:Input.mouse_mode=mouse_mode
	var before_walls=Time.get_ticks_usec() if performance_log!=null else 0
	for id in pending_rebuild:
		var o: Dictionary=pending_rebuild[id];var view: Dictionary=object_views[id];view.root.visible=o.alive and float(o.get("draw_opacity",1))>.015
		if view.mesh!=null and (wall_batches==null or not wall_batches.members.has(id)):view.mesh.mesh=Props.wall_mesh(o,view.get("cut_height",INF))
		static_prop_batches.changed(o)
		if wall_batches!=null:wall_batches.changed(o)
	pending_rebuild.clear()
	static_prop_batches.flush()
	if wall_batches!=null:wall_batches.flush()
	if performance_log!=null:
		performance_log.last_frame.hud_logic_ms=(before_walls-before_hud)/1000.0
		performance_log.last_frame.wall_updates_ms=(Time.get_ticks_usec()-before_walls)/1000.0
		performance_log.last_frame.wall_cells=wall_batches.last_cells if wall_batches!=null else 0
		performance_log.last_frame.wall_upload_bytes=wall_batches.last_bytes if wall_batches!=null else 0
		performance_log.last_frame.wall_cut_cells=wall_batches.last_cut_cells if wall_batches!=null else 0
		performance_log.last_frame.wall_damage_cells=wall_batches.last_damage_cells if wall_batches!=null else 0
		performance_log.last_frame.wall_fallbacks=wall_batches.last_fallbacks if wall_batches!=null else 0
	for i in range(damage_labels.size()-1,-1,-1):
		var entry: Dictionary=damage_labels[i];entry.age+=delta;entry.node.position.y+=delta*.7;entry.node.modulate.a=maxf(0,1-entry.age)
		if entry.age>1:entry.node.queue_free();damage_labels.remove_at(i)
	if editing:
		selection_ring.visible=not editor.selected.is_empty() or not editor.palette_id.is_empty()
		var at=ground_mouse()
		if editor.palette_id.is_empty():
			var item=editor.find_item()
			if not item.is_empty():at=catalog.position(item,plan) if item.has("x") else catalog.position_point((Vector2(item.x1,item.y1)+Vector2(item.x2,item.y2))*.5,plan)
		selection_ring.position=Vector3(at.x,world.terrain.height(at)+.05,at.y)
	else:selection_ring.hide()
	if performance_log!=null:
		performance_log.last_frame.render_batches={"crowd_ms":crowd_batches.last_ms if is_instance_valid(crowd_batches) else 0,"parts_ms":vehicle_part_batches.last_ms if is_instance_valid(vehicle_part_batches) else 0,"rigid_ms":rigid_batches.last_ms if is_instance_valid(rigid_batches) else 0,"weapons_ms":weapon_batches.last_ms if is_instance_valid(weapon_batches) else 0,"flash_ms":flash_batches.last_ms if is_instance_valid(flash_batches) else 0,"hud_ms":hud_batches.last_ms,"combat_draw_ms":combat_hud.last_draw_ms}
		performance_log.record_frame(started,delta,world,not home_open() and not editing and not paused and not armory.visible and (not world.campaign_active() or world.campaign.phase=="playing"))
		if play_recording and not performance_log.recording and not performance_log.log_error.is_empty():
			var reason=performance_log.log_error;set_play_recording(false);message(reason)

func refresh_debug_status():
	var mount=""
	if world.player.mounted>=0:
		var v: Dictionary=world.vehicles[world.player.mounted]
		if v.emplacement:mount="  |  固定武器耐久 %d/%d · F 离开操作位"%[v.health,v.max_health]
		else:
			var running_gear="%s %d / %d"%[preload("res://scripts/vehicle_durability.gd").gear_name(v),v.track_health,v.max_track]
			mount="  |  车体 %d/%d  %s  %.1f m/s · %s%s"%[v.health,v.max_health,running_gear,v.get("velocity",Vector2.ZERO).length(),v.get("ground",{}).get("label","草地")," / 受阻" if v.get("drive_blocked",false) else ""]
	var pose=({"step":"低墙跨越","vault":"中墙撑越","climb":"高墙攀爬"}.get(world.player.vault.get("mode","vault"),"翻越中")) if not world.player.vault.is_empty() else "腾空 %.1f m"%world.player.elevation if not world.player.grounded else "快跑" if world.player.sprinting else ["站立","蹲伏","卧倒"][world.player.stance]
	if not world.player.ladder.is_empty():pose="梯子攀爬"
	pose=str(Classes.profile(player_class).name)+" / "+pose
	hud.text=("编辑中 · 左键放置 / 拖动  ·  中键平移  ·  Ctrl Z 撤销  ·  Ctrl S 保存  ·  F8 实地测试" if editing else "%s  %s  |  命中 %d  击倒 %d  破坏 %d"%[pose,"无敌" if world.invulnerable else "HP "+str(int(world.player.health)),world.hits,world.kills,world.broken])+mount+"  |  %d FPS"%frames_per_second
	if lan!=null:hud.text+=lan.diagnostics_text()
	if not editing:
		for view in roof_views:
			if view.data.get("house",false) and view.get("interior",false):
				hud.text+=" | 住宅 %d 楼"%(int(view.active_storey)+1);break

func update_camera(delta: float):
	var rendered_player=RenderMotion.sample(world.player,presentation_fraction(),world.time,1.0/Engine.physics_ticks_per_second)
	var driving=world.enclosed(world.player)
	# A platform keeps one view across weapon slots, so switching between its
	# cannon and coaxial MG cannot make the battlefield repeatedly zoom in/out.
	var view_size=zoom
	if not editing and not close_view and world.player.mounted>=0:
		var mount: Dictionary=world.vehicles[world.player.mounted]
		view_size=maxf(zoom*1.30,float(MOUNTED_VIEW_SIZES.get(mount.type,32.0)))
	if driving:rendered_player=VehicleRenderMotion.sample(world.vehicles[world.player.mounted],presentation_fraction()).position
	var ahead=minf(7.5,zoom*.375) if plan.get("godot3d",{}).get("range",false) or is_style_range() else 0.0
	if close_view:ahead=0
	if world.player.mounted>=0:ahead=minf(ahead,zoom*.15)
	var focus=editor_focus if editing else Vector2(rendered_player.x,rendered_player.z)+Vector2(0,-ahead)
	var offset=Vector2(minf(3.2,zoom*.14),0) if (editing or (armory!=null and armory.visible)) else Vector2.ZERO
	var target=Vector3(focus.x+offset.x,(.7 if close_view else 0)+rendered_player.y*.65 if not editing else world.terrain.height(focus),focus.y)
	var desired=target+Vector3(0,48,.001 if editing and top_down else 48)
	if delta>0:
		var previous_height=camera_follow_position.y
		camera_follow_position=camera_follow_position.lerp(desired,1-exp(-delta*10))
		if driving:camera_follow_position.y=lerpf(previous_height,desired.y,1-exp(-delta*4))
	else:camera_follow_position=desired
	camera_follow_size=lerpf(camera_follow_size,view_size,1-exp(-delta*8)) if delta>0 else view_size
	camera.position=camera_follow_position
	camera.look_at(camera.position-Vector3(0,48,.001 if editing and top_down else 48),Vector3.UP)
	camera.size=camera_follow_size
	if scope_view!=null:scope_view.apply_camera(delta,camera_follow_position,camera_follow_size)
	feedback_camera_offset=Vector3.ZERO
	if fx!=null and fx.feedback!=null and not paused and not editing and not armory.visible and not (scope_view!=null and scope_view.active):
		fx.feedback.camera_scale=feedback_camera_scale
		var offset_pixels: Vector2=fx.feedback.camera_offset();var pixel=camera.size/maxf(1,get_viewport().get_visible_rect().size.y)
		feedback_camera_offset=(camera.global_basis.x*offset_pixels.x+camera.global_basis.y*offset_pixels.y)*pixel
		camera.position+=feedback_camera_offset

func presentation_fraction() -> float:
	if paused or editing or (armory!=null and armory.visible) or world.time<=0 or (world.campaign_active() and world.campaign.phase!="playing"):return 1.0
	return Engine.get_physics_interpolation_fraction()

func update_views(delta: float):
	var pose_cost=0
	var viewport_rect=get_viewport().get_visible_rect().grow(100)
	var fraction=presentation_fraction();var world_frame=stage.global_transform
	for v in world.vehicles:
		if v.emplacement:EmplacementMotion.update_weapon(vehicle_views[v.id],lan.render_vehicle(v),world.time)
	for index in range(world.units.size()):
		var u: Dictionary=world.units[(index+pose_cursor)%world.units.size()]
		if lan.is_client() and u.player:u=lan.prediction.render_unit(u)
		if u.player and u.get("throw_state",{}).is_empty() and u.get("melee",{}).is_empty():u.aim_point=aim
		var view: Dictionary=actors[u.id];var physical_position=Vector3(u.position.x,u.elevation,u.position.y)
		var physical_world=world_frame*physical_position
		view.root.visible=u.alive and not world.enclosed(u)
		var rendered_position=RenderMotion.sample(u,fraction,world.time,1.0/Engine.physics_ticks_per_second)
		var translate_batch: bool=crowd_batches!=null and not u.player and u.mounted<0
		if view.has("render_translation"):view.render_translation.offset=Vector3.ZERO
		if not view.root.visible:continue
		# Render positions remain current. Expensive source-clip sampling and hand IK
		# use staggered visual rates for AI; firing still evaluates the exact muzzle.
		# Cached bone capsules use a physics-space origin; ray candidates apply
		# translation on demand instead of rewriting every limb during rendering.
		view.pose_age=float(view.get("pose_age",0))+delta
		view.pose_wait=float(view.get("pose_wait",0))-delta
		var screen=camera.unproject_position(physical_world+Vector3.UP)
		var on_screen=not camera.is_position_behind(physical_world) and viewport_rect.has_point(screen)
		var interval=1.0/24.0 if on_screen else 1.0/6.0
		var force=u.player or u.mounted>=0 or not view.has("pose_ready") or u.get("hit_shapes",[]).is_empty() or view.weapon!=u.weapon_id or not u.vault.is_empty() or not u.ladder.is_empty()
		if not force and (float(view.pose_wait)>0 or pose_cost>=1800):
			if translate_batch:view.render_translation.offset=world_frame.basis*(rendered_position-Vector3(view.root.position))
			else:view.root.position=rendered_position
			continue
		var pose_started=Time.get_ticks_usec()
		view.root.position=physical_position
		var pose_delta=float(view.pose_age);view.pose_age=0.0
		view.pose_wait=interval*float(u.id%11)/11 if not view.has("pose_ready") else maxf(.001,interval+minf(0,float(view.pose_wait)))
		view.pose_ready=true
		Classes.apply(view,str(u.get("class_id","assault")),int(u.team))
		if crowd_batches!=null:crowd_batches.register(view,int(u.team))
		var floor_height=world.ground_height(u.position,.05,u.elevation+.025)
		for marker in view.ground_markers:marker.node.position.y=marker.height+floor_height-u.elevation
		if u.mounted>=0:
			preload("res://scripts/medical_motion.gd").hide_props(view)
			EmplacementMotion.update_operator(view,u,vehicle_views[u.mounted],lan.render_vehicle(world.vehicles[u.mounted]),delta,world.time)
			continue
		EmplacementMotion.release(view)
		if view.weapon!=u.weapon_id:replace_weapon(view,world.weapon_for(u))
		Motion.update(view,u,pose_delta,world.time,float(world.weapon_for(u).reload))
		view.held.visible=not u.get("holstered",false) and u.get("healing",{}).is_empty() and (world.weapon_for(u).kind!="grenade" or u.ammo>0)
		if not u.player:pose_cost+=Time.get_ticks_usec()-pose_started
		if translate_batch:view.render_translation.offset=world_frame.basis*(rendered_position-Vector3(view.root.position))
		else:view.root.position=rendered_position
	pose_cursor=(pose_cursor+7)%maxi(1,world.units.size())
	for v in world.vehicles:
		if v.emplacement:continue
		var presented=lan.render_vehicle(v)
		var view: Dictionary=vehicle_views[v.id];VehicleRig.update(view,presented,world.time,VehicleRenderMotion.sample(presented,fraction))
		VehicleDynamics.update_wheels(view,v,world.terrain,delta)

func update_roofs(delta: float):
	for u in world.units:u.camera_hidden=false
	for view in roof_views:
		if view.data.get("house",false):preload("res://scripts/house_visibility.gd").apply(self,view);continue
		var roof: Dictionary=view.data;var inside=Geometry2D.is_point_in_polygon(world.player.position,PackedVector2Array(roof.points))
		if view.revision!=world.topology_revision:
			var intact=0;var total=0
			for o in view.members:
				total+=int(o.get("initial_solid_count",o.hp.size()))
				for hp in o.hp:
					if hp>0:intact+=1
			view.collapse=total>0 and float(intact)/total<.35;view.revision=world.topology_revision
		var collapse=bool(view.collapse)
		var target=0.0 if roof_mode==1 or collapse or editing else (.13 if roof_mode==2 and inside else 0.0 if inside else 1.0)
		view.opacity=move_toward(view.opacity,target,delta*5);view.root.visible=view.opacity>.015;view.material.set_shader_parameter("cutaway_opacity",view.opacity)
		for o in view.members:
			var object_view: Dictionary=object_views[o.id];var height=1.15 if inside and not editing else INF
			if object_view.get("cut_height",INF)!=height:
				object_view.cut_height=height;o.aim_cut_height=height;pending_rebuild[o.id]=o

func update_projectiles(delta: float=0.0):
	var frozen=paused or editing or (world.campaign_active() and (armory.visible or world.campaign.phase!="playing"))
	if bullet_flight_batch!=null:bullet_flight_batch.refresh(lan.bullet_presentations() if lan!=null else world.projectiles,camera,0.0 if frozen else delta,1.0 if frozen else Engine.get_physics_interpolation_fraction(),world.player.id)
	var live: Dictionary={}
	for p in world.projectiles:
		if BulletFlight.supports(p.weapon):continue
		live[p.id]=true
		if not projectile_views.has(p.id):
			var node=WeaponEffects.projectile(stage,p.weapon,true)
			if weapon_batches!=null:weapon_batches.register_tree(node)
			projectile_views[p.id]=node
		var node: Node3D=projectile_views[p.id]
		# Heavy rounds use the same bounded physics interval as ordinary bullets.
		var current=Vector3(p.position.x,p.height,p.position.y)
		var previous=Vector3(p.previous.x,p.previous_height,p.previous.y)
		node.position=previous.lerp(current,1.0 if frozen else BulletFlight.presentation_blend(p,Engine.get_physics_interpolation_fraction()))
		if p.weapon.kind=="grenade":
			node.rotation=p.motion.rotation
			node.get_node("VisibleBody").scale=Vector3.ONE*clampf(camera.size/get_viewport().get_visible_rect().size.y*8.5/.17,1.0,1.35)
			continue
		var travel=Vector3(p.position.x-p.previous.x,p.height-p.previous_height,p.position.y-p.previous.y)
		if travel.length_squared()<.000001:travel=Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y)
		if travel.length_squared()>.000001:node.basis=Basis.looking_at(travel.normalized(),Vector3.UP if absf(travel.normalized().y)<.98 else Vector3.FORWARD)
		if p.weapon.kind!="grenade":
			var profile=WeaponProfile.get_profile(p.weapon);var pixel=camera.size/maxf(1,get_viewport().get_visible_rect().size.y)
			var axis=-node.basis.z;var projected_length=Vector2(axis.dot(camera.global_basis.x),axis.dot(camera.global_basis.y)).length()
			var dimensions=WeaponEffects.visible_dimensions(profile,p.weapon.kind,pixel,projected_length)
			var visible_radius=dimensions.x;var visible_length=dimensions.y
			if p.has("origin"):
				# The nose starts at the physical muzzle; expose the enlarged tail only as it exits.
				var travel_from_muzzle=node.position.distance_to(Vector3(p.origin.x,p.start_height,p.origin.y))
				visible_length=minf(visible_length,maxf(.01,travel_from_muzzle))
			node.get_node("VisibleBody").scale=Vector3(visible_radius/profile.radius,visible_radius/profile.radius,visible_length/profile.length)
		if p.weapon.kind=="rocket" and p.age-float(node.get_meta("smoke_age",-.1))>.055:
			node.set_meta("smoke_age",p.age);fx.piece(node.position+node.basis.z*.50,Vector3.ONE*.08,Color("b6adbf"),Vector3(0,.10,0),.45,true,0,"smoke")
	for id in projectile_views.keys():
		if not live.has(id):projectile_views[id].queue_free();projectile_views.erase(id)

func on_world_event(event: Dictionary):
	if lan!=null and lan.is_client() and lan.prediction.replaying:return
	if lan!=null and lan.is_host():lan.replicate_event(event)
	if loot_open() and (event.type in ["player_changed","mount","dismount"] or (event.type=="death" and int(event.unit.id)==loot_panel.owner_id)):
		loot_panel.close()
	if event.type=="round_finished":
		if bullet_flight_batch!=null:bullet_flight_batch.finish(event.round)
		return
	if event.type=="headshot" and event.unit.id>=0 and event.unit.id<actors.size():fx.detach_helmet(actors[event.unit.id],event.impulse)
	if fx!=null:fx.handle(event)
	match event.type:
		"mortar_deployed":
			var view=Props.vehicle(stage,event.vehicle);vehicle_views.append(view)
			EmplacementMotion.update_weapon(view,event.vehicle,world.time)
			if flash_batches!=null:flash_batches.register_tree(view.root)
			if rigid_batches!=null:rigid_batches.register_tree(view.root)
			if event.unit.player:
				trigger_pressed=false;weapon_input_latched=true;update_weapon_details();message("迫击炮已部署 · 靠近按 F 蹲姿操作，再按 F 离开")
		"object_changed":pending_rebuild[event.object.id]=event.object
		"notice":message(event.text)
		"campaign_stage_changed":
			if campaign_ui!=null:campaign_ui.rebuild_world()
		"campaign_finished":record_campaign_result()
		"damage":
			if int(event.get("source_id",-1))!=int(world.player.id) or float(event.amount)<=0:return
			if event.unit.team!=world.player.team and crosshair!=null:
				crosshair.hit_time=.18 if event.get("fatal",false) else .12
				crosshair.hit_fatal=bool(event.get("fatal",false))
		"death":if event.unit.player:message("已倒地 · 正在接管存活队友" if world.campaign_active() else "已倒地。F5 重置场景，或在武器库补给复活")
		"player_changed":
			if equipment_wheel!=null:equipment_wheel.close(false)
			if scope_view!=null:scope_view.cancel()
			world.cancel_firing();trigger_pressed=false;jump_pressed=false
			player_class=str(world.player.get("class_id","assault"));aim=world.player.position+world.player.facing*12
			update_weapon_details();refresh_class_detail();message("已接管队友 · 保留其随身装备和剩余弹药")
		"equip":pass
		"mount","dismount":
			if equipment_wheel!=null:equipment_wheel.close(false)
			if scope_view!=null:scope_view.cancel()
			trigger_pressed=false;jump_pressed=false;weapon_input_latched=true;update_weapon_details()
		"vehicle_destroyed":message("固定武器损毁 · 已离开操作位" if event.vehicle.emplacement else "载具损毁 · 残骸仍可阻挡射线")

func message(text: String):
	if notice!=null:notice.text=text;notice_age=4
func toggle_close_view():
	if editing:return
	if scope_view!=null:scope_view.cancel()
	close_view=not close_view;zoom=5 if close_view else float(plan.get("godot3d",{}).get("combat_camera_size",20))
	message("动作近景 · Shift 快跑，空格跳跃 / 翻越，C 蹲伏，Z 卧倒，F1 返回" if close_view else "返回演武场视野")
func toggle_armory():
	if loot_panel!=null:loot_panel.close()
	if equipment_wheel!=null:equipment_wheel.close(false)
	if editing:return
	if world.campaign_active() and world.campaign.phase!="playing":return
	if scope_view!=null:scope_view.cancel()
	world.cancel_firing();trigger_pressed=false
	armory.visible=not armory.visible;get_viewport().gui_release_focus();update_weapon_details()

func toggle_inventory():
	if loot_open():loot_panel.close();return
	if armory.visible:toggle_armory();return
	if editing or paused or has_text_focus():return
	var bag=world.loot.nearest(world,world.player)
	if not bag.is_empty():loot_panel.open(int(bag.id))
	else:toggle_armory()

func cycle_fire_mode():
	trigger_pressed=false
	if lan!=null and lan.is_client():lan.request_action("cycle")
	else:world.cycle_fire_mode()
	update_weapon_details();get_viewport().gui_release_focus()
func toggle_editor():
	if world.campaign_active():message("正式关卡正在进行 · Debug 可返回联合演武场后编辑预制体");return
	if editor==null:return
	editing=not editing;paused=false;armory.hide();editor.panel.visible=editing;trigger_pressed=false;get_viewport().gui_release_focus()
	if editing:
		combat_view_before_editor=zoom
		editor_focus=world.player.position;rebuild(editor.plan);message("编辑模式：场景破坏不会写回布局。F8 进入测试")
	else:
		zoom=combat_view_before_editor
		rebuild(editor.plan);message("测试当前布局 · C 蹲伏，Z 卧倒，Tab 武器库，F8 返回编辑")
		if debug_ui!=null:debug_ui.set_open(false)
func reset_range():
	if bool(plan.get("godot3d",{}).get("campaign_offline",false)):
		start_campaign_chapter(int(plan.godot3d.campaign_chapter),str(plan.godot3d.get("campaign_tactic","T01")))
		return
	if lan!=null and lan.is_client():message("请房主重新开始战役");return
	if lan!=null and lan.active():lan.stop()
	if debug_ui!=null:debug_ui.set_open(false)
	paused=false;armory.hide()
	var source=plan if world.campaign_active() else editor.plan if editor!=null else plan
	rebuild(source);message("第一关已重新开始" if world.campaign_active() else "当前场景已重置，破坏与残留效果已清除")
func cycle_roof():
	if world.campaign_active():return
	roof_mode=(roof_mode+1)%3;message(["房顶：进入房间自动隐藏","房顶：始终隐藏","房顶：进入房间半透明"][roof_mode])

func _unhandled_input(event: InputEvent):
	if loading_active or not world_ready:return
	if home_open():
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:home_ui.hide_menu()
		get_viewport().set_input_as_handled();return
	if debug_open() and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		debug_ui.set_open(false);get_viewport().set_input_as_handled();return
	var offline_retry=preload("res://scripts/campaign_input_policy.gd").retry_shortcut(event,plan,lan!=null and lan.active(),editing,has_text_focus(),loot_open(),wheel_open())
	if event is InputEventKey and event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F8] and not debug_open() and not offline_retry:return
	if debug_open() and not editing and not (event is InputEventKey and event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F5,KEY_F8]):return
	if loot_open():return
	if wheel_open():return
	if event is InputEventKey and event.keycode==KEY_G and event.pressed and not event.echo:
		if equipment_wheel!=null and equipment_wheel.open():get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and not editing and not paused and not has_text_focus() and not over_ui():
		if not Handling.is_topdown(world.active_weapon()) and (world.player.aiming or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			var magnification=1.0/scope_view.view_ratio if scope_view!=null else 1.0
			Handling.compensate(world.active_state(),maxf(0,event.relative.y)*.0018/magnification)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:toggle_close_view();return
			KEY_F2:toggle_graphic_style();return
			KEY_F8:debug_ui.open_editor();return
			KEY_F5:reset_range();return
			KEY_F3:cycle_roof();return
			KEY_F4:return
			KEY_TAB:toggle_inventory();return
			KEY_M:
				fx.muted=not fx.muted
				if fx.muted:fx.feedback.audio.clear()
				message("音效关闭" if fx.muted else "音效开启");return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if editing:
				zoom=maxf(5,zoom*.88) if event.button_index==MOUSE_BUTTON_WHEEL_UP else minf(90,zoom/.88)
			elif weapon_shortcut_available():
				equip_quick_slot(world.next_equipment_slot(1 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -1))
			# Combat scrolling always selects weapons, including while aiming.
			get_viewport().set_input_as_handled()
			return
	if editing:
		if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):editor_focus+=Vector2(-event.relative.x,-event.relative.y*(1 if top_down else 1.414))*zoom/get_viewport().get_visible_rect().size.y
		editor.input(event);return
	if has_text_focus():return
	if world.campaign_active() and world.campaign.phase!="playing":return
	if paused and not (event is InputEventKey and event.keycode==KEY_ESCAPE):return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not armory.visible and not over_ui():trigger_pressed=true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and not armory.visible and not over_ui() and world.player.mounted<0 and world.active_weapon().kind=="grenade":
		var low=not bool(world.player.get("throw_low",false))
		if lan!=null and lan.is_client():lan.request_action("throw_low",low)
		else:world.player.throw_low=low
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:
			if weapon_shortcut_available():
				if event.keycode==KEY_5 and world.player.mounted<0:use_quick_medicine()
				else:equip_quick_slot(int(event.keycode-KEY_1))
			get_viewport().set_input_as_handled();return
		match event.keycode:
			KEY_V:if scope_view!=null:scope_view.toggle()
			KEY_H:
				if close_view and not world.campaign_active():
					var u=world.player
					if not u.get("helmet_lost",false):
						u.helmet_lost=true;fx.detach_helmet(actors[u.id],Vector3(u.facing.x,0,u.facing.y)*2.5);message("头盔脱落演示 · H 不造成伤害；F5 重置后恢复")
			KEY_SPACE:if world.player.mounted<0:jump_pressed=true
			KEY_C:
				var stance=0 if world.player.stance==1 else 1
				if lan!=null and lan.is_client():lan.request_action("stance",stance)
				else:world.set_stance(stance)
			KEY_Z:
				var stance=0 if world.player.stance==2 else 2
				if lan!=null and lan.is_client():lan.request_action("stance",stance)
				else:world.set_stance(stance)
			KEY_R:
				if lan!=null and lan.is_client():lan.request_action("reload")
				else:world.reload_weapon()
			KEY_B:cycle_fire_mode()
			KEY_E:
				if lan!=null and lan.is_client():lan.request_action("interact")
				else:Interaction.activate(self)
			KEY_F:
				if not armory.visible and not over_ui():
					if lan!=null and lan.is_client():lan.request_action("mount")
					else:world.interact_vehicle();update_weapon_details()
			KEY_ESCAPE:
				if lan!=null and lan.active():show_home();return
				if world.cancel_medicine():trigger_pressed=false;weapon_input_latched=true
				elif world.player.get("throw_state",{}).get("phase","") in ["aim","windup"]:world.cancel_firing();trigger_pressed=false;message("已取消投掷")
				elif armory.visible:armory.hide()
				else:
					paused=not paused;world.cancel_firing();trigger_pressed=false;jump_pressed=false
					if scope_view!=null:scope_view.cancel()
					message("已暂停 · Esc 继续" if paused else "继续战斗" if world.campaign_active() else "继续测试")

func equip_campaign_slot(index: int):
	equip_quick_slot(index)

func weapon_shortcut_available() -> bool:
	return not debug_open() and not editing and not paused and not armory.visible and not loot_open() and not wheel_open() and not has_text_focus() and not over_ui() and get_window().has_focus() and QuickEquipment.selection_available(world.player,world.vehicles) and (not world.campaign_active() or world.campaign.phase=="playing")

func equip_quick_slot(index: int):
	if editing or paused or (world.campaign_active() and world.campaign.phase!="playing"):return
	if lan!=null and lan.is_client():lan.request_action("slot",index)
	elif not world.equip_slot(index):return
	if scope_view!=null:scope_view.cancel()
	trigger_pressed=false;jump_pressed=false;weapon_input_latched=Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT);update_weapon_details()
	get_viewport().gui_release_focus()

func use_quick_medicine():
	if editing or paused:return
	if lan!=null and lan.is_client():
		lan.request_action("medicine",str(world.player.get("medical_selected","bandage")))
		trigger_pressed=false;weapon_input_latched=true;return
	if world.cancel_medicine():trigger_pressed=false;weapon_input_latched=true;return
	if world.use_medicine(str(world.player.get("medical_selected","bandage"))):
		trigger_pressed=false;weapon_input_latched=true
		if scope_view!=null:scope_view.cancel()

func prepare_medical_training():
	if world.campaign_active() or editing or paused or not QuickEquipment.available(world.player):return
	world.cancel_medicine();world.cancel_firing();world.player.health=world.player.max_health*.35
	world.player.medical_stock={"bandage":3,"first-aid":2};world.player.medical_selected="first-aid"
	world.player.medical_feedback={"kind":"ready","remaining":1.2}
	armory.hide();trigger_pressed=false;jump_pressed=false;weapon_input_latched=true
	if scope_view!=null:scope_view.cancel()
	get_viewport().gui_release_focus()

func holster_weapon():
	if lan!=null and lan.is_client():lan.request_action("holster");trigger_pressed=false;weapon_input_latched=true;return
	if world.holster():
		trigger_pressed=false;weapon_input_latched=true
		if scope_view!=null:scope_view.cancel()

func start_campaign_chapter(number: int,tactic: String="T01"):
	if loading_active:return
	var direct_retry=number==startup_chapter and int(plan.get("godot3d",{}).get("campaign_chapter",0))==number
	if not campaign_progress.can_play(number) and not direct_retry:message("请先完成前一关");return
	if lan!=null and lan.active():lan.stop()
	loading_chapter=number;loading_tactic=tactic
	_start_loading("正在准备第 %02d 关"%number)
	var generation=loading_generation
	# The loading canvas must be presented before plan construction or world setup.
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	if not _loading_valid(generation):_finish_loading(false,generation);return
	loading_ui.drawn=DisplayServer.get_name()!="headless"
	loading_ui.update_stage("读取关卡资料",0,0)
	var chapter_plan=CampaignCatalog.plan(catalog,number,tactic)
	if chapter_plan.is_empty():loading_ui.failure="关卡资料无法载入";_finish_loading(false,generation);return
	chapter_plan.godot3d.campaign_checkpoint=campaign_progress.can_play(number)
	if debug_ui!=null:debug_ui.set_open(false)
	paused=false;editing=false;close_view=false;roof_mode=0;zoom=25;armory.hide()
	if editor!=null:editor.panel.hide()
	world=World.new()
	var success=await rebuild(chapter_plan,true)
	if generation!=loading_generation:return
	_finish_loading(success,generation)
	if not success:return
	if chapter_plan.godot3d.campaign_checkpoint:campaign_progress.begin_chapter(number,tactic)
	trigger_pressed=false;jump_pressed=false;weapon_input_latched=true
	if editor!=null:editor.plan=plan.duplicate(true);editor.undo_stack.clear();editor.redo_stack.clear();editor.selected="";editor.palette_id=""
	aim=world.player.position+Vector2.UP*12;update_camera(0)
	set_game_title("小小战地 · "+str(plan.title))
	if home_ui!=null:home_ui.hide_menu()
	# Every offline entry and retry is frozen in the same existing equipment briefing.
	armory.show();campaign_ui.refresh()
	message(str(plan.title)+"已准备 · 选择战术，按 Tab 或“继续战斗”开始")
	if not campaign_progress.last_error.is_empty():message(campaign_progress.last_error)

func _ensure_loading_ui():
	if loading_ui!=null:return
	loading_ui=preload("res://scripts/campaign_loading.gd").new();add_child(loading_ui)
	loading_ui.retry_requested.connect(func():
		if not world_ready:get_tree().reload_current_scene()
		else:loading_ui.hide();start_campaign_chapter(loading_chapter,loading_tactic))
	loading_ui.home_requested.connect(func():
		if loading_active:loading_ui.cancelled=true;loading_return_home=true
		elif home_ui!=null:loading_ui.hide();show_home()
		# Startup has no home menu; its home button is hidden.
	)
	loading_ui.exit_requested.connect(func():get_tree().quit())

func _start_loading(title_text: String):
	_ensure_loading_ui()
	loading_generation+=1;loading_active=true;loading_return_home=false;loading_snapshot.clear()
	for field in LOADING_FIELDS:loading_snapshot[field]=get(field)
	loading_snapshot.window_title=get_window().title
	loading_snapshot.engine_physics_hz=Engine.physics_ticks_per_second
	loading_snapshot.engine_jitter_fix=Engine.physics_jitter_fix
	loading_snapshot.engine_max_steps=Engine.max_physics_steps_per_frame
	loading_snapshot.ui_mode=ui.process_mode
	loading_snapshot.editor_visible=editor.panel.visible if editor!=null else false
	loading_snapshot.style_visible=style_button.visible if style_button!=null else false
	loading_snapshot.ui_visible=ui.visible
	loading_snapshot.armory_visible=armory.visible if armory!=null else false
	loading_snapshot.stage_mode=stage.process_mode if stage!=null else Node.PROCESS_MODE_INHERIT
	if stage!=null:stage.process_mode=Node.PROCESS_MODE_DISABLED;stage.hide()
	ui.hide();ui.process_mode=Node.PROCESS_MODE_DISABLED
	if performance_log!=null:performance_log.boundary("loading_start")
	loading_ui.begin(title_text)
	var generation=loading_generation
	get_tree().create_timer(121.0).timeout.connect(func():
		if loading_active and generation==loading_generation:
			loading_ui.failure="加载超时，请重试";_finish_loading(false,generation);loading_generation+=1)

func _loading_valid(generation: int) -> bool:
	return loading_active and generation==loading_generation and loading_ui.valid()

func _finish_loading(success: bool,expected_generation: int=-1):
	if expected_generation>=0 and expected_generation!=loading_generation:return
	if not loading_active:return
	if success:
		var old_stage=loading_snapshot.get("stage")
		if is_instance_valid(old_stage):remove_child(old_stage);old_stage.queue_free()
		world.event.connect(on_world_event)
		stage.process_mode=Node.PROCESS_MODE_INHERIT;stage.show();loading_ui.finish()
	else:
		if stage!=loading_snapshot.get("stage") and is_instance_valid(stage):remove_child(stage);stage.queue_free()
		for field in LOADING_FIELDS:set(field,loading_snapshot[field])
		if stage!=null:stage.process_mode=loading_snapshot.stage_mode;stage.show()
		preload("res://scripts/campaign_background.gd").apply(scene_environment,plan)
		RenderingServer.global_shader_parameter_set("range2_enabled",is_style_range() and graphic_style)
		Engine.physics_ticks_per_second=loading_snapshot.engine_physics_hz
		Engine.physics_jitter_fix=loading_snapshot.engine_jitter_fix
		Engine.max_physics_steps_per_frame=loading_snapshot.engine_max_steps
		build_theme();get_window().title=loading_snapshot.window_title
		if campaign_ui!=null:
			campaign_ui.cached_equipment=""
			campaign_ui.sync_mode();campaign_ui.rebuild_world()
		if vehicle_list!=null:refresh_vehicles();update_weapon_details()
		refresh_class_detail()
		if editor!=null:editor.panel.visible=loading_snapshot.editor_visible
		if style_button!=null:style_button.visible=loading_snapshot.style_visible
		for key in training_switches:training_switches[key].set_pressed_no_signal(bool(world.get(key)))
		if armory!=null:armory.visible=loading_snapshot.armory_visible
		loading_ui.fail(loading_ui.failure if not loading_ui.failure.is_empty() else "已返回上一个完整场景")
	world_ready=world!=null and not world.player.is_empty()
	loading_active=false;ui.process_mode=loading_snapshot.ui_mode;ui.visible=loading_snapshot.ui_visible
	loading_snapshot.clear()
	if loading_return_home and home_ui!=null:loading_ui.hide();show_home()
	if performance_log!=null:performance_log.boundary("loading_ready" if success else "loading_rollback")

func record_campaign_result():
	if lan!=null and lan.active():return
	if campaign_result_recorded or not bool(plan.get("godot3d",{}).get("campaign_offline",false)):return
	if world.campaign.phase!="won" or not bool(plan.godot3d.get("campaign_checkpoint",true)):return
	if Time.get_ticks_msec()-campaign_save_attempt_at<2000:return
	campaign_save_attempt_at=Time.get_ticks_msec()
	campaign_result_recorded=campaign_progress.mark_completed(int(plan.godot3d.campaign_chapter))
	if not campaign_result_recorded:message(campaign_progress.last_error)

func next_campaign_chapter():
	if lan!=null and lan.active():return
	if not bool(plan.get("godot3d",{}).get("campaign_offline",false)) or world.campaign.phase!="won":return
	record_campaign_result()
	var next=int(plan.godot3d.campaign_chapter)+1
	if next<=CampaignCatalog.COUNT and campaign_progress.can_play(next):start_campaign_chapter(next,str(plan.godot3d.get("campaign_tactic","T01")))
	else:show_campaign_chapters()

func show_campaign_chapters():
	if home_ui==null:return
	if home_ui_dirty or home_ui.page!="campaign" or not home_ui.overlay.visible:replace_home_page("campaign")
	home_ui.show_menu("campaign")

func start_level01():
	if lan!=null and lan.active():lan.stop()
	if debug_ui!=null:debug_ui.set_open(false)
	paused=false;editing=false;close_view=false;roof_mode=0;zoom=preload("res://scripts/orchard_layout.gd").CAMERA_SIZE;armory.hide()
	if editor!=null:editor.panel.hide()
	rebuild(load(ORCHARD_LEVEL_PATH).plan(catalog))
	if editor!=null:editor.plan=plan.duplicate(true);editor.undo_stack.clear();editor.redo_stack.clear();editor.selected="";editor.palette_id=""
	aim=world.player.position+Vector2.UP*12;update_camera(0)
	set_game_title("小小战地 · 第一关：石墙果园")
	message("第一关 · 夺取果园 B 点；西侧高地观察，战壕迂回，公路机动。1–4 换装备，F 操作载具")

func start_training():
	if lan!=null and lan.active():lan.stop()
	if debug_ui!=null:debug_ui.set_open(false)
	paused=false;editing=false;close_view=false;roof_mode=0;zoom=20;armory.hide()
	if editor!=null:editor.panel.hide()
	rebuild(catalog.range_plan())
	if editor!=null:editor.plan=plan.duplicate(true);editor.undo_stack.clear();editor.redo_stack.clear();editor.selected="";editor.palette_id=""
	aim=world.player.position+Vector2.UP*12;update_camera(0)
	set_game_title("小小战地 · 联合演武场");message("已返回联合演武场 · Tab 武器 / 载具，Debug 中的“第一关”进入石墙果园")

func is_style_range() -> bool:
	return bool(plan.get("godot3d",{}).get("style_range",false))

func start_style_range():
	if lan!=null and lan.active():lan.stop()
	if debug_ui!=null:debug_ui.set_open(false)
	paused=false;editing=false;close_view=false;roof_mode=0;zoom=20;armory.hide();graphic_style=true
	if editor!=null:editor.panel.hide()
	rebuild(StyleRange.plan(catalog))
	if editor!=null:editor.plan=plan.duplicate(true);editor.undo_stack.clear();editor.redo_stack.clear();editor.selected="";editor.palette_id=""
	aim=world.player.position+Vector2.UP*12;update_camera(0)
	set_game_title("小小战地 · 演武场2：荒原墨线")
	message("F2 原地切换荒原墨线 / 原版材质；F1 近景，Tab 换枪 / 试驾，F5 复原")

func toggle_graphic_style():
	if not is_style_range():return
	graphic_style=not graphic_style
	RenderingServer.global_shader_parameter_set("range2_enabled",graphic_style)
	if campaign_ui!=null:campaign_ui.sync_mode()
	print("RANGE2_STYLE enabled=",graphic_style," simulation_time=",world.time)

func capture():
	for i in range(25):await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_path)
	print("CAPTURE ",capture_path);get_tree().quit()

func _exit_tree():
	if performance_log!=null:performance_log.stop_session()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
