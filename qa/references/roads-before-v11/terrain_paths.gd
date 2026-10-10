extends RefCounted
## Source-compatible Catmull–Rom; one sampled path drives paint and flat corridors.
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

static func ribbon(v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,a: Vector2,b: Vector2,width: float,tint: Color,terrain,lift: float):
	var dir=(b-a).normalized();var side=Vector2(-dir.y,dir.x)*width*.5
	var steps=maxi(1,ceili(a.distance_to(b)/.4))
	for j in range(steps):
		var start=a.lerp(b,float(j)/steps);var end=a.lerp(b,float(j+1)/steps)
		var corners=[start-side,start+side,end+side,end-side]
		for k in [0,1,2,0,2,3]:
			var p: Vector2=corners[k];v.append(Vector3(p.x,terrain.height(p)+lift,p.y));n.append(Vector3.UP);c.append(tint)

static func render(f: Dictionary,v: PackedVector3Array,n: PackedVector3Array,c: PackedColorArray,terrain,base: Color,layer: float):
	if not f.has("path_lengths") or str(f.id).begins_with("landform."):return
	var color_value=color(f,base);var shoulder=base.lerp(Color.from_string(str(f.get("shoulderColor","#9e987d")),base),float(f.get("shoulderAlpha",.5)))
	# Source center-line dash phase remains continuous through every sampled span.
	var line: Dictionary=f.get("centerLine",{});var dash=maxf(.05,float(line.get("dash",48))/40);var period=dash+maxf(.025,float(line.get("gap",40))/40)
	for i in range(f.points.size()-1):
		var a: Vector2=f.points[i];var b: Vector2=f.points[i+1]
		ribbon(v,n,c,a,b,f.shoulder_m,shoulder,terrain,layer)
		ribbon(v,n,c,a,b,f.width,color_value,terrain,layer+.004)
		if line.is_empty():continue
		var length=a.distance_to(b);var cursor=0.0
		while cursor<length-.00001:
			var phase=fposmod(float(f.path_lengths[i])+cursor,period);var on=phase<dash
			var step=minf(length-cursor,maxf(.00001,(dash if on else period)-phase))
			if on:ribbon(v,n,c,a.lerp(b,cursor/length),a.lerp(b,(cursor+step)/length),float(line.get("width",4))/40,color_value.lerp(Color.from_string(str(line.get("color","#e4d9b4")),Color.WHITE),float(line.get("alpha",.65))),terrain,layer+.008)
			cursor+=step
