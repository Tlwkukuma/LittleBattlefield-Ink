extends RefCounted
## Living bodies yield to vehicles; walls still constrain every centimetre of the push.
const Person=preload("res://scripts/vehicle_person_contact.gd")
const Reaction=preload("res://scripts/combat_reaction.gd")
const Motion=preload("res://scripts/render_motion.gd")
const Flight=preload("res://scripts/vehicle_impact_motion.gd")
const RADIUS=.28
# Arcade impact weights, not real vehicle masses.
const WEIGHT={"truck":1.4,"armedJeep":1.0,"scoutCar":1.25,"apc":1.8,"ifv":2.0,"lightTank":2.15,"tank":2.7,"heavyTank":3.2}
const IMPACT={
	"truck":{"damage":11.0,"lift":4.0,"throw":1.14},
	"armedJeep":{"damage":8.0,"lift":3.6,"throw":1.08},
	"scoutCar":{"damage":10.0,"lift":3.9,"throw":1.12},
	"apc":{"damage":13.0,"lift":4.2,"throw":1.18},
	"ifv":{"damage":15.0,"lift":4.5,"throw":1.22},
	"lightTank":{"damage":17.0,"lift":4.7,"throw":1.27},
	"tank":{"damage":21.0,"lift":5.0,"throw":1.33},
	"heavyTank":{"damage":25.0,"lift":5.3,"throw":1.40}
}
const HIT_INTERVAL=.55

static func damage(speed: float,weight: float,prone: bool,gear: bool,trapped: bool,pressure: bool,coefficient: float=8.0) -> float:
	var amount=pow(maxf(0,speed-.9),2)*coefficient*(1.2 if prone else 1.0)
	if prone and gear and speed>.25:amount=maxf(amount,28.0*weight)
	if trapped and pressure:amount=maxf(amount,48.0*weight)
	return minf(500,amount)

static func launch_velocity(v: Dictionary,u: Dictionary,normal: Vector2,surface: Vector2,closing: float) -> Vector3:
	var profile: Dictionary=IMPACT[v.type]
	var forward=Vector2.from_angle(v.angle);var side=Vector2(-forward.y,forward.x)
	var lateral=(Vector2(u.position)-Vector2(v.position)).dot(side)
	var outward=side*(1.0 if lateral>.01 or (absf(lateral)<=.01 and int(u.id)%2==0) else -1.0)
	# Front/rear hits deflect towards the nearer flank, clear of the following wheels.
	var direction=(normal+outward*.65*absf(normal.dot(forward))).normalized()
	var horizontal=direction*clampf(maxf(closing,surface.length())*float(profile.throw)+1.0,2.5,13.0)
	return Vector3(horizontal.x,clampf(float(profile.lift)+(closing-2)*.25,3.4,6.7),horizontal.y)

static func push(world,u: Dictionary,offset: Vector2,ignore_vehicle: int=-1) -> Vector2:
	var origin: Vector2=u.position;var steps=maxi(1,ceili(offset.length()/.05));var step=offset/steps
	var body_radius=Flight.radius(u.vehicle_flight) if not u.get("vehicle_flight",{}).is_empty() else RADIUS
	for i in range(steps):
		var next: Vector2=u.position+step;var base: float=u.elevation
		# Query scenery support, excluding roofs of vehicles from a horizontal shove.
		if u.get("grounded",true):
			var support: float=world.ground_height(next,RADIUS,base+.221,func(_o):return true)
			if absf(support-base)<=.221:base=support
		if world.blocked(next,body_radius,world.collision_height(u),ignore_vehicle,base):break
		var occupied=false
		for other in world.nearby_units(next,RADIUS*2):
			if other.id==u.id or not other.alive or world.enclosed(other):continue
			if other.elevation>=base+world.collision_height(u) or other.elevation+world.collision_height(other)<=base:continue
			if next.distance_squared_to(other.position)<pow(RADIUS*2-.015,2):occupied=true;break
		if occupied:break
		u.position=next;u.elevation=base
	if u.position!=origin:
		world.index_unit(u)
		u.last_clear={"position":u.position,"elevation":u.elevation}
		var floor_height: float=world.ground_height(u.position,RADIUS,u.elevation+.001,func(_o):return true)
		if u.elevation-floor_height>.025:u.grounded=false
	return u.position-origin

static func clear_body(world,v: Dictionary,u: Dictionary,end: Dictionary,normal: Vector2) -> bool:
	var body_radius=Flight.radius(u.vehicle_flight) if not u.get("vehicle_flight",{}).is_empty() else RADIUS
	for i in range(6):
		var hit=Person.contact(end,u.position,body_radius,u.elevation,world.collision_height(u))
		if hit.is_empty():return true
		var direction: Vector2=hit.normal
		if direction.dot(normal)<.1:direction=normal
		var distance=minf(.18,float(hit.depth)+.012)
		var moved=push(world,u,direction*distance,v.id)
		if moved.length()<distance*.8:
			# A small lateral deflection can free a body at a wall corner; never teleport it.
			for angle in [.65,-.65]:
				moved+=push(world,u,direction.rotated(angle)*minf(.08,distance),v.id)
		if moved.length_squared()<.00001:break
	return Person.contact(end,u.position,body_radius,u.elevation,world.collision_height(u)).is_empty()

static func resolve(world,v: Dictionary,contact: Dictionary,end: Dictionary,velocity: Vector2,yaw: float) -> Dictionary:
	var u: Dictionary=contact.target;var normal: Vector2=-contact.normal
	var lever: Vector2=contact.point-v.position
	var surface=velocity+Vector2(-lever.y,lever.x)*yaw
	var closing=maxf(0,(surface-Vector2(u.get("velocity",Vector2.ZERO))).dot(normal))
	var moving=maxf(0,surface.dot(normal))
	var pressing=(Vector2.from_angle(v.angle)*float(v.get("throttle_input",0))).dot(normal)>.12 and float(v.get("brake_input",0))<.2
	var record: Dictionary=u.get("vehicle_contacts",{}).get(v.id,{})
	var fresh=world.time>=float(record.get("next",-INF))
	var weight: float=WEIGHT[v.type];var original: Vector2=u.position
	var free=clear_body(world,v,u,end,normal)
	if not u.get("vehicle_flight",{}).is_empty():u.vehicle_flight.position=Vector3(u.position.x,u.elevation,u.position.y)
	var amount=damage(closing,weight,int(u.stance)==2,bool(contact.get("gear",false)),not free,pressing or moving>.5,float(IMPACT[v.type].damage)) if moving>.025 or pressing else 0.0
	if fresh and (moving>.025 or pressing):
		if not u.has("vehicle_contacts"):u.vehicle_contacts={}
		u.vehicle_contacts[v.id]={"next":world.time+HIT_INTERVAL}
		var impulse=Vector3(normal.x,.12 if amount>0 else 0.0,normal.y)*clampf(closing*.85,.25,7.0)
		# Install before the death event: fatal and surviving hits use the same trajectory.
		if closing>=1.6 or amount>=float(u.health):
			impulse=launch_velocity(v,u,normal,surface,closing)
			Reaction.register_hit(u,impulse,"body",amount,false)
			u.vehicle_flight=Flight.create(Vector3(u.position.x,u.elevation,u.position.y),impulse,Reaction.death_choice(u,impulse))
			u.vertical_speed=impulse.y;u.grounded=false;u.vehicle_push=Vector2.ZERO
			if u.mounted>=0:release_mount(world,u)
			u.vault={};u.ladder={};u.sprinting=false;u.flash=0
			preload("res://scripts/grenade_throw_control.gd").cancel(u)
			preload("res://scripts/melee_action.gd").cancel(u)
		if amount>0:
			var source_id=int(world.player.id) if world.player.mounted==v.id else -1
			var height=float(u.elevation)+minf(.65,world.collision_height(u)*.5)
			var weapon={"id":"vehicle_collision","name":"载具撞击","kind":"vehicle","damage":amount}
			world.damage_unit(u,amount,impulse,weapon,false,false,height,"body",Vector3(contact.point.x,height,contact.point.y),impulse.normalized(),source_id)
		elif closing>.1:Reaction.register_hit(u,impulse,"body",0,false)
		# A person absorbs only a small fraction of vehicle momentum, with heavier hulls losing less.
		velocity*=1.0-.12/weight;yaw*=1.0-.08/weight
		if u.alive and closing>.1 and u.get("vehicle_flight",{}).is_empty():
			u.vehicle_push=normal*clampf(closing*.65,.20,4.5);u.vehicle_stagger=minf(.45,.10+closing*.06)
		var forward=Vector2.from_angle(v.angle);var side=Vector2(-forward.y,forward.x)
		v.contact_kick=Vector2(normal.dot(forward),-normal.dot(side))*minf(.018,closing*.003)/sqrt(weight)
	if u.position!=original:
		# Interrupt scripted attachment paths so the next update cannot snap the body back.
		if u.mounted>=0:release_mount(world,u)
		u.vault={};u.ladder={};u.sprinting=false
		Motion.after_unit(u,world.time,1.0/60)
	return {"cleared":not u.alive or free,"velocity":velocity,"yaw":yaw}

static func tick_unit(world,u: Dictionary,delta: float) -> void:
	if not u.alive:return
	var flight: Dictionary=u.get("vehicle_flight",{})
	if not flight.is_empty():
		Flight.step(world,flight,delta)
		var p: Vector3=flight.position;var v: Vector3=flight.velocity
		u.position=Vector2(p.x,p.z);u.elevation=p.y;u.vertical_speed=v.y;u.velocity=Vector2(v.x,v.z)
		u.grounded=false;u.requested_velocity=Vector2.ZERO;world.index_unit(u)
		if flight.settled:
			# Recover on the ground, rather than popping straight back to standing.
			u.stance=2;u.stance_blend=2.0;u.grounded=true;u.vehicle_stagger=.4;u.vehicle_flight={}
			u.last_clear={"position":u.position,"elevation":u.elevation}
		return
	u.vehicle_stagger=maxf(0,float(u.get("vehicle_stagger",0))-delta)
	var velocity: Vector2=u.get("vehicle_push",Vector2.ZERO)
	if velocity.length_squared()<.0025:return
	var moved=push(world,u,velocity*delta)
	u.velocity+=moved/maxf(.001,delta)
	u.vehicle_push=velocity*exp(-delta*7.0) if moved.length()>=velocity.length()*delta*.5 else Vector2.ZERO

static func release_mount(world,u: Dictionary) -> void:
	var mount: Dictionary=world.vehicles[u.mounted]
	if int(mount.get("driver_id",-1))==int(u.id):mount.driver=false;mount.driver_id=-1
	if mount.has("passenger_ids"):mount.passenger_ids.erase(u.id)
	u.mounted=-1;u.hanlue_passenger=false
