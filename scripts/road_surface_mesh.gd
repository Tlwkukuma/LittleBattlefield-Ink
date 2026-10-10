extends RefCounted
## Bake joined road masks onto the real terrain triangles, once at scene build.
## Topmost paint owns each fragment: intersections have no overlapping shoulders.
const OFFSET_SCALE=100.0
const EPS=.000001

static func outline(points: PackedVector2Array,width: float,end_type: int=Geometry2D.END_ROUND) -> Array:
	var clean=PackedVector2Array()
	for point in points:
		if clean.is_empty() or clean[-1].distance_squared_to(point)>EPS:clean.append(point)
	if clean.size()<2 or width<=0:return []
	# Clipper's arc tolerance is in input units; centimetres keep round joins fine.
	var scaled=PackedVector2Array()
	for p in clean:scaled.append(p*OFFSET_SCALE)
	var result=[]
	for polygon in Geometry2D.offset_polyline(scaled,width*.5*OFFSET_SCALE,Geometry2D.JOIN_ROUND,end_type):
		for i in range(polygon.size()):polygon[i]/=OFFSET_SCALE
		result.append({"points":polygon,"bounds":bounds_of(polygon),"hole":Geometry2D.is_polygon_clockwise(polygon)})
	return result

static func bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds=Rect2(points[0],Vector2.ZERO)
	for point in points:bounds=bounds.expand(point)
	return bounds

static func layer(contours: Array,tint: Color) -> Dictionary:
	var bounds=Rect2()
	for contour in contours:bounds=contour.bounds if not bounds.has_area() else bounds.merge(contour.bounds)
	return {"contours":contours,"color":tint,"bounds":bounds}

static func has_hole(polygons: Array) -> bool:
	for polygon in polygons:
		if Geometry2D.is_polygon_clockwise(polygon):return true
	return false

static func intersection(piece: PackedVector2Array,contours: Array) -> Array:
	var result=[];var bounds=bounds_of(piece).grow(EPS)
	for contour in contours:
		if contour.hole or not bounds.intersects(contour.bounds):continue
		result.append_array(Geometry2D.intersect_polygons(piece,contour.points))
	for contour in contours:
		if not contour.hole or not bounds.intersects(contour.bounds):continue
		var next=[]
		for polygon in result:next.append_array(Geometry2D.clip_polygons(polygon,contour.points))
		result=next
	return result

static func bake(layers: Array,terrain,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,lift: float):
	if layers.is_empty():return
	var bounds: Rect2=layers[0].bounds
	for paint in layers:bounds=bounds.merge(paint.bounds)
	var first: Vector2i=Vector2i(((bounds.position+terrain.bounds)/terrain.cell).floor()).clamp(Vector2i.ZERO,terrain.size-Vector2i.ONE)
	var last: Vector2i=Vector2i(((bounds.end+terrain.bounds)/terrain.cell).floor()).clamp(Vector2i.ZERO,terrain.size-Vector2i.ONE)
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var a=Vector2(x,z)*terrain.cell-terrain.bounds;var b=a+Vector2(terrain.cell,0);var d=a+Vector2(0,terrain.cell);var e=a+Vector2.ONE*terrain.cell
			var nearby=[];var tile=Rect2(a,Vector2.ONE*terrain.cell).grow(EPS)
			for paint in layers:
				if tile.intersects(paint.bounds):nearby.append(paint)
			if nearby.is_empty():continue
			paint_triangle(PackedVector2Array([a,d,b]),nearby,terrain,v,n,c,lift)
			paint_triangle(PackedVector2Array([b,d,e]),nearby,terrain,v,n,c,lift)

static func subdivide(tile: PackedVector2Array,layers: Array,terrain,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,lift: float,depth: int):
	var ab=(tile[0]+tile[1])*.5;var bc=(tile[1]+tile[2])*.5;var ca=(tile[2]+tile[0])*.5
	for child in [PackedVector2Array([tile[0],ab,ca]),PackedVector2Array([ab,tile[1],bc]),PackedVector2Array([ca,bc,tile[2]]),PackedVector2Array([ab,bc,ca])]:
		paint_triangle(child,layers,terrain,v,n,c,lift,depth+1)

static func paint_triangle(tile: PackedVector2Array,layers: Array,terrain,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,lift: float,depth: int=0):
	# 3D terrain's upward winding is clockwise in X/Z; Clipper's outer loops
	# use the opposite winding. Normalize even an untouched remaining triangle.
	if Geometry2D.is_polygon_clockwise(tile):tile.reverse()
	if depth>=12:
		# Bound degeneracies below a millimetre instead of recursively amplifying
		# floating-point slivers. One paint still owns the entire tiny fragment.
		var center=(tile[0]+tile[1]+tile[2])/3
		for index in range(layers.size()-1,-1,-1):
			var inside=false
			for contour in layers[index].contours:
				if Geometry2D.is_point_in_polygon(center,contour.points):inside=not inside
			if inside:
				emit(tile,layers[index].color,terrain,v,n,c,lift);return
		return
	var remaining=[tile];var output=[]
	for index in range(layers.size()-1,-1,-1):
		var paint: Dictionary=layers[index];var next=[]
		for piece in remaining:
			var covered=intersection(piece,paint.contours)
			var rest=[piece]
			# A closed loop or short marking can lie inside a terrain triangle.
			# Split that triangle until contours touch its edges; never fill a hole.
			if has_hole(covered):
				subdivide(tile,layers,terrain,v,n,c,lift,depth);return
			for polygon in covered:
				output.append({"points":polygon,"color":paint.color})
				var fragments=[]
				for uncovered in rest:fragments.append_array(Geometry2D.clip_polygons(uncovered,polygon))
				rest=fragments
			if has_hole(rest):
				subdivide(tile,layers,terrain,v,n,c,lift,depth);return
			next.append_array(rest)
		remaining=next
		if remaining.is_empty():break
	for fragment in output:
		emit(fragment.points,fragment.color,terrain,v,n,c,lift)

static func emit(points: PackedVector2Array,tint: Color,terrain,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,lift: float):
	for index in Geometry2D.triangulate_polygon(points):
		var p=points[index];v.append(Vector3(p.x,terrain.height(p)+lift,p.y));n.append(Vector3.UP);c.append(tint)
