extends RefCounted
## The same occupied vehicle sections meet the upright walking body in both directions.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")

static func polygon(box: Dictionary,bottom: float,top: float) -> PackedVector2Array:
	var ends=Dimensions.limits(box);var frame=Dimensions.frame_for(box);var corners=[];var points=PackedVector2Array()
	for i in range(8):
		var p=frame*Vector3(ends[1].x if i&1 else ends[0].x,ends[1].y if i&2 else ends[0].y,ends[1].z if i&4 else ends[0].z)
		corners.append(p)
		if p.y>=bottom and p.y<=top:points.append(Vector2(p.x,p.z))
	for i in range(8):
		for mask in [1,2,4]:
			if i&mask:continue
			var a: Vector3=corners[i];var b: Vector3=corners[i|mask]
			if absf(a.y-b.y)<.000001:continue
			for height in [bottom,top]:
				var t=(height-a.y)/(b.y-a.y)
				if t>=0 and t<=1:
					var p=a.lerp(b,t);points.append(Vector2(p.x,p.z))
	return Geometry2D.convex_hull(points) if points.size()>=3 else PackedVector2Array()

static func circle_polygon(point: Vector2,radius: float,outline: PackedVector2Array) -> Dictionary:
	if outline.size()<3:return {}
	var nearest=Vector2.ZERO;var distance=INF
	for i in range(outline.size()-1):
		var at=Geometry2D.get_closest_point_to_segment(point,outline[i],outline[i+1]);var d=point.distance_to(at)
		if d<distance:distance=d;nearest=at
	var inside=Geometry2D.is_point_in_polygon(point,outline)
	var depth=radius+distance if inside else radius-distance
	if depth<=.001:return {}
	var normal=(nearest-point if inside else point-nearest).normalized()
	if normal.length_squared()<.1:normal=Vector2.RIGHT
	return {"depth":depth,"normal":normal,"point":nearest}

static func shape_contact(box: Dictionary,point: Vector2,radius: float,bottom: float,height: float) -> Dictionary:
	if bottom>=box.top-.001 or bottom+height<=box.bottom+.001:return {}
	var frame=Dimensions.frame_for(box)
	if absf(frame.basis.y.y)>.99999:
		# Exact circle / oriented rectangle distance avoids the square-expanded corner halo.
		var local=(point-box.center).rotated(-box.angle);var half: Vector2=box.half
		var nearest=local.clamp(-half,half);var delta=local-nearest;var distance=delta.length()
		var depth=radius-distance;var normal=delta.normalized()
		if distance<.000001:
			var gap=half-local.abs()
			if gap.x<gap.y:normal=Vector2(1 if local.x>=0 else -1,0);depth=radius+gap.x
			else:normal=Vector2(0,1 if local.y>=0 else -1);depth=radius+gap.y
			nearest=local+normal*(depth-radius)
		if depth<=.001:return {}
		return {"depth":depth,"normal":normal.rotated(box.angle),"point":box.center+nearest.rotated(box.angle)}
	return circle_polygon(point,radius,polygon(box,bottom+.001,bottom+height-.001))

static func contact(v: Dictionary,point: Vector2,radius: float,bottom: float,height: float,first_only: bool=false) -> Dictionary:
	if not Dimensions.might_contain(v,point,radius+.001):return {}
	if not Dimensions.planar_bounds(v).grow(radius+.001).has_point(point):return {}
	var result={}
	for box in Dimensions.hit_boxes(v):
		var hit=shape_contact(box,point,radius,bottom,height)
		if hit.is_empty():continue
		hit.gear=box.get("gear",false)
		if first_only:return hit
		if result.is_empty() or hit.depth>result.depth:result=hit
	return result
