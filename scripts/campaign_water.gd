extends RefCounted
## Source-authored deep-water exclusion, compiled once into the existing index.
## Uses the same sampled/outlined path as paint. Source gaps and visible decks
## remain open; water never becomes ballistic cover or a walkable raised floor.
const Paths=preload("res://scripts/terrain_paths.gd")
const Surface=preload("res://scripts/road_surface_mesh.gd")
const TILE=4.0
const HEIGHT=1.0
const ELEVATION=-.25

static func compile(catalog,plan: Dictionary,out: Dictionary) -> void:
	if int(plan.get("godot3d",{}).get("campaign_chapter",0))<=1:return
	var decks=[]
	for feature in out.ground:
		var id=str(feature.get("id",""))
		if feature.get("kind","")=="yard" and ("bridge" in id or "boardwalk" in id or "dry-island" in id or feature.get("renderLayer","")=="bridge" or str(feature.get("mapKitPrefabId","")).begins_with("bridge.")):
			var points=world_points(catalog,plan,feature.get("points",[]))
			if points.size()>=3:decks.append(points)
	for feature in out.ground:
		if str(feature.get("collision",""))!="blocked" or str(feature.get("surface",""))!="water":continue
		var points=world_points(catalog,plan,feature.get("points",[]))
		if points.size()<2:continue
		var sampled=Paths.sample(points,str(feature.get("pathMode","polyline")))
		# The supplied first-ten paths use this same visible width; do not invent
		# collision outside the displayed water strip from its decorative banks.
		var width=float(feature.get("collisionWidth",feature.get("width",80)))/40.0
		var visible_width=float(feature.get("width",80))/40.0
		width=minf(width,visible_width)
		var contours=Surface.outline(sampled,width)
		if contours.is_empty():continue
		var openings=decks.duplicate()
		for gap in feature.get("gaps",[]):
			var center=catalog.position(gap,plan);var radius=float(gap.get("r",0))/40.0
			if radius<=0:continue
			var circle=PackedVector2Array()
			for index in range(64):circle.append(center+Vector2.from_angle(index*TAU/64.0)*radius)
			openings.append(circle)
		var bounds: Rect2=contours[0].bounds
		for contour in contours:bounds=bounds.merge(contour.bounds)
		bounds=bounds.intersection(Rect2(-out.bounds,out.bounds*2))
		if not bounds.has_area():continue
		var first=Vector2i((bounds.position/TILE).floor());var last=Vector2i((bounds.end/TILE).ceil())
		for x in range(first.x,last.x):
			for y in range(first.y,last.y):
				var low=(Vector2(x,y)*TILE).max(-out.bounds)
				var high=(Vector2(x+1,y+1)*TILE).min(out.bounds)
				var a=low;var b=Vector2(high.x,low.y);var c=high;var d=Vector2(low.x,high.y)
				var polygons=[]
				polygons.append_array(wet_pieces(PackedVector2Array([a,b,c]),contours,openings))
				polygons.append_array(wet_pieces(PackedVector2Array([a,c,d]),contours,openings))
				if polygons.is_empty():continue
				var center=(low+high)*.5;var pa=catalog.original_point(Vector2(low.x,center.y),plan);var pb=catalog.original_point(Vector2(high.x,center.y),plan)
				var id="campaign-water-%s-%d-%d"%[str(feature.get("id","river")),x,y]
				var object=catalog.object_from_segment(id,"terrain.water-block",pa,pb,(high.y-low.y)*40.0,plan,{"height":HEIGHT,"elevation":ELEVATION},id)
				object.campaign_water=true;object.water_source=str(feature.get("id",""));object.water_polygons=[];object.nature_solids=[]
				for polygon in polygons:
					for convex in Geometry2D.decompose_polygon_in_convex(polygon):
						if convex.size()<3:continue
						var local=PackedVector2Array()
						for point in convex:local.append(point-center)
						object.water_polygons.append(local);object.nature_solids.append(prism(local))
				if not object.nature_solids.is_empty():out.objects.append(object)

static func world_points(catalog,plan: Dictionary,source: Array) -> PackedVector2Array:
	var points=PackedVector2Array()
	for point in source:points.append(catalog.position(point,plan))
	return points

static func wet_pieces(tile: PackedVector2Array,contours: Array,openings: Array,depth: int=0) -> Array:
	var pieces=Surface.intersection(tile,contours)
	for opening in openings:
		var open_bounds=Surface.bounds_of(opening);var next=[]
		for polygon in pieces:
			if not Surface.bounds_of(polygon).intersects(open_bounds):next.append(polygon);continue
			next.append_array(Geometry2D.clip_polygons(polygon,opening))
		if Surface.has_hole(next):
			# Avoid ever filling an enclosed source gap. Small bounded subdivision
			# keeps every final piece hole-free for the existing convex collider.
			if depth>=8:return []
			var ab=(tile[0]+tile[1])*.5;var bc=(tile[1]+tile[2])*.5;var ca=(tile[2]+tile[0])*.5;var split=[]
			for child in [PackedVector2Array([tile[0],ab,ca]),PackedVector2Array([ab,tile[1],bc]),PackedVector2Array([ca,bc,tile[2]]),PackedVector2Array([ab,bc,ca])]:split.append_array(wet_pieces(child,contours,openings,depth+1))
			return split
		pieces=next
		if pieces.is_empty():break
	return pieces

static func prism(polygon: PackedVector2Array) -> Dictionary:
	var part={"solid":true,"vertices":[],"faces":[],"triangles":[],"planes":[],"low":0.0,"high":HEIGHT}
	var count=polygon.size();var bottom=[];var top=[]
	for point in polygon:part.vertices.append(Vector3(point.x,0,point.y))
	for point in polygon:part.vertices.append(Vector3(point.x,HEIGHT,point.y))
	for index in range(count):
		bottom.append(count-1-index);top.append(count+index)
		part.faces.append([index,(index+1)%count,(index+1)%count+count,index+count])
	part.faces.append(bottom);part.faces.append(top)
	var center=Vector3.ZERO
	for point in part.vertices:center+=point
	center/=part.vertices.size()
	for face in part.faces:
		for index in range(1,face.size()-1):
			var a: Vector3=part.vertices[face[0]];var b: Vector3=part.vertices[face[index]];var c: Vector3=part.vertices[face[index+1]]
			var normal=(b-a).cross(c-a).normalized()
			if normal.length_squared()<.1:continue
			if normal.dot(center-a)>0:var swap=b;b=c;c=swap;normal=-normal
			part.triangles.append([a,b,c,normal]);part.planes.append(Plane(normal,normal.dot(a)))
	return part
