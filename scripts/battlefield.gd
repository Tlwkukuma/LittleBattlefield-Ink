extends Node3D

const Sim = preload("res://scripts/simulation.gd")
const Art = preload("res://scripts/ink_art.gd")
const Motion = preload("res://scripts/soldier_motion.gd")
const Batch = preload("res://scripts/mesh_batch.gd")
const Hud = preload("res://scripts/hud.gd")
var sim = Sim.new()
var level: Dictionary
var weapon: Dictionary
var camera: Camera3D
var hud: Control
var stage: Node3D
var actor_views: Dictionary = {}
var wall_views: Dictionary = {}
var houses: Array = []
var effects: Array = []
var flag: Node3D
var flag_cloth: Node3D
var objective_ring: MeshInstance3D
var paused = false
var zoom_goal = 24.5
var time = 0.0
var rng = RandomNumberGenerator.new()
var qa_mode = false
var qa_frames = 0
var qa_capture = ""
var closeup = false
var qa_walk = false
var inspection = false
var inspection_walk = false
var inspect_at_start = false
var sound_player: AudioStreamPlayer
var sounds: Dictionary = {}
var music_on = true
var crowd_mode = false
var roof_mode = 0
var benchmark = false
var simulation_ms = 0.0
var animation_ms = 0.0
var perf_clock = 0.0
var room_preview = false
var rooms_at_start = false

func _ready() -> void:
	level = JSON.parse_string(FileAccess.get_file_as_string("res://data/street.json"))
	weapon = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapon.json"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			qa_capture = arg.trim_prefix("--capture=")
		if arg == "--qa-scene":
			qa_mode = true
		if arg == "--closeup":
			closeup = true
		if arg == "--qa-walk":
			qa_walk = true
		if arg == "--crowd":
			crowd_mode=true
		if arg == "--rooms":
			rooms_at_start=true
		if arg == "--inspect":
			inspect_at_start = true
	rng.seed = int(level.seed)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a8a7b0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e5e2e0")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_color = Color("efeee1")
	sun.light_energy = 0.8
	sun.shadow_enabled = false
	sun.directional_shadow_max_distance = 90
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom_goal
	camera.position = Vector3(0,32,32)
	camera.far = 150
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.camera = camera
	hud.world = sim
	sim.shot.connect(on_shot)
	sim.impact.connect(on_impact)
	sim.wall_broken.connect(on_wall_broken)
	sim.unit_died.connect(on_unit_died)
	sim.finished.connect(on_finished)
	sound_player = AudioStreamPlayer.new()
	sound_player.max_polyphony = 8
	sound_player.volume_db = -15
	add_child(sound_player)
	make_sounds()
	var requested_closeup = closeup
	reset_match()
	closeup=requested_closeup
	if qa_mode:
		for u in sim.units:
			u.facing = Vector2(-0.75,-0.65) if u.team==0 else Vector2(-0.55,0.85)
		update_views(0)
	if closeup:
		hud.visible = false
		zoom_goal = 5.5
		camera.size=zoom_goal
		if qa_mode:
			sim.units[0].position=Vector2(0,4)
			sim.units[1].position=Vector2(-2.6,4)
			sim.units[2].position=Vector2(2.6,4)
		sim.units[0].facing=Vector2(0.45,0.9).normalized()
		sim.units[1].facing=Vector2(-0.75,-0.65).normalized()
		sim.units[2].facing=Vector2(0.98,-0.18).normalized()
		update_views(0)
		camera.position=Vector3(sim.player.position.x,32.75,sim.player.position.y+32)
		camera.look_at(Vector3(sim.player.position.x,0.75,sim.player.position.y))
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if inspect_at_start:
		toggle_inspection()
		sim.player.facing=Vector2(0.45,0.9).normalized()
	if rooms_at_start:
		enter_room_preview()

func reset_match() -> void:
	if is_instance_valid(stage):
		stage.free()
	stage = Node3D.new()
	add_child(stage)
	actor_views.clear()
	wall_views.clear()
	houses.clear()
	effects.clear()
	rng.seed = int(level.seed)
	level.crowd=crowd_mode
	sim.setup(level,weapon)
	paused = false
	inspection = false
	room_preview = false
	hud.room_preview = false
	closeup = false
	if is_instance_valid(hud):
		hud.inspection = false
		hud.visible = true
	zoom_goal=30.0 if crowd_mode else 24.5
	hud.paused = false
	hud.notify("50 vs 50 · 阵亡两秒后复活 · F2 切换小队模式" if crowd_mode else "房屋南北门均可进入 · F3 切换屋顶显示")
	var ground=Node3D.new()
	stage.add_child(ground)
	var saved_stage=stage
	stage=ground
	build_ground()
	build_props()
	Batch.collapse(ground)
	stage=saved_stage
	for item in level.buildings:
		houses.append(Art.building(stage,item))
	for item in level.walls:
		wall_views[str(item.id)] = Art.wall(stage,item)
		Batch.collapse(wall_views[str(item.id)])
	for point in level.trees:
		var tree_group=Node3D.new()
		stage.add_child(tree_group)
		Art.tree(tree_group,Sim.vec(point),rng)
		Batch.collapse(tree_group)
	for point in level.crates:
		Art.crate(stage,Sim.vec(point))
	for u in sim.units:
		actor_views[u.id] = Art.soldier(stage,int(u.team),bool(u.player),bool(u.player) or not crowd_mode)
	build_flag()
	update_views(0.0)

func build_ground() -> void:
	Art.box(stage,Vector3(0,-0.12,0),Vector3(85,0.15,75),Color("a8a7b0"),false)
	Art.box(stage,Vector3(0,-0.018,0),Vector3(34,0.03,26),Color("c7c3ce"),false)
	# Two roads, bordered sidewalks and a cobbled intersection.
	Art.box(stage,Vector3(0,0.006,0),Vector3(9.4,0.02,60),Color("a4a6b3"),false)
	Art.box(stage,Vector3(0,0.012,4),Vector3(75,0.02,4.8),Color("a4a6b3"),false)
	for x in [-5.05,5.05]:
		for z in [-5.9,10.0]:
			Art.box(stage,Vector3(x,0.055,z),Vector3(0.60,0.12,13.8 if z<0 else 5.8),Color("d4d0dc"))
	for z in [1.35,6.65]:
		Art.box(stage,Vector3(-11,0.055,z),Vector3(12,0.12,0.45),Color("d4d0dc"))
		Art.box(stage,Vector3(11,0.055,z),Vector3(12,0.12,0.45),Color("d4d0dc"))
	for z in range(-12,13,2):
		if z >= 2 and z <= 6:
			continue
		Art.box(stage,Vector3(0,0.03,z),Vector3(0.065,0.014,0.75),Color("d8d2df"),false)
	for i in range(1450):
		var x = rng.randf_range(-16.8,16.8)
		var z = rng.randf_range(-12.8,12.8)
		var len = rng.randf_range(0.08,0.40)
		Art.line(stage,Vector3(x,0.037,z),Vector3(x+len,0.037,z+len*0.18),Color("8d879d").lightened(rng.randf_range(0.24,0.45)))
	for z in range(-12,13):
		Art.line(stage,Vector3(-5.34,0.12,z),Vector3(-4.74,0.12,z),Color("a6aaa3"))
		Art.line(stage,Vector3(4.74,0.12,z),Vector3(5.34,0.12,z),Color("a6aaa3"))
	# Grass tufts at the margins, deliberately kept out of the aiming area.
	for i in range(75):
		var x = rng.randf_range(6,16.5) * (-1 if i%2==0 else 1)
		var z = rng.randf_range(-12,12)
		for j in range(3):
			Art.line(stage,Vector3(x,0.04,z),Vector3(x+(j-1)*0.12,0.24+rng.randf()*0.15,z+0.03),Color("81788e"))

func build_flag() -> void:
	flag = Node3D.new()
	flag.position = Vector3(sim.objective.x,0,sim.objective.y)
	stage.add_child(flag)
	objective_ring = Art.ring(flag,Vector3(0,0.045,0),2.7,Color("9c7272"),0.055)
	Art.ring(flag,Vector3(0,0.045,0),2.85,Color(0.45,0.35,0.40,0.18),0.018)
	Art.box(flag,Vector3(0,0.08,0),Vector3(0.9,0.16,0.9),Color("bbbcb1"))
	Art.cylinder(flag,Vector3(0,1.4,0),0.048,2.8,Art.INK)
	Art.sphere(flag,Vector3(0,2.84,0),0.09,Color("c3b28b"))
	flag_cloth = Art.box(flag,Vector3(0.57,2.4,0),Vector3(1.10,0.61,0.025),Art.RED,false)
	Art.box(flag,Vector3(-0.54,0.38,-0.18),Vector3(0.55,0.70,0.40),Color("717f83"))
	Art.line(flag,Vector3(-0.53,0.7,-0.18),Vector3(-0.61,1.5,-0.18))

func build_props() -> void:
	for p in [Vector3(-5.8,0,7),Vector3(5.8,0,-10.5)]:
		Art.cylinder(stage,p+Vector3(0,1.5,0),0.055,3,Art.INK)
		Art.box(stage,p+Vector3(0.24,3,0),Vector3(0.6,0.055,0.055),Art.INK)
		Art.box(stage,p+Vector3(0.48,2.86,0),Vector3(0.33,0.23,0.33),Color("dbd4b7"))
	# Parked utility truck: scenery for checking the vehicle art direction.
	var truck = Node3D.new()
	truck.position = Vector3(-11,0,4.1)
	truck.rotation.y = -0.25
	stage.add_child(truck)
	Art.box(truck,Vector3(0,0.66,0),Vector3(1.6,0.5,3.0),Color("bfc0d1"))
	Art.box(truck,Vector3(0,1.17,-0.65),Vector3(1.52,0.63,1.2),Color("e4e1eb"))
	Art.box(truck,Vector3(0,1.28,-1.26),Vector3(1.29,0.35,0.025),Color("514963"))
	Art.box(truck,Vector3(0,1.28,-1.285),Vector3(0.055,0.38,0.035),Art.PAPER)
	Art.box(truck,Vector3(0,0.99,0.88),Vector3(1.45,0.25,1.18),Color("a9a4bd"))
	Art.box(truck,Vector3(0,0.92,0.92),Vector3(1.28,0.06,1.0),Color("68627b"))
	for x in [-0.78,0.78]:
		Art.box(truck,Vector3(x,0.94,0.75),Vector3(0.055,0.49,1.45),Color("c9c4d6"))
		Art.box(truck,Vector3(x,0.67,-0.4),Vector3(0.04,0.16,1.6),Art.BLUE)
		for z in [-0.9,-0.72,-0.54,-0.36]:
			Art.line(truck,Vector3(x,0.88,z),Vector3(x,1.04,z),Art.INK)
	for i in range(10):
		Art.line(truck,Vector3(-0.6+i*0.13,0.59,-1.515),Vector3(-0.6+i*0.13,0.80,-1.515),Art.INK)
	for x in [-0.6,0.6]:
		Art.sphere(truck,Vector3(x,0.8,-1.55),0.095,Art.PAPER)
	for x in [-0.79,0.79]:
		for z in [-0.91,0.91]:
			var wheel = Art.cylinder(truck,Vector3(x,0.40,z),0.36,0.23,Art.INK)
			wheel.rotation.z = PI/2
	for z in [-11.8,11.8]:
		for x in [-15.5,15.5]:
			Art.box(stage,Vector3(x,0.25,z),Vector3(0.3,0.5,0.3),Art.STONE)

func _physics_process(delta: float) -> void:
	if qa_mode or paused:
		return
	var movement = Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var started=Time.get_ticks_usec()
	sim.step(delta,movement,mouse_aim(),Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	simulation_ms=(Time.get_ticks_usec()-started)/1000.0

func mouse_aim() -> Vector2:
	var mouse = get_viewport().get_mouse_position()
	# Acquire the visible soldier silhouette before intersecting the weapon-height plane.
	for u in sim.units:
		if u.team != 1 or not u.alive:
			continue
		var center = camera.unproject_position(Vector3(u.position.x,1.2,u.position.y))
		if mouse.distance_to(center) < 19.0 * 24.5/camera.size:
			return u.position
	var origin = camera.project_ray_origin(mouse)
	var direction = camera.project_ray_normal(mouse)
	var t = (1.355-origin.y)/direction.y
	var p = origin+direction*t
	return Vector2(p.x,p.z)

func _process(delta: float) -> void:
	time += delta
	qa_frames += 1
	if qa_walk:
		for u in sim.units:
			u.walk=1.15+float(u.id)*1.2
			u.velocity=Vector2(2.2,0)
	if inspection:
		var turn = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
		sim.player.facing=sim.player.facing.rotated(turn*delta*1.8)
		sim.player.velocity=Vector2(2.3,0) if inspection_walk else Vector2.ZERO
		if inspection_walk:
			sim.player.walk+=delta*2.3*TAU/1.67
		if sim.player.reload>0:
			sim.player.reload=maxf(0,sim.player.reload-delta)
			if sim.player.reload==0:
				var amount=mini(int(weapon.mag)-int(sim.player.ammo),int(sim.player.reserve))
				sim.player.ammo+=amount
				sim.player.reserve-=amount
	if not paused or inspection:
		var started=Time.get_ticks_usec()
		update_views(delta)
		animation_ms=(Time.get_ticks_usec()-started)/1000.0
		update_effects(delta)
	camera.size = lerpf(camera.size,zoom_goal,1.0-exp(-delta*10))
	var focus = Vector3.ZERO
	if camera.size < 22:
		focus = Vector3(sim.player.position.x*0.4,0,sim.player.position.y*0.4)
	if closeup:
		focus = Vector3(sim.player.position.x,0.75,sim.player.position.y)
	camera.position = camera.position.lerp(focus+Vector3(0,32,32),1.0-exp(-delta*4))
	camera.look_at(focus)
	perf_clock+=delta
	if perf_clock>.35:
		perf_clock=0
		hud.perf="%d FPS  |  仿真 %.1f ms  动作 %.1f ms  |  Draw %d" % [Engine.get_frames_per_second(),simulation_ms,animation_ms,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
		if qa_mode and not benchmark: hud.perf="画面检查模式 · 此画面不用于性能采样"
		hud.roof_label=["自动切顶","常驻无顶","屋顶淡化"][roof_mode]
	if not qa_capture.is_empty() and qa_frames == 12:
		capture_frame.call_deferred()

func update_views(delta: float) -> void:
	for u in sim.units:
		var view: Dictionary = actor_views[u.id]
		view.root.position = Vector3(u.position.x,0,u.position.y)
		if not u.alive:
			view.body.rotation.z = lerp_angle(view.body.rotation.z,PI/2,minf(1,delta*9))
			view.body.position.y = lerpf(view.body.position.y,-0.03,minf(1,delta*9))
			view.muzzle.visible = false
			continue
		# Refresh distant AI poses at 30 Hz, staggered; transforms remain frame-rate smooth.
		var interval=1.0/30 if crowd_mode and not u.player and u.position.distance_squared_to(sim.player.position)>16.0 else 0.0
		view.pose_clock=float(view.get("pose_clock",float(u.id%4)/120.0))+delta
		view.muzzle.visible=u.flash>0
		if delta==0 or view.pose_clock>=interval:
			Motion.update(view,u,float(view.pose_clock) if delta>0 else 0.0,time,float(weapon.reload))
			view.pose_clock=0.0
	update_roofs(delta)
	if is_instance_valid(flag_cloth):
		flag_cloth.rotation.y = sin(time*2.8)*0.08

func update_roofs(delta: float) -> void:
	var room=""
	for house in houses:
		var rectangle=Rect2(house.position-house.size*.5,house.size)
		var inside=rectangle.grow(.20 if house.inside else 0.0).has_point(sim.player.position)
		house.inside=inside
		if inside: room="室内 · 门洞可以通行，墙体仍挡子弹"
		var p=Vector3(sim.player.position.x,1.0,sim.player.position.y)
		var b=house.root.position
		var box=AABB(Vector3(b.x-house.size.x*.5,house.height,b.z-house.size.y*.5),Vector3(house.size.x,1.4,house.size.y))
		var obstructing=box.intersects_segment(camera.position,p)
		var cut=roof_mode==1 or inside or obstructing
		var goal=(.12 if roof_mode==2 else 0.0) if cut else 1.0
		house.fade=move_toward(float(house.fade),goal,delta*5.0) if delta>0 else goal
		house.roof.visible=house.fade>.001
		house.body.visible=house.fade>.001
		for node in house.fade_nodes:
			node.material_override.set_shader_parameter("cutaway_opacity",house.fade)
	hud.room_label=room

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			crowd_mode=not crowd_mode
			reset_match()
		elif event.keycode == KEY_F3:
			roof_mode=(roof_mode+1)%3
			hud.notify("屋顶显示："+["自动切顶","常驻无顶","屋顶淡化"][roof_mode])
		elif event.keycode == KEY_F4:
			if room_preview: reset_match()
			else: enter_room_preview()
		elif event.keycode == KEY_R and inspection:
			sim.player.ammo=15
			sim.start_reload(sim.player)
		elif event.keycode == KEY_F1:
			toggle_inspection()
		elif event.keycode == KEY_SPACE and inspection:
			inspection_walk=not inspection_walk
		elif event.keycode == KEY_ESCAPE and inspection:
			toggle_inspection()
		elif event.keycode == KEY_ESCAPE:
			paused = not paused
			hud.paused = paused
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_HIDDEN
		elif event.keycode == KEY_F5 or ((event.keycode == KEY_R or event.keycode == KEY_ENTER) and not sim.result.is_empty()):
			reset_match()
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		elif event.keycode == KEY_R and not paused:
			if sim.start_reload(sim.player):
				play_sound("reload")
		elif event.keycode == KEY_M:
			music_on = not music_on
			hud.notify("音效已开启" if music_on else "音效已关闭")
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_goal = clampf(zoom_goal-(0.4 if inspection else 1.4),3.5 if inspection else (7 if room_preview else 14),10 if inspection else 32)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_goal = clampf(zoom_goal+(0.4 if inspection else 1.4),3.5 if inspection else (7 if room_preview else 14),10 if inspection else 32)
		elif event.button_index == MOUSE_BUTTON_LEFT and not sim.result.is_empty():
			var mouse = get_viewport().get_mouse_position()/get_viewport().get_visible_rect().size*Vector2(1440,900)
			if Rect2(544,497,352,52).has_point(mouse):
				reset_match()
				Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func toggle_inspection() -> void:
	inspection=not inspection
	closeup=inspection
	paused=inspection
	hud.inspection=inspection
	hud.paused=false
	hud.visible=true
	zoom_goal=5.5 if inspection else (30.0 if crowd_mode else 24.5)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if inspection else Input.MOUSE_MODE_HIDDEN
	if not inspection:
		sim.player.velocity=Vector2.ZERO
		if room_preview:
			closeup=true
			zoom_goal=9.0

func enter_room_preview() -> void:
	room_preview=true
	inspection=false
	closeup=true
	paused=false
	hud.paused=false
	hud.inspection=false
	hud.room_preview=true
	hud.visible=true
	sim.result=""
	for u in sim.units:
		if not u.player:
			u.alive=false
			actor_views[u.id].root.visible=false
	# Disable crowd respawns for this separate, explicitly labelled inspection mode.
	sim.crowd=false
	sim.exploration=true
	sim.player.alive=true
	sim.player.health=160.0
	sim.player.position=Sim.vec(level.buildings[0].position)+Vector2(0,1.0)
	sim.player.facing=Vector2(0,1)
	sim.player.velocity=Vector2.ZERO
	sim.player.requested_velocity=Vector2.ZERO
	sim.build_spatial()
	zoom_goal=9.0
	hud.notify("室内漫游 · WASD 进出门洞 · F3 比较屋顶方案 · F4 返回战场")
	update_views(0)

func on_shot(origin: Vector2, endpoint: Vector2, team: int, unit_id: int) -> void:
	var a = actor_views[unit_id].muzzle.global_position
	# An adjacent wall must still receive the shot before the visual barrel emerges.
	if origin.distance_to(endpoint)<0.5:
		a=Vector3(origin.x,1.355,origin.y)
	var b = Vector3(endpoint.x,1.355,endpoint.y)
	var tracer = Art.line(stage,a,b,Color("fff0ba") if team==0 else Color("d4a598"))
	effects.append({"node":tracer,"life":0.07,"velocity":Vector3.ZERO,"gravity":false})
	play_sound("shot" if team==0 else "enemy")

func on_impact(point: Vector2, kind: String) -> void:
	if kind == "hit":
		hud.hit_time = 0.13
	for i in range(4 if kind=="stone" else 2):
		var p = Vector3(point.x,0.9,point.y)
		var debris = Art.box(stage,p,Vector3.ONE*rng.randf_range(0.04,0.09),Color("d6c9a6") if kind=="stone" else Color("a97073"),false)
		effects.append({"node":debris,"life":0.28,"velocity":Vector3(rng.randf_range(-1,1),rng.randf_range(1,3),rng.randf_range(-1,1)),"gravity":true})

func on_wall_broken(id: String) -> void:
	var wall: Node3D = wall_views[id]
	var at = wall.position
	wall.visible = false
	for i in range(13):
		var debris = Art.box(stage,at+Vector3(rng.randf_range(-0.7,0.7),rng.randf_range(0.2,1.1),rng.randf_range(-0.2,0.2)),Vector3(rng.randf_range(0.12,0.30),0.14,0.2),Art.STONE)
		debris.rotation = Vector3(rng.randf(),rng.randf()*PI,rng.randf())
		effects.append({"node":debris,"life":1.0,"velocity":Vector3(rng.randf_range(-2,2),rng.randf_range(1,4),rng.randf_range(-2,2)),"gravity":true,"rubble":true})
	hud.notify("掩体已击碎 · 通路打开")
	play_sound("break")

func on_unit_died(id: int) -> void:
	if sim.units[id].team==1 and sim.enemies_alive()==0:
		hud.notify("守军已清除 · 进入 A 点完成占领")
		objective_ring.material_override = Art.material(Art.BLUE)
	play_sound("hit")

func on_finished(won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if won:
		flag_cloth.queue_free()
		flag_cloth = Art.box(flag,Vector3(0.57,2.4,0),Vector3(1.1,0.61,0.025),Art.BLUE,false)
	play_sound("win" if won else "break")

func update_effects(delta: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		var effect: Dictionary = effects[i]
		effect.life -= delta
		if effect.gravity:
			effect.velocity.y -= 12*delta
			effect.node.position += effect.velocity*delta
			if effect.node.position.y < 0.10:
				effect.node.position.y = 0.10
				effect.velocity = Vector3.ZERO
		if effect.life <= 0:
			if not effect.get("rubble",false):
				effect.node.queue_free()
			effects.remove_at(i)

func make_sounds() -> void:
	# Original short procedural sounds, no downloaded assets or runtime dependencies.
	for name in ["shot","enemy","reload","break","hit","win"]:
		var duration = 0.12 if name in ["shot","enemy","hit"] else (0.55 if name=="win" else 0.28)
		var count = int(22050*duration)
		var data = PackedByteArray()
		data.resize(count*2)
		for i in range(count):
			var t = float(i)/22050
			var envelope = pow(1.0-float(i)/count,3)
			var frequency = 160.0 if name=="shot" else 110.0
			var value = (rng.randf_range(-1,1)*0.7+sin(t*TAU*frequency)*0.3)*envelope*0.6
			if name=="win":
				frequency = 440.0 if t<0.18 else (554.37 if t<0.36 else 659.25)
				value = sin(t*TAU*frequency)*envelope*0.25
			elif name=="reload":
				value *= 1.0 if fmod(t,0.12)<0.022 else 0.05
			data.encode_s16(i*2,int(value*32767))
		var stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		stream.data = data
		sounds[name] = stream

func play_sound(name: String) -> void:
	if qa_mode or not music_on:
		return
	sound_player.stream = sounds[name]
	sound_player.play()

func capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var error = image.save_png(qa_capture)
	print("CAPTURE_RESULT ",error," ",qa_capture)
	get_tree().quit(0 if error==OK else 1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not benchmark:
		paused = true
		if is_instance_valid(hud):
			hud.paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
