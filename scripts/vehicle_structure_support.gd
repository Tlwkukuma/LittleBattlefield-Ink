extends RefCounted
## Reachable live floors and steps carry wheels/tracks just like the ground.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Collision=preload("res://scripts/vehicle_collision.gd")
const Offroad=preload("res://scripts/vehicle_offroad.gd")

static func nearby(world,v: Dictionary,at: Vector2,reach: float) -> Array:
	var result=[]
	if world==null:return result
	var ceiling=float(v.get("elevation",0))+float(Offroad.profile(v).step)+.012
	for o in world.candidates(at,at,reach):
		if not o.alive or not o.collision or not o.has("solid_parts"):continue
		if o.get("house_role","") not in ["floor","stairs"]:continue
		var frame=Transform3D(Basis(Vector3.UP,-o.angle),Vector3(o.position.x,o.elevation,o.position.y))
		for part in o.solid_parts:
			if part.has("cell") and o.hp[part.cell]<=0:continue
			var top=float(o.elevation)+part.at.y+part.size.y*.5
			if top>ceiling:continue # Never snap onto the storey above the vehicle.
			result.append({"object":o,"part":part,"frame":frame,"inverse":frame.affine_inverse(),"top":top,
				"shape":Collision.data(frame,part.at-part.size*.5,part.at+part.size*.5)})
	return result

static func contact(base: Dictionary,surfaces: Array,point: Vector2,radius: float) -> Dictionary:
	base.structure=false
	for surface in surfaces:
		var o: Dictionary=surface.object;var part: Dictionary=surface.part
		if not o.alive or (part.has("cell") and o.hp[part.cell]<=0):continue
		var local: Vector3=surface.inverse*Vector3(point.x,0,point.y)
		var p=Vector2(local.x-part.at.x,local.z-part.at.z);var half=Vector2(part.size.x,part.size.z)*.5
		var distance=p.distance_to(p.clamp(-half,half))
		if distance>radius+.00001:continue
		var height=float(surface.top)+sqrt(maxf(0,radius*radius-distance*distance))-radius
		if height>float(base.height):base.height=height;base.structure=true;base.rock="";base.timber=false
	return base

static func gear_lift(v: Dictionary,surfaces: Array) -> float:
	if surfaces.is_empty():return 0.0
	var lift=0.0;var shapes=[]
	for box in Dimensions.hit_boxes(v):
		if box.get("gear",false):shapes.append(Collision.shape_data(box))
	# The rectangular track collider reaches a lip before its axle probes do.
	# Resolve only that reachable support overlap, then recheck the complete hull.
	for surface in surfaces:
		for shape in shapes:
			if Collision.overlap(shape,surface.shape):lift=maxf(lift,float(surface.top)-float(shape.min.y)+Collision.SKIN+.001)
	return lift if lift<=float(Offroad.profile(v).step)+.012 else INF
