extends RefCounted
## Presentation snapshots only. Collision, driving and shot origins stay physical.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")

static func pose(v: Dictionary) -> Dictionary:
	return {"position":Vector3(v.position.x,float(v.get("elevation",0)),v.position.y),
		"body":Dimensions.body_basis(v),"turret":Dimensions.turret_basis(v),"destroyed":v.destroyed}

static func before_step(vehicles: Array) -> void:
	for v in vehicles:
		if not v.emplacement:v.render_vehicle_from=pose(v)

static func after_step(vehicles: Array) -> void:
	for v in vehicles:
		if v.emplacement:continue
		var current=pose(v)
		var previous: Dictionary=v.get("render_vehicle_from",current)
		# Scene moves, resets and destruction must never interpolate across the map
		# or reuse the previous vehicle's live pose for a newly destroyed wreck.
		if previous.position.distance_squared_to(current.position)>4.0 or previous.destroyed!=current.destroyed:
			v.render_vehicle_from=current
		v.render_vehicle_to=current

static func sample(v: Dictionary,fraction: float) -> Dictionary:
	var current=pose(v)
	if v.has("net_motion_received_usec") and not v.destroyed:
		var age=clampf((Time.get_ticks_usec()-int(v.net_motion_received_usec))/1000000.0,0,float(v.get("net_motion_max_age",.1)))
		var velocity: Vector2=v.velocity
		current.position+=Vector3(velocity.x,0,velocity.y)*age
		return current
	var last: Dictionary=v.get("render_vehicle_to",{})
	if fraction>=1.0 or last.is_empty() or last!=current:return current
	var previous: Dictionary=v.get("render_vehicle_from",current)
	var alpha=clampf(fraction,0,1)
	return {"position":previous.position.lerp(current.position,alpha),
		"body":previous.body.slerp(current.body,alpha) if previous.body!=current.body else current.body,
		"turret":previous.turret.slerp(current.turret,alpha) if previous.turret!=current.turret else current.turret}
