extends RefCounted
const Art=preload("res://scripts/terrain_art.gd")
const Ink=preload("res://scripts/ink_art.gd")
const ENTRY_SPEED=2.4

static func path(ladder: Dictionary) -> Array:
	return [ladder.low,Vector3(ladder.low.x,ladder.high.y+.18,ladder.low.z),ladder.high+Vector3.UP*.18,ladder.high]

static func length(ladder: Dictionary) -> float:
	var points=path(ladder);var result=0.0
	for i in range(points.size()-1):result+=points[i].distance_to(points[i+1])
	return result

static func sample(ladder: Dictionary,travel: float) -> Vector3:
	var points=path(ladder)
	for i in range(points.size()-1):
		var span=points[i].distance_to(points[i+1])
		if travel<=span:return points[i].lerp(points[i+1],clampf(travel/maxf(.001,span),0,1))
		travel-=span
	return points.back()

static func clear(world,at: Vector3) -> bool:
	return not world.blocked(Vector2(at.x,at.z),.28,world.stance_height(0),-1,at.y)

static func nearest(world) -> Dictionary:
	var u: Dictionary=world.player
	if not u.alive or u.mounted>=0 or not u.grounded or not u.vault.is_empty():return {}
	var foot=Vector3(u.position.x,u.elevation,u.position.y);var best={};var distance=1.35
	for ladder in world.terrain.ladders:
		for end in [0,1]:
			var at: Vector3=ladder.low if end==0 else ladder.high
			if absf(foot.y-at.y)>.35 or foot.distance_to(at)>=distance:continue
			var valid=true
			for i in range(1,16):
				if not clear(world,foot.lerp(at,i/15.0)):valid=false;break
			if valid:best={"ladder":ladder,"end":end};distance=foot.distance_to(at)
	return best

static func interact(world) -> bool:
	var u: Dictionary=world.player
	if not u.get("ladder",{}).is_empty():release(u);return true
	var found=nearest(world)
	if found.is_empty():return false
	var ladder: Dictionary=found.ladder
	# Validate every part of the route before accepting the mount.
	var total=length(ladder)
	for i in range(ceili(total/.06)+1):
		if not clear(world,sample(ladder,minf(total,i*.06))):
			world.event.emit({"type":"notice","text":"梯子通路或出口被挡住，请先清理障碍"});return true
	var foot=Vector3(u.position.x,u.elevation,u.position.y)
	var entry: Vector3=ladder.low if found.end==0 else ladder.high
	u.ladder={"spec":ladder,"travel":0.0 if found.end==0 else total,"total":total,"motion":0.0,
		"entry_from":foot,"entry_to":entry,"entry_length":foot.distance_to(entry),"entry_travel":0.0,"age":0.0,"blocked":false}
	world.cancel_firing()
	u.stance=0;u.stance_blend=0.0;u.grounded=false;u.sprinting=false;u.reload=0.0
	u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;u.vertical_speed=0
	# E reserves the ladder without teleporting the body to an endpoint.
	world.event.emit({"type":"notice","text":"下端上梯 · W 上爬 · E / 空格松手" if found.end==0 else "上端下梯 · S 下爬 · E / 空格松手"})
	return true

static func approaching(state: Dictionary) -> bool:
	return float(state.get("entry_travel",0))<float(state.get("entry_length",0))-.0001

static func hint(world) -> String:
	var state: Dictionary=world.player.ladder
	if not state.is_empty():
		if state.get("blocked",false):return "梯子通路受阻 · 反向返回 / E 松手"
		if approaching(state):return "正在靠近梯子 · E / 空格取消"
		if state.travel<=.0001:return "W 向上攀爬 · E / 空格松手"
		if state.travel>=state.total-.0001:return "S 向下攀爬 · E / 空格松手"
		return "W 上爬 · S 下爬 · E / 空格松手"
	var found=nearest(world)
	return "" if found.is_empty() else "E  上梯 · 爬出壕沟" if found.end==0 else "E  下梯 · 进入壕沟"

static func blocked_notice(world,state: Dictionary):
	if not state.get("blocked",false):world.event.emit({"type":"notice","text":"梯子通路受阻，可以反向返回或按 E 松手"})
	state.blocked=true

static func set_position(u: Dictionary,at: Vector3):
	u.position=Vector2(at.x,at.z);u.elevation=at.y
	var ladder: Dictionary=u.ladder.spec
	u.facing=Vector2(ladder.high.x-ladder.low.x,ladder.high.z-ladder.low.z).normalized()

static func release(u: Dictionary):
	u.ladder={};u.grounded=false;u.vertical_speed=0.0;u.air_speed=3.4;u.jump_cooldown=.15
	u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO

static func move(world,u: Dictionary,input: Vector2,delta: float,jump: bool):
	if jump:release(u);return
	var state: Dictionary=u.ladder;state.age=float(state.get("age",0))+delta
	if approaching(state):
		var from: float=state.entry_travel;var target=minf(state.entry_length,from+ENTRY_SPEED*delta)
		var steps=maxi(1,ceili((target-from)/.04));var previous=Vector3(u.position.x,u.elevation,u.position.y)
		for i in range(1,steps+1):
			var next=lerpf(from,target,float(i)/steps);var at: Vector3=state.entry_from.lerp(state.entry_to,next/maxf(.0001,state.entry_length))
			if not clear(world,at):blocked_notice(world,state);break
			state.blocked=false;state.entry_travel=next;set_position(u,at)
		var displacement=Vector3(u.position.x,u.elevation,u.position.y)-previous
		u.velocity=Vector2(displacement.x,displacement.z)/maxf(.0001,delta)
		if u.velocity.length_squared()>.001:u.facing=u.velocity.normalized()
		state.motion=0.0
		return
	u.velocity=Vector2.ZERO
	var speed=-input.y*1.35
	var target=clampf(state.travel+speed*delta,0,state.total)
	var steps=maxi(1,ceili(absf(target-state.travel)/.04));var from: float=state.travel
	for i in range(1,steps+1):
		var next=lerpf(from,target,float(i)/steps);var at=sample(state.spec,next)
		if not clear(world,at):blocked_notice(world,state);break
		state.blocked=false;state.travel=next;set_position(u,at)
	state.motion=(state.travel-from)/maxf(.0001,delta)
	# Holding the key used to approach the ladder must not immediately undo E.
	# Auto-exit only after actually traversing into an endpoint from its interior.
	if absf(state.travel-from)>.000001 and ((state.travel<=.0001 and speed<0) or (state.travel>=state.total-.0001 and speed>0)):
		var at=sample(state.spec,state.travel)
		if clear(world,at):
			release(u);u.grounded=true;u.elevation=world.ground_height(u.position,.28,u.elevation+.02)

static func build(world,parent: Node3D):
	for ladder in world.terrain.ladders:
		var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
		var forward=Vector3(ladder.high.x-ladder.low.x,0,ladder.high.z-ladder.low.z).normalized()
		var side=forward.cross(Vector3.UP);var base: Vector3=ladder.low+forward*.38
		var top=Vector3(base.x,ladder.high.y+1.05,base.z);var width: float=clampf(ladder.width,.65,1.2)
		for sign_value in [-1,1]:
			rod(v,n,c,base+side*width*.5*sign_value,top+side*width*.5*sign_value,.055,Color("626f69"))
			rod(v,n,c,top+side*width*.5*sign_value,ladder.high+Vector3.UP*1.05+side*width*.5*sign_value,.05,Color("626f69"))
		for i in range(1,ceili((top.y-base.y)/.28)):
			var at=base+Vector3.UP*i*.28
			rod(v,n,c,at-side*width*.5,at+side*width*.5,.045,Color("c7b68e"))
		Ink.mesh_node(parent,Art.mesh_from(v,n,c),Vector3.ZERO,Color.WHITE)

static func rod(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,a: Vector3,b: Vector3,width: float,color: Color):
	var along=(b-a).normalized();var side=along.cross(Vector3.UP if absf(along.y)<.9 else Vector3.RIGHT).normalized()
	var other=along.cross(side);var corners=[side+other,side-other,-side-other,-side+other]
	for i in range(4):
		var j=(i+1)%4;var face=[a+corners[i]*width*.5,a+corners[j]*width*.5,b+corners[j]*width*.5,b+corners[i]*width*.5]
		var normal=(corners[i]+corners[j]).normalized()
		for index in [0,1,2,0,2,3]:v.append(face[index]);n.append(normal);c.append(color)
