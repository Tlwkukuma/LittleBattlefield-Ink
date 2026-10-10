extends RefCounted
## Campaign UI lives in the existing proving ground and reads the rule state.
const Art=preload("res://scripts/ink_art.gd")
var game
var training_box: VBoxContainer
var equipment_box: VBoxContainer
var status: Label
var briefing: Label
var slots: Array=[]
var slot_choices: Array=[]
var cached_equipment=""
var result_panel: PanelContainer
var result_title: Label
var result_detail: Label
var title: Label
var controls: Label
var controls_mode=-1
var armory_button: Button
var editor_button: Button
var roof_button: Button
var objective_views: Array=[]
var control_ring: Node3D

func build(host,training: VBoxContainer,parent: VBoxContainer):
	game=host;training_box=training
	equipment_box=VBoxContainer.new();parent.add_child(equipment_box);equipment_box.add_theme_constant_override("separation",10)
	game.label(equipment_box,"石墙果园 · 随身装备",20)
	briefing=game.label(equipment_box,"",14);briefing.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;briefing.custom_minimum_size.x=265
	for i in range(4):
		var index=i
		var row=HBoxContainer.new();equipment_box.add_child(row)
		var item=game.button(row,"",func():game.equip_campaign_slot(index))
		item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		item.alignment=HORIZONTAL_ALIGNMENT_LEFT;slots.append(item)
		var choices=OptionButton.new();choices.custom_minimum_size.x=95;choices.focus_mode=Control.FOCUS_NONE;row.add_child(choices);slot_choices.append(choices)
		choices.item_selected.connect(func(choice):
			var id=str(choices.get_item_metadata(choice))
			if id.is_empty():game.world.clear_quick_slot(index)
			else:game.world.assign_quick_weapon(id,index)
			game.update_weapon_details();game.get_viewport().gui_release_focus())
	game.label(equipment_box,"1–3 武器 · 4 战术 · 5 医疗\n按住 G 轮盘 · R 装填 · F 载具\nTab 关闭面板后继续战斗",14)
	game.button(equipment_box,"继续战斗  Tab",func():game.toggle_armory())
	game.button(equipment_box,"重新开始第一关  F5",func():game.reset_range())
	game.button(equipment_box,"返回联合演武场",func():game.start_training())
	var entry=game.button(training_box,"进入第一关 · 石墙果园",func():game.start_level01());training_box.move_child(entry,0)
	status=game.label(game.ui,"",16);status.position=Vector2(24,130);status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result_panel=game.make_panel(game.ui,Vector2(-230,-145),Vector2(460,290))
	result_panel.anchor_left=.5;result_panel.anchor_right=.5;result_panel.anchor_top=.5;result_panel.anchor_bottom=.5
	var box=VBoxContainer.new();result_panel.add_child(box);box.add_theme_constant_override("separation",14)
	result_title=game.label(box,"",30);result_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	result_detail=game.label(box,"",16);result_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	game.button(box,"重新开始  F5",func():game.reset_range())
	game.button(box,"返回联合演武场",func():game.start_training())
	result_panel.hide();sync_mode();rebuild_world()

func sync_mode():
	var active=game.world.campaign_active()
	training_box.visible=not active;equipment_box.visible=active;status.visible=active
	if title!=null:title.text="小小战地  /  第一关 · 石墙果园" if active else "小小战地  /  林地前哨" if game.plan.get("godot3d",{}).get("terrain_review",false) else "小小战地  /  联合演武场"
	if title!=null and game.is_style_range():title.text="小小战地  /  演武场2 · 荒原墨线"
	if armory_button!=null:armory_button.text="随身装备  Tab" if active else "武器 / 载具  Tab"
	if editor_button!=null:editor_button.visible=not active
	if roof_button!=null:roof_button.visible=not active
	if game.is_style_range():editor_button.hide();roof_button.hide()
	controls_mode=-1;sync_controls()
	game.subtitle.text="蓝军推进 · 占领果园 B 点，或消灭全部敌军" if active else "实弹测试 · 动作检视 · 可破坏场景"
	if game.is_style_range():game.subtitle.text=("荒原墨线" if game.graphic_style else "原版材质")+" · F2 画风对比 · F1 近景 · Tab 配装 / 试驾"
	game.subtitle.text="v%s · %s 启动 · %s"%[game.BUILD_VERSION,game.launch_time,game.subtitle.text]
	game.subtitle.tooltip_text="启动 %s · PID %s"%[game.launch_stamp,OS.get_process_id()]
	result_panel.hide()

func rebuild_world():
	objective_views=[];control_ring=null
	if not game.world.campaign_active():return
	control_ring=Art.ring(game.stage,Vector3.ZERO,.48,Art.BLUE.lightened(.2),.025)
	for point in game.world.campaign.points:
		var at: Vector2=point.position
		var ring=Art.ring(game.stage,Vector3(at.x,game.world.terrain.height(at)+.045,at.y),float(point.radius),Color("dfc78d"),.055)
		var material=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("dfc78d");ring.material_override=material
		var marker=Label3D.new();marker.text="B · 果园";marker.font_size=48;marker.pixel_size=.015;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.no_depth_test=true
		marker.font=game.ui.theme.default_font
		game.stage.add_child(marker);marker.position=Vector3(at.x,game.world.terrain.height(at)+3.3,at.y)
		marker.layers=0
		var label_batch=preload("res://scripts/objective_label_batch.gd").new();label_batch.game=game;label_batch.source=marker;game.stage.add_child(label_batch)
		objective_views.append({"point":point,"ring":ring,"material":material,"marker":marker,"label_batch":label_batch})
	refresh()

func sync_controls():
	if controls==null:return
	var mounted: int=game.world.player.mounted
	var mode=0 if mounted<0 else 2 if game.world.vehicles[mounted].emplacement else 1
	if mode==controls_mode:return
	controls_mode=mode
	if mode==1:controls.text="W/S 前进 / 制动倒车   A/D 左右转向   Shift 加速   空格 手刹漂移   左键 射击   右键 聚焦   数字 / 滚轮 换武器   G 轮盘   R 装填   F 下车"
	elif mode==2:controls.text="鼠标 瞄准   左键 射击   右键 聚焦   数字 / 滚轮 换武器   G 轮盘   R 装填   F 离开操作位"
	else:controls.text="WASD 移动   Shift 快跑   空格 跳跃 / 翻越   C 蹲伏   Z 卧倒   左键 射击   右键 聚焦   数字 / 滚轮 换武器   G 轮盘   5 医疗   R 换弹   E 交互   F 上下车"

func refresh():
	sync_controls()
	if not game.world.campaign_active():return
	var campaign=game.world.campaign;var counts=campaign.active_counts();var reserves=campaign.reserves
	var point: Dictionary=campaign.points[0] if not campaign.points.is_empty() else {}
	var occupation=""
	if not point.is_empty():
		var owner=int(point.owner)
		occupation="争夺中" if point.contested else "蓝军控制" if owner==0 else "红军控制" if owner==1 else "蓝军占领中" if point.progress>.001 else "红军占领中" if point.progress<-.001 else "中立"
		occupation+=" · %d%%"%int(absf(point.progress)*100)
		var toward: Vector2=point.position-game.world.player.position
		var bearing=["东","东南","南","西南","西","西北","北","东北"][posmod(int(round(toward.angle()/(PI/4))),8)]
		occupation+=" · %s %d m"%[bearing,int(toward.length())]
	status.text="蓝军 %d / 30  ·  预备 %d     红军 %d / 30  ·  预备 %d\nB 果园：%s"%[counts[0],reserves[0],counts[1],reserves[1],occupation]
	status.text+="\n"+game.world.campaign_director.status_text()
	if not game.world.player.alive and campaign.phase=="playing":status.text+="\n倒地 · 正在接管存活队友"
	elif game.paused and campaign.phase=="playing":status.text+="\n已暂停 · Esc 继续"
	elif game.armory.visible:status.text+="\n装备面板已暂停战斗"
	if is_instance_valid(control_ring):
		var unit: Dictionary=game.world.player
		control_ring.visible=unit.alive and unit.mounted<0
		control_ring.position=Vector3(unit.position.x,game.world.ground_height(unit.position,.05,unit.elevation+.025)+.035,unit.position.y)
	for view in objective_views:
		var p: Dictionary=view.point;var color=Art.BLUE.lightened(.25) if float(p.progress)>.001 else Art.RED.lightened(.2) if float(p.progress)<-.001 else Color("dfc78d")
		view.material.albedo_color=color;view.marker.modulate=color
		view.marker.text="B · "+("争夺中" if p.contested else "蓝军" if int(p.owner)==0 else "红军" if int(p.owner)==1 else "果园")
	if game.armory.visible:
		briefing.text="占领 B 点，或耗尽敌方兵力。\n"+status.text+"\n阵亡后沿用被接管队友的装备和弹药。"
		var loadout: Array=game.world.player.get("quick_slots",[]).duplicate()
		loadout.append(game.world.player.get("quick_tactical",""))
		var owned: Array=game.world.player.get("quick_owned",[])
		var signature=JSON.stringify(owned)
		if signature!=cached_equipment:
			cached_equipment=signature
			for i in range(4):
				var choices: OptionButton=slot_choices[i];choices.clear()
				if i<3:choices.add_item("空位");choices.set_item_metadata(0,"")
				for id in owned:
					var w: Dictionary=game.catalog.weapons[id]
					if game.QuickEquipment.tactical(w)!=(i==3):continue
					choices.add_item(str(w.name));choices.set_item_metadata(choices.item_count-1,id)
		for i in range(4):
			slots[i].disabled=i>=loadout.size() or str(loadout[i]).is_empty() or game.world.player.mounted>=0 or not game.world.player.alive
			slots[i].text="%d   %s%s"%[i+1,str(game.catalog.weapons.get(loadout[i],{}).get("name","空位")) if i<loadout.size() else "空位","  ◀" if i<loadout.size() and game.world.player.weapon_id==loadout[i] and not game.world.player.get("holstered",false) else ""]
			slot_choices[i].disabled=game.world.player.mounted>=0 or not game.world.player.alive
			for n in range(slot_choices[i].item_count):
				if str(slot_choices[i].get_item_metadata(n))==str(loadout[i]):slot_choices[i].select(n);break
	if campaign.phase!="playing":
		if not result_panel.visible:
			game.paused=true;game.world.cancel_firing();game.trigger_pressed=false;game.jump_pressed=false
			if game.scope_view!=null:game.scope_view.cancel()
			game.armory.hide()
		result_title.text="第一关 · 胜利" if campaign.phase=="won" else "第一关 · 战败"
		result_detail.text=("果园阵地已夺取。" if int(point.get("owner",-1))==0 else "敌军兵力已耗尽。") if campaign.phase=="won" else "没有存活的蓝军队友可供接管。"
		result_detail.text+="\n蓝军在场 %d · 预备 %d\n红军在场 %d · 预备 %d"%[counts[0],reserves[0],counts[1],reserves[1]]
		result_panel.show()
