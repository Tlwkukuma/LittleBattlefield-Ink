extends RefCounted
## Independent game-space lob solver. Preview and flight share this trajectory/sweep.
const GRAVITY=14.0
const RADIUS=.085
const STEP=1.0/60.0
const OVERHAND_ANGLE=28.0
const UNDERHAND_ANGLE=12.0
const VehicleDimensions=preload("res://scripts/vehicle_dimensions.gd")

static func max_range(w: Dictionary,stance: int,low: bool) -> float:
	return float(w.get("range",780))/40.0*[1.0,.82,.54][clampi(stance,0,2)]*(.58 if low else 1.0)

static func speed_limit(w: Dictionary,stance: int,low: bool) -> float:
	# Game-scale tuning, not claimed PUBG asset values. Underarm is a short toss.
	return (8.5 if low or stance==2 else 18.0)*sqrt([1.0,.82,.54][clampi(stance,0,2)])*sqrt(clampf(float(w.get("range",780))/780.0,.6,1.4))

static func solve(origin: Vector3,target: Vector3,w: Dictionary,stance: int,low: bool,forward: Vector2=Vector2.UP) -> Dictionary:
	low=low or stance==2
	var reach=max_range(w,stance,low);var offset=Vector2(target.x-origin.x,target.z-origin.z)
	var wanted=offset.length();var direction=offset.normalized() if wanted>.01 else forward.normalized()
	var distance=clampf(wanted,.30,reach)
	var rise=target.y+RADIUS-origin.y
	var angle=deg_to_rad(UNDERHAND_ANGLE if low else OVERHAND_ANGLE)
	# Elevated surfaces require a steeper throw; never invent unlimited lift/speed.
	angle=maxf(angle,minf(atan2(rise,distance)+deg_to_rad(8),deg_to_rad(38 if low else 65)))
	var denominator=2*pow(cos(angle),2)*(distance*tan(angle)-rise)
	var cap=speed_limit(w,stance,low)
	var required=sqrt(GRAVITY*distance*distance/denominator) if denominator>.00001 else INF
	var speed=minf(required,cap);var vertical=speed*sin(angle);var horizontal=speed*cos(angle)
	var velocity=Vector3(direction.x*horizontal,vertical,direction.y*horizontal)
	var limited=wanted>reach+.05 or required>cap+.001
	var duration=distance/maxf(.001,horizontal)
	if required>cap+.001:
		# For unreachable heights preview the actual descending flight. A guide must
		# not end in mid-air at an impossible cursor point or force the grenade there.
		var level=minf(rise,0.0)
		duration=(vertical+sqrt(maxf(0,vertical*vertical-2*GRAVITY*level)))/GRAVITY
	var goal=position_at(origin,velocity,duration)
	return {"origin":origin,"velocity":velocity,"target":goal,"requested_target":target,"flight":duration,"aim_distance":distance,"distance":Vector2(goal.x-origin.x,goal.z-origin.z).length(),
		"power":clampf(speed/cap,0,1),"limited":limited,"low":low,"radius":RADIUS,"angle":angle,"speed":speed}

static func position_at(origin: Vector3,velocity: Vector3,time: float) -> Vector3:
	return origin+velocity*time+Vector3.DOWN*(.5*GRAVITY*time*time)

static func box_normal(point: Vector3,low: Vector3,high: Vector3) -> Vector3:
	var nearest=INF;var normal=Vector3.UP
	for axis in range(3):
		for side in [-1,1]:
			var distance=absf(point[axis]-(low[axis] if side<0 else high[axis]))
			if distance<nearest:nearest=distance;normal=Vector3.ZERO;normal[axis]=side
	return normal

static func normal_for(world,hit: Dictionary,point: Vector3,flight: Vector3,radius: float) -> Vector3:
	if hit.has("normal"):return hit.normal
	if hit.type=="terrain":
		if not world.terrain.active:return Vector3.UP
		var triangle: Array=world.terrain.triangle(Vector2(point.x,point.z))
		var normal: Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
		return normal if normal.y>=0 else -normal
	var normal=-flight.normalized();var pad=Vector3.ONE*radius
	if hit.type=="object":
		var o: Dictionary=hit.target;var at=(Vector2(point.x,point.z)-o.position).rotated(-o.angle)
		var local_point=Vector3(at.x,point.y-o.elevation,at.y);var local=Vector3.UP
		if o.has("solid_parts"):
			# Floors, stairs and furniture use separate boxes, including empty space
			# underneath. Select the contacted face, not the object's overall bounds.
			var nearest=INF
			for part in o.solid_parts:
				if part.has("cell") and o.hp[part.cell]<=0:continue
				var low: Vector3=part.at-part.size*.5-pad;var high: Vector3=part.at+part.size*.5+pad
				var face=box_normal(local_point,low,high);var axis=face.abs().max_axis_index()
				var plane=float(low[axis] if face[axis]<0 else high[axis])
				var error=local_point.distance_squared_to(local_point.clamp(low,high))+pow(local_point[axis]-plane,2)
				if error<nearest:nearest=error;local=face
		else:
			var low=Vector3(-o.size.x*.5+int(hit.col)*o.cell_width,int(hit.row)*o.cell_height,-o.size.y*.5)
			var high=low+Vector3(o.cell_width,o.cell_height,o.size.y)
			local=box_normal(local_point,low-pad,high+pad)
		var flat=Vector2(local.x,local.z).rotated(o.angle);normal=Vector3(flat.x,local.y,flat.y)
	elif hit.type=="vehicle":
		var nearest=INF
		for box in VehicleDimensions.hit_boxes(hit.target):
			var frame=VehicleDimensions.frame_for(box);var ends=VehicleDimensions.limits(box)
			var local=frame.affine_inverse()*point;var low: Vector3=ends[0]-pad;var high: Vector3=ends[1]+pad
			var nearest_point=local.clamp(low,high);var error=local.distance_squared_to(nearest_point)
			if error<nearest:
				nearest=error;normal=(frame.basis*box_normal(local,low,high)).normalized()
	return normal

static func sweep(world,start: Vector3,end: Vector3,radius: float=RADIUS) -> Dictionary:
	var flight=end-start;var distance=flight.length()
	if distance<.000001:return {}
	var direction=flight/distance
	var hit: Dictionary=world.trace_3d(start,direction,distance,{"radius":radius},true)
	# World bullet rays use a point on terrain; test the grenade's underside too.
	var ground: Dictionary=world.terrain.ray(start-Vector3.UP*radius,direction,distance)
	if not ground.is_empty() and float(ground.distance)<float(hit.get("distance",INF)):hit=ground
	if hit.is_empty():return {}
	hit=hit.duplicate();hit.point=start+direction*float(hit.distance)
	hit.normal=normal_for(world,hit,hit.point,flight,radius)
	return hit

static func preview(world,solution: Dictionary) -> Dictionary:
	var points=PackedVector3Array([solution.origin]);var last: Vector3=solution.origin
	# Bounded first-contact guide, not a guessed final rest point after several bounces.
	var duration=minf(3.2,float(solution.flight)+.7)
	var segments=mini(80,maxi(18,ceili(duration/.035)))
	for i in range(1,segments+1):
		var point=position_at(solution.origin,solution.velocity,duration*float(i)/segments)
		var hit=sweep(world,last,point)
		if not hit.is_empty():
			points.append(hit.point);return {"points":points,"hit":hit,"point":hit.point,"normal":hit.normal}
		points.append(point);last=point
	return {"points":points,"hit":{},"point":last,"normal":Vector3.UP}

static func motion(solution: Dictionary) -> Dictionary:
	return {"at":solution.origin,"velocity":solution.velocity,"radius":RADIUS,"bounces":0,"settled":false,"support_age":0.0,"spin":Vector3(6.4,2.1,4.7),"rotation":Vector3.ZERO}

static func response(velocity: Vector3,normal: Vector3,soft: bool=false) -> Vector3:
	var approach=velocity.dot(normal)
	if approach>=0:return velocity
	var tangent=velocity-normal*approach
	return tangent*(.57 if soft else .72)-normal*approach*(.14 if soft else .32)

static func advance(state: Dictionary,world,delta: float) -> Array:
	var contacts=[]
	if state.settled:
		state.support_age-=delta
		if state.support_age>0:return contacts
		state.support_age=.18
		if not sweep(world,state.at+Vector3.UP*.015,state.at-Vector3.UP*.075).is_empty():return contacts
		state.settled=false
	var remaining=delta;var iterations=0
	while remaining>.00001 and iterations<12:
		iterations+=1;var dt=minf(STEP,remaining);remaining-=dt
		var start: Vector3=state.at;var velocity: Vector3=state.velocity
		var end=position_at(start,velocity,dt);var hit=sweep(world,start,end,state.radius)
		if hit.is_empty():state.at=end;state.rotation+=state.spin*dt;state.velocity=velocity+Vector3.DOWN*GRAVITY*dt;continue
		var fraction=clampf(float(hit.distance)/maxf(.000001,start.distance_to(end)),0,1)
		state.rotation+=state.spin*dt*fraction
		velocity+=Vector3.DOWN*GRAVITY*dt*fraction
		var normal: Vector3=hit.normal
		state.at=hit.point+normal*.006
		var soft=str(hit.target.get("component_id",hit.target.get("kind",""))) in ["terrain.snow","terrain.desert","terrain.grass","sandbag"]
		var impact=maxf(0,-velocity.dot(normal));state.velocity=response(velocity,normal,soft);state.bounces+=1;state.spin*=.66
		if impact>.7:contacts.append({"position":state.at,"speed":impact,"soft":soft})
		# Continuous sweeps stop at the first face. Consume the residual substep after
		# separating from it, so wall impacts don't teleport to the endpoint or tunnel.
		if fraction>.02:remaining+=dt*(1-fraction)
		if normal.y>.55 and Vector3(state.velocity).length()<.65:
			state.velocity=Vector3.ZERO;state.spin=Vector3.ZERO;state.settled=true;state.support_age=.18;break
	return contacts
