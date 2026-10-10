extends RefCounted
## Interpolate only presentation. Simulation, muzzle and hit capsules stay authoritative.
static func position(unit: Dictionary) -> Vector3:
	return Vector3(unit.position.x,unit.elevation,unit.position.y)
static func before_step(units: Array):
	for unit in units:before_unit(unit)
static func before_unit(unit: Dictionary):
	unit.render_from=position(unit);unit.render_was_alive=unit.alive
static func after_step(units: Array):
	for unit in units:after_unit(unit)
static func after_unit(unit: Dictionary,clock: float=-1,duration: float=1.0/60):
	unit.render_to=position(unit)
	if not unit.get("render_was_alive",false) or unit.render_to.distance_squared_to(unit.get("render_from",unit.render_to))>4:
		unit.render_from=unit.render_to
	if clock>=0:unit.render_clock=clock;unit.render_duration=duration
static func sample(unit: Dictionary,alpha: float,clock: float=-1,physics_delta: float=1.0/60) -> Vector3:
	var current=position(unit)
	if unit.has("net_predicted_position") and unit.alive and unit.mounted<0:return unit.net_predicted_position
	if unit.has("net_motion_received_usec") and unit.alive and unit.mounted<0:
		# The client has no local simulation step. Use the last authoritative
		# velocity between network frames so 75 FPS presentation does not jump
		# at the 10/20 Hz snapshot cadence. Never advance the actual hit position.
		var age=clampf((Time.get_ticks_usec()-int(unit.net_motion_received_usec))/1000000.0,0,float(unit.get("net_motion_max_age",.1)))
		var motion: Vector2=unit.velocity
		return current+Vector3(motion.x,0,motion.y)*age
	# Direct editor/interaction teleports invalidate old interpolation endpoints.
	if alpha>=1 or unit.mounted>=0 or unit.get("render_to",Vector3.INF)!=current:return current
	if clock>=0 and unit.has("render_clock"):
		alpha=(clock-float(unit.render_clock)+alpha*physics_delta)/maxf(.0001,float(unit.render_duration))
	return Vector3(unit.get("render_from",current)).lerp(current,clampf(alpha,0,1))
