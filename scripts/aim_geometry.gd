extends RefCounted
static func box_normal(point: Vector3,low: Vector3,high: Vector3) -> Vector3:
	var nearest:=INF;var normal:=Vector3.UP
	for axis: int in range(3):
		for side: int in [-1,1]:
			var distance:=absf(point[axis]-(low[axis] if side<0 else high[axis]))
			if distance<nearest:nearest=distance;normal=Vector3.ZERO;normal[axis]=side
	return normal

## Parametric rays: direction need not be normalized (ballistics uses horizontal metres).
static func box_hit(origin: Vector3,direction: Vector3,low: Vector3,high: Vector3,limit: float) -> float:
	var enter:=0.0;var leave:=limit
	for axis: int in range(3):
		if absf(direction[axis])<.000001:
			if origin[axis]<low[axis] or origin[axis]>high[axis]:return INF
		else:
			var a:=(low[axis]-origin[axis])/direction[axis];var b:=(high[axis]-origin[axis])/direction[axis]
			enter=maxf(enter,minf(a,b));leave=minf(leave,maxf(a,b))
			if leave<enter:return INF
	return enter

static func box_span(origin: Vector3,direction: Vector3,low: Vector3,high: Vector3,limit: float) -> Vector2:
	var enter:=0.0;var leave:=limit
	for axis: int in range(3):
		if absf(direction[axis])<.000001:
			if origin[axis]<low[axis] or origin[axis]>high[axis]:return Vector2(INF,INF)
		else:
			var a:=(low[axis]-origin[axis])/direction[axis];var b:=(high[axis]-origin[axis])/direction[axis]
			enter=maxf(enter,minf(a,b));leave=minf(leave,maxf(a,b))
			if leave<enter:return Vector2(INF,INF)
	return Vector2(enter,leave)

static func sphere_hit(origin: Vector3,direction: Vector3,center: Vector3,radius: float) -> float:
	var offset:=origin-center;var a:=direction.length_squared();var b:=offset.dot(direction);var c:=offset.length_squared()-radius*radius
	if c<=0:return 0.0
	if a<.000001:return INF
	var h:=b*b-a*c
	if h<0:return INF
	var t:=(-b-sqrt(h))/a
	return t if t>=0 else INF

static func capsule_hit(origin: Vector3,direction: Vector3,start: Vector3,end: Vector3,radius: float) -> float:
	var ba:=end-start;var oa:=origin-start;var length2:=ba.length_squared()
	if length2<.000001:return sphere_hit(origin,direction,start,radius)
	if origin.distance_squared_to(start+ba*clampf(oa.dot(ba)/length2,0,1))<=radius*radius:return 0.0
	var axis_ray:=ba.dot(direction);var axis_origin:=ba.dot(oa)
	var a:=length2*direction.length_squared()-axis_ray*axis_ray
	var b:=length2*oa.dot(direction)-axis_origin*axis_ray
	var c:=length2*oa.length_squared()-axis_origin*axis_origin-radius*radius*length2
	var h:=b*b-a*c;var t:=INF
	if a>.000001 and h>=0:
		var candidate:=(-b-sqrt(h))/a;var y:=axis_origin+candidate*axis_ray
		if candidate>=0 and y>0 and y<length2:t=candidate
	return minf(t,minf(sphere_hit(origin,direction,start,radius),sphere_hit(origin,direction,end,radius)))
