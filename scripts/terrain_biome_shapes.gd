extends RefCounted
## Different landforms, not a shared plane with a different tint.
static func is_relief(id: String) -> bool:return id in ["terrain.snow","terrain.desert"]

static func frame(f: Dictionary) -> Dictionary:
	var points: PackedVector2Array=f.points
	if points.size()<2:return {}
	var a=points[0];var b=points[1];var width: float=f.width
	if points.size()>2:
		var rect=Rect2(points[0],Vector2.ZERO)
		for p in points:rect=rect.expand(p)
		a=Vector2(rect.position.x,rect.get_center().y);b=Vector2(rect.end.x,rect.get_center().y);width=rect.size.y
	return {"center":(a+b)*.5,"angle":(b-a).angle(),"length":maxf(.1,a.distance_to(b)),"width":maxf(.1,width),"amplitude":absf(float(f.get("godot3d",{}).get("height",1.6 if f.id=="terrain.snow" else 2.3)))}

static func sample(f: Dictionary,point: Vector2) -> Dictionary:
	var frame_data: Dictionary=f.get("biome_frame",{})
	if frame_data.is_empty():return {"height":0.0,"cover":0.0,"softness":0.0}
	var p=(point-frame_data.center).rotated(-frame_data.angle)
	var length: float=frame_data.length;var width: float=frame_data.width
	var edge=minf(length*.5-absf(p.x),width*.5-absf(p.y))
	var cover=smoothstep(0,minf(1.6,minf(length,width)*.15),edge+.10*sin(p.x*1.7+p.y*.4))
	if cover<=0 or (f.points.size()>2 and not Geometry2D.is_point_in_polygon(point,f.points)):return {"height":0.0,"cover":0.0,"softness":0.0}
	if f.id=="terrain.snow":
		# Rounded wind deposits on either side of a sinuous compacted east-west trail.
		var trail=sin(p.x*.32)*.65
		var powder=smoothstep(.80,1.90,absf(p.y-trail))
		var bank_a=exp(-pow((p.x+length*.23)/(length*.21),2)-pow((p.y+width*.23)/(width*.22),2))
		var bank_b=exp(-pow((p.x-length*.24)/(length*.23),2)-pow((p.y-width*.22)/(width*.20),2))
		var mass=(.10+powder*(.20+bank_a*1.45+bank_b*1.10))*float(frame_data.amplitude)/1.6
		return {"height":cover*mass,"cover":cover,"softness":cover*powder,"trail":1-powder}
	# Two curved crescent ridges: long windward rise, shorter lee face, low corridor between.
	var bow=.8*sin(p.y*.34)+1.0*pow(p.y/(width*.5),2)
	var ridge_a=-length*.26+bow;var ridge_b=length*.26+bow*.7
	var dune_a=dune(p.x-ridge_a,length*.30,length*.16)
	var dune_b=dune(p.x-ridge_b,length*.26,length*.14)*.76
	var along=clampf(1-absf(p.y)/(width*.72),.2,1)
	var ridge=maxf(dune_a,dune_b)*along
	return {"height":cover*(.055+float(frame_data.amplitude)*ridge),"cover":cover,"softness":clampf(ridge*1.4,.06,1),"trail":1-clampf(ridge*4,0,1)}

static func dune(offset: float,windward: float,lee: float) -> float:
	# A distinct crest remains visible in the shared mesh; no noise-only fake dune.
	return pow(clampf(1+offset/maxf(.1,windward),0,1),1.2) if offset<=0 else clampf(1-offset/maxf(.1,lee),0,1)
