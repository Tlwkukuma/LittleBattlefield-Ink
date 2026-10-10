extends Control
## Nearby loot over the live battlefield; all transfers revalidate reach and walls.
const Equipment=preload("res://scripts/quick_equipment.gd")
var game
var bag_id=-1
var owner_id=-1
var panel: PanelContainer
var nearby: VBoxContainer
var carried: VBoxContainer
var assignment: OptionButton
var refresh_clock=0.0
var signature=""
var icons: Dictionary={}

func _ready():
	name="LootPanel";z_index=40;mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade=ColorRect.new();shade.color=Color(0,0,0,.42);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel=PanelContainer.new();add_child(panel)
	var margin=MarginContainer.new();panel.add_child(margin)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,16)
	var main=VBoxContainer.new();main.add_theme_constant_override("separation",12);margin.add_child(main)
	var header=HBoxContainer.new();main.add_child(header)
	var title=Label.new();title.text="附近背包";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	game.button(header,"武器 / 载具",func():close();game.toggle_armory())
	game.button(header,"关闭  Tab",close)
	var columns=HBoxContainer.new();columns.add_theme_constant_override("separation",18);columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;main.add_child(columns)
	var left=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(left)
	var label=Label.new();label.text="附近";left.add_child(label)
	nearby=scroll_list(left)
	game.button(left,"全部拾取",func():
		if game.lan!=null and game.lan.is_client():game.lan.request_action("loot_all",bag_id);close()
		elif game.world.loot.take_all(game.world,game.world.player,bag_id):close())
	var right=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(right)
	var loadout=HBoxContainer.new();right.add_child(loadout)
	label=Label.new();label.text="随身装备";label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;loadout.add_child(label)
	assignment=OptionButton.new();assignment.focus_mode=Control.FOCUS_NONE;loadout.add_child(assignment)
	for i in range(3):assignment.add_item("武器位 %d"%(i+1))
	carried=scroll_list(right)
	hide()

func scroll_list(parent: Control) -> VBoxContainer:
	var scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;parent.add_child(scroll)
	var list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",8);scroll.add_child(list);return list

func open(id: int) -> bool:
	if game.editing or game.paused or game.has_text_focus() or not game.world.loot.can_access(game.world,game.world.player,game.world.loot.find(id)):return false
	if game.equipment_wheel!=null:game.equipment_wheel.close(false)
	game.armory.hide();game.world.cancel_firing();game.trigger_pressed=false;game.jump_pressed=false;game.weapon_input_latched=true
	if game.scope_view!=null:game.scope_view.cancel()
	bag_id=id;owner_id=int(game.world.player.id);signature="";refresh_clock=0;show();refresh_rows();get_viewport().gui_release_focus();return true

func close():
	if not visible:return
	hide();bag_id=-1;game.world.cancel_firing();game.trigger_pressed=false;game.jump_pressed=false;game.weapon_input_latched=true
	if game.scope_view!=null:game.scope_view.cancel()
	get_viewport().gui_release_focus()

func _notification(what: int):
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and visible:close()

func _input(event: InputEvent):
	if not visible:return
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode in [KEY_TAB,KEY_ESCAPE]:close()
		get_viewport().set_input_as_handled()

func _process(delta: float):
	if not visible:return
	var area=get_viewport_rect().size;panel.size=Vector2(minf(940,area.x-40),minf(560,area.y-140));panel.position=(area-panel.size)*.5
	refresh_clock-=delta
	if refresh_clock>0:return
	refresh_clock=.15
	var bag=game.world.loot.find(bag_id)
	if game.editing or game.paused or owner_id!=int(game.world.player.id) or not game.world.loot.can_access(game.world,game.world.player,bag):close();return
	refresh_rows()

func clear_rows(list: VBoxContainer):
	for child in list.get_children():list.remove_child(child);child.queue_free()

func icon(id: String) -> Texture2D:
	if icons.has(id):return icons[id]
	var w: Dictionary=game.catalog.weapons.get(id,{})
	var texture=preload("res://scripts/weapon_icon.gd").get_texture(w,game.atlas,game.catalog.atlas.frames)
	icons[id]=texture;return texture

func item_row(list: VBoxContainer,id: String,title: String,detail: String,action: String,callback: Callable):
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",8);list.add_child(row)
	var picture=TextureRect.new();picture.custom_minimum_size=Vector2(64,38);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.texture=icon(id);row.add_child(picture)
	var text=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	var name=Label.new();name.text=title;name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name.custom_minimum_size.x=115;text.add_child(name)
	if not detail.is_empty():
		var info=Label.new();info.text=detail;info.add_theme_font_size_override("font_size",13);info.modulate=Color("b8b6bf");text.add_child(info)
	if not action.is_empty():
		var button=game.button(row,action,callback);button.focus_mode=Control.FOCUS_NONE

func refresh_rows():
	var bag=game.world.loot.find(bag_id)
	if bag.is_empty():close();return
	var u: Dictionary=game.world.player
	var next=JSON.stringify([game.world.loot.revision,u.quick_owned,u.quick_slots,u.quick_tactical,u.weapon_id,u.ammo,u.reserve,u.inventory,u.medical_stock,u.get("weapon_copies",{})])
	if next==signature:return
	signature=next;clear_rows(nearby);clear_rows(carried)
	for key in bag.items:
		var item: Dictionary=bag.items[key];var id=str(item.id)
		var title=str(game.catalog.weapons[id].name) if item.kind=="weapon" else str(Equipment.MEDICINE[id].name)
		if int(item.amount)>1:title+=" × %d"%int(item.amount)
		var detail="%d / %d"%[item.ammo,item.reserve] if item.kind=="weapon" and game.catalog.weapons[id].kind!="melee" else ""
		item_row(nearby,id,title,detail,"拾取",func():
			if game.lan!=null and game.lan.is_client():game.lan.request_action("loot_take",{"bag":bag_id,"key":key})
			elif game.world.loot.take(game.world,game.world.player,bag_id,key):refresh_rows())
	for id in u.quick_owned:
		var w: Dictionary=game.catalog.weapons[id];var state: Dictionary=u if id==u.weapon_id else u.inventory.get(id,{"ammo":w.mag,"reserve":w.reserve})
		var title=str(w.name);var count=int(u.get("weapon_copies",{}).get(id,1))
		if count>1:title+=" × %d"%count
		item_row(carried,id,title,"%d / %d"%[state.ammo,state.reserve] if w.kind!="melee" else "","装备",func():
			if game.lan!=null and game.lan.is_client():game.lan.request_action("assign",{"id":id,"slot":assignment.selected})
			else:game.world.assign_quick_weapon(id,assignment.selected)
			game.update_weapon_details();signature="";refresh_rows())
	for id in u.medical_stock:
		if int(u.medical_stock[id])>0:item_row(carried,id,str(Equipment.MEDICINE[id].name)+" × %d"%int(u.medical_stock[id]),"","使用",func():
			close();game.world.player.medical_selected=id;game.use_quick_medicine())
