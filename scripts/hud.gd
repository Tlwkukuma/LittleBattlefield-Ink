extends Control

const Tactical=preload("res://scripts/tactical_ui.gd")
const INK = Tactical.INK
const MUTED = Tactical.MUTED
const BLUE = Color("91b9ff")
const RED = Color("df97a2")
const PAPER = Tactical.PANEL
var perf = ""
var roof_label = "自动切顶"
var room_label = ""
var room_preview = false
var world
var camera: Camera3D
var paused = false
var inspection = false
var font = Tactical.font_resource()
var toast = "沿街口推进 · 石墙可以击碎"
var toast_time = 5.0
var hit_time = 0.0
var clock = 0.0

func _ready() -> void:
	Tactical.apply(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	clock += delta
	toast_time = maxf(0.0,toast_time-delta)
	hit_time = maxf(0.0,hit_time-delta)
	queue_redraw()

func notify(message: String) -> void:
	toast = message
	toast_time = 3.0

func panel(rect: Rect2, color: Color = PAPER, border: Color = Tactical.BORDER) -> void:
	draw_rect(Rect2(rect.position+Vector2(3,4),rect.size),Color(0.18,0.22,0.28,0.10))
	draw_rect(rect,color)
	draw_rect(rect,border,false,1)

func text(at: Vector2, value: String, size_px: int, color: Color = INK) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func centered(y: float, value: String, size_px: int, color: Color = INK) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	text(Vector2((1440-width)/2,y),value,size_px,color)

func _draw() -> void:
	if world == null:
		return
	var scale_factor = size / Vector2(1440,900)
	draw_set_transform(Vector2.ZERO,0,scale_factor)
	if inspection:
		panel(Rect2(38,36,600,88))
		text(Vector2(58,68),"军装细节 · 实时模型",21)
		text(Vector2(58,102),"A / D  转身     空格  迈步   R  换弹   滚轮  缩放   F1  返回",14,MUTED)
		return
	# Thin drafting border and quiet editorial labels.
	# The reference uses floating charcoal panels, without a surrounding dashboard frame.
	panel(Rect2(38,36,315,106))
	draw_rect(Rect2(38,36,5,106),BLUE)
	text(Vector2(59,64),"LITTLE BATTLEFIELD  /  GODOT",11,MUTED)
	text(Vector2(57,103),"小小战地",30)
	text(Vector2(59,127),"墨线街区     /     F1 查看人物细节",12,MUTED)
	panel(Rect2(1089,36,313,106))
	text(Vector2(1108,62),"OPERATION 01",11,MUTED)
	text(Vector2(1108,91),"灰桥街区",23)
	var seconds = int(world.elapsed)
	text(Vector2(1108,125),"夺回信号站",13)
	text(Vector2(1325,125),"%02d:%02d" % [seconds/60,seconds%60],13,MUTED)
	panel(Rect2(516,36,408,67))
	var remaining = world.enemies_alive()
	var mission = "50 vs 50 · 持续交战 / 两秒复活" if world.crowd else ("清除街区守军" if remaining > 0 else "进入旗圈 · 占领信号站")
	if room_preview: mission="室内漫游 · WASD 进出南北门"
	text(Vector2(537,63),mission,17)
	if room_preview:
		text(Vector2(537,86),"F3 比较屋顶显示     F4 返回战场",12,MUTED)
	elif world.crowd:
		var allies=world.units.filter(func(u):return u.alive and u.team==0).size()
		text(Vector2(537,86),"蓝方  %d / 50" % allies,12,BLUE)
		text(Vector2(775,86),"红方  %d / 50" % remaining,12,RED)
	else:
		for i in range(5):
			draw_circle(Vector2(544+i*18,83),3.5,RED if i < remaining else Color("c4c7c2"))
		text(Vector2(775,86),"守军  %d / 5" % remaining,12,MUTED)
	panel(Rect2(38,150,540,65))
	text(Vector2(54,173),perf,13,MUTED)
	text(Vector2(54,199),"F2 百人战场   F3 "+roof_label+"   F4 室内查看",13)
	if not room_label.is_empty(): centered(738,room_label,15,BLUE)
	minimap()
	# Health and squad.
	panel(Rect2(38,764,289,98))
	draw_rect(Rect2(54,782,30,30),BLUE)
	text(Vector2(62,804),"01",13,PAPER)
	text(Vector2(98,797),"突击兵",19)
	text(Vector2(99,816),"蓝方 / ALPHA",10,MUTED)
	var health_ratio = clampf(float(world.player.health)/160.0,0,1)
	draw_rect(Rect2(55,834,196,7),Color("d4d6cf"))
	draw_rect(Rect2(55,834,196*health_ratio,7),BLUE if health_ratio>0.3 else RED)
	text(Vector2(265,843),str(int(world.player.health)),15)
	panel(Rect2(1094,746,308,116))
	text(Vector2(1114,773),"M416",20)
	text(Vector2(1287,771),"5.56 mm",12,MUTED)
	if world.player.reload > 0:
		text(Vector2(1115,808),"换弹中…",23,BLUE)
		var ratio = 1.0-float(world.player.reload)/float(world.weapon.reload)
		draw_rect(Rect2(1116,823,160,4),Color("c4c9c9"))
		draw_rect(Rect2(1116,823,160*ratio,4),BLUE)
	else:
		text(Vector2(1113,816),"%02d" % int(world.player.ammo),34)
		text(Vector2(1174,813),"/ %03d" % int(world.player.reserve),17,MUTED)
	text(Vector2(1294,845),"R  换弹",12,MUTED)
	text(Vector2(1115,846),"全自动",11,MUTED)
	panel(Rect2(378,818,684,44),Tactical.SURFACE)
	text(Vector2(396,846),"W A S D  移动     鼠标  瞄准     左键  射击     R  换弹     滚轮  缩放     Esc  暂停",12)
	if toast_time > 0 and world.result.is_empty():
		centered(788,toast,15,INK)
	if remaining == 0 and world.result.is_empty() and not room_preview:
		panel(Rect2(553,125,334,51))
		var progress = world.capture/float(world.definition.capture_seconds)
		text(Vector2(570,149),"占领进度",12,BLUE)
		draw_rect(Rect2(570,159,300,4),Color("c5ccc9"))
		draw_rect(Rect2(570,159,300*progress,4),BLUE)
	world_labels(scale_factor)
	if world.result.is_empty() and not paused:
		var mouse = get_local_mouse_position() / scale_factor
		var color = RED if hit_time > 0 else INK
		for dir in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
			draw_line(mouse+dir*5,mouse+dir*12,color,1.5,true)
		draw_circle(mouse,1.6,color)
		if hit_time > 0:
			for dir in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
				draw_line(mouse+dir*9,mouse+dir*14,RED,2,true)
	if not world.result.is_empty():
		result_panel()
	elif paused:
		draw_rect(Rect2(0,0,1440,900),Color(0.15,0.20,0.26,0.38))
		panel(Rect2(520,350,400,180))
		centered(408,"战斗已暂停",28)
		centered(454,"Esc  继续战斗",16,MUTED)
		centered(490,"F5  重新开始",13,MUTED)

func minimap() -> void:
	var rect = Rect2(1224,160,178,158)
	panel(rect,Tactical.PANEL)
	text(Vector2(1238,181),"战术示意",10,MUTED)
	var origin = Vector2(1312,247)
	var factor = 3.8
	for o in world.obstacles:
		if o.alive:
			draw_rect(Rect2(origin+(o.position-o.size*0.5)*factor,o.size*factor),Color("b4adbf"))
	draw_circle(origin+world.objective*factor,9,Color(0.3,0.4,0.55,0.12))
	draw_arc(origin+world.objective*factor,9,0,TAU,24,BLUE,1,true)
	for u in world.units:
		if u.alive:
			draw_circle(origin+u.position*factor,3.3 if u.player else 2,BLUE if u.team == 0 else RED)

func world_labels(scale_factor: Vector2) -> void:
	if camera == null:
		return
	for u in world.units:
		if not u.alive:
			continue
		var location = camera.unproject_position(Vector3(u.position.x,2.0,u.position.y))/scale_factor
		if u.player:
			text(location+Vector2(-11,-3),"你",12,BLUE)
		elif u.team == 1:
			draw_rect(Rect2(location+Vector2(-12,0),Vector2(24,3)),Color("d2c9c0"))
			draw_rect(Rect2(location+Vector2(-12,0),Vector2(24*float(u.health)/84.0,3)),RED)
	var flag = camera.unproject_position(Vector3(world.objective.x,3.4,world.objective.y))/scale_factor
	draw_circle(flag+Vector2(0,-3),13,BLUE if world.enemies_alive()==0 else RED)
	text(flag+Vector2(-5,2),"A",13,PAPER)

func result_panel() -> void:
	var won = world.result == "victory"
	draw_rect(Rect2(0,0,1440,900),Color(0.16,0.20,0.26,0.38))
	panel(Rect2(480,262,480,345))
	draw_rect(Rect2(480,262,480,6),BLUE if won else RED)
	centered(315,"OPERATION COMPLETE" if won else "OPERATION FAILED",12,MUTED)
	centered(373,"街区已控制" if won else "行动失利",38,BLUE if won else RED)
	centered(414,"信号站已重新上线。" if won else "利用墙角与队友推进，再试一次。",16)
	centered(459,"击倒 %d   ·   破坏掩体 %d   ·   用时 %d 秒" % [world.kills,world.broken,int(world.elapsed)],14,MUTED)
	draw_rect(Rect2(544,497,352,52),BLUE)
	centered(530,"Enter / R   再来一局",18,PAPER)
	centered(582,"最小循环  /  移动 · 射击 · 破坏 · 占领",12,MUTED)
