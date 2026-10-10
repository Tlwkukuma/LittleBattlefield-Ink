extends Node3D
## Two persistent GPU batches; no per-particle node, light, collider or CPU motion.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const CAPACITY=192
const DEBRIS_CAPACITY=64
const EMITTER_LIMIT=8
const FRAME_SPAWN_LIMIT=48
const RANGE_SQUARED=55.0*55.0
var world
var material: ShaderMaterial
var batches: Array=[]
var emitters: Array=[]
var clock=0.0
var poll=0.0
var frame_spawns=0
var spawn_frame=-1
var serial=0
var writes=0
var last_ms=0.0

func _ready():
	material=ShaderMaterial.new();material.shader=preload("res://shaders/vehicle_destruction.gdshader")
	var smoke=SphereMesh.new();smoke.radius=.5;smoke.height=1.0;smoke.radial_segments=8;smoke.rings=3
	var chip=BoxMesh.new();chip.size=Vector3.ONE
	for mesh in [smoke,chip]:
		var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.use_custom_data=true;mm.mesh=mesh
		mm.instance_count=CAPACITY if mesh==smoke else DEBRIS_CAPACITY;mm.visible_instance_count=0
		mm.custom_aabb=AABB(Vector3(-world.bounds.x-12,-64,-world.bounds.y-12),Vector3(world.bounds.x*2+24,256,world.bounds.y*2+24))
		var node=MultiMeshInstance3D.new();node.multimesh=mm;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.visible=false;add_child(node)
		batches.append({"mesh":mm,"node":node,"entries":[]})
	set_process(false)

static func strength(v: Dictionary) -> float:
	return {"armedJeep":.75,"scoutCar":.85,"apc":1.0,"ifv":1.10,"lightTank":1.05,"tank":1.25,"heavyTank":1.45}.get(v.type,.45)

static func engine_point(v: Dictionary) -> Vector3:
	var d=Dimensions.for_vehicle(v)
	var local=Vector3(0,float(d.deck),-float(d.half.x)*.64 if v.type=="armedJeep" else float(d.half.x)*.60)
	return Vector3(v.position.x,float(v.get("elevation",0)),v.position.y)+Dimensions.body_basis(v)*local

func near(v: Dictionary) -> bool:return Vector2(v.position).distance_squared_to(world.player.position)<=RANGE_SQUARED

func spawn(at: Vector3,size: Vector3,color: Color,kind: int,life: float) -> void:
	var frame=Engine.get_process_frames()
	if frame!=spawn_frame:spawn_frame=frame;frame_spawns=0
	if frame_spawns>=FRAME_SPAWN_LIMIT:return
	frame_spawns+=1;serial+=1
	var group: Dictionary=batches[1 if kind==4 else 0]
	if group.entries.size()>=group.mesh.instance_count:remove(group,0)
	var seed=fposmod(serial*.61803398875,1.0)
	var entry={"pose":Transform3D(Basis.from_scale(size),at),"color":color,"data":Color(fposmod(clock,64.0),life,kind,seed),"end":clock+life}
	var slot=group.entries.size();group.entries.append(entry);upload(group,slot,entry)
	group.mesh.visible_instance_count=group.entries.size();group.node.visible=true

func upload(group: Dictionary,slot: int,entry: Dictionary):
	group.mesh.set_instance_transform(slot,entry.pose);group.mesh.set_instance_color(slot,entry.color);group.mesh.set_instance_custom_data(slot,entry.data);writes+=1

func remove(group: Dictionary,index: int):
	var last: Dictionary=group.entries.pop_back()
	if index<group.entries.size():group.entries[index]=last;upload(group,index,last)
	group.mesh.visible_instance_count=group.entries.size();group.node.visible=not group.entries.is_empty()

func remember(v: Dictionary):
	for entry in emitters:
		if entry.vehicle.id==v.id:return
	if emitters.size()>=EMITTER_LIMIT:
		var farthest=0;var distance=-1.0
		for i in range(emitters.size()):
			var d: float=emitters[i].vehicle.position.distance_squared_to(world.player.position)
			if d>distance:distance=d;farthest=i
		if distance<Vector2(v.position).distance_squared_to(world.player.position):return
		emitters.remove_at(farthest)
	emitters.append({"vehicle":v,"smoke_at":clock,"fire_at":clock})

func damage(v: Dictionary):
	if not v.emplacement and v.health>0 and v.health/v.max_health<=.35:
		clock=float(world.time);remember(v);set_process(true)

func destroyed(v: Dictionary):
	clock=float(world.time)
	material.set_shader_parameter("effect_clock",fposmod(clock,64.0));set_process(true)
	if not v.emplacement:remember(v)
	if not near(v):return
	var power=strength(v);var origin=engine_point(v)
	var center=Vector3(v.position.x,float(v.get("elevation",0))+.65,v.position.y)
	spawn(center,Vector3.ONE*(1.15*power),Color.WHITE,2,.16)
	for i in range(6):
		var angle=float(i)*TAU/6;var offset=Vector3(cos(angle),.2,sin(angle))*power*.43
		spawn(center+offset,Vector3(.72,1.05,.72)*power,Color.WHITE,1,.42+i*.035)
	for i in range(7):
		var angle=float(i)*2.39996;var offset=Vector3(cos(angle)*.45,.12*i,sin(angle)*.45)*power
		spawn(origin+offset,Vector3.ONE*(.46+i*.052)*power,Color("514a50"),0,2.4+i*.14)
	for i in range(6):
		var angle=float(i)*TAU/6;var at=center+Vector3(cos(angle),0,sin(angle))*power*.65
		at.y=world.terrain.height(Vector2(at.x,at.z))+.09
		spawn(at,Vector3(.65,.16,.65)*power,Color("9e947f"),3,.75)
	for i in range(8 if not v.emplacement else 4):
		spawn(origin,Vector3(.09+i%3*.035,.035,.15)*power,Color("49434a") if i%2 else Color("9a8973"),4,.65+i*.028)

func clear():
	emitters.clear();frame_spawns=0;set_process(false)
	for group in batches:group.entries.clear();group.mesh.visible_instance_count=0;group.node.visible=false

func _process(delta: float):
	var started=Time.get_ticks_usec();clock=float(world.time)
	material.set_shader_parameter("effect_clock",fposmod(clock,64.0))
	poll-=delta
	if poll>0:last_ms=(Time.get_ticks_usec()-started)/1000.0;return
	poll=.1
	for group in batches:
		for i in range(group.entries.size()-1,-1,-1):
			if float(group.entries[i].end)<=clock:remove(group,i)
	for i in range(emitters.size()-1,-1,-1):
		var entry: Dictionary=emitters[i];var v: Dictionary=entry.vehicle
		var age=maxf(0,clock-float(v.get("destroy_time",clock)))
		if (v.destroyed and age>24) or (not v.destroyed and v.health/v.max_health>.35):emitters.remove_at(i);continue
		if not near(v):continue
		var power=strength(v);var origin=engine_point(v)
		if clock>=float(entry.smoke_at):
			var burnt=bool(v.destroyed);var late=age>9 and burnt
			spawn(origin,Vector3.ONE*(.48*power if burnt else .24),Color("605860") if burnt else Color("8b838d"),0,2.8 if burnt else 1.6)
			entry.smoke_at=clock+(1.1 if late else .42 if burnt else .9)
		if v.destroyed and age<8 and clock>=float(entry.fire_at):
			var fade=1.0-smoothstep(4,8,age)
			var drift=Vector3(sin(clock*4+v.id)*.17,0,cos(clock*3+v.id)*.12)*power
			spawn(origin+drift,Vector3(.36,.76,.36)*power*maxf(.15,fade),Color.WHITE,1,.46)
			entry.fire_at=clock+.18
	last_ms=(Time.get_ticks_usec()-started)/1000.0
	if emitters.is_empty() and batches[0].entries.is_empty() and batches[1].entries.is_empty():set_process(false)

func stats() -> Dictionary:
	var count=0;var draws=0
	for group in batches:
		count+=group.entries.size()
		if not group.entries.is_empty():draws+=1
	return {"instances":count,"capacity":CAPACITY+DEBRIS_CAPACITY,"batches":draws,"emitters":emitters.size(),"uploads":writes,"cpu_ms":last_ms}
