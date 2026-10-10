extends RefCounted
## Source-compatible Catmull–Rom; one sampled path drives paint and flat corridors.
const SurfaceMesh=preload("res://scripts/road_surface_mesh.gd")
static func is_path(f: Dictionary) -> bool:
	return f.get("kind","") in ["path","road"] or f.get("points",[]).size()==2

static func sample(points: PackedVector2Array,mode: String="polyline",count: int=18) -> PackedVector2Array:
	if points.size()<2 or mode in ["polyline","linear","straight"]:return points.duplicate()
	var result=PackedVector2Array()
	for i in range(points.size()-1):
		var p0=points[maxi(0,i-1)];var p1=points[i];var p2=points[i+1];var p3=points[mini(points.size()-1,i+2)]
		for j in range(count):
			var t=float(j)/count
			result.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
	result.append(points[-1]);return result

static func prepare(f: Dictionary):
	if not is_path(f) or str(f.id).begins_with("landform."):return
	f.points=sample(f.points,str(f.get("pathMode","polyline")))
	f.path_lengths=PackedFloat32Array([0.0]);var length=0.0
	for i in range(1,f.points.size()):
		length+=f.points[i-1].distance_to(f.points[i]);f.path_lengths.append(length)
	f.path_length=length
	f.shoulder_m=maxf(f.width,float(f.get("shoulderWidth",f.width*40))/40)
	if not f.points.is_empty():
		var bounds=Rect2(f.points[0],Vector2.ZERO)
		for point in f.points:bounds=bounds.expand(point)
		f.path_bounds=bounds.grow(maxf(f.shoulder_m,float(f.get("level_width_m",0)))*.5+float(f.get("level_transition_m",1))+1)

static func nearest(points: PackedVector2Array,point: Vector2) -> Dictionary:
	var best=INF;var along=0.0;var total=0.0;var segment=0;var ratio=0.0
	for i in range(points.size()-1):
		var a=points[i];var delta=points[i+1]-a;var length=delta.length()
		var t=clampf((point-a).dot(delta)/maxf(.000001,delta.length_squared()),0,1)
		var distance=point.distance_squared_to(a+delta*t)
		if distance<best:best=distance;along=total+length*t;segment=i;ratio=t
		total+=length
	return {"distance":sqrt(best),"along":along,"length":total,"segment":segment,"ratio":ratio}

static func contains(f: Dictionary,point: Vector2,width: float=-1) -> bool:
	if f.has("path_bounds") and not f.path_bounds.has_point(point):return false
	return nearest(f.points,point).distance<=(f.width if width<0 else width)*.5

static func color(f: Dictionary,fallback: Color) -> Color:
	var visual: Dictionary=f.get("mapKitVisual",{})
	if visual.has("fill"):return Color.from_string(str(visual.fill),fallback).lerp(fallback,1-float(visual.get("alpha",1)))
	return Color("b69a6c") if f.get("surface","")=="track" else fallback

static func render(f: Dictionary,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,terrain,base: Color,layer: float):
	render_all([f],v,n,c,terrain,base,layer)

static func render_all(features: Array,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,terrain,base: Color,layer: float):
	var shoulders=[];var roads=[];var markings=[]
	for f in features:
		if not f.has("path_lengths") or str(f.id).begins_with("landform."):continue
		var color_value=color(f,base)
		if not f.get("mapKitVisual",{}).has("fill") and f.get("surface","")!="track":color_value=f.get("color",base)
		var shoulder=base.lerp(Color.from_string(str(f.get("shoulderColor","#9e987d")),base),float(f.get("shoulderAlpha",.5)))
		shoulders.append(SurfaceMesh.layer(SurfaceMesh.outline(f.points,f.shoulder_m),shoulder))
		roads.append(SurfaceMesh.layer(SurfaceMesh.outline(f.points,f.width),color_value))
		var line: Dictionary=f.get("centerLine",{})
		if line.is_empty():continue
		var dash=maxf(.05,float(line.get("dash",48))/40);var period=dash+maxf(.025,float(line.get("gap",40))/40)
		var contours=[];var cursor=0.0
		while cursor<float(f.path_length)-.00001:
			var points=span(f,cursor,minf(cursor+dash,f.path_length))
			contours.append_array(SurfaceMesh.outline(points,float(line.get("width",4))/40,Geometry2D.END_BUTT))
			cursor+=period
		if not contours.is_empty():markings.append(SurfaceMesh.layer(contours,color_value.lerp(Color.from_string(str(line.get("color","#e4d9b4")),Color.WHITE),float(line.get("alpha",.65)))))
	# One non-overlapping paint mesh: every road owns pixels ahead of any shoulder.
	# Dash masks share the same continuous path and accumulated arc-length phase.
	SurfaceMesh.bake(shoulders+roads+markings,terrain,v,n,c,layer)

static func span(f: Dictionary,start: float,end: float) -> PackedVector2Array:
	var result=PackedVector2Array()
	for i in range(f.points.size()-1):
		var a=float(f.path_lengths[i]);var b=float(f.path_lengths[i+1])
		if b<=start or a>=end or b-a<.000001:continue
		var first: Vector2=f.points[i].lerp(f.points[i+1],clampf((start-a)/(b-a),0,1))
		var last: Vector2=f.points[i].lerp(f.points[i+1],clampf((end-a)/(b-a),0,1))
		if result.is_empty():result.append(first)
		result.append(last)
	return result
