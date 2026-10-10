extends RefCounted
## Bounded swept motion shared by a living casualty and its eventual corpse.
const Person=preload("res://scripts/vehicle_person_contact.gd")
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const GRAVITY=18.0

static func create(position: Vector3,velocity: Vector3,choice: Dictionary) -> Dictionary:
	return {"position":position,"velocity":velocity,"age":0.0,"radius":.28,"landed":false,"land_age":0.0,"settled":false,"choice":choice}

static func radius(state: Dictionary) -> float:return float(state.get("radius",.28))
static func height(state: Dictionary) -> float:return lerpf(1.95,.72,smoothstep(0,.35,float(state.age)))

static func separate(world,state: Dictionary) -> bool:
	var shifted=false;var p: Vector3=state.position;var r=radius(state);var h=height(state)
	# Only 18 retained corpses, broad phase before fitted vehicle sections.
	for car in world.vehicles:
		if not Dimensions.planar_bounds(car).grow(r+.04).has_point(Vector2(p.x,p.z)):continue
		for attempt in range(12):
			var hit=Person.contact(car,Vector2(p.x,p.z),r,p.y,h)
			if hit.is_empty():break
			var direction: Vector2=hit.normal;var distance=minf(.12,float(hit.depth)+.012)
			var start=Vector2(p.x,p.z);var moved=false
			var depth: float=world.collision_depth(start,r,h,car.id,p.y)
			for angle in [0.0,.7,-.7]:
				var next=start+direction.rotated(angle)*distance
				# May leave an existing overlap, never deepen or cross a wall.
				if world.collision_depth(next,r,h,car.id,p.y)>maxf(.001,depth-.00001):continue
				p.x=next.x;p.z=next.y;moved=true;shifted=true;break
			if not moved:break
			var velocity: Vector3=state.velocity;var horizontal=Vector2(velocity.x,velocity.z)
			var car_speed: Vector2=car.get("velocity",Vector2.ZERO)
			horizontal+=direction*maxf(0,car_speed.dot(direction)+.5-horizontal.dot(direction))
			state.velocity=Vector3(horizontal.x,velocity.y,horizontal.y)
	state.position=p
	if shifted:state.settled=false;state.land_age=0.0
	return shifted

static func step(world,state: Dictionary,delta: float) -> void:
	# A stalled renderer cannot trigger an unbounded physics catch-up.
	var elapsed=minf(delta,1.0/15.0)
	separate(world,state)
	if state.settled:
		var p: Vector3=state.position
		if absf(p.y-world.ground_height(Vector2(p.x,p.z),.28,p.y+.025))<.025:return
		state.settled=false;state.landed=false
	var speed: float=state.velocity.length()
	var count=clampi(ceili(maxf(elapsed*60,speed*elapsed/.08)),1,24);var dt=elapsed/count
	for i in range(count):
		state.age+=dt
		var p: Vector3=state.position;var v: Vector3=state.velocity
		var r=radius(state);var h=height(state)
		var spread=lerpf(.28,.85,smoothstep(0,.35,float(state.age)))
		# A falling pose spreads horizontally only into available room.
		if spread>r and not world.blocked(Vector2(p.x,p.z),spread,h,-1,p.y):r=spread;state.radius=r
		v.y-=GRAVITY*dt
		var next=p+v*dt
		var floor_height: float=world.ground_height(Vector2(next.x,next.z),.28,maxf(p.y,next.y)+.025)
		if next.y<=floor_height:
			next.y=floor_height
			if v.y< -2.5 and not state.landed:v.y=-v.y*.16
			else:v.y=0.0
			state.landed=true
		if world.blocked(Vector2(next.x,next.z),r,h,-1,next.y):
			# Axis slides retain tangential motion at a wall; blocked axes rebound softly.
			for axis in [0,2]:
				var slide=p;slide[axis]=next[axis]
				if not world.blocked(Vector2(slide.x,slide.z),r,h,-1,p.y):p[axis]=slide[axis]
				else:v[axis]*=-.18
			if not world.blocked(Vector2(p.x,p.z),r,h,-1,next.y):p.y=next.y
			elif v.y>0:v.y=0.0
		else:p=next
		var drag=exp(-(7.0 if state.landed and absf(v.y)<.5 else .28)*dt)
		v.x*=drag;v.z*=drag
		state.position=p;state.velocity=v
		if state.landed:state.land_age+=dt
		if state.landed and v.length_squared()<.025 and state.land_age>.25:
			state.velocity=Vector3.ZERO;state.settled=true;break
