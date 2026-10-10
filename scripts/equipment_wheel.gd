extends Control
## A single CanvasItem overlay: no extra world viewport or camera.
const Equipment=preload("res://scripts/quick_equipment.gd")
const MountedIcon=preload("res://scripts/mounted_weapon_icon.gd")
const Tactical=preload("res://scripts/tactical_ui.gd")
const INK=Tactical.INK
const MUTED=Tactical.MUTED
const ACCENT=Tactical.ACCENT
var game
var active=false
var hovered=-1
var owner_id=-1
var owner_mount=-1
var scroll_hovered=-1
var selected_tactical=""
var selected_medical=""
var saved_mouse=Vector2.ZERO
var saved_time_scale=1.0
var icons: Dictionary={}

func _ready():
	Tactical.apply(self)
	name="EquipmentWheel";z_index=30;mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hide()

func allowed() -> bool:
	return game!=null and not game.editing and not game.paused and not game.armory.visible and not game.loot_open() and not game.has_text_focus() and game.get_window().has_focus() and Equipment.selection_available(game.world.player,game.world.vehicles) and (not game.world.campaign_active() or game.world.campaign.phase=="playing")

func open() -> bool:
	if active or not allowed():return false
	var u: Dictionary=game.world.player
	owner_id=int(u.id);selected_tactical=str(u.get("quick_tactical",""));selected_medical=str(u.get("medical_selected","bandage"))
	owner_mount=int(u.mounted);scroll_hovered=-1
	saved_mouse=get_viewport().get_mouse_position();saved_time_scale=Engine.time_scale
	active=true;hovered=-1;show();Engine.time_scale=saved_time_scale*.2
	game.world.cancel_firing();game.trigger_pressed=false;game.jump_pressed=false;game.weapon_input_latched=true
	if game.scope_view!=null:game.scope_view.cancel()
	get_viewport().gui_release_focus();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_viewport().warp_mouse(get_viewport_rect().size*.5)
	queue_redraw();return true

func close(commit: bool=false):
	if not active:return
	active=false;hide();Engine.time_scale=saved_time_scale
	game.weapon_input_latched=true;game.trigger_pressed=false;game.jump_pressed=false
	game.world.cancel_firing()
	if game.scope_view!=null:game.scope_view.cancel()
	if game.get_window().has_focus():get_viewport().warp_mouse(saved_mouse)
	if not commit or not allowed() or not same_context():return
	if owner_mount>=0:
		if hovered>=0:game.equip_quick_slot(hovered)
		return
	var index=Equipment.slot_for_sector(hovered)
	if hovered==2:
		if selected_tactical in Equipment.options(game.world.player,game.catalog.weapons):
			game.world.player.quick_tactical=selected_tactical
			if game.lan!=null and game.lan.is_client():game.lan.request_action("tactical",selected_tactical)
			game.equip_quick_slot(3)
	elif index>=0:game.equip_quick_slot(index)
	elif hovered==4:
		game.world.player.medical_selected=selected_medical;game.use_quick_medicine()
	elif hovered==3:game.holster_weapon()

func _exit_tree():
	if active:Engine.time_scale=saved_time_scale

func _notification(what: int):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and active:close(false)

func same_context() -> bool:
	return owner_id==int(game.world.player.id) and owner_mount==int(game.world.player.mounted)

func _process(_delta: float):
	if not active:return
	if not allowed() or not same_context():close(false);return
	var count=game.world.equipment_entries().size() if owner_mount>=0 else 6
	hovered=scroll_hovered if scroll_hovered>=0 else Equipment.sector((get_viewport().get_mouse_position()-get_viewport_rect().size*.5)/ui_scale(),count)
	queue_redraw()

func _input(event: InputEvent):
	if not active:return
	if event is InputEventKey:
		if event.keycode==KEY_G and not event.pressed:close(true)
		elif event.pressed and not event.echo:
			if event.keycode==KEY_ESCAPE:close(false)
			elif event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:
				hovered=int(event.keycode-KEY_1) if owner_mount>=0 else {KEY_1:0,KEY_2:1,KEY_3:5,KEY_4:2,KEY_5:4}[event.keycode]
				close(true)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT:close(false)
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var step=1 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -1
			if owner_mount>=0 and same_context():
				var v: Dictionary=game.world.vehicles[owner_mount]
				scroll_hovered=posmod((hovered if hovered>=0 else int(v.mode))+step,v.modes.size());hovered=scroll_hovered
			elif hovered==2:selected_tactical=Equipment.cycle(Equipment.options(game.world.player,game.catalog.weapons),selected_tactical,step)
			elif hovered==4:selected_medical=Equipment.cycle(Equipment.MEDICAL_IDS,selected_medical,step)
	elif event is InputEventMouseMotion:scroll_hovered=-1
	get_viewport().set_input_as_handled()

func ui_scale() -> float:
	return minf(1.0,minf(get_viewport_rect().size.x/760.0,get_viewport_rect().size.y/690.0))

func text_center(at: Vector2,value: String,font_size: int,color: Color=INK,max_width: float=240):
	var font=get_theme_default_font();var shown=value
	while shown.length()>1 and font.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>max_width:
		shown=shown.left(shown.length()-1)
	var width=font.get_string_size(shown,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,at-Vector2(width*.5,0),shown,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func icon(id: String,at: Vector2,extent: Vector2,color: Color=INK):
	if not game.catalog.weapons.has(id):return
	if not icons.has(id):
		icons[id]=preload("res://scripts/weapon_icon.gd").get_texture(game.catalog.weapons[id],game.atlas,game.catalog.atlas.frames)
	var texture: Texture2D=icons[id]
	if texture==null:return
	var scale=minf(extent.x/texture.get_width(),extent.y/texture.get_height())
	var size=texture.get_size()*scale
	draw_texture_rect(texture,Rect2(at-size*.5,size),false,color)

func medicine_icon(at: Vector2,color: Color):
	draw_rect(Rect2(at-Vector2(20,13),Vector2(40,26)),color,false,2)
	draw_line(at-Vector2(8,0),at+Vector2(8,0),color,4,true)
	draw_line(at-Vector2(0,8),at+Vector2(0,8),color,4,true)

func ammo_text(id: String) -> String:
	if not game.catalog.weapons.has(id):return "—"
	var w: Dictionary=game.catalog.weapons[id];var u: Dictionary=game.world.player
	if w.kind=="melee":return ""
	var state: Dictionary=u if id==u.weapon_id else u.inventory.get(id,{"ammo":w.mag,"reserve":w.reserve})
	return "%d / %d"%[state.ammo,state.reserve]

func _draw():
	if not active:return
	var viewport=get_viewport_rect().size;var u: Dictionary=game.world.player
	draw_rect(Rect2(Vector2.ZERO,viewport),Color(.035,.04,.055,.60))
	draw_set_transform(viewport*.5,0,Vector2.ONE*ui_scale())
	if owner_mount>=0:
		draw_mounted(game.world.equipment_entries());return
	for i in range(6):
		var angle=-PI*.5+float(i)*TAU/6;var polygon=PackedVector2Array()
		for n in range(33):polygon.append(Vector2.from_angle(angle-PI/6+.025+(PI/3-.05)*n/32.0)*260)
		for n in range(32,-1,-1):polygon.append(Vector2.from_angle(angle-PI/6+.025+(PI/3-.05)*n/32.0)*98)
		draw_colored_polygon(polygon,Tactical.HOVER if hovered==i else Tactical.PANEL)
		polygon.append(polygon[0]);draw_polyline(polygon,ACCENT if hovered==i else Tactical.BORDER,2 if hovered==i else 1,true)
		var at=Vector2.from_angle(angle)*184;var slot=Equipment.slot_for_sector(i)
		var id=selected_tactical if i==2 else Equipment.slot_weapon(u,slot) if slot>=0 else ""
		if slot>=0:
			text_center(at+Vector2(0,-29),str(slot+1),15,ACCENT)
			if id.is_empty():text_center(at+Vector2(0,5),"空位",16,MUTED)
			else:icon(id,at+Vector2(0,1),Vector2(106,35))
			text_center(at+Vector2(0,41),ammo_text(id),13,MUTED)
		elif i==4:
			text_center(at+Vector2(0,-29),"5",15,ACCENT);medicine_icon(at,INK)
			text_center(at+Vector2(0,41),"× %d"%int(u.medical_stock.get(selected_medical,0)),13,MUTED)
		else:
			draw_arc(at,20,0,TAU,32,INK,1.5,true);draw_line(at-Vector2(14,14),at+Vector2(14,14),INK,2,true)
			text_center(at+Vector2(0,41),"收枪",14,MUTED)
		if i==2 or i==4:
			var values: Array=Equipment.options(u,game.catalog.weapons) if i==2 else Equipment.MEDICAL_IDS
			var selected=selected_tactical if i==2 else selected_medical
			if values.size()>1:text_center(at+Vector2(0,60),"‹  %d / %d  ›"%[values.find(selected)+1,values.size()],12,ACCENT if hovered==i else MUTED)
	draw_circle(Vector2.ZERO,88,Tactical.BACKGROUND)
	var selected_id=selected_tactical if hovered==2 else Equipment.slot_weapon(u,Equipment.slot_for_sector(hovered))
	var title="快捷装备";var detail="G"
	if hovered==4:title=str(Equipment.MEDICINE[selected_medical].name);detail="+%d HP · %.1f s"%[Equipment.MEDICINE[selected_medical].heal,Equipment.MEDICINE[selected_medical].seconds]
	elif hovered==3:title="收枪";detail=""
	elif hovered>=0:
		title=str(game.catalog.weapons.get(selected_id,{}).get("name","空位"));detail=ammo_text(selected_id)
	text_center(Vector2(0,-5),title,19,INK,155);text_center(Vector2(0,24),detail,13,ACCENT,155)
	if hovered in [2,4]:
		var values: Array=Equipment.options(u,game.catalog.weapons) if hovered==2 else Equipment.MEDICAL_IDS
		var current=selected_tactical if hovered==2 else selected_medical
		for n in range(values.size()):
			var at=Vector2((n-(values.size()-1)*.5)*62,308)
			var selected=values[n]==current
			draw_rect(Rect2(at-Vector2(28,23),Vector2(56,46)),Color(.12,.13,.16,.98))
			if selected:draw_rect(Rect2(at-Vector2(28,23),Vector2(56,46)),ACCENT,false,2)
			if hovered==2:icon(values[n],at,Vector2(46,29),INK if selected else MUTED)
			else:medicine_icon(at,INK if selected else MUTED)

func draw_mounted(slots: Array):
	var count=slots.size()
	if count==0:return
	for i in range(count):
		var angle=-PI*.5+float(i)*TAU/count;var half=PI/count;var polygon=PackedVector2Array()
		var segments=maxi(32,128/count)
		for n in range(segments+1):polygon.append(Vector2.from_angle(angle-half+.025+(half*2-.05)*n/segments)*260)
		for n in range(segments,-1,-1):polygon.append(Vector2.from_angle(angle-half+.025+(half*2-.05)*n/segments)*98)
		draw_colored_polygon(polygon,Tactical.HOVER if hovered==i else Tactical.PANEL)
		polygon.append(polygon[0]);draw_polyline(polygon,ACCENT if hovered==i else Tactical.BORDER,2 if hovered==i else 1,true)
		var entry: Dictionary=slots[i];var at=Vector2.from_angle(angle)*184
		text_center(at+Vector2(0,-30),str(entry.index+1),15,ACCENT)
		MountedIcon.draw(self,entry.weapon,at,Vector2(106,35),INK)
		text_center(at+Vector2(0,36),str(entry.weapon.get("label","武器")),14,INK,175)
		text_center(at+Vector2(0,57),"%d / %d"%[entry.state.ammo,entry.state.reserve],13,MUTED)
		if entry.selected:draw_line(at+Vector2(-30,66),at+Vector2(30,66),ACCENT,2,true)
	draw_circle(Vector2.ZERO,88,Tactical.BACKGROUND)
	var title="快捷装备";var detail="G"
	if hovered>=0 and hovered<count:
		var entry: Dictionary=slots[hovered]
		title=str(entry.weapon.get("label","武器"));detail="%d / %d"%[entry.state.ammo,entry.state.reserve]
	text_center(Vector2(0,-5),title,19,INK,155);text_center(Vector2(0,24),detail,13,ACCENT,155)
