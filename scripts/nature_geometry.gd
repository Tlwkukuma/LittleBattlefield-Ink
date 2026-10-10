extends RefCounted
## Shared convex pieces: the render faces also define rays, body slices and support.
const Library=preload("res://scripts/nature_library.gd")
const Forms=preload("res://scripts/nature_forms.gd")

static func prepare(o: Dictionary):
	if not Library.SPECS.has(o.component_id):return
	for key in ["vehicle_support_faces","vehicle_support_grid","vehicle_support_frame","vehicle_contact_parts","vehicle_contact_frame"]:o.erase(key)
	var spec: Array=Library.SPECS[o.component_id]
	var scale=Vector3(o.size.x/spec[2].x,o.height/spec[1],o.size.y/spec[2].y)
	o.nature_parts=Forms.parts(o.component_id,hash(o.id),o.get("nature_biome","")=="snow" or "snow" in str(o.get("surface","")))
	o.nature_solids=[]
	for part in o.nature_parts:
		var center=Vector3.ZERO
		for i in range(part.vertices.size()):
			part.vertices[i]*=scale;center+=part.vertices[i]
			var p: Vector3=part.vertices[i]
			o.size=o.size.max(Vector2(absf(p.x),absf(p.z))*2);o.height=maxf(o.height,p.y)
		center/=part.vertices.size();part.triangles=[];part.planes=[]
		part.low=INF;part.high=-INF
		for p in part.vertices:part.low=minf(part.low,p.y);part.high=maxf(part.high,p.y)
		for face in part.faces:
			for i in range(1,face.size()-1):
				var a: Vector3=part.vertices[face[0]];var b: Vector3=part.vertices[face[i]];var c: Vector3=part.vertices[face[i+1]]
				var normal=(b-a).cross(c-a).normalized()
				if normal.length_squared()<.1:continue
				if normal.dot(center-a)>0:var swap=b;b=c;c=swap;normal=-normal
				part.triangles.append([a,b,c,normal]);part.planes.append(Plane(normal,normal.dot(a)))
		if part.solid:o.nature_solids.append(part)
	# Wood trunks yield sooner than stone; large rocks remain durable cover.
	o.health_scale*=7.0 if o.component_id.begins_with("rock.") and o.height>1.2 else 3.0 if o.component_id.begins_with("rock.") else 2.5

static func mesh(o: Dictionary) -> ArrayMesh:
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray()
	for part in o.nature_parts:
		for tri in part.triangles:
			var n: Vector3=tri[3];var tint: Color=part.color.darkened((1-maxf(0,n.dot(Vector3(-.3,.9,.2).normalized())))*.13)
			for i in range(3):vertices.append(tri[i]);normals.append(n);colors.append(tint)
	var data=[];data.resize(Mesh.ARRAY_MAX);data[Mesh.ARRAY_VERTEX]=vertices;data[Mesh.ARRAY_NORMAL]=normals;data[Mesh.ARRAY_COLOR]=colors
	var result=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data);return result

static func ray(o: Dictionary,origin: Vector3,direction: Vector3,limit: float,radius: float=0,inside: Dictionary={},traveled: float=0) -> Dictionary:
	var best={}
	for index in range(o.nature_solids.size()):
		if float(inside.get(str(o.id)+":"+str(index),-1))>traveled:continue
		var part: Dictionary=o.nature_solids[index]
		var enter=0.0;var leave=INF;var normal=-direction.normalized();var valid=true
		for plane in part.planes:
			var dist=plane.normal.dot(origin)-plane.d-radius;var speed=plane.normal.dot(direction)
			if absf(speed)<.0000001:
				if dist>0:valid=false;break
				continue
			var t=-dist/speed
			if speed<0:
				if t>enter:enter=t;normal=plane.normal
			else:leave=minf(leave,t)
			if enter>leave+.000001:valid=false;break
		if valid and leave>=0 and enter<=limit:limit=enter;best={"distance":enter,"exit_distance":leave,"piece":index,"normal":normal}
	return best

static func clip_height(polygon: Array,height: float,above: bool) -> Array:
	var output=[]
	if polygon.is_empty():return output
	var previous: Vector3=polygon.back();var prev_in=previous.y>=height if above else previous.y<=height
	for p in polygon:
		var current_in=p.y>=height if above else p.y<=height
		if current_in!=prev_in:output.append(previous.lerp(p,(height-previous.y)/(p.y-previous.y)))
		if current_in:output.append(p)
		previous=p;prev_in=current_in
	return output

static func polygon_depth(point: Vector2,polygon: PackedVector2Array,radius: float) -> float:
	if polygon.size()<3:return 0
	var distance=INF
	for i in range(polygon.size()):distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])))
	return radius+distance if Geometry2D.is_point_in_polygon(point,polygon) else maxf(0,radius-distance)

static func depth(o: Dictionary,point: Vector2,radius: float,base: float,height: float) -> float:
	var result=0.0
	for part in o.nature_solids:
		if part.low>=base+height-.001 or part.high<=base+.001:continue
		var vertices=PackedVector2Array()
		for tri in part.triangles:
			var clipped=clip_height(clip_height([tri[0],tri[1],tri[2]],base+.001,true),base+height-.001,false)
			for p in clipped:vertices.append(Vector2(p.x,p.z))
		if vertices.size()>=3:result=maxf(result,polygon_depth(point,Geometry2D.convex_hull(vertices),radius))
	return result

static func face_support(tri: Array,point: Vector2,radius: float) -> float:
	var a: Vector3=tri[0];var n: Vector3=tri[3]
	if n.y<.00001:return -INF
	var polygon=PackedVector2Array([Vector2(tri[0].x,tri[0].z),Vector2(tri[1].x,tri[1].z),Vector2(tri[2].x,tri[2].z)])
	var choices=[]
	if Geometry2D.is_point_in_polygon(point,polygon):choices.append(point)
	# The maximum of a plane over a disk occurs along its slope or on a clipped edge.
	var slope=Vector2(-n.x,-n.z).normalized();var peak=point+slope*radius
	if Geometry2D.is_point_in_polygon(peak,polygon):choices.append(peak)
	for i in range(3):
		var start: Vector2=polygon[i];var end: Vector2=polygon[(i+1)%3];var v=end-start;var delta=start-point
		if start.distance_squared_to(point)<=radius*radius+.000001:choices.append(start)
		var closest=Geometry2D.get_closest_point_to_segment(point,start,end)
		if closest.distance_squared_to(point)<=radius*radius+.000001:choices.append(closest)
		var aa=v.length_squared();var bb=2*delta.dot(v);var cc=delta.length_squared()-radius*radius;var disc=bb*bb-4*aa*cc
		if aa>.000001 and disc>=0:
			for sign_value in [-1,1]:
				var t=(-bb+sign_value*sqrt(disc))/(2*aa)
				if t>=0 and t<=1:choices.append(start+v*t)
	var top=-INF
	for p in choices:top=maxf(top,a.y-(n.x*(p.x-a.x)+n.z*(p.y-a.z))/n.y)
	return top

static func support(o: Dictionary,point: Vector2,radius: float,below: float) -> float:
	var result=-INF
	for part in o.nature_solids:
		for tri in part.triangles:
			var top=face_support(tri,point,radius)
			if top<=below+.00001:result=maxf(result,top)
	return result

static func closest_triangle(point: Vector3,tri: Array) -> Vector3:
	var a: Vector3=tri[0];var b: Vector3=tri[1];var c: Vector3=tri[2];var normal: Vector3=tri[3]
	var projected=point-normal*normal.dot(point-a)
	if (b-a).cross(projected-a).dot(normal)>=-.00001 and (c-b).cross(projected-b).dot(normal)>=-.00001 and (a-c).cross(projected-c).dot(normal)>=-.00001:return projected
	var closest=a;var distance=INF
	for edge in [[a,b],[b,c],[c,a]]:
		var v: Vector3=edge[1]-edge[0];var candidate: Vector3=edge[0]+v*clampf((point-edge[0]).dot(v)/maxf(.000001,v.length_squared()),0,1)
		if point.distance_squared_to(candidate)<distance:distance=point.distance_squared_to(candidate);closest=candidate
	return closest

static func distance_to_solid(o: Dictionary,point: Vector3) -> float:
	var result=INF
	for part in o.nature_solids:
		var inside=true
		for plane in part.planes:
			if plane.distance_to(point)>.000001:inside=false;break
		if inside:return 0
		for tri in part.triangles:result=minf(result,point.distance_to(closest_triangle(point,tri)))
	return result
