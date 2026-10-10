extends RefCounted
## Edits the original 2D scene schema. Godot-only properties live under godot3d.
const VehicleLivery=preload("res://scripts/vehicle_livery.gd")
var host
var plan: Dictionary
var undo_stack: Array=[]
var redo_stack: Array=[]
var selected=""
var palette_id=""
var palette_kind="prefab"
var snap=.25
var dragging=false
var drag_origin=Vector2.ZERO
var drag_item=Vector2.ZERO
var panel: PanelContainer
var library: ItemList
var library_kind: OptionButton
var search: LineEdit
var status: Label
var selection_label: Label
var rotation_field: SpinBox
var scale_field: SpinBox
var height_field: SpinBox
var elevation_field: SpinBox
var durability_field: SpinBox
var destructible_field: CheckBox
var roof_field: CheckBox
var windows_field: CheckBox
var material_field: OptionButton
var team_field: OptionButton
var file_dialog: FileDialog

func _init(owner):host=owner;plan=host.plan.duplicate(true)

func build(parent: Control):
	panel=host.make_panel(parent,Vector2(-326,90),Vector2(310,725),true)
	panel.anchor_bottom=1;panel.offset_bottom=-98
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	var box=VBoxContainer.new();scroll.add_child(box);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",6)
	host.label(box,"场景工坊",22)
	host.label(box,"保留 2D 布局 · 叠加高度与破坏",13)
	var scenes=OptionButton.new();scenes.add_item("联合演武场")
	for item in host.catalog.scenes:scenes.add_item(item.get("title",item.id))
	scenes.add_item("林地前哨 · 地形与破坏")
	scenes.add_item("演武场2 · 荒原墨线")
	box.add_child(scenes);scenes.item_selected.connect(func(i):load_plan(preload("res://scripts/style_range.gd").plan(host.catalog) if i==host.catalog.scenes.size()+2 else preload("res://scripts/terrain_showcase.gd").plan(host.catalog) if i==host.catalog.scenes.size()+1 else host.catalog.range_plan() if i==0 else host.catalog.scenes[i-1]))
	var row=HBoxContainer.new();box.add_child(row)
	host.button(row,"打开 JSON",func():open_file(false));host.button(row,"另存为",func():open_file(true))
	row=HBoxContainer.new();box.add_child(row)
	host.button(row,"撤销",undo);host.button(row,"重做",redo);host.button(row,"俯视 / 立体",func():host.top_down=not host.top_down)
	library_kind=OptionButton.new();library_kind.add_item("%d 个预制体"%host.catalog.prefabs.size());library_kind.add_item("%d 个组件 · 含新地形"%host.catalog.components.size());library_kind.add_item("载具 / 固定武器");library_kind.add_item("布置靶兵 / 出生点")
	box.add_child(library_kind);library_kind.item_selected.connect(func(_i):refresh_library())
	search=LineEdit.new();search.placeholder_text="搜索名称 / ID";box.add_child(search);search.text_changed.connect(func(_t):refresh_library())
	library=ItemList.new();library.custom_minimum_size=Vector2(280,155);box.add_child(library);library.item_selected.connect(choose)
	row=HBoxContainer.new();box.add_child(row)
	host.button(row,"选择 / 移动",func():palette_id="";status.text="单击选择，拖动移动；Q / E 旋转")
	host.button(row,"复制",duplicate_selected);host.button(row,"删除",delete_selected)
	selection_label=host.label(box,"未选择物件",13)
	var grid=GridContainer.new();grid.columns=2;box.add_child(grid)
	rotation_field=field(grid,"旋转（度）",-360,360,5,0)
	scale_field=field(grid,"平面缩放",.1,8,.1,1)
	height_field=field(grid,"高度 / 沟深（米）",.15,12,.05,2.8)
	elevation_field=field(grid,"离地（米）",-8,8,.05,0)
	durability_field=field(grid,"耐久倍率",.1,20,.1,1)
	host.label(grid,"破坏材质",13);material_field=OptionButton.new();grid.add_child(material_field)
	for value in ["原版默认","concrete","building","bunker","sandbag","barrier","wood","brick","metal"]:material_field.add_item(value)
	host.label(grid,"载具阵营",13);team_field=OptionButton.new();grid.add_child(team_field)
	for team in [0,1,-1]:
		team_field.add_item(VehicleLivery.label(team));team_field.set_item_metadata(team_field.item_count-1,team)
	team_field.disabled=true
	destructible_field=CheckBox.new();destructible_field.text="可破坏";destructible_field.button_pressed=true;grid.add_child(destructible_field)
	roof_field=CheckBox.new();roof_field.text="显示房顶";roof_field.button_pressed=true;grid.add_child(roof_field)
	windows_field=CheckBox.new();windows_field.text="建筑窗洞";windows_field.button_pressed=true;grid.add_child(windows_field)
	host.button(box,"应用到选中物件",apply_properties)
	status=host.label(box,"选择素材后点击地面放置；Esc 退出放置",12);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	host.button(box,"▶ 进入此场景测试  [ F8 ]",func():host.toggle_editor())
	file_dialog=FileDialog.new();file_dialog.access=FileDialog.ACCESS_FILESYSTEM;file_dialog.filters=PackedStringArray(["*.json ; 场景 JSON"]);file_dialog.size=Vector2i(850,600);parent.add_child(file_dialog)
	file_dialog.file_selected.connect(func(path):
		if file_dialog.file_mode==FileDialog.FILE_MODE_SAVE_FILE:save(path)
		else:load_file(path))
	refresh_library()

func field(parent: Control,title: String,minimum: float,maximum: float,step: float,value: float) -> SpinBox:
	host.label(parent,title,13);var spin=SpinBox.new();spin.min_value=minimum;spin.max_value=maximum;spin.step=step;spin.value=value;spin.custom_minimum_size.x=132;parent.add_child(spin);return spin

func refresh_library():
	library.clear();var query=search.text.to_lower();var index=library_kind.selected
	if index<2:
		var source: Dictionary=host.catalog.prefabs if index==0 else host.catalog.components
		for id in source:
			var item: Dictionary=source[id];var title=str(item.get("label",item.get("title",id)))
			if not query.is_empty() and not (title+id).to_lower().contains(query):continue
			var at=library.add_item(title);library.set_item_metadata(at,{"id":id,"kind":"prefab" if index==0 else "component"});library.set_item_tooltip(at,id)
	elif index==2:
		for group in ["vehicles","emplacements"]:
			for id in host.catalog.data[group]:
				var title=str(host.catalog.data[group][id].get("label",id))
				if not query.is_empty() and not (title+id).to_lower().contains(query):continue
				var at=library.add_item(title);library.set_item_metadata(at,{"id":id,"kind":group})
	else:
		for id in ["target","spawn"]:
			var at=library.add_item("敌方靶兵" if id=="target" else "玩家出生点");library.set_item_metadata(at,{"id":id,"kind":id})

func choose(index: int):
	var item: Dictionary=library.get_item_metadata(index);palette_id=item.id;palette_kind=item.kind
	selected="";status.text="点击地面放置："+library.get_item_text(index)+"；Esc 返回选择"
	if palette_kind=="component":height_field.value=host.catalog.default_height(palette_id)
	elif palette_kind=="prefab" and host.catalog.prefabs[palette_id].has("godot_height"):height_field.value=maxf(.15,host.catalog.prefabs[palette_id].godot_height)
	terrain_fields(palette_id)
	team_field.disabled=palette_kind not in ["vehicles","emplacements"]
	if palette_id=="access.ladder":status.text="梯子需跨过高低地形边缘；用旋转调整朝向。也可直接放置“壕沟 · 端坡与梯子”预制体。"
	if palette_id=="building.residence-two-storey":status.text="两层住宅：16×12 m，层高固定 3.4 m。内外楼梯直接步行；整体旋转 / 缩放，家具和楼板随房屋生成。建议放在平坦地面。"
	if host.catalog.prefabs.get(palette_id,{}).get("nature",false):status.text="树石预制体：点击放置，支持旋转 / 缩放 / 高度。组合内每棵树、每块石头独立破坏；树冠叶片不作实心碰撞。"

func terrain_fields(id: String):
	var ground=id.begins_with("terrain.") or id.begins_with("biome.") or id.begins_with("landform.") or id=="access.ladder"
	destructible_field.disabled=ground;durability_field.editable=not ground;material_field.disabled=ground
	roof_field.disabled=ground;windows_field.disabled=ground;elevation_field.editable=not ground
	height_field.editable=not ground or "mountain" in id or "trench" in id or "snow" in id or "desert" in id
	if id=="building.residence-two-storey":height_field.editable=false

func checkpoint():
	undo_stack.append(plan.duplicate(true));redo_stack.clear()
	if undo_stack.size()>40:undo_stack.pop_front()

func changed():host.rebuild(plan);refresh_selection()
func undo():
	if undo_stack.is_empty():return
	redo_stack.append(plan.duplicate(true));plan=undo_stack.pop_back();selected="";changed();status.text="已撤销"
func redo():
	if redo_stack.is_empty():return
	undo_stack.append(plan.duplicate(true));plan=redo_stack.pop_back();selected="";changed();status.text="已重做"

func load_plan(source: Dictionary) -> bool:
	var validation_error = preload("res://scripts/editor_plan_validation.gd").error_for(source, host.catalog)
	if not validation_error.is_empty():
		status.text = "无法读取：" + validation_error
		return false
	checkpoint();plan=source.duplicate(true)
	for key in ["instances","looseSegments","trees","vehicles","emplacements"]:if not plan.has(key):plan[key]=[]
	if not plan.has("deployment"):plan.deployment={"player":{"x":plan.world.w*.5,"y":plan.world.h*.65}}
	if not plan.has("units"):plan.units={"red":[],"blue":[]}
	selected="";changed();host.editor_focus=host.world.player.position;status.text="已载入："+str(plan.get("title",plan.get("id","场景")));return true

func open_file(saving: bool):
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://exports"))
	file_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.current_dir=ProjectSettings.globalize_path("res://exports")
	if saving:file_dialog.current_file=str(plan.get("id","scene"))+".json"
	file_dialog.popup_centered()

func save(path: String) -> bool:
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:status.text="保存失败："+error_string(FileAccess.get_open_error());return false
	var output=plan.duplicate(true)
	if not output.has("godot3d"):output.godot3d={}
	output.godot3d.schema_version=1;output.godot3d.pixels_per_metre=40
	file.store_string(JSON.stringify(output,"\t"));file.close();status.text="已保存："+path.get_file();return true

func load_file(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		status.text = "读取失败：" + error_string(FileAccess.get_open_error())
		return false
	var content = file.get_as_text()
	file.close()
	var parser = JSON.new()
	var result = parser.parse(content)
	if result != OK:
		status.text = "JSON 格式错误（第 %d 行）：%s" % [parser.get_error_line(), parser.get_error_message()]
		return false
	if not parser.data is Dictionary:
		status.text = "JSON 场景必须是对象"
		return false
	return load_plan(parser.data)

func details() -> Dictionary:
	var result={"height":height_field.value,"elevation":elevation_field.value,"health_scale":durability_field.value,"destructible":destructible_field.button_pressed,"roof":roof_field.button_pressed,"windows":windows_field.button_pressed}
	if material_field.selected>0:result.material=material_field.get_item_text(material_field.selected)
	return result

func place(point: Vector2):
	if palette_id.is_empty():return
	checkpoint();var p=host.catalog.original_point(point.snapped(Vector2.ONE*snap),plan);var angle=deg_to_rad(rotation_field.value);var id="godot-"+str(Time.get_ticks_usec())
	var item={"id":id,"x":p.x,"y":p.y}
	match palette_kind:
		"prefab":
			item.merge({"prefabId":palette_id,"rotation":angle,"scale":scale_field.value,"godot3d":details()});plan.instances.append(item)
		"component":
			var c: Dictionary=host.catalog.components[palette_id];var defaults: Dictionary=c.get("defaults",{})
			var length=float(defaults.get("length",120))*scale_field.value;var offset=Vector2.from_angle(angle)*length*.5
			item={"id":id,"componentId":palette_id,"x1":p.x-offset.x,"y1":p.y-offset.y,"x2":p.x+offset.x,"y2":p.y+offset.y,"thickness":float(defaults.get("thickness",30))*scale_field.value,"godot3d":details()};plan.looseSegments.append(item)
		"vehicles","emplacements":item.merge({"type":palette_id,"angle":angle,"team":VehicleLivery.key(int(team_field.get_item_metadata(team_field.selected)))});plan[palette_kind].append(item)
		"target":plan.units.red.append(item)
		"spawn":plan.deployment.player={"x":p.x,"y":p.y};selected="";changed();return
	selected=id;changed();status.text="已放置；可继续点击放置，Esc 切换选择"

func arrays() -> Array:return [plan.instances,plan.looseSegments,plan.trees,plan.vehicles,plan.emplacements,plan.units.get("red",[])]
func find_item() -> Dictionary:
	for list in arrays():
		for item in list:if str(item.get("id",""))==selected:return item
	return {}

func select_at(point: Vector2):
	selected="";var best=2.0
	for o in host.world.objects:
		var local=(point-o.position).rotated(-o.angle);var d=Vector2(maxf(0,absf(local.x)-o.size.x*.5),maxf(0,absf(local.y)-o.size.y*.5)).length()
		if d<best:best=d;selected=o.owner
	for v in host.world.vehicles:
		var d=maxf(0,point.distance_to(v.position)-v.radius)
		if d<best:best=d;selected=v.source_id
	for item in plan.units.get("red",[]):
		var d=point.distance_to(host.catalog.position(item,plan))
		if d<best:best=d;selected=str(item.get("id",""))
	# Openings and terrain have no solid object; keep them selectable by segment distance.
	for item in plan.instances:
		if not str(item.prefabId).begins_with("biome."):continue
		var local=(point-host.catalog.position(item,plan)).rotated(-float(item.get("rotation",0)))*40
		var scale=Vector2(float(item.get("scaleX",item.get("scale",1))),float(item.get("scaleY",item.get("scale",1))))
		var points=PackedVector2Array()
		for p in host.catalog.prefabs[item.prefabId].footprint:points.append(host.catalog.v(p)*scale)
		if best>0 and Geometry2D.is_point_in_polygon(local,points):selected=item.id;best=0
	for item in plan.looseSegments:
		var a=host.catalog.position_point(Vector2(item.x1,item.y1),plan);var b=host.catalog.position_point(Vector2(item.x2,item.y2),plan)
		var d=point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))
		if d<best:best=d;selected=item.id
	refresh_selection()

func refresh_selection():
	if selection_label==null:return
	var item=find_item();selection_label.text="选中："+selected if not item.is_empty() else "未选择物件"
	team_field.disabled=item.is_empty() or not item.has("type")
	if item.is_empty():return
	if item.has("type"):
		var team=VehicleLivery.team_id(item.get("team","neutral"))
		for i in range(team_field.item_count):
			if int(team_field.get_item_metadata(i))==team:team_field.select(i)
	var settings: Dictionary=item.get("godot3d",{})
	terrain_fields(str(item.get("componentId",item.get("prefabId",""))))
	rotation_field.value=rad_to_deg(float(item.get("rotation",item.get("angle",(Vector2(item.get("x2",1),item.get("y2",0))-Vector2(item.get("x1",0),item.get("y1",0))).angle()))))
	var default_height=float(host.catalog.prefabs.get(item.get("prefabId",""),{}).get("godot_height",host.catalog.default_height(str(item.get("componentId","wall.concrete")))))
	scale_field.value=float(item.get("scale",1));height_field.value=float(settings.get("height",default_height))
	elevation_field.value=float(settings.get("elevation",0));durability_field.value=float(settings.get("health_scale",1));destructible_field.button_pressed=bool(settings.get("destructible",true));roof_field.button_pressed=bool(settings.get("roof",true))
	windows_field.button_pressed=bool(settings.get("windows",str(item.get("prefabId","")).begins_with("building.") and "bunker" not in str(item.get("prefabId",""))))
	material_field.select(0)
	for i in range(1,material_field.item_count):if material_field.get_item_text(i)==settings.get("material",""):material_field.select(i)

func apply_properties():
	var item=find_item()
	if item.is_empty():return
	checkpoint();item.godot3d=details();var angle=deg_to_rad(rotation_field.value)
	if item.has("prefabId"):item.rotation=angle;item.scale=scale_field.value;item.erase("scaleX");item.erase("scaleY")
	elif item.has("x1"):
		var a=Vector2(item.x1,item.y1);var b=Vector2(item.x2,item.y2);var centre=(a+b)*.5;var offset=Vector2.from_angle(angle)*a.distance_to(b)*.5*scale_field.value
		item.x1=centre.x-offset.x;item.y1=centre.y-offset.y;item.x2=centre.x+offset.x;item.y2=centre.y+offset.y;item.thickness*=scale_field.value;scale_field.value=1
	else:item.angle=angle
	if item.has("type"):item.team=VehicleLivery.key(int(team_field.get_item_metadata(team_field.selected)))
	changed();status.text="物件属性已应用"

func move_selected(offset: Vector2):
	var item=find_item()
	if item.is_empty():return
	checkpoint();var movement=offset.snapped(Vector2.ONE*snap)*40
	if item.has("x1"):item.x1+=movement.x;item.x2+=movement.x;item.y1+=movement.y;item.y2+=movement.y
	else:item.x+=movement.x;item.y+=movement.y
	changed()

func delete_selected():
	if find_item().is_empty():return
	checkpoint()
	for list in arrays():
		for i in range(list.size()-1,-1,-1):if str(list[i].get("id",""))==selected:list.remove_at(i)
	selected="";changed()

func duplicate_selected():
	if find_item().is_empty():return
	checkpoint()
	for list in arrays():
		for item in list:
			if str(item.get("id",""))==selected:
				var copy=item.duplicate(true);copy.id="godot-"+str(Time.get_ticks_usec())
				if copy.has("x1"):copy.x1+=40;copy.x2+=40;copy.y1+=40;copy.y2+=40
				else:copy.x+=40;copy.y+=40
				list.append(copy);selected=copy.id;changed();return

func input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:palette_id="";status.text="选择模式：单击选择，拖动移动"
			KEY_DELETE:delete_selected()
			KEY_Q,KEY_E:
				rotation_field.value+=-15 if event.keycode==KEY_Q else 15
				if palette_id.is_empty():apply_properties()
			KEY_Z:if event.ctrl_pressed:undo()
			KEY_Y:if event.ctrl_pressed:redo()
			KEY_D:if event.ctrl_pressed:duplicate_selected()
			KEY_S:if event.ctrl_pressed:open_file(true)
			KEY_O:if event.ctrl_pressed:open_file(false)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var point=host.ground_mouse()
			if not palette_id.is_empty():place(point)
			else:select_at(point);drag_origin=point;dragging=not selected.is_empty()
		elif dragging:
			dragging=false;var offset=host.ground_mouse()-drag_origin
			if offset.length()>.10:move_selected(offset)
