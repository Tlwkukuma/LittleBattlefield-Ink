extends RefCounted
## Static scenery beyond a physical, height-field ridge. No expanded AI grid.
const WIDTH=2.0
const RINGS=[0.0,2.0,6.0,14.0,30.0,64.0,96.0]

static func weight(p: Vector2,bounds: Vector2) -> float:
	var t=clampf(1.0-minf(bounds.x-absf(p.x),bounds.y-absf(p.y))/WIDTH,0,1)
	return t*t*(3.0-2.0*t)

static func crest(p: Vector2) -> float:
	return 3.5+.45*sin(p.x*.33)+.35*cos(p.y*.28)

static func relief(p: Vector2,bounds: Vector2) -> float:
	return crest(p)*weight(p,bounds)

static func pigment(p: Vector2) -> Color:
	return Color("8f947b").lerp(Color("a89b80"),.5+.5*sin(p.x*.21+p.y*.17))

static func append_exterior(terrain,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray):
	var edge: Array[Vector3]=[]
	for x in range(terrain.size.x):edge.append(terrain.vertex(x,0))
	for z in range(terrain.size.y):edge.append(terrain.vertex(terrain.size.x,z))
	for x in range(terrain.size.x,0,-1):edge.append(terrain.vertex(x,terrain.size.y))
	for z in range(terrain.size.y,0,-1):edge.append(terrain.vertex(0,z))
	var previous=edge
	for ring in range(1,RINGS.size()):
		var distance: float=RINGS[ring];var next: Array[Vector3]=[]
		for base in edge:
			var p=Vector2(base.x,base.z)*(terrain.bounds+Vector2.ONE*distance)/terrain.bounds
			var hills=5.0+1.7*sin(p.x*.11)+1.2*cos(p.y*.14)+.6*sin((p.x+p.y)*.23)
			var h=lerpf(base.y,hills,clampf(distance/6.0,0,1))
			next.append(Vector3(p.x,h,p.y))
		for i in range(edge.size()):
			var j=(i+1)%edge.size()
			for tri in [[previous[i],next[i],previous[j]],[previous[j],next[i],next[j]]]:
				var normal: Vector3=(tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
				# Perimeter runs clockwise in XZ; retain upward-facing triangles.
				if normal.y<0:tri.reverse();normal=-normal
				for point in tri:
					v.append(point);n.append(normal)
					c.append(pigment(Vector2(point.x,point.z)))
		previous=next
