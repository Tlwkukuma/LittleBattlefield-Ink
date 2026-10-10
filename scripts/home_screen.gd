extends Control

## Native port of the original Pixi HomeScreen; LAN opens the running campaign.
const GROUND=Color("a5b4cc")
const INK=Color("f1f5fb")
const FINE=Color("c1ccd9")
const PANEL=Color("263747")
const BUTTON=Color("1c3045")
const BUTTON_HOVER=Color("365c8a")

var game
var overlay: ColorRect
var shell: Panel
var main_view: Control
var campaign_view: Control
var chapter_buttons: Array=[]
var chapter_title: Label
var chapter_brief: Label
var chapter_tactics: OptionButton
var chapter_start: Button
var chapter_resume: Button
var selected_chapter=1
var lan_view: Control
var logo: TextureRect
var play_button: Button
var status: Label
var address: LineEdit
var room_list: ItemList
var room_state: Label
var join_room_button: Button
var room_entries: Array=[]
var host_button: Button
var leave_button: Button
var host_address: Label
var footer: Label
var page="home"
var last_status=""

func setup(host,show_immediately: bool=false):
	game=host
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=60
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var corner=make_button(self,"战役菜单",func():if overlay.visible:hide_menu() else:game.show_home(),15)
	corner.anchor_left=1;corner.anchor_right=1;corner.offset_left=-240;corner.offset_right=-110;corner.offset_top=16;corner.offset_bottom=50
	overlay=ColorRect.new();overlay.color=GROUND;overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(overlay)
	for index in range(1,20):
		var line=ColorRect.new();line.color=Color(0.075,0.157,0.302,0.06);line.mouse_filter=Control.MOUSE_FILTER_IGNORE
		line.anchor_left=float(index)/20.0;line.anchor_right=line.anchor_left;line.anchor_bottom=1.0;line.offset_right=1.0;overlay.add_child(line)
	for index in range(1,13):
		var line=ColorRect.new();line.color=Color(0.075,0.157,0.302,0.06);line.mouse_filter=Control.MOUSE_FILTER_IGNORE
		line.anchor_top=float(index)/13.0;line.anchor_bottom=line.anchor_top;line.anchor_right=1.0;line.offset_bottom=1.0;overlay.add_child(line)
	shell=Panel.new();shell.clip_contents=true;overlay.add_child(shell)
	var shell_style=StyleBoxFlat.new();shell_style.bg_color=PANEL;shell_style.border_color=Color("c4d4e2");shell_style.set_border_width_all(2);shell_style.set_corner_radius_all(2)
	shell.add_theme_stylebox_override("panel",shell_style)
	var texture=TextureRect.new();texture.texture=preload("res://assets/ui/home/frost-clouds-v2.png");texture.modulate.a=0.78
	texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode=TextureRect.STRETCH_SCALE;texture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shell.add_child(texture)
	main_view=Control.new();main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shell.add_child(main_view)
	logo=TextureRect.new();logo.texture=preload("res://assets/ui/home/logo_title.png")
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter=Control.MOUSE_FILTER_IGNORE;main_view.add_child(logo)
	play_button=make_button(main_view,"战役",run_campaign,24)
	make_button(main_view,"局域网协作",open_lan,24).name="JoinCampaign"
	make_button(main_view,"联合演武场",run_training,24).name="Training"
	build_campaign_view()
	lan_view=Control.new();lan_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shell.add_child(lan_view)
	make_label(lan_view,"局域网协作",36,INK).name="LanTitle"
	make_label(lan_view,"同一场战役 · 战斗中随时加入",16,FINE).name="LanSubtitle"
	host_button=make_button(lan_view,"开放当前战役给队友",host_campaign,21)
	host_address=make_label(lan_view,"",16,INK)
	make_label(lan_view,"发现的局域网房间",18,INK).name="RoomTitle"
	make_button(lan_view,"刷新",func():room_state.text="正在重新搜索局域网房间…";game.lan.discovery.remember_host(address.text);game.lan.discovery.refresh_scan(),15).name="RefreshRooms"
	room_list=ItemList.new();room_list.select_mode=ItemList.SELECT_SINGLE;room_list.allow_reselect=true;lan_view.add_child(room_list)
	var room_panel=StyleBoxFlat.new();room_panel.bg_color=BUTTON;room_panel.border_color=FINE;room_panel.set_border_width_all(1)
	room_list.add_theme_stylebox_override("panel",room_panel)
	var room_selected=StyleBoxFlat.new();room_selected.bg_color=BUTTON_HOVER
	room_list.add_theme_stylebox_override("selected",room_selected)
	room_list.add_theme_color_override("font_color",INK);room_list.add_theme_color_override("font_selected_color",INK)
	room_list.add_theme_font_size_override("font_size",16)
	room_list.item_selected.connect(func(_index):update_room_selection())
	room_list.item_activated.connect(func(_index):join_selected_room())
	room_state=make_label(lan_view,"正在搜索局域网房间…",14,FINE)
	join_room_button=make_button(lan_view,"加入所选房间",join_selected_room,17);join_room_button.disabled=true
	make_label(lan_view,"或手动输入房主 IP",17,INK).name="JoinTitle"
	address=LineEdit.new();address.placeholder_text="房主 IP，例如 192.168.1.8:%d"%game.lan.PORT;address.caret_blink=true;lan_view.add_child(address);style_address(address)
	if not game.lan.discovery.known_hosts.is_empty():address.text=game.lan.discovery.known_hosts[game.lan.discovery.known_hosts.size()-1]
	make_button(lan_view,"加入",join_campaign,18).name="JoinButton"
	status=make_label(lan_view,"",15,FINE);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	leave_button=make_button(lan_view,"离开局域网协作",leave_lan,16)
	make_button(lan_view,"‹  返回首页",back_home,16).name="BackButton"
	footer=make_label(overlay,"v%s · 启动 %s"%[game.BUILD_VERSION,game.launch_stamp],12,Color("3e567c"))
	footer.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	game.lan.status_changed.connect(func(message):last_status=message;refresh())
	game.lan.discovery.rooms_changed.connect(update_rooms)
	game.lan.discovery.scan_failed.connect(func(reason):last_status=reason;refresh())
	overlay.resized.connect(layout)
	refresh()
	if not show_immediately:overlay.hide()
	call_deferred("layout")

func build_campaign_view():
	campaign_view=Control.new();campaign_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shell.add_child(campaign_view)
	chapter_title=make_label(campaign_view,"十章战役",30,INK)
	for chapter in preload("res://scripts/campaign_catalog.gd").chapters():
		var number=int(chapter.id)
		var entry=make_button(campaign_view,"%02d  %s"%[number,chapter.title],func():select_chapter(number),17)
		chapter_buttons.append(entry)
	chapter_brief=make_label(campaign_view,"",16,INK);chapter_brief.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	chapter_brief.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	chapter_tactics=OptionButton.new();campaign_view.add_child(chapter_tactics);chapter_tactics.focus_mode=Control.FOCUS_NONE
	chapter_tactics.add_theme_font_size_override("font_size",17)
	chapter_start=make_button(campaign_view,"进入关卡",func():
		var tactic=str(chapter_tactics.get_item_metadata(chapter_tactics.selected))
		game.start_campaign_chapter(selected_chapter,tactic),21)
	chapter_resume=make_button(campaign_view,"继续当前战斗",func():hide_menu(),17)
	make_button(campaign_view,"‹  返回首页",back_home,16).name="CampaignBack"
	selected_chapter=game.campaign_progress.selected
	select_chapter(selected_chapter)

func select_chapter(number: int):
	if not game.campaign_progress.can_play(number):return
	selected_chapter=number
	var entry=preload("res://scripts/campaign_catalog.gd").chapter(number)
	chapter_brief.text=str(entry.get("briefing",""))+"\n仅保存已完成章节；重新进入本关将从开战前开始。"
	var previous=game.campaign_progress.tactic
	if chapter_tactics.item_count>0 and chapter_tactics.selected>=0:previous=str(chapter_tactics.get_item_metadata(chapter_tactics.selected))
	chapter_tactics.clear()
	var names: Dictionary=preload("res://scripts/campaign_plan.gd").NAMES if number==1 else entry.get("tacticNames",{})
	for id in names:
		chapter_tactics.add_item(id+" · "+str(names[id]));chapter_tactics.set_item_metadata(chapter_tactics.item_count-1,id)
		if str(id)==previous:chapter_tactics.select(chapter_tactics.item_count-1)
	chapter_start.text="进入第 %02d 关 · %s"%[number,entry.get("title","")]
	refresh_chapters()

func refresh_chapters():
	if chapter_title==null:return
	var progress=game.campaign_progress
	chapter_title.text="十章战役 · 已完成" if progress.finished() else "十章战役 · %d / 10 已完成"%progress.completed.size()
	for index in range(chapter_buttons.size()):
		var number=index+1;var entry=preload("res://scripts/campaign_catalog.gd").chapter(number)
		chapter_buttons[index].disabled=not progress.can_play(number)
		chapter_buttons[index].text=("▶ " if number==selected_chapter else "")+"%02d  %s"%[number,entry.get("title","")]+(" ✓" if number in progress.completed else " · 未解锁" if not progress.can_play(number) else "")
	chapter_resume.visible=game.world.campaign_active() and game.world.campaign.phase=="playing"

func make_label(parent: Control,caption: String,font_size: int,color: Color) -> Label:
	var result=Label.new();result.text=caption;result.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;result.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size",font_size);result.add_theme_color_override("font_color",color)
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(result);return result

func make_button(parent: Control,caption: String,callback: Callable,font_size: int) -> Button:
	var result=Button.new();result.text=caption;result.focus_mode=Control.FOCUS_NONE;parent.add_child(result)
	style_button(result,font_size);result.pressed.connect(callback);return result

func style_button(target: Button,font_size: int):
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style=StyleBoxFlat.new();style.bg_color=BUTTON_HOVER if state in ["hover","pressed"] else BUTTON
		style.border_color=Color("8ebeff") if state in ["hover","pressed"] else Color("d6e0eb")
		style.set_border_width_all(2 if state in ["hover","pressed"] else 1);style.set_corner_radius_all(2)
		style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=5;style.content_margin_bottom=5
		target.add_theme_stylebox_override(state,style)
	target.add_theme_color_override("font_color",INK);target.add_theme_color_override("font_hover_color",INK)
	target.add_theme_color_override("font_pressed_color",INK);target.add_theme_font_size_override("font_size",font_size)
	target.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND

func style_address(target: LineEdit):
	for state in ["normal","focus","read_only"]:
		var style=StyleBoxFlat.new();style.bg_color=BUTTON;style.border_color=FINE;style.set_border_width_all(1)
		style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=8;style.content_margin_bottom=8
		target.add_theme_stylebox_override(state,style)
	target.add_theme_color_override("font_color",INK);target.add_theme_color_override("font_placeholder_color",FINE)
	target.add_theme_color_override("caret_color",INK);target.add_theme_font_size_override("font_size",16)

func layout():
	if shell==null:return
	var viewport_size=overlay.size
	var width=minf(660.0,viewport_size.x-32.0)
	var height=minf(750.0,viewport_size.y-32.0)
	shell.position=(viewport_size-Vector2(width,height))*0.5;shell.size=Vector2(width,height)
	var button_width=minf(420.0,width-86.0)
	var button_height=clampf(height*0.1125,50.0,72.0)
	var button_x=(width-button_width)*0.5
	var button_y=minf(height*0.417,height-3.0*button_height-72.0)
	var logo_width=minf(383.0,width*0.70)
	var logo_height=logo_width*298.0/558.0
	logo.position=Vector2((width-logo_width)*0.5,40)
	logo.size=Vector2(logo_width,logo_height)
	var main_buttons=[play_button,main_view.get_node("JoinCampaign"),main_view.get_node("Training")]
	for index in main_buttons.size():
		main_buttons[index].position=Vector2(button_x,button_y+index*(button_height+14.0))
		main_buttons[index].size=Vector2(button_width,button_height)
	chapter_title.position=Vector2(28,18);chapter_title.size=Vector2(width-56,48)
	var chapter_width=(width-76)/2.0
	var chapter_height=clampf((height-401)/5.0,31,49)
	for index in range(chapter_buttons.size()):
		chapter_buttons[index].position=Vector2(28+(index%2)*(chapter_width+20),78+int(index/2)*(chapter_height+8))
		chapter_buttons[index].size=Vector2(chapter_width,chapter_height)
	var chapters_bottom=78+5*(chapter_height+8)
	chapter_brief.position=Vector2(34,chapters_bottom+4);chapter_brief.size=Vector2(width-68,80)
	chapter_tactics.position=Vector2(34,chapters_bottom+89);chapter_tactics.size=Vector2(width-68,36)
	chapter_start.position=Vector2(34,chapters_bottom+133);chapter_start.size=Vector2(width-68,44)
	chapter_resume.position=Vector2(34,height-98);chapter_resume.size=Vector2(width-68,34)
	campaign_view.get_node("CampaignBack").position=Vector2(34,height-55);campaign_view.get_node("CampaignBack").size=Vector2(width-68,34)
	lan_view.get_node("LanTitle").position=Vector2(36,18);lan_view.get_node("LanTitle").size=Vector2(width-72,56)
	lan_view.get_node("LanSubtitle").position=Vector2(36,76);lan_view.get_node("LanSubtitle").size=Vector2(width-72,28)
	host_button.position=Vector2(button_x,111);host_button.size=Vector2(button_width,52)
	host_address.position=Vector2(42,169);host_address.size=Vector2(width-84,40)
	lan_view.get_node("RoomTitle").position=Vector2(button_x,217);lan_view.get_node("RoomTitle").size=Vector2(button_width-80,30)
	lan_view.get_node("RefreshRooms").position=Vector2(button_x+button_width-76,217);lan_view.get_node("RefreshRooms").size=Vector2(76,30)
	room_list.position=Vector2(button_x,253);room_list.size=Vector2(button_width,155)
	room_state.position=Vector2(button_x,410);room_state.size=Vector2(button_width,28)
	join_room_button.position=Vector2(button_x,443);join_room_button.size=Vector2(button_width,42)
	lan_view.get_node("JoinTitle").position=Vector2(button_x,497);lan_view.get_node("JoinTitle").size=Vector2(button_width,28)
	address.position=Vector2(button_x,529);address.size=Vector2(button_width-92,43)
	lan_view.get_node("JoinButton").position=Vector2(button_x+button_width-84,529);lan_view.get_node("JoinButton").size=Vector2(84,43)
	status.position=Vector2(38,579);status.size=Vector2(width-76,45)
	leave_button.position=Vector2(button_x,632);leave_button.size=Vector2(button_width,38)
	lan_view.get_node("BackButton").position=Vector2(button_x,height-60);lan_view.get_node("BackButton").size=Vector2(button_width,40)
	footer.position=Vector2(maxf(10.0,viewport_size.x-500.0),viewport_size.y-29.0);footer.size=Vector2(minf(480.0,viewport_size.x-20.0),22)

func open_lan():
	game.show_lan()

func back_home():
	game.lan.discovery.stop_scan();game.show_home()

func update_rooms(rooms: Array):
	var selected=""
	var selection=room_list.get_selected_items()
	if not selection.is_empty() and selection[0]<room_entries.size():selected=str(room_entries[selection[0]].endpoint)
	room_entries=rooms
	room_list.clear()
	for room in room_entries:
		var same_version=str(room.version)==game.BUILD_VERSION
		var compatible=game.lan.compatible_version(str(room.version))
		var suffix=" · 不兼容" if not compatible else " · 已满" if int(room.players)>=int(room.capacity) else " · 兼容 v%s"%str(room.version).get_slice(".",3) if not same_version else ""
		var ip=str(room.endpoint).get_slice(":",0)
		var location=str(room.name).get_slice(" · ",0)
		room_list.add_item("%s · %s · %d/%d%s"%[ip,location,room.players,room.capacity,suffix])
		if str(room.endpoint)==selected:room_list.select(room_list.item_count-1)
	room_state.text="未发现房间；跨网段请填房主 IP 后刷新。" if room_entries.is_empty() else "发现 %d 个房间 · 双击可加入的房间"%room_entries.size()
	update_room_selection()

func own_room(room: Dictionary) -> bool:
	if not game.lan.is_host():return false
	var ip=str(room.endpoint).get_slice(":",0)
	return ip=="127.0.0.1" or IP.get_local_addresses().has(ip)

func update_room_selection():
	var selection=room_list.get_selected_items()
	join_room_button.disabled=selection.is_empty()
	if selection.is_empty() or selection[0]>=room_entries.size():return
	var room: Dictionary=room_entries[selection[0]]
	join_room_button.disabled=not game.lan.compatible_version(str(room.version)) or int(room.players)>=int(room.capacity) or own_room(room)
	join_room_button.text="当前房间" if own_room(room) else "版本不兼容" if not game.lan.compatible_version(str(room.version)) else "房间已满" if int(room.players)>=int(room.capacity) else "加入所选房间"

func join_selected_room():
	update_room_selection()
	if join_room_button.disabled:return
	var selection=room_list.get_selected_items()
	if selection.is_empty():return
	address.text=str(room_entries[selection[0]].endpoint)
	join_campaign()

func run_campaign():
	if game.lan.is_client():hide_menu();return
	game.show_campaign_chapters()

func run_training():
	if game.lan.active():game.lan.stop()
	game.start_training();hide_menu()

func host_campaign():
	if game.lan.is_host() or game.lan.is_client():hide_menu();return
	if bool(game.plan.get("godot3d",{}).get("campaign_offline",false)):game.start_level01()
	if game.lan.host_game():last_status="当前战役已开放。房主继续游玩，队友可随时加入。"
	refresh()

func join_campaign():
	game.lan.join_game(address.text)

func leave_lan():
	var was_client=game.lan.is_client();game.lan.stop()
	if was_client:game.start_training()
	refresh()

func show_menu(target_page: String="home"):
	if target_page=="home":game.lan.discovery.stop_scan()
	page=target_page;refresh();overlay.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game.trigger_pressed=false;game.jump_pressed=false
	if game.scope_view!=null:game.scope_view.cancel()
	if game.equipment_wheel!=null:game.equipment_wheel.close(false)
	if game.loot_panel!=null:game.loot_panel.close()
	if game.armory!=null:game.armory.hide()

func hide_menu():
	if game.lan.mode=="connecting":return
	if game.lan.is_client() and not game.world.campaign_active():return
	game.lan.discovery.stop_scan();overlay.hide();game.get_viewport().gui_release_focus()

func refresh():
	if overlay==null:return
	main_view.visible=page=="home";lan_view.visible=page=="lan";campaign_view.visible=page=="campaign"
	refresh_chapters()
	play_button.text="继续协作战役" if game.lan.is_client() else "十章战役"
	host_button.text="继续当前战役" if game.lan.active() else "开始并开放第一关" if bool(game.plan.get("godot3d",{}).get("campaign_offline",false)) else "开放当前战役给队友"
	leave_button.visible=game.lan.active()
	host_address.text="队友连接：%s:%d"%[game.lan.local_addresses(),game.lan.PORT] if game.lan.is_host() else "房主继续战斗，队友接管一名蓝军士兵。"
	status.text=last_status
	update_room_selection()
	layout()
