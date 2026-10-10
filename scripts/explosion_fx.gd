extends Node3D
## Weapon explosions: shared GPU motion, bounded writes and reserved impact cues.
const CLOUD_CAPACITY=384
const CHIP_CAPACITY=96
const FLASH_RESERVE=24
const DETAIL_PER_FRAME=112
const FLASH_PER_FRAME=12
const Surface=preload("res://scripts/blast_surface.gd")
var world
var camera: Camera3D
var material: ShaderMaterial
var groups: Array=[]
var frame=-1
var details=0
var flashes=0
var serial=0
var poll=0.0
var uploads=0
var dropped=0
var active=0
var last_ms=0.0

func _ready():
	material=ShaderMaterial.new();material.shader=preload("res://shaders/explosion.gdshader")
	# Two triangles per puff; rolling density and torn silhouettes live on the GPU.
	var cloud=QuadMesh.new();cloud.size=Vector2.ONE
	var chip=BoxMesh.new();chip.size=Vector3.ONE
	for mesh in [cloud,chip]:
		var count=CLOUD_CAPACITY if mesh==cloud else CHIP_CAPACITY
		var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.use_custom_data=true;mm.mesh=mesh;mm.instance_count=count;mm.visible_instance_count=0
		mm.custom_aabb=AABB(Vector3(-world.bounds.x-15,-64,-world.bounds.y-15),Vector3(world.bounds.x*2+30,256,world.bounds.y*2+30))
		var node=MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.hide();add_child(node)
		var ends=PackedFloat32Array();ends.resize(count);ends.fill(-1)
		groups.append({"mesh":mm,"node":node,"ends":ends,"cursor":0,"flash_cursor":0,"latest":-1.0})
		# Submit a zero-area instance during startup to compile the real GPU variant.
		mm.set_instance_custom_data(0,Color(0,0,0,0));mm.visible_instance_count=1;node.show()
	RenderingServer.frame_post_draw.connect(finish_warmup,CONNECT_ONE_SHOT)
	set_process(false)

func finish_warmup():
	for g in groups:
		if float(g.latest)<0:g.mesh.visible_instance_count=0;g.node.hide()

static func profile(w: Dictionary) -> Dictionary:
	var kind=str(w.get("kind","shell"))
	var p={"fire":3,"smoke":6,"chips":8,"jets":4,"scale":1.0,"lift":1.0,"life":.24,"dark":false,"directed":false}
	if str(w.get("blastStyle",""))=="fuel":p.fire=6;p.smoke=9;p.chips=6;p.jets=0;p.scale=1.2;p.life=.62;p.dark=true
	elif float(w.get("impactBlastRadius",0))>0:p.fire=1;p.smoke=2;p.chips=4;p.jets=2;p.scale=.55;p.life=.10
	elif kind in ["grenadeProjectile","vehicleGrenade"]:p.fire=2;p.smoke=4;p.chips=5;p.jets=3;p.scale=.65;p.life=.14
	elif kind=="grenade":p.fire=2;p.smoke=5;p.chips=8;p.jets=5;p.scale=.80;p.life=.16
	elif kind=="rocket":p.fire=3;p.smoke=6;p.chips=8;p.directed=true;p.life=.24
	elif kind in ["mortar","vehicleMortar"]:p.fire=2;p.smoke=7;p.chips=10;p.jets=7;p.lift=1.5;p.life=.16
	elif kind=="shell":
		var caliber=str(preload("res://scripts/weapon_profile.gd").get_profile(w).flight_identity)
		p.fire=3 if caliber=="45" else 5 if caliber=="88" else 4
		p.smoke=6 if caliber=="45" else 10 if caliber=="88" else 8;p.chips=8 if caliber=="45" else 12 if caliber=="88" else 10
		p.life=.19 if caliber=="45" else .30 if caliber=="88" else .24;p.lift=1.25;p.jets=4 if caliber=="45" else 7 if caliber=="88" else 5
	return p

static func outward_seed(seed: float,normal: Vector3) -> float:
	var radial=Vector3(cos(seed*TAU),0,sin(seed*TAU))
	if normal.length_squared()>.1 and absf(normal.y)<.65 and radial.dot(normal)<0:
		radial=radial.bounce(normal);return fposmod(atan2(radial.z,radial.x)/TAU,1.0)
	return seed

func spawn(at: Vector3,size: Vector3,color: Color,kind: int,life: float,power: float,seed: float,delay: float=0.0) -> void:
	var critical=kind==2
	if (critical and flashes>=FLASH_PER_FRAME) or (not critical and details>=DETAIL_PER_FRAME):dropped+=1;return
	if critical:flashes+=1
	else:details+=1
	var g: Dictionary=groups[1 if kind==4 else 0]
	var slot: int
	if critical:
		slot=g.flash_cursor;g.flash_cursor=(slot+1)%FLASH_RESERVE
	elif kind==4:
		slot=g.cursor;g.cursor=(slot+1)%CHIP_CAPACITY
	else:
		slot=FLASH_RESERVE+int(g.cursor);g.cursor=(int(g.cursor)+1)%(CLOUD_CAPACITY-FLASH_RESERVE)
	var now=float(world.time);var birth=now+delay
	if float(g.ends[slot])<=now:active+=1
	g.ends[slot]=birth+life;g.latest=maxf(g.latest,birth+life)
	g.mesh.set_instance_transform(slot,Transform3D(Basis.from_scale(size),at))
	g.mesh.set_instance_color(slot,Color(color.r,color.g,color.b,power))
	g.mesh.set_instance_custom_data(slot,Color(birth,life,kind,seed))
	g.mesh.visible_instance_count=g.mesh.instance_count;g.node.show();uploads+=1

func burst(e: Dictionary) -> bool:
	var distance: float=Vector2(e.position).distance_to(world.player.position)
	if distance>64:return false
	var at=Vector3(e.position.x,float(e.get("height",.3)),e.position.y)
	var normal: Vector3=e.get("normal",Vector3.ZERO)
	var wall_contact=normal.length_squared()>.1 and absf(normal.y)<.65
	if wall_contact:at+=normal*.08
	if camera!=null:
		var margin=160.0
		if camera.is_position_behind(at) or not get_viewport().get_visible_rect().grow(margin).has_point(camera.unproject_position(at)):return distance<20
	var current_frame=Engine.get_process_frames()
	if current_frame!=frame:frame=current_frame;details=0;flashes=0
	var p=profile(e.get("weapon",{}));var power=clampf(float(e.radius)*.32,.55,2.2)*float(p.scale)
	var detail=.55 if distance>32 else 1.0
	serial+=1;var seed=fposmod(float(serial)*.618033989,1.0)
	material.set_shader_parameter("effect_clock",float(world.time));set_process(true)
	spawn(at,Vector3.ONE*.72*power,Color.WHITE,2,.085,power,seed)
	if details>=DETAIL_PER_FRAME:return true
	var ground: float=world.terrain.height(e.position)
	var grounded=at.y-ground<1.15 and at.y>=ground-.15
	var palette=Surface.palette(world,e.position)
	var dust: Color=palette.dust
	if wall_contact:
		var contact=preload("res://scripts/combat_feedback_profile.gd").material(str(e.get("material","stone")))
		dust=Color("9b7954") if contact=="wood" else Color("85887d") if contact=="metal" else Color("aaa497")
	var smoke=Color("56534c") if p.dark else dust.darkened(.18)
	var direction: Vector2=e.get("direction",Vector2.ZERO)
	for i in range(int(ceil(float(p.fire)*detail))):
		var a=seed*TAU+i*2.39996;var offset=Vector3(cos(a),.2,sin(a))*power*.20
		if wall_contact and offset.dot(normal)<0:offset=offset.bounce(normal)
		if p.directed:offset+=Vector3(direction.x,.15,direction.y)*power*float(i)*.13
		spawn(at+offset,Vector3(.86,1.0,.86)*power,Color.WHITE,1,float(p.life)+i*.015,power,outward_seed(fposmod(seed+i*.217,1),normal),i*.012)
	for i in range(int(ceil(float(p.smoke)*detail))):
		var a=i*2.39996+seed*TAU;var spread=.16+float(i%3)*.15
		var offset=Vector3(cos(a)*spread,.15+float(i)*.075*float(p.lift),sin(a)*spread)*power
		if wall_contact and offset.dot(normal)<0:offset=offset.bounce(normal)
		spawn(at+offset,Vector3(1.08,1.0*float(p.lift),1.08)*power,smoke,0,1.3+float(i%4)*.25,power,outward_seed(fposmod(seed+i*.137,1),normal),.055+i*.035)
	if grounded or wall_contact:
		for i in range(int(ceil(float(p.jets)*detail))):
			spawn(at+Vector3.UP*.08,Vector3(.24,.95*float(p.lift),.24)*power,dust.darkened(.13),5,.52+float(i%3)*.10,power,outward_seed(fposmod(seed+i*.381966,1),normal),i*.008)
	if grounded:
		for i in range(6 if detail<1 else 9):
			var a=float(i)*TAU/(6 if detail<1 else 9)+seed;var planar=Vector2(cos(a),sin(a))
			var point: Vector2=e.position+planar*power*.35
			var height: float=world.terrain.height(point)
			# Do not bridge a trench/cliff with a floating circular dust sheet.
			if absf(height-ground)>.45:continue
			spawn(Vector3(point.x,height+.12,point.y),Vector3(1.0,.30,1.0)*power,dust,3,.78+seed*.2,power,outward_seed(fposmod(a/TAU,1),normal),.025)
	for i in range(int(ceil(float(p.chips)*detail))):
		spawn(at,Vector3(.045,.055,.09)*power,Color("d5af73") if i%4==0 else dust.darkened(.30),4,.38+float(i%4)*.08,power,outward_seed(fposmod(seed+i*.381966,1),normal))
	return true

func clear() -> void:
	active=0;details=0;flashes=0;set_process(false)
	for g in groups:
		g.ends.fill(-1);g.latest=-1.0;g.mesh.visible_instance_count=0;g.node.hide()
		# Clear old birth times too: scene repair must not resurrect stale instances.
		for i in range(g.mesh.instance_count):g.mesh.set_instance_custom_data(i,Color(0,0,0,0))

func _process(delta: float):
	var started=Time.get_ticks_usec();var now=float(world.time)
	material.set_shader_parameter("effect_clock",now);poll-=delta
	if poll<=0:
		poll=.10;active=0
		for g in groups:
			for end in g.ends:
				if end>now:active+=1
			if float(g.latest)<=now:g.mesh.visible_instance_count=0;g.node.hide()
		if active==0:set_process(false)
	last_ms=(Time.get_ticks_usec()-started)/1000.0

func stats() -> Dictionary:
	var draws=0
	for g in groups:
		if g.node.visible:draws+=1
	return {"instances":active,"capacity":CLOUD_CAPACITY+CHIP_CAPACITY,"batches":draws,"uploads":uploads,"dropped_detail":dropped,"cpu_ms":last_ms}
