extends RefCounted
## One native, opt-in developer surface. Never part of the retained battle HUD.
var game
var panel: PanelContainer
var toggle_button: Button
var tabs: TabContainer
var overview: VBoxContainer
var tools_box: VBoxContainer
var editor_page: MarginContainer
var recording: CheckBox
var refresh_age=0.0
var refresh_count=0

func _init(host):game=host

func build():
	toggle_button=game.button(game.ui,"Debug",func():set_open(not panel.visible))
	toggle_button.name="DebugButton";toggle_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toggle_button.offset_left=-92;toggle_button.offset_right=-16;toggle_button.offset_top=14;toggle_button.offset_bottom=46
	toggle_button.z_index=50
	panel=game.make_panel(game.ui,Vector2(-646,56),Vector2(630,810),true)
	panel.name="DebugDrawer";panel.set_meta("hud_native",true);panel.anchor_bottom=1;panel.offset_bottom=-18;panel.z_index=40;panel.hide()
	var box=VBoxContainer.new();panel.add_child(box);box.add_theme_constant_override("separation",8)
	game.campaign_ui.title=game.label(box,"小小战地",19)
	game.subtitle=game.label(box,"",12);game.subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tabs=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(tabs)
	overview=page("性能 / 状态");tools_box=page("测试工具")
	editor_page=MarginContainer.new();editor_page.name="场景工坊";tabs.add_child(editor_page)
	game.label(editor_page,"从「测试工具」打开场景工坊。第一关中不提供编辑。",14).name="EditorHint"
	game.hud=game.label(overview,"",14);game.hud.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	game.campaign_ui.controls=game.label(overview,"",13);game.campaign_ui.controls.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	recording=CheckBox.new();recording.clip_text=true;recording.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;recording.text="详细 CPU / GPU 计时写入日志（仅此页打开期间）";overview.add_child(recording)
	recording.button_pressed="--performance-log" in OS.get_cmdline_user_args()
	recording.toggled.connect(func(_on):sync_sampling())
	game.notice=game.label(tools_box,"",14);game.notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tabs.tab_changed.connect(func(_tab):sync_sampling())
	game.button(box,"关闭  Esc",func():set_open(false))
	game.ui.resized.connect(layout);layout()

func page(title: String) -> VBoxContainer:
	var scroll=ScrollContainer.new();scroll.name=title;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;tabs.add_child(scroll)
	var box=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",8);scroll.add_child(box)
	return box

func attach_performance(overlay):
	overview.add_child(overlay);overview.move_child(overlay,0);overlay.set_monitoring(false)

func attach_editor():
	game.editor.panel.reparent(editor_page)
	game.editor.panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.editor.panel.custom_minimum_size=Vector2.ZERO
	game.editor.panel.hide()

func open_editor():
	game.toggle_editor()
	if game.editing:tabs.current_tab=2;editor_page.get_node("EditorHint").hide()

func set_open(value: bool):
	if value==panel.visible:return
	if not value and game.editing:
		# Hide first: leaving the editor rebuilds and closes its tools too.
		panel.hide();game.toggle_editor()
	if value:
		game.armory.hide()
		if game.loot_panel!=null:game.loot_panel.close()
		if game.equipment_wheel!=null:game.equipment_wheel.close(false)
		refresh_age=0.0
	game.world.cancel_firing();game.trigger_pressed=false;game.jump_pressed=false;game.weapon_input_latched=true
	if game.scope_view!=null:game.scope_view.cancel()
	panel.visible=value;toggle_button.text="Debug ×" if value else "Debug"
	editor_page.get_node("EditorHint").visible=not game.editing
	game.get_viewport().gui_release_focus();sync_sampling()
	if game.hud_batches!=null:game.hud_batches.dirty=true

func sync_sampling():
	var active=panel.visible and tabs.current_tab==0
	if game.performance_overlay!=null:game.performance_overlay.set_monitoring(active)
	game.set_debug_profiling(active and recording.button_pressed)

func refresh(delta: float):
	if not panel.visible:return
	refresh_age-=delta
	if refresh_age>0:return
	refresh_age=.25;refresh_count+=1
	if tabs.current_tab==0:
		game.refresh_debug_status();game.campaign_ui.sync_controls()
	game.notice.visible=not game.notice.text.is_empty()

func layout():
	var width=minf(630,maxf(260,game.ui.size.x-32))
	panel.offset_left=-width-16;panel.offset_right=-16
