extends Node3D
## Bounded world-space ink splashes/stains, one shared GPU batch.
const SHADER=preload("res://shaders/blood_ink.gdshader")
const MAX_DROPS=192
const MAX_STAINS=96
const MAX_BURSTS_PER_FRAME=6
const MAX_TRACE_PER_FRAME=24
const MERGE_SECONDS=.055
var world
var camera: Camera3D
var drops: Array=[]
var stains: Array=[]
var pending: Dictionary={}
var last_hit: Dictionary={}
var age=0.0
var trace_budget=0
var rng=RandomNumberGenerator.new()
var spray_mesh: MultiMesh
var stain_mesh: MultiMesh
var stains_dirty=true
var stain_uploads=0
var gpu=preload("res://scripts/blood_gpu_motion.gd").new()
var warming=true

func _ready():
	rng.seed=260926
	spray_mesh=make_batch("BloodInk",MAX_DROPS+MAX_STAINS)
	stain_mesh=spray_mesh
	gpu.bind(spray_mesh,false)
	# Zero-area slots compile the real GPU variant during loading, before combat.
	spray_mesh.visible_instance_count=1
	RenderingServer.frame_post_draw.connect(finish_warmup,CONNECT_ONE_SHOT)

func finish_warmup():
	warming=false;write_batches()

func make_batch(label: String,capacity: int) -> MultiMesh:
	var mesh=QuadMesh.new();mesh.size=Vector2.ONE*2
	var material=ShaderMaterial.new();material.shader=SHADER;mesh.material=material
	var batch=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.use_colors=true;batch.use_custom_data=true
	batch.mesh=mesh;batch.instance_count=capacity;batch.visible_instance_count=0
	var bounds: Vector2=world.bounds if world!=null else Vector2(100,100)
	batch.custom_aabb=AABB(Vector3(-bounds.x-4,-2,-bounds.y-4),Vector3(bounds.x*2+8,32,bounds.y*2+8))
	var node=MultiMeshInstance3D.new();node.name=label;node.multimesh=batch;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node)
	return batch

static func strength(e: Dictionary) -> float:
	var value=lerpf(.85,1.25,clampf((float(e.get("amount",20))-12)/100,0,1))
	if e.get("region","")=="head":value+=.18
	if e.get("fatal",false):value+=.28
	return minf(1.65,value)

static func flight(p: Dictionary,t: float) -> Vector3:
	return Vector3(p.origin)+Vector3(p.velocity)*t+Vector3.DOWN*float(p.gravity)*t*t*.5

func queue_hit(e: Dictionary):
	if float(e.get("amount",0))<=0:return
	var id=int(e.unit.id)
	if pending.has(id):
		var old: Dictionary=pending[id]
		old.amount+=float(e.amount);old.fatal=bool(old.get("fatal",false)) or bool(e.get("fatal",false))
		# Keep an actual contact point (especially head/foot hits), not the body centre.
		if e.get("region","")=="head":old.region="head";old.point=e.point;old.incoming=e.incoming
		return
	if age-float(last_hit.get(id,-100))<MERGE_SECONDS and not e.get("fatal",false):return
	if pending.size()<128:pending[id]=e.duplicate()

func prepare_flight(p: Dictionary):
	# Sweep the short ballistic arc once on creation. Read the live destructible
	# geometry; blood stops at cover without a physics body or per-frame raycast.
	var previous: Vector3=p.origin;var last_time: float=0.0
	for i: int in range(1,7):
		var t: float=float(p.life)*i/6;var at: Vector3=flight(p,t)
		if world!=null:
			if trace_budget<=0:
				# Under load, retain a short contact flash instead of tracing more arcs.
				if last_time<=0:p.life=.09;p.velocity*=.15;p.gravity=0.0
				else:p.life=last_time
				p.mark=false;return
			trace_budget-=1
			var travel: Vector3=at-previous
			var hit: Dictionary=world.trace_3d(previous,travel.normalized(),travel.length(),{},true) if travel.length_squared()>.000001 else {}
			if not hit.is_empty() and hit.type!="terrain":
				p.life=lerpf(last_time,t,clampf(float(hit.distance)/maxf(.0001,travel.length()),0,1));p.mark=false;return
		var floor_height: float=world.ground_height(Vector2(at.x,at.z),.015,previous.y+.015) if world!=null else 0.0
		if at.y<=floor_height+.025:
			var lo=last_time;var hi=t
			for k in range(8):
				var mid=(lo+hi)*.5
				if flight(p,mid).y>floor_height+.025:lo=mid
				else:hi=mid
			p.life=hi;p.landing=flight(p,hi);p.landing.y=floor_height+.025;return
		previous=at;last_time=t
	p.mark=false

func burst(e: Dictionary,first_delta: float=0.0):
	var at: Vector3=e.point;var forward: Vector3=e.incoming
	if not at.is_finite():return
	if not forward.is_finite() or forward.length_squared()<.0001:forward=Vector3.FORWARD
	forward=forward.normalized()
	var side=forward.cross(Vector3.UP).normalized()
	if side.length_squared()<.1:side=Vector3.RIGHT
	var power=strength(e);var fatal=bool(e.get("fatal",false));var count=9 if fatal else 7
	for i in range(count):
		var splash=i<3
		# Immediate entry splash plus larger droplets following the impact direction.
		var dir=forward*(-1.0 if i<2 else 1.0)
		var velocity=dir*rng.randf_range(1.0,2.7)*power+side*rng.randf_range(-1.1,1.1)+Vector3.UP*rng.randf_range(.45,1.8)
		var p={"origin":at,"velocity":velocity,"gravity":3.0 if splash else 12.0,"age":0.0,"life":rng.randf_range(.16,.23) if splash else rng.randf_range(.55,.82),"radius":rng.randf_range(.13,.20)*power if splash else rng.randf_range(.045,.080)*power,"splash":splash,"seed":rng.randf(),"mark":not splash and i<6,"landing":Vector3.ZERO,"color":Color("b73443") if splash else Color("912433")}
		prepare_flight(p)
		if float(p.life)<.025:continue
		if drops.size()>=MAX_DROPS:gpu.release(drops.pop_front(),false)
		drops.append(p)
		gpu.add(p,age-first_delta,false)

func add_stain(p: Dictionary,first_delta: float=0.0):
	stains_dirty=true
	var size=float(p.radius)*rng.randf_range(1.7,2.6)
	if stains.size()>=MAX_STAINS:gpu.release(stains.pop_front(),true)
	var stain={"position":p.landing+Vector3.UP*rng.randf_range(0,.003),"radius":size,"angle":rng.randf()*TAU,"seed":p.seed,"age":0.0,"life":rng.randf_range(10,14)}
	stains.append(stain);gpu.add(stain,age-first_delta,true);stain_uploads+=1

func advance(delta: float):
	age+=delta;trace_budget=MAX_TRACE_PER_FRAME
	var events: Array=pending.values();pending.clear()
	# Keep nearby/fatal impacts readable when many soldiers are hit simultaneously.
	# Collision detail is cosmetic: prioritize the nearest/fatal impacts within
	# 24 traces. The existing short contact flash fallback keeps every selected
	# hit readable when arcs exceed the budget; gameplay bullet rays are untouched.
	if events.size()>1:
		var focus=Vector3.ZERO
		if world!=null:focus=Vector3(world.player.position.x,world.player.elevation,world.player.position.y)
		events.sort_custom(func(a,b):return Vector3(a.point).distance_squared_to(focus)-(25 if a.get("fatal",false) else 0)<Vector3(b.point).distance_squared_to(focus)-(25 if b.get("fatal",false) else 0))
	for i in range(mini(events.size(),MAX_BURSTS_PER_FRAME)):
		last_hit[int(events[i].unit.id)]=age;burst(events[i],delta)
	for id in last_hit.keys():
		if age-float(last_hit[id])>1.0:last_hit.erase(id)
	for i in range(drops.size()-1,-1,-1):
		var p: Dictionary=drops[i];p.age+=delta
		if p.age>=p.life:
			if p.mark:add_stain(p,delta)
			gpu.release(p,false)
			drops.remove_at(i)
	for i in range(stains.size()-1,-1,-1):
		stains[i].age+=delta
		if stains[i].age>=stains[i].life:gpu.release(stains[i],true);stains.remove_at(i);stains_dirty=true
	write_batches()

func write_batches():
	if spray_mesh==null:return
	var facing=camera.global_basis if camera!=null else Basis(Vector3.RIGHT,-PI*.25)
	var pixel=camera.size/maxf(1,get_viewport().get_visible_rect().size.y) if camera!=null else .015
	gpu.refresh(age,facing,pixel)
	spray_mesh.visible_instance_count=MAX_DROPS+MAX_STAINS if not drops.is_empty() or not stains.is_empty() else 1 if warming else 0
	stains_dirty=false
