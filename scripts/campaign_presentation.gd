extends RefCounted
## Campaign UI lives in the existing proving ground and reads the rule state.
const Art=preload("res://scripts/ink_art.gd")
var game
var hud_summary: Dictionary={}
var summary_age=0.0
var hud_counts: Array=[0,0]
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
var result_restart_button: Button
var result_next_button: Button
var equipment_heading: Label
var title: Label
var controls: Label
var controls_mode=-1
var armory_button: Button
var editor_button: Button
var roof_button: Button
var objective_views: Array=[]
var control_ring: Node3D
var plan_choice: OptionButton

func build(host,training: VBoxContainer,parent: VBoxContainer):
	game=host;training_box=training
	equipment_box=VBoxContainer.new();parent.add_child(equipment_box);equipment_box.add_theme_constant_override("separation",10)
	equipment_heading=game.label(equipment_box,"石墙果园 · 随身装备",20)
	configure_equipment_heading(equipment_heading)
	briefing=game.label(equipment_box,"",14);briefing.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;briefing.custom_minimum_size.x=265
	game.label(equipment_box,"进攻战术 · 开战前选择，战斗中修改下局生效",14)
	plan_choice=OptionButton.new();equipment_box.add_child(plan_choice);plan_choice.focus_mode=Control.FOCUS_NONE
	for id in preload("res://scripts/campaign_plan.gd").NAMES:
		plan_choice.add_item(id+" · "+preload("res://scripts/campaign_plan.gd").NAMES[id]);plan_choice.set_item_metadata(plan_choice.item_count-1,id)
	plan_choice.item_selected.connect(func(index):
		if game.lan!=null and game.lan.is_client():return
		var id=str(plan_choice.get_item_metadata(index));game.plan.godot3d.campaign_tactic=id
		if game.world.time<.001:game.world.campaign_director.plan_executor.select(id)
		game.get_viewport().gui_release_focus())
	for i in range(4):
		var index=i
		var row=HBoxContainer.new();equipment_box.add_child(row)
		var item=game.button(row,"",func():game.equip_campaign_slot(index))
		item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		item.alignment=HORIZONTAL_ALIGNMENT_LEFT;slots.append(item)
		var choices=OptionButton.new();choices.custom_minimum_size.x=95;choices.focus_mode=Control.FOCUS_NONE;row.add_child(choices);slot_choices.append(choices)
		choices.item_selected.connect(func(choice):
			var id=str(choices.get_item_metadata(choice))
			if game.lan!=null and game.lan.is_client():
				if id.is_empty():game.lan.request_action("clear_slot",index)
				else:game.lan.request_action("assign",{"id":id,"slot":index})
			elif id.is_empty():game.world.clear_quick_slot(index)
			else:game.world.assign_quick_weapon(id,index)
			game.update_weapon_details();game.get_viewport().gui_release_focus())
	game.label(equipment_box,"1–3 武器 · 4 战术 · 5 医疗\n按住 G 轮盘 · R 装填 · F 载具\nTab 关闭面板后继续战斗",14)
	game.button(equipment_box,"继续战斗  Tab",func():game.toggle_armory())
	status=game.label(game.debug_ui.overview,"",14);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	result_panel=game.make_panel(game.ui,Vector2(-250,-190),Vector2(500,380))
	result_panel.anchor_left=.5;result_panel.anchor_right=.5;result_panel.anchor_top=.5;result_panel.anchor_bottom=.5
	var box=VBoxContainer.new();result_panel.add_child(box);box.add_theme_constant_override("separation",14)
	result_title=game.label(box,"",30);result_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;result_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result_detail=game.label(box,"",16);result_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result_next_button=game.button(box,"下一关",func():game.next_campaign_chapter())
	result_restart_button=game.button(box,"重新开始  F5",func():game.reset_range())
	game.button(box,"返回战役章节",func():game.show_campaign_chapters())
	game.button(box,"返回联合演武场",func():game.start_training())
	game.ui.resized.connect(layout_result);layout_result()
	result_panel.hide();sync_mode();rebuild_world()

func sync_mode():
	var active=game.world.campaign_active()
	training_box.visible=not active;equipment_box.visible=active;status.visible=active
	if title!=null:title.text="小小战地  /  "+str(game.plan.title) if active else "小小战地  /  林地前哨" if game.plan.get("godot3d",{}).get("terrain_review",false) else "小小战地  /  联合演武场"
	if title!=null and game.is_style_range():title.text="小小战地  /  演武场2 · 荒原墨线"
	if armory_button!=null:armory_button.text="随身装备  Tab" if active else "武器 / 载具  Tab"
	if editor_button!=null:editor_button.visible=not active
	if roof_button!=null:roof_button.visible=not active
	if game.is_style_range():editor_button.hide();roof_button.hide()
	controls_mode=-1;summary_age=0;hud_summary.clear()
	equipment_heading.text=str(game.plan.get("title","石墙果园"))+" · 随身装备"
	var tactic_names=preload("res://scripts/campaign_plan.gd").names_for(game.plan)
	for index in range(plan_choice.item_count):
		var id=str(plan_choice.get_item_metadata(index));plan_choice.set_item_text(index,id+" · "+str(tactic_names.get(id,id)))
	game.subtitle.text=game.world.campaign.objective_text() if active else "实弹测试 · 动作检视 · 可破坏场景"
	if game.is_style_range():game.subtitle.text=("荒原墨线" if game.graphic_style else "原版材质")+" · F2 画风对比 · F1 近景 · Tab 配装 / 试驾"
	game.subtitle.text="v%s · %s 启动 · %s"%[game.BUILD_VERSION,game.launch_time,game.subtitle.text]
	game.subtitle.tooltip_text="启动 %s · PID %s"%[game.launch_stamp,OS.get_process_id()]
	result_panel.hide()

func rebuild_world():
	for view in objective_views:
		if is_instance_valid(view.flag):view.flag.queue_free()
	if is_instance_valid(control_ring):control_ring.queue_free()
	objective_views=[];control_ring=null
	if not game.world.campaign_active():return
	control_ring=Art.ring(game.stage,Vector3.ZERO,.48,Art.BLUE.lightened(.2),.025)
	for point in game.world.campaign.points:
		var flag=preload("res://scripts/objective_flag.gd").new();game.stage.add_child(flag);flag.build(game,point)
		objective_views.append({"point":point,"flag":flag})
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

func refresh(delta: float=0):
	if not game.world.campaign_active():return
	var campaign=game.world.campaign;var reserves=campaign.reserves
	summary_age-=delta
	var update_summary=summary_age<=0 or hud_summary.is_empty() or delta==0
	if update_summary:hud_counts=campaign.active_counts();summary_age=.1
	var counts=hud_counts
	var point: Dictionary=campaign.points[0] if not campaign.points.is_empty() else {}
	if update_summary:
		var occupation="B · 果园"
		if not point.is_empty():
			occupation=str(point.get("label","B"))+" · "+preload("res://scripts/capture_zone.gd").state(point)
			occupation+="  %d%%"%int(absf(point.progress)*100)
			var toward: Vector2=point.position-game.world.player.position
			var bearing=["东","东南","南","西南","西","西北","北","东北"][posmod(int(round(toward.angle()/(PI/4))),8)]
			occupation+="  ·  %s %d m"%[bearing,int(toward.length())]
		if not campaign.mission.is_empty():occupation=campaign.objective_text()+" · "+occupation
		hud_summary={"remaining":[counts[0]+reserves[0],counts[1]+reserves[1]],"total":[int(game.plan.deployment.blue.totalForce),int(game.plan.deployment.red.totalForce)],"objective":occupation}
		if not point.is_empty():
			hud_summary.capture={"label":point.label,"name":point.name,"progress":absf(float(point.progress)),"state":preload("res://scripts/capture_zone.gd").state(point),"color":preload("res://scripts/capture_zone.gd").color(point),"inside":preload("res://scripts/capture_zone.gd").contains(point,game.world.player.position,game.world.player.elevation),"distance":int(game.world.player.position.distance_to(point.position)),"contested":point.contested}
		if not point.is_empty() and not campaign.mission.is_empty():
			var mission_stage=campaign.current_stage()
			hud_summary.capture.name="%d/%d %s"%[campaign.stage_index+1,campaign.mission.stages.size(),point.name]
			if str(mission_stage.get("mode","capture"))=="hold" and point.owner==0:
				hud_summary.capture.state=("争夺 · " if point.contested else "守住 · ")+"%d/%d 秒"%[int(campaign.hold_elapsed),int(mission_stage.get("holdSeconds",0))]
		if game.debug_open() and game.debug_ui.tabs.current_tab==0:
			status.text="蓝军在场 %d / %d · 预备 %d\n红军在场 %d / %d · 预备 %d\n%s\n%s"%[counts[0],campaign.maximum[0],reserves[0],counts[1],campaign.maximum[1],reserves[1],occupation,game.world.campaign_director.status_text()]
	if is_instance_valid(control_ring):
		var unit: Dictionary=game.world.player
		control_ring.visible=unit.alive and unit.mounted<0
		control_ring.position=Vector3(unit.position.x,game.world.ground_height(unit.position,.05,unit.elevation+.025)+.035,unit.position.y)
	for view in objective_views:
		if update_summary:view.flag.refresh(game)
	if game.armory.visible:
		plan_choice.disabled=game.lan!=null and game.lan.is_client()
		var chosen=str(game.plan.godot3d.get("campaign_tactic","T01"))
		for index in range(plan_choice.item_count):
			if str(plan_choice.get_item_metadata(index))==chosen:plan_choice.select(index);break
		briefing.text=str(game.plan.godot3d.get("campaign_briefing","占领 B 点，或耗尽敌方兵力。"))+"\n"+campaign.objective_text()+"\n蓝军兵力 %d · 红军兵力 %d\n阵亡后接管存活友军；装备和弹药沿用该士兵。"%[counts[0]+reserves[0],counts[1]+reserves[1]]
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
		game.record_campaign_result()
		var offline=bool(game.plan.godot3d.get("campaign_offline",false)) and (game.lan==null or not game.lan.active())
		var checkpoint=offline and bool(game.plan.godot3d.get("campaign_checkpoint",true))
		var chapter=int(game.plan.godot3d.get("campaign_chapter",1))
		var ending=checkpoint and chapter==10 and campaign.phase=="won"
		result_next_button.visible=checkpoint and campaign.phase=="won"
		result_next_button.text="战役已完成 · 查看章节" if ending else "下一关 · 第 %02d 关"%(chapter+1)
		result_restart_button.disabled=game.lan!=null and game.lan.is_client()
		result_restart_button.text="等待房主重新开始" if result_restart_button.disabled else "重新开始  F5"
		if not result_panel.visible:
			game.paused=true;game.world.cancel_firing();game.trigger_pressed=false;game.jump_pressed=false
			if game.scope_view!=null:game.scope_view.cancel()
			game.armory.hide()
		result_title.text="十章战役 · 完成" if ending else str(game.plan.get("title","第一关"))+(" · 胜利" if campaign.phase=="won" else " · 战败")
		result_detail.text="从果园到村落，十章行动全部完成。\n最终阵地已稳固，战役进度已保存。" if ending else result_reason(str(campaign.phase),str(campaign.reason),point)+("。下一关已解锁。" if checkpoint and campaign.phase=="won" else "")
		if offline and not checkpoint:result_detail.text+="\n此关尚未解锁；直接启动的结果不计入战役进度。"
		if checkpoint and game.campaign_progress.dirty:result_detail.text=result_detail.text.replace("战役进度已保存。","进度尚未保存。")+"\n"+game.campaign_progress.last_error
		result_detail.text+="\n蓝军在场 %d · 预备 %d\n红军在场 %d · 预备 %d"%[counts[0],reserves[0],counts[1],reserves[1]]
		result_panel.show()

static func result_reason(phase: String,reason: String,point: Dictionary) -> String:
	if not reason.is_empty():return reason
	if phase=="won":return "阵地已夺取" if int(point.get("owner",-1))==0 else "敌军兵力已耗尽"
	if phase=="lost":return "没有存活的蓝军队友可供接管"
	return ""

static func configure_equipment_heading(heading: Label) -> void:
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size.x=265
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL

func layout_result():
	var width=minf(500,maxf(250,game.ui.size.x-32))
	result_panel.offset_left=-width*.5;result_panel.offset_right=width*.5
