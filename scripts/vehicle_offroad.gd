extends RefCounted
## Vehicle-specific travel limits and rolling contact with low rocks and fallen timber.
const PROFILES={
	"armedJeep":{"label":"高机动越野","rock":.82,"step":.32,"clearance":.36,"grade":.72,"cross":.48,"articulation":.28,"compression":.12,"pace":.60},
	"scoutCar":{"label":"轻型轮式","rock":.60,"step":.24,"clearance":.30,"grade":.60,"cross":.42,"articulation":.23,"compression":.10,"pace":.52},
	"apc":{"label":"运输履带","rock":.78,"step":.40,"clearance":.36,"grade":.68,"cross":.48,"articulation":.49,"compression":0.0,"pace":.48},
	"ifv":{"label":"全地形履带","rock":.96,"step":.48,"clearance":.40,"grade":.78,"cross":.53,"articulation":.52,"compression":0.0,"pace":.58},
	"lightTank":{"label":"灵活履带","rock":1.00,"step":.50,"clearance":.41,"grade":.82,"cross":.56,"articulation":.55,"compression":0.0,"pace":.64},
	"tank":{"label":"重载越障","rock":1.08,"step":.56,"clearance":.43,"grade":.80,"cross":.55,"articulation":.58,"compression":0.0,"pace":.54},
	"heavyTank":{"label":"强越障 / 慢速","rock":1.16,"step":.62,"clearance":.44,"grade":.74,"cross":.51,"articulation":.62,"compression":0.0,"pace":.43},
}
const SUPPORT_CELL=.75
const SUPPORT_PAD=.5 # Covers every current wheel radius; larger queries use the full list.

static func profile(v: Dictionary) -> Dictionary:return PROFILES[v.type]

static func is_rock(o: Dictionary) -> bool:
	return o.alive and o.collision and str(o.get("component_id","")).begins_with("rock.") and o.has("nature_solids")

static func supports_part(o: Dictionary,v: Dictionary,part: Dictionary) -> bool:
	if not o.alive or not o.collision:return false
	if is_rock(o):return float(o.height)<=float(profile(v).rock)+.001
	# A tall broken branch must not make the entire low trunk an impassable wall.
	return o.get("component_id","")=="nature.fallen-log" and float(part.high)<=float(profile(v).rock)+.001

static func traversable(o: Dictionary,v: Dictionary) -> bool:
	for part in o.get("nature_solids",[]):
		if supports_part(o,v,part):return true
	return false

static func nearby(world,v: Dictionary,at: Vector2,reach: float) -> Array:
	var rocks=[]
	if world==null:return rocks
	for o in world.candidates(at,at,reach):
		if traversable(o,v) and o.position.distance_to(at)<reach+o.size.length()*.5:rocks.append(o)
	return rocks

static func faces(o: Dictionary) -> Array:
	var frame=Transform3D(Basis(Vector3.UP,-o.angle),Vector3(o.position.x,o.elevation,o.position.y))
	if o.has("vehicle_support_faces") and o.get("vehicle_support_frame",Transform3D(Basis.IDENTITY,Vector3.INF))==frame:return o.vehicle_support_faces
	var result=[];var grid={}
	for part in o.nature_solids:
		for tri in part.triangles:
			if tri[3].y<=.00001:continue
			var a: Vector3=frame*tri[0];var b: Vector3=frame*tri[1];var c: Vector3=frame*tri[2];var n: Vector3=frame.basis*tri[3]
			var polygon=[Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)]
			var low: Vector2=polygon[0].min(polygon[1]).min(polygon[2]);var high: Vector2=polygon[0].max(polygon[1]).max(polygon[2])
			var face={"points":polygon,"heights":[a.y,b.y,c.y],"gradient":Vector2(-n.x/n.y,-n.z/n.y),"bounds":Rect2(low,high-low),"part":part,"top":maxf(a.y,maxf(b.y,c.y))}
			result.append(face)
			# Expanded insertion means a rolling footprint needs one cell lookup, with no
			# duplicate faces and no scan over every separate stone in a scree cluster.
			for x in range(floori((low.x-SUPPORT_PAD-.001)/SUPPORT_CELL),floori((high.x+SUPPORT_PAD+.001)/SUPPORT_CELL)+1):
				for y in range(floori((low.y-SUPPORT_PAD-.001)/SUPPORT_CELL),floori((high.y+SUPPORT_PAD+.001)/SUPPORT_CELL)+1):
					var cell=Vector2i(x,y)
					if not grid.has(cell):grid[cell]=[]
					grid[cell].append(face)
	o.vehicle_support_faces=result;o.vehicle_support_grid=grid;o.vehicle_support_frame=frame;return result

static func nearby_faces(o: Dictionary,point: Vector2,radius: float) -> Array:
	var all_faces=faces(o)
	if radius>SUPPORT_PAD:return all_faces
	return o.vehicle_support_grid.get(Vector2i(floori(point.x/SUPPORT_CELL),floori(point.y/SUPPORT_CELL)),[])

static func inside(p: Vector2,triangle: Array) -> bool:
	var a: float=(triangle[1]-triangle[0]).cross(p-triangle[0]);var b: float=(triangle[2]-triangle[1]).cross(p-triangle[1]);var c: float=(triangle[0]-triangle[2]).cross(p-triangle[2])
	return (minf(a,minf(b,c))>=-.000001 or maxf(a,maxf(b,c))<=.000001)

static func face_height(face: Dictionary,p: Vector2,radius: float) -> float:
	if not face.bounds.grow(radius+.0001).has_point(p):return -INF
	var points: Array=face.points;var heights: Array=face.heights;var gradient: Vector2=face.gradient
	if radius<=.00001:
		return heights[0]+gradient.dot(p-points[0]) if inside(p,points) else -INF
	# Maximize surface height + circular wheel envelope over each triangle.
	# Interior optimum plus constrained edge optima avoids discrete probe pops at ledges.
	var result=-INF;var q=p+gradient*radius/sqrt(1+gradient.length_squared())
	if inside(q,points):result=heights[0]+gradient.dot(q-points[0])+sqrt(maxf(0,radius*radius-p.distance_squared_to(q)))-radius
	for i in range(3):
		var j=(i+1)%3;var edge: Vector2=points[j]-points[i];var length=edge.length()
		if length<.00001:continue
		var t0=(p-points[i]).dot(edge)/(length*length);var nearest: Vector2=points[i]+edge*t0
		var rr=radius*radius-p.distance_squared_to(nearest)
		if rr<0:continue
		var dy: float=heights[j]-heights[i];var reach=sqrt(rr)/length
		var low=maxf(0,t0-reach);var high=minf(1,t0+reach)
		if low>high:continue
		var t=clampf(t0+sqrt(rr)*dy/(length*sqrt(length*length+dy*dy)),low,high)
		q=points[i]+edge*t
		result=maxf(result,lerpf(heights[i],heights[j],t)+sqrt(maxf(0,radius*radius-p.distance_squared_to(q)))-radius)
	return result

static func contact(terrain,rocks: Array,point: Vector2,radius: float=0.0,v: Dictionary={}) -> Dictionary:
	var ground: float=terrain.height(point);var height=ground;var source="";var timber=false
	for o in rocks:
		if not o.alive:continue
		for face in nearby_faces(o,point,radius):
			if face.top<=height or not face.bounds.grow(radius+.0001).has_point(point):continue
			if not v.is_empty() and not supports_part(o,v,face.part):continue
			var h=face_height(face,point,radius)
			if h>height:height=h;source=o.id;timber=o.get("component_id","")=="nature.fallen-log"
	return {"height":height,"terrain":ground,"rock":source,"timber":timber}

static func description(v: Dictionary) -> String:
	var p=profile(v)
	return "%s · 低障碍参考上限 %.2f m · 离地 %.2f m · 纵坡约 %d°"%[p.label,p.rock,p.clearance,roundi(rad_to_deg(atan(p.grade)))]
