extends RefCounted
## Racing steering with terrain grip, progressive boost and momentum-preserving handbrake slides.
const Ground=preload("res://scripts/vehicle_grounding.gd")
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const GroundEffects=preload("res://scripts/vehicle_ground_effects.gd")
const Offroad=preload("res://scripts/vehicle_offroad.gd")
const Collision=preload("res://scripts/vehicle_collision.gd")
const Contact=preload("res://scripts/vehicle_contact_response.gd")
const Vertical=preload("res://scripts/vehicle_vertical_motion.gd")
const TUNING={
	"armedJeep":{"launch":2.1,"stop":.85,"steer":.55,"response":10.5,"suspension":.16,"boost":1.32,"power":1.65,"slide_grip":.85,"slide_yaw":1.85},
	"scoutCar":{"launch":2.5,"stop":1.0,"steer":.50,"response":9.0,"suspension":.15,"boost":1.28,"power":1.55,"slide_grip":1.05,"slide_yaw":1.70},
	"apc":{"launch":2.7,"stop":1.15,"steer":1.05,"response":7.7,"suspension":.14,"boost":1.22,"power":1.45,"slide_grip":1.85,"slide_yaw":1.35},
	"ifv":{"launch":2.9,"stop":1.2,"steer":1.0,"response":7.4,"suspension":.14,"boost":1.22,"power":1.45,"slide_grip":1.95,"slide_yaw":1.32},
	"lightTank":{"launch":2.6,"stop":1.1,"steer":1.05,"response":8.0,"suspension":.14,"boost":1.25,"power":1.50,"slide_grip":1.65,"slide_yaw":1.45},
	"tank":{"launch":3.2,"stop":1.25,"steer":.92,"response":6.6,"suspension":.13,"boost":1.18,"power":1.35,"slide_grip":2.20,"slide_yaw":1.25},
	"heavyTank":{"launch":3.7,"stop":1.4,"steer":.82,"response":5.8,"suspension":.12,"boost":1.15,"power":1.30,"slide_grip":2.50,"slide_yaw":1.18},
}

static func reset(v: Dictionary) -> void:
	v.erase("render_vehicle_from");v.erase("render_vehicle_to")
	v.velocity=Vector2.ZERO;v.speed=0.0;v.throttle_input=0.0;v.brake_input=0.0;v.steer_input=0.0;v.steer_angle=0.0;v.yaw_rate=0.0
	v.drive_pitch=0.0;v.drive_roll=0.0;v.travel=0.0;v.track_distance=0.0;v.impact_cooldown=0.0;v.drive_blocked=false
	v.rebound_cooldown=0.0;v.contact_release=0.0;v.contact_age=1.0;v.contact_normal=Vector2.ZERO;v.contact_kick=Vector2.ZERO
	v.fall_speed=0.0;v.airborne=false;v.descending=false
	v.boost_input=0.0;v.handbrake_input=0.0;v.drift=0.0

static func wheel_turn(steer: float,speed: float,wheelbase: float,steering_limit: float,turning: float,grip: float) -> Vector2:
	# Racing controls: A/D request left/right steering lock. Signed travel speed
	# determines the resulting yaw, including natural counter-yaw while reversing.
	var wheel_angle=steer*steering_limit/(1.0+pow(absf(speed)/5.2,2))
	var yaw=speed/wheelbase*tan(wheel_angle)*turning
	var limit=5.8*grip/maxf(1.0,absf(speed))
	return Vector2(wheel_angle,clampf(yaw,-limit,limit))

static func update(world,v: Dictionary,throttle: float,steer: float,delta: float,brake: bool,boost: bool=false,parking: bool=false) -> void:
	if v.emplacement:return
	if not v.has("velocity"):reset(v)
	if not v.has("ground"):Ground.initialize(world.terrain,v,world)
	Ground.begin_step(v)
	var tune: Dictionary=TUNING[v.type];var p: Dictionary=v.profile;var tracks=Ground.tracked(v)
	var ground=Ground.sample(world.terrain,v,v.position,v.angle,true,world)
	v.ground=ground;v.impact_cooldown=maxf(0,v.impact_cooldown-delta)
	v.rebound_cooldown=maxf(0,float(v.get("rebound_cooldown",0))-delta)
	v.contact_release=maxf(0,float(v.get("contact_release",0))-delta);v.contact_kick=Vector2.ZERO
	v.contact_age=minf(1.0,float(v.get("contact_age",1.0))+delta)
	var condition=preload("res://scripts/vehicle_durability.gd").mobility(v)
	var mobility=condition.x;var turning=condition.y
	var forward=Vector2.from_angle(v.angle);var side=Vector2(-forward.y,forward.x)
	# Briefly unload the engine into a touched surface, while reverse and steering stay live.
	if v.contact_release>0 and (forward*throttle).dot(v.get("contact_normal",Vector2.ZERO))<-.01:throttle=0.0;v.throttle_input=0.0
	var speed: float=v.velocity.dot(forward);var previous_speed=speed;var lateral: float=v.velocity.dot(side)
	var reverse_brake=throttle*speed<-.035
	v.throttle_input=move_toward(v.throttle_input,throttle,delta*5.5)
	v.steer_input=lerpf(v.steer_input,steer,1.0-exp(-delta*float(tune.response)))
	var grounded=not bool(v.get("airborne",false))
	var grip: float=ground.grip
	var boost_target=1.0 if boost and throttle>0 and not brake and not parking and not reverse_brake and grounded else 0.0
	v.boost_input=move_toward(float(v.get("boost_input",0)),boost_target,delta*2.8)
	v.handbrake_input=move_toward(float(v.get("handbrake_input",0)),1.0 if brake and not parking and grounded else 0.0,delta*(9.0 if brake else 2.4))
	var boost_scale=lerpf(1.0,float(tune.boost),v.boost_input)
	var top=float(p.maxSpeed)/40.0*mobility*ground.speed*boost_scale
	var backwards=float(p.reverseSpeed)/40.0*mobility*ground.speed
	var braking=brake or parking or reverse_brake
	v.brake_input=move_toward(float(v.get("brake_input",0)),1.0 if braking else 0.0,delta*6.0)
	if braking:
		# At speed, locking the rear axle trades some stopping force for a slide.
		# Low-speed parking and opposite-throttle braking retain the full brake force.
		var brake_scale=lerpf(1.0,.46 if tracks else .28,clampf((absf(speed)-.6)/1.8,0,1)) if brake and not parking and not reverse_brake else 1.0
		if grounded:speed=move_toward(speed,0,float(p.maxSpeed)/40.0/float(tune.stop)*grip*v.brake_input*brake_scale*delta)
		v.throttle_input=0.0
	elif grounded:
		var target=(top if v.throttle_input>=0 else backwards)*v.throttle_input
		if absf(throttle)>.01:
			var acceleration=float(p.maxSpeed)/40.0/float(tune.launch)*(.35+.65*mobility)*grip*lerpf(1.0,float(tune.power),v.boost_input)
			speed=move_toward(speed,target,acceleration*delta)
		else:speed=move_toward(speed,0,(float(ground.drag)+.028*speed*speed)*delta)
		# Low gearing and automatic hill hold keep starts controllable; slopes resist travel.
		speed-=float(ground.slope.x)*absf(speed)*.70*delta
		# Entering rock / soft ground reduces speed progressively instead of snapping to a new cap.
		speed=move_toward(speed,clampf(speed,-backwards*1.10,top*1.12),float(p.maxSpeed)/40.0/float(tune.stop)*.45*delta)
		# Boost release sheds excess speed progressively, without snapping to the old cap.
		speed=clampf(speed,-float(p.reverseSpeed)/40.0*1.10,float(p.maxSpeed)/40.0*float(tune.boost)*1.12)
	if absf(speed)<.025 and (braking or absf(throttle)<.01):speed=0.0
	# All mobile vehicles share racing-style intent. Tracks retain a tighter
	# effective turn radius and their damage response, without stationary pivoting.
	var wheelbase=Dimensions.for_vehicle(v).half.x*(1.0 if tracks else 1.22)
	var turn=wheel_turn(v.steer_input,speed,wheelbase,float(tune.steer)*(.64 if tracks else 1.0),turning,grip)
	v.steer_angle=turn.x
	var slide=float(v.handbrake_input)*clampf((absf(speed)-.65)/2.0,0,1)
	var desired_yaw=turn.y*lerpf(1.0,float(tune.slide_yaw),slide)
	if tracks:desired_yaw=clampf(desired_yaw,-float(p.steerRate)*turning,float(p.steerRate)*turning)
	if grounded:v.yaw_rate=lerpf(v.yaw_rate,desired_yaw,1.0-exp(-delta*lerpf(8.0 if tracks else 11.0,4.5,slide)))
	if speed==0 and grounded:v.yaw_rate=0.0
	# Keep world-space momentum through a turn; tires progressively remove lateral
	# velocity. Handbrake release restores this grip over time, rather than snapping.
	if grounded:
		var lateral_grip=lerpf(lerpf(4.0,13.0,grip),float(tune.slide_grip)*grip,slide)
		lateral*=exp(-delta*lateral_grip)
		if parking:lateral=move_toward(lateral,0,6.0*grip*delta)
	var velocity=forward*speed+side*lateral
	var steps=maxi(1,ceili(maxf(velocity.length()*delta,absf(v.yaw_rate)*Dimensions.for_vehicle(v).half.length()*delta)/.10))
	steps=mini(steps,16)
	var dt=delta/steps;var old_position: Vector2=v.position;var old_angle: float=v.angle
	v.drive_blocked=false
	for i in range(steps):
		var response=Contact.move(world,v,velocity,v.yaw_rate,dt)
		velocity=response.velocity;v.yaw_rate=response.yaw;v.drive_blocked=v.drive_blocked or response.collided
		if response.collided and response.strength>2.2 and v.impact_cooldown<=0:
			var target: Dictionary=response.target
			if not target.is_empty() and target.alive and target.destructible and target.kind in ["barrier","sandbag","jungle"]:
				world.damage_object(target,response.point,v.elevation+.45,minf(65,response.strength*7),false)
			v.impact_cooldown=.35
	# A collision at the end of a frame must preserve its outgoing impulse for the next frame.
	v.velocity=velocity if v.drive_blocked else (v.position-old_position)/maxf(.0001,delta)
	v.speed=v.velocity.dot(Vector2.from_angle(v.angle))
	var slip_speed=absf(v.velocity.dot(Vector2(-sin(v.angle),cos(v.angle))))
	v.drift=clampf((slip_speed-.25)/2.0,0,1) if grounded and v.velocity.length()>1.0 else 0.0
	var distance=v.position.distance_to(old_position);v.travel+=distance;v.track_distance+=distance+absf(wrapf(v.angle-old_angle,-PI,PI))*Dimensions.for_vehicle(v).half.y
	var acceleration=clampf((v.speed-previous_speed)/maxf(.001,delta),-8,8)
	var sway=.25 if v.ground.get("rock_contacts",0)>0 else 1.0
	v.drive_pitch=clampf(lerpf(v.drive_pitch+v.contact_kick.x,-acceleration*.0035*sway,1.0-exp(-delta*7.5)),-.06,.06)
	v.drive_roll=clampf(lerpf(v.drive_roll+v.contact_kick.y,-v.speed*v.yaw_rate*.0045*sway,1.0-exp(-delta*7)),-.06,.06)
	var final_ground=Ground.sample(world.terrain,v,v.position,v.angle,true,world)
	final_ground=Vertical.settle(world,v,final_ground,delta);v.ground=final_ground
	v.pose_basis=Ground.basis(v.angle,final_ground.normal)*Basis(Vector3.RIGHT,v.drive_pitch)*Basis(Vector3.FORWARD,v.drive_roll)
	if v.contact_release>0 and Collision.blocked(world,v):v.pose_basis=Ground.basis(v.angle,final_ground.normal)
	if v.track_distance>=.30:
		v.track_distance=fmod(v.track_distance,.30);world.event.emit({"type":"vehicle_ground","vehicle":v})
	if world.campaign_active():world.campaign_ai.invalidate_vehicle(v)
	Ground.end_step(v)

static func transition(v: Dictionary,support: Dictionary,point: Vector2) -> bool:
	return Contact.transition(v,support,point)

static func place(world,v: Dictionary,point: Vector2,angle: float) -> bool:
	var support=Ground.sample(world.terrain,v,point,angle,true,world)
	var probe=v.duplicate();probe.position=point;probe.angle=angle
	probe.elevation=support.height;probe.pose_basis=Ground.basis(angle,support.normal)
	if not support.passable or world.vehicle_blocked(probe,point):return false
	reset(v);v.position=point;v.angle=angle;Ground.initialize(world.terrain,v,world)
	if world.campaign_active():world.campaign_ai.invalidate_vehicle(v)
	return true

static func update_wheels(view: Dictionary,v: Dictionary,terrain,delta: float) -> void:
	GroundEffects.update_shadow(view,v,terrain)
	if v.destroyed:return
	var tracks=Ground.tracked(v);var scale: Vector3=Dimensions.for_vehicle(v).model_scale
	# Presentation follows the same left/right steering lock as the physical pose.
	if not tracks:view.wheel_steer=lerpf(float(view.get("wheel_steer",v.steer_angle)),float(v.steer_angle),1.0-exp(-delta*16.0))
	for wheel in view.wheels:
		if not wheel.has_meta("drive_rest"):
			wheel.set_meta("drive_rest",wheel.position);wheel.set_meta("drive_basis",wheel.basis);wheel.set_meta("drive_spin",0.0)
		var rest: Vector3=wheel.get_meta("drive_rest")
		var radius=.23 if tracks else .29 if v.type=="armedJeep" else .31
		var speed=float(v.speed)-(signf(rest.x)*float(v.yaw_rate)*absf(rest.x)*scale.x if tracks else 0.0)
		if tracks or rest.z>0:speed*=1.0-float(v.get("handbrake_input",0))
		var spin=float(wheel.get_meta("drive_spin"))+speed*delta/(radius*scale.y)
		wheel.set_meta("drive_spin",fposmod(spin,TAU))
		wheel.basis=Basis(Vector3.UP,-float(view.wheel_steer) if not tracks and rest.z<0 else 0.0)*wheel.get_meta("drive_basis")*Basis(Vector3.UP,spin)
		if tracks:continue # Road wheels stay inside the continuous track belt.
		var contact: Vector3=view.body.to_global(rest-Vector3.UP*radius)
		var travel=float(TUNING[v.type].suspension)/scale.y
		var support=Offroad.contact(terrain,v.get("ground",{}).get("rocks",[]),Vector2(contact.x,contact.z),radius*scale.y,v)
		support=Ground.Structure.contact(support,v.get("ground",{}).get("structures",[]),Vector2(contact.x,contact.z),radius*scale.y)
		var offset=(support.height-contact.y)/maxf(.3,view.body.global_basis.y.y)
		wheel.position.y=lerpf(wheel.position.y,rest.y+clampf(offset,-travel,travel),1.0-exp(-delta*20))
