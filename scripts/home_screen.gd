extends Control

## Native menus share the tactical UI; no world rendering changes.
const Tactical=preload("res://scripts/tactical_ui.gd")
const GROUND=Tactical.BACKGROUND
const INK=Tactical.INK
const FINE=Tactical.MUTED
const PANEL=Tactical.PANEL
const BUTTON=Tactical.SURFACE
const BUTTON_HOVER=Tactical.HOVER

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
var logo: Label
var page_scroll: ScrollContainer
var page_canvas: Control
var recording: CheckButton
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
	Tactical.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=60
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var corner=make_button(self,"战役菜单",func():if overlay.visible:hide_menu() else:game.show_home(),15)
	corner.anchor_left=1;corner.anchor_right=1;corner.offset_left=-240;corner.offset_right=-110;corner.offset_top=16;corner.offset_bottom=50
	overlay=ColorRect.new();overlay.color=GROUND;overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(overlay)
	shell=Panel.new();shell.clip_contents=true;overlay.add_child(shell)
	page_scroll=ScrollContainer.new();shell.add_child(page_scroll)
	page_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	page_canvas=Control.new();page_canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL;page_scroll.add_child(page_canvas)
	main_view=Control.new();main_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);page_canvas.add_child(main_view)
	logo=make_label(main_view,"小小战地",46,INK)
	logo.name="Title";logo.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var subtitle=make_label(main_view,"战役行动 / 联合作战",16,FINE);subtitle.name="HomeSubtitle"
	recording=CheckButton.new();recording.name="PlayRecording";recording.text="录制游玩日志";main_view.add_child(recording)
	if game.has_signal("play_recording_changed"):
		recording.set_pressed_no_signal(game.play_recording)
		game.play_recording_changed.connect(func(enabled):recording.set_pressed_no_signal(enabled))
	recording.toggled.connect(func(enabled):
		if game.has_method("set_play_recording"):game.set_play_recording(enabled))
	play_button=make_button(main_view,"战役",run_campaign,24)
	make_button(main_view,"历史战役 · H01 韩略村",func():game.start_hanlue(),24).name="HistoricalCampaign"
	make_button(main_view,"局域网协作",open_lan,24).name="JoinCampaign"
	make_button(main_view,"联合演武场",run_training,24).name="Training"
	build_campaign_view()
	lan_view=Control.new();lan_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);page_canvas.add_child(lan_view)
	make_label(lan_view,"局域网协作",36,INK).name="LanTitle"
	make_label(lan_view,"同一场战役 · 战斗中随时加入",16,FINE).name="LanSubtitle"
	host_button=make_button(lan_view,"开放当前战役给队友",host_campaign,21)
	host_address=make_label(lan_view,"",16,INK)
	make_label(lan_view,"发现的局域网房间",18,INK).name="RoomTitle"
	make_button(lan_view,"刷新",func():room_state.text="正在重新搜索局域网房间…";game.lan.discovery.remember_host(address.text);game.lan.discovery.refresh_scan(),15).name="RefreshRooms"
	room_list=ItemList.new();room_list.select_mode=ItemList.SELECT_SINGLE;room_list.allow_reselect=true;lan_view.add_child(room_list)
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
	footer=make_label(overlay,"v%s · 启动 %s"%[game.BUILD_VERSION,game.launch_stamp],12,FINE)
	footer.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;footer.autowrap_mode=TextServer.AUTOWRAP_OFF;footer.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	game.lan.status_changed.connect(func(message):last_status=message;refresh())
	game.lan.discovery.rooms_changed.connect(update_rooms)
	game.lan.discovery.scan_failed.connect(func(reason):last_status=reason;refresh())
	overlay.resized.connect(layout)
	refresh()
	if not show_immediately:overlay.hide()
	call_deferred("layout")

func build_campaign_view():
	campaign_view=Control.new();campaign_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);page_canvas.add_child(campaign_view)
	chapter_title=make_label(campaign_view,"十章战役",30,INK)
	for chapter in preload("res://scripts/campaign_catalog.gd").chapters():
		var number=int(chapter.id)
		var entry=make_button(campaign_view,"%02d  %s"%[number,chapter.title],func():select_chapter(number),17)
		chapter_buttons.append(entry)
	chapter_brief=make_label(campaign_view,"",16,INK);chapter_brief.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	chapter_brief.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	chapter_tactics=OptionButton.new();campaign_view.add_child(chapter_tactics);chapter_tactics.focus_mode=Control.FOCUS_ALL;chapter_tactics.fit_to_longest_item=false;chapter_tactics.clip_text=true
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
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;result.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(result);return result

func make_button(parent: Control,caption: String,callback: Callable,font_size: int) -> Button:
	var result=Button.new();result.text=caption;result.focus_mode=Control.FOCUS_ALL;result.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;result.clip_text=true;result.tooltip_text=caption;parent.add_child(result)
	style_button(result,font_size);result.pressed.connect(callback);return result

func style_button(target: Button,font_size: int):
	target.add_theme_font_size_override("font_size",font_size)
	target.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND

func style_address(target: LineEdit):
	target.add_theme_font_size_override("font_size",16)

# Measure native controls after theme/font resolution, never assume requested height wins.
func place(control: Control,x: float,y: float,width: float,height: float) -> float:
	control.position=Vector2(x,y)
	control.size=Vector2(width,maxf(height,control.get_combined_minimum_size().y))
	return control.position.y+control.size.y+10.0

func layout():
	if shell==null:return
	var viewport_size=overlay.size
	var width=maxf(260,minf(660,viewport_size.x-32))
	var height=maxf(160,minf(790,viewport_size.y-58))
	shell.position=Vector2((viewport_size.x-width)*.5,16);shell.size=Vector2(width,height)
	# Reserve scrollbar width even before its visibility settles.
	width-=18
	var x=22.0;var inner=width-44.0;var y=24.0
	y=place(logo,x,y,inner,100)
	y=place(main_view.get_node("HomeSubtitle"),x,y,inner,30)+24
	for control in [play_button,main_view.get_node("HistoricalCampaign"),main_view.get_node("JoinCampaign"),main_view.get_node("Training")]:y=place(control,x,y,inner,62)
	y=place(recording,x,y+10,inner,42)
	var home_height=y+24
	y=place(chapter_title,x,18,inner,50)
	var columns=1 if width<470 else 2
	var chapter_width=(inner-10*(columns-1))/columns
	for index in range(chapter_buttons.size()):
		var control: Button=chapter_buttons[index]
		place(control,x+(index%columns)*(chapter_width+10),y,chapter_width,42)
		if index%columns==columns-1 or index==chapter_buttons.size()-1:y+=maxf(42,control.get_combined_minimum_size().y)+10
	y=place(chapter_brief,x,y+6,inner,90)
	y=place(chapter_tactics,x,y,inner,42)
	y=place(chapter_start,x,y,inner,48)
	if chapter_resume.visible:y=place(chapter_resume,x,y,inner,40)
	y=place(campaign_view.get_node("CampaignBack"),x,y,inner,40)
	var campaign_height=y+18
	y=place(lan_view.get_node("LanTitle"),x,18,inner,55)
	y=place(lan_view.get_node("LanSubtitle"),x,y,inner,30)
	y=place(host_button,x,y,inner,50)
	y=place(host_address,x,y,inner,50)
	var refresh_button: Button=lan_view.get_node("RefreshRooms")
	var row_bottom=place(refresh_button,x+inner-78,y,78,30)
	y=maxf(row_bottom,place(lan_view.get_node("RoomTitle"),x,y,inner-88,30))
	y=place(room_list,x,y,inner,155)
	y=place(room_state,x,y,inner,44)
	y=place(join_room_button,x,y,inner,42)
	y=place(lan_view.get_node("JoinTitle"),x,y,inner,28)
	row_bottom=place(address,x,y,inner-90,43)
	y=maxf(row_bottom,place(lan_view.get_node("JoinButton"),x+inner-80,y,80,43))
	y=place(status,x,y,inner,45)
	if leave_button.visible:y=place(leave_button,x,y,inner,40)
	y=place(lan_view.get_node("BackButton"),x,y,inner,40)
	page_canvas.custom_minimum_size=Vector2(0,home_height if page=="home" else campaign_height if page=="campaign" else y+18)
	footer.position=Vector2(10,viewport_size.y-29);footer.size=Vector2(maxf(1,viewport_size.x-20),22)

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
	page=target_page;page_scroll.scroll_vertical=0;refresh();overlay.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
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
