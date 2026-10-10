extends RefCounted
const Emplacement=preload("res://scripts/emplacement_profile.gd")
const Aim=preload("res://scripts/aim_geometry.gd")
const Parts=preload("res://scripts/vehicle_collision_parts.gd")
## Closed vehicles enlarged a further ~20%, anchored to the supplied soldier (~1.94 m).
## Footprints include running gear, but exclude projecting barrels and antennae.
const CHARACTER_HEIGHT = 1.94
const PROFILES = {
	"truck": {"footprint":Vector2(4.8,2.2),"source":Vector2(4.8,2.2),"deck":.9,"top":2.03,"turret":Vector2.ZERO,"cabin":true},
	"armedJeep": {"footprint":Vector2(3.00,1.82),"source":Vector2(2.225703,1.441),"deck":.82,"top":1.69,"turret":Vector2(.29,.27),"cabin":true},
	"scoutCar": {"footprint":Vector2(3.12,2.02),"source":Vector2(2.375203,1.6305),"deck":1.0,"top":1.42,"turret":Vector2(.45,.425)},
	"apc": {"footprint":Vector2(3.68,2.39),"source":Vector2(2.832453,1.92725),"deck":1.24,"top":1.69,"turret":Vector2(.315,.389)},
	"ifv": {"footprint":Vector2(3.90,2.54),"source":Vector2(3.038328,2.05391),"deck":.94,"top":1.46,"turret":Vector2(.70,.59)},
	"lightTank": {"footprint":Vector2(3.65,2.35),"source":Vector2(2.844333,1.92725),"deck":.84,"top":1.41,"turret":Vector2(.74,.49)},
	"tank": {"footprint":Vector2(4.07,2.69),"source":Vector2(3.167587,2.1385),"deck":.90,"top":1.60,"turret":Vector2(.94,.67)},
	"heavyTank": {"footprint":Vector2(4.50,2.93),"source":Vector2(3.620079,2.502),"deck":.95,"top":1.65,"turret":Vector2(1.10,.82)},
}

static func for_vehicle(v: Dictionary) -> Dictionary:
	if v.has("dimensions"): return v.dimensions
	if v.get("emplacement",false): return Emplacement.dimensions(v.type)
	if not PROFILES.has(v.type):
		return {"model_scale":Vector3.ONE,"half":Vector2(v.radius*1.4,v.radius*.8),"deck":1.9,"top":1.9,"turret":Vector2.ZERO,"cabin":false}
	var p: Dictionary = PROFILES[v.type]
	var factor: float = p.footprint.x / p.source.x
	var width_factor: float = p.footprint.y / p.source.y
	# Y and Z use the same factor, keeping wheel cross-sections circular.
	return {"model_scale":Vector3(width_factor,factor,factor),"half":p.footprint*.5,"deck":p.deck*factor,"top":p.top*factor,
		"turret":p.turret*Vector2(factor,width_factor),"cabin":p.get("cabin",false)}

static func hit_boxes(v: Dictionary) -> Array:
	var pose=Vector4(v.position.x,v.position.y,v.angle,v.turret_angle)
	var height_pose=Transform3D(body_basis(v),Vector3(0,float(v.get("elevation",0)),0))
	if v.get("collision_pose",Vector4.INF)==pose and v.get("collision_height_pose",Transform3D(Basis.IDENTITY,Vector3.INF))==height_pose and v.get("collision_destroyed",false)==v.get("destroyed",false) and v.has("collision_boxes"):return v.collision_boxes
	var boxes=build_hit_boxes(v)
	v.collision_pose=pose;v.collision_boxes=boxes;v.collision_height_pose=height_pose
	v.collision_destroyed=bool(v.get("destroyed",false))
	var low=Vector2(INF,INF);var high=-low
	for box in boxes:
		var half: Vector2=box.half
		var extent=Vector2(absf(cos(box.angle))*half.x+absf(sin(box.angle))*half.y,absf(sin(box.angle))*half.x+absf(cos(box.angle))*half.y)
		low=low.min(box.center-extent);high=high.max(box.center+extent)
	v.collision_bounds=Rect2(low,high-low)
	return boxes

static func planar_bounds(v: Dictionary) -> Rect2:
	hit_boxes(v)
	return v.collision_bounds

static func might_contain(v: Dictionary,point: Vector2,padding: float) -> bool:
	# A rotation-invariant sphere around ALL authored solid parts rejects distant
	# walkers before validating/rebuilding the vehicle's detailed pose and boxes.
	# Nearby queries still use the exact current tilted parts, gaps and heights.
	var scale: Vector3=for_vehicle(v).get("model_scale",Vector3.ONE)
	if not v.has("body_query_radius") or v.get("body_query_scale",Vector3.ZERO)!=scale or v.get("body_query_type","")!=v.type:
		var radius=0.0
		if v.get("emplacement",false):
			Emplacement.hit_boxes(v)
			for box in v.emplacement_boxes:radius=maxf(radius,box.offset.length()+box.half.length())
		else:
			hit_boxes(v)
			for part in v.collision_parts:radius=maxf(radius,((part.at*scale).abs()+part.size*scale*.5).length())
			var pivot=turret_offset(v)
			for part in v.collision_turret_parts:radius=maxf(radius,pivot.length()+((part.at*scale-pivot).abs()+part.size*scale*.5).length())
		v.body_query_radius=radius+.001;v.body_query_scale=scale;v.body_query_type=v.type
	return point.distance_squared_to(v.position)<=pow(float(v.body_query_radius)+padding,2)

static func build_hit_boxes(v: Dictionary) -> Array:
	if v.get("emplacement",false): return Emplacement.hit_boxes(v)
	var d = for_vehicle(v)
	var pose=Transform3D(body_basis(v),Vector3(v.position.x,float(v.get("elevation",0)),v.position.y))
	var box_basis=Basis(Vector3.UP,PI*.5)
	if not v.has("collision_parts"):
		var r=float(v.profile.get("radius",35))/40.0
		v.collision_parts=Parts.body(v.type,r,PROFILES[v.type].source.y)
		v.collision_turret_parts=Parts.turret(v.type,r)
	var shapes=[]
	for part in v.collision_parts:
		var at: Vector3=part.at*d.model_scale;var size: Vector3=part.size*d.model_scale
		var frame=pose*Transform3D(box_basis,Vector3(at.x,0,at.z))
		var box=shape(frame,Vector2(size.z,size.x)*.5,at.y-size.y*.5,at.y+size.y*.5,v.angle)
		box.gear=part.gear;box.body=true;box.along=-at.z;shapes.append(box)
	var turret_frame=Transform3D(turret_basis(v),pose*turret_offset(v))
	for part in v.collision_turret_parts:
		var at: Vector3=part.at*d.model_scale-turret_offset(v);var size: Vector3=part.size*d.model_scale
		shapes.append(shape(turret_frame*Transform3D(box_basis,Vector3(at.x,0,at.z)),Vector2(size.z,size.x)*.5,at.y-size.y*.5,at.y+size.y*.5,v.turret_angle))
	return shapes

static func body_basis(v: Dictionary) -> Basis:
	if v.has("pose_basis"):return v.pose_basis
	return Basis(Vector3.UP,-v.angle-PI*.5)

static func turret_basis(v: Dictionary) -> Basis:
	var up=body_basis(v).y.normalized()
	var forward=Vector3(cos(v.turret_angle),-(up.x*cos(v.turret_angle)+up.z*sin(v.turret_angle))/maxf(.1,up.y),sin(v.turret_angle)).normalized()
	var basis=Basis(forward.cross(up).normalized(),up,-forward)
	if v.get("destroyed",false) and not v.get("emplacement",false):basis=basis*Basis(Vector3.FORWARD,.18)*Basis(Vector3.RIGHT,-.065)
	return basis

static func shape(frame: Transform3D,half: Vector2,bottom: float,top: float,angle: float) -> Dictionary:
	var low=Vector3(-half.x,bottom,-half.y);var high=Vector3(half.x,top,half.y)
	var center=frame*((low+high)*.5);var extent=(high-low)*.5
	var x=Vector3(cos(angle),0,sin(angle));var z=Vector3(-sin(angle),0,cos(angle))
	var projected=Vector2.ZERO;var vertical=0.0
	for i in range(3):
		projected+=Vector2(absf(frame.basis[i].dot(x)),absf(frame.basis[i].dot(z)))*extent[i]
		vertical+=absf(frame.basis[i].y)*extent[i]
	return {"frame":frame,"inverse":frame.affine_inverse(),"low":low,"high":high,"center3":center,"extent":extent,
		"center":Vector2(center.x,center.z),"angle":angle,"half":projected,"bottom":center.y-vertical,"top":center.y+vertical}

static func frame_for(box: Dictionary) -> Transform3D:
	return box.get("frame",Transform3D(Basis(Vector3.UP,-box.angle),Vector3(box.center.x,0,box.center.y)))

static func limits(box: Dictionary) -> Array:
	return [box.low,box.high] if box.has("frame") else [Vector3(-box.half.x,box.bottom,-box.half.y),Vector3(box.half.x,box.top,box.half.y)]

static func ray(box: Dictionary,origin: Vector3,direction: Vector3,limit: float,pad: Vector3) -> float:
	var inverse: Transform3D=box.inverse if box.has("inverse") else frame_for(box).affine_inverse()
	var ends=limits(box)
	return Aim.box_hit(inverse*origin,inverse.basis*direction,ends[0]-pad,ends[1]+pad,limit)

static func vertical_span(box: Dictionary,point: Vector2,radius: float=0.0) -> Vector2:
	var inverse: Transform3D=box.inverse if box.has("inverse") else frame_for(box).affine_inverse()
	var at=inverse*Vector3(point.x,0,point.y);var along=inverse.basis*Vector3.UP
	var ends=limits(box);var low: Vector3=ends[0]-Vector3(radius,0,radius);var high: Vector3=ends[1]+Vector3(radius,0,radius)
	var enter=-INF;var leave=INF
	for axis in range(3):
		if absf(along[axis])<.000001:
			if at[axis]<low[axis] or at[axis]>high[axis]:return Vector2(INF,-INF)
		else:
			var a=(low[axis]-at[axis])/along[axis];var b=(high[axis]-at[axis])/along[axis]
			enter=maxf(enter,minf(a,b));leave=minf(leave,maxf(a,b))
	return Vector2(enter,leave)

static func distance_to_shape(box: Dictionary,point: Vector3) -> float:
	var frame=frame_for(box);var local=frame.affine_inverse()*point;var ends=limits(box)
	return point.distance_to(frame*local.clamp(ends[0],ends[1]))

static func turret_offset(v: Dictionary) -> Vector3:
	var fraction: float={"ifv":-.13,"lightTank":-.17,"tank":-.12,"heavyTank":-.10}.get(v.type,0.0)
	return Vector3(0,0,fraction*float(v.profile.get("radius",35))/40.0)*for_vehicle(v).model_scale

static func turret_position(v: Dictionary) -> Vector2:
	var offset=body_basis(v)*turret_offset(v)
	return v.position+Vector2(offset.x,offset.z)

static func exit_point(v: Dictionary, direction: Vector2, clearance: float) -> Vector2:
	var half: Vector2 = for_vehicle(v).half
	var local: Vector2 = direction.rotated(-v.angle)
	var edge: float = minf(half.x/maxf(.0001,absf(local.x)),half.y/maxf(.0001,absf(local.y)))
	return v.position+direction*(edge+clearance)
