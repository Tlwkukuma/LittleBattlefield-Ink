extends RefCounted
## Contact response shares the same terrain, live solids and vehicle poses as movement.
const Ground=preload("res://scripts/vehicle_grounding.gd")
const Collision=preload("res://scripts/vehicle_collision.gd")
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Offroad=preload("res://scripts/vehicle_offroad.gd")
const Runover=preload("res://scripts/vehicle_runover.gd")
# Gameplay response, not real-world vehicle masses: restitution / maximum rebound speed.
const REBOUND={"armedJeep":Vector2(.23,1.35),"scoutCar":Vector2(.20,1.15),"apc":Vector2(.15,.95),"ifv":Vector2(.14,.90),"lightTank":Vector2(.17,1.05),"tank":Vector2(.12,.80),"heavyTank":Vector2(.10,.65)}

static func transition(v: Dictionary,support: Dictionary,point: Vector2) -> bool:
	if not support.passable and not Ground.descending(v,support,point) and not recovering_support(v,support):return false
	var previous: Array=v.get("ground",{}).get("contacts",[])
	var limit=float(Offroad.profile(v).step)+v.position.distance_to(point)*float(Offroad.profile(v).grade)
	for i in range(mini(previous.size(),support.contacts.size())):
		if support.contacts[i].height-previous[i].height>limit:return false
	return true

static func support_errors(support: Dictionary,capability: Dictionary) -> Vector4:
	return Vector4(maxf(0,absf(support.slope.x)/float(capability.grade)-1),maxf(0,absf(support.slope.y)/float(capability.cross)-1),maxf(0,float(support.residual)/float(capability.articulation)-1),maxf(0,(float(support.belly)-.011)/.10))

static func recovering_support(v: Dictionary,support: Dictionary) -> bool:
	var previous: Dictionary=v.get("ground",{})
	if previous.is_empty() or previous.passable or support.get("flooded",false) or not is_finite(float(support.get("support_lift",0))):return false
	var capability=Offroad.profile(v);var before=support_errors(previous,capability);var after=support_errors(support,capability)
	# Allow only monotonic escape from an already invalid support pose. Solid
	# collision is still checked by pose(); entry into an unsafe slope stays blocked.
	for axis in range(4):
		if after[axis]>before[axis]+.00001:return false
	return after.length_squared()<before.length_squared()-.000001 or float(support.height)<float(previous.height)-.0001

static func pose(world,v: Dictionary,point: Vector2,angle: float) -> Dictionary:
	var support=Ground.sample(world.terrain,v,point,angle,false,world)
	var allowed=transition(v,support,point)
	var descending=Ground.descending(v,support,point)
	if descending:support=Ground.descent_support(support)
	var probe=v.duplicate();probe.position=point;probe.angle=angle
	probe.elevation=maxf(float(v.elevation),float(support.height)) if v.has("fall_speed") else support.height
	probe.pose_basis=Ground.basis(angle,support.normal);probe.ground=support
	probe.descending=descending or (v.get("descending",false) and not support.passable)
	var contact={};var blocked=Collision.blocked(world,probe,contact)
	return {"probe":probe,"allowed":allowed and not blocked,"contact":contact}

static func accept(v: Dictionary,probe: Dictionary) -> void:
	v.position=probe.position;v.angle=probe.angle;v.elevation=probe.elevation;v.pose_basis=probe.pose_basis;v.ground=probe.ground
	v.descending=bool(probe.get("descending",false))
	for key in ["collision_pose","collision_height_pose","collision_destroyed","collision_boxes","collision_bounds","vehicle_sat_cache","vehicle_rock_recipe"]:
		if probe.has(key):v[key]=probe[key]

static func sweep(world,v: Dictionary,displacement: Vector2,rotation: float) -> Dictionary:
	var end=pose(world,v,v.position+displacement,wrapf(v.angle+rotation,-PI,PI))
	if end.allowed:return {"fraction":1.0,"probe":end.probe,"contact":{}}
	var low=0.0;var high=1.0;var safe=v.duplicate();var blocked=end
	# Movement is already subdivided to <= 10 cm; refine only the blocked substep.
	for i in range(6):
		var mid=(low+high)*.5
		var candidate=pose(world,v,v.position+displacement*mid,wrapf(v.angle+rotation*mid,-PI,PI))
		if candidate.allowed:low=mid;safe=candidate.probe
		else:high=mid;blocked=candidate
	return {"fraction":low,"probe":safe,"end_probe":end.probe,"contact":blocked.contact}

static func reflect_velocity(velocity: Vector2,normal: Vector2,rebound: float) -> Vector2:
	var inward=minf(0,velocity.dot(normal))
	# Preserve tangential travel on a scrape; a head-on impact keeps only its rebound.
	var tangent=(velocity-normal*inward)*.94 if inward<0 else velocity
	return tangent+normal*rebound

static func move(world,v: Dictionary,velocity: Vector2,yaw: float,delta: float) -> Dictionary:
	# No displacement means there is no sweep to bisect, even on a non-passable pose.
	# Ground settlement is still evaluated by vehicle_dynamics at the end of the tick.
	if velocity.length_squared()<.0000000001 and absf(yaw)<.000001:
		return {"velocity":velocity,"yaw":yaw,"collided":false,"strength":0.0,"target":{},"point":v.position}
	var remaining=delta;var collided=false;var damage_target: Dictionary={};var strength=0.0;var impact_point: Vector2=v.position
	var incoming=velocity;var start: Vector2=v.position;var start_angle: float=v.angle;var strongest_rebound=0.0
	for iteration in range(3):
		var result=sweep(world,v,velocity*remaining,yaw*remaining)
		accept(v,result.probe)
		if result.fraction>=1:break
		collided=true;remaining*=1.0-result.fraction
		var contact: Dictionary=result.contact
		if contact.get("kind","")=="person":
			var body=Runover.resolve(world,v,contact,result.end_probe,velocity,yaw)
			velocity=body.velocity;yaw=body.yaw
			if body.cleared:
				# Re-query after moving or killing the body; scenery and other people still block.
				if iteration==2:
					var release=sweep(world,v,velocity*remaining,yaw*remaining)
					accept(v,release.probe)
				continue
		var normal: Vector2=contact.get("normal",-velocity.normalized())
		if normal.length_squared()<.01:normal=-Vector2.from_angle(v.angle)
		normal=normal.normalized()
		# Descending off a support can hit the underside while horizontal motion points
		# away from its separating face. Retreat along the checked approach in that case.
		if velocity.length_squared()>.0001 and velocity.dot(normal)>-.01 and absf(yaw)<.001:normal=-velocity.normalized()
		var lever: Vector2=contact.get("point",v.position)-v.position
		lever=lever.limit_length(Dimensions.for_vehicle(v).half.length())
		var rotational_speed=Vector2(-lever.y,lever.x)*yaw
		var approach=maxf(0,-velocity.dot(normal))+maxf(0,-rotational_speed.dot(normal))
		if approach<.025 and absf(yaw)>.001:
			approach=absf(yaw)*Dimensions.for_vehicle(v).half.length()*.5;yaw=0.0
		strength=maxf(strength,approach)
		var rebound=0.0
		var fresh=float(v.get("contact_age",INF))>.4 or v.get("contact_normal",Vector2.ZERO).dot(normal)<.5 or approach>1.0
		if fresh and approach>.025 and float(v.get("rebound_cooldown",0))<=0:
			var tuning: Vector2=REBOUND[v.type]
			rebound=clampf(approach*tuning.x,.12+tuning.x*.4,tuning.y)
			if contact.get("kind","")=="person":rebound=minf(.08,rebound*.1)
			v.rebound_cooldown=.35
			strongest_rebound=maxf(strongest_rebound,rebound)
			var forward=Vector2.from_angle(v.angle);var side=Vector2(-forward.y,forward.x)
			v.contact_kick=Vector2(-normal.dot(forward),normal.dot(side))*minf(.035,approach*.006)*sqrt(tuning.x/.23)
		v.contact_normal=normal;v.contact_release=.18;v.contact_age=0.0
		velocity=reflect_velocity(velocity,normal,rebound)
		# Let steering away from the touching corner continue; stop rotation into it.
		if rotational_speed.dot(normal)<-.001:yaw=0.0
		if damage_target.is_empty() and contact.get("kind","") in ["wall","solid","nature"]:damage_target=contact.get("target",{});impact_point=contact.get("point",v.position)
		if remaining<.00001:break
		if iteration==2:
			# Never spend unchecked residual travel at a corner with several contacts.
			var release=sweep(world,v,velocity*remaining,yaw*remaining)
			accept(v,release.probe)
			if release.fraction<1:
				velocity=Vector2.ZERO;yaw=0.0
				# Several small fitted parts can meet at a seam. Try a checked retreat along
				# the approach instead of cancelling the impact at that seam.
				if strongest_rebound>0:
					var retreat=(start-v.position).normalized() if start.distance_squared_to(v.position)>.000001 else -incoming.normalized()
					var recovery=sweep(world,v,retreat*strongest_rebound*remaining,wrapf(start_angle-v.angle,-PI,PI))
					accept(v,recovery.probe)
					if recovery.fraction>=1:velocity=retreat*strongest_rebound;v.contact_normal=retreat
	return {"velocity":velocity,"yaw":yaw,"collided":collided,"strength":strength,"target":damage_target,"point":impact_point}
