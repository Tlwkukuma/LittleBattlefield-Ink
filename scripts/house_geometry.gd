extends RefCounted
const Furniture=preload("res://scripts/house_furniture.gd")
const Aim=preload("res://scripts/aim_geometry.gd")

static func prepare(o: Dictionary):
	if str(o.component_id).begins_with("furniture."):o.solid_parts=Furniture.parts(o.component_id,o.size,o.height)
	elif str(o.component_id).begins_with("structure."):
		var parts=[];var h: float=o.height;var w: float=o.size.x;var d: float=o.size.y
		if o.component_id=="structure.rail":
			var along_x=w>d;var length=maxf(w,d);var count=maxi(1,ceili(length/.8))
			for i in range(count):
				var p=(i+.5)*length/count-length*.5
				Furniture.box(parts,Vector3(p if along_x else 0,h*.5,0 if along_x else p),Vector3(.075,h,.075),Color("7c8c86"))
			for y in [.48,h-.04]:Furniture.box(parts,Vector3(0,y,0),Vector3(w,.075,d),Color("abb3a3"))
		else:
			var color=Color("c2baa1") if o.get("house_role","")=="floor" else Color("8c9b93") if o.get("house_role","")=="roof" else Color("b4b4a6")
			if o.get("floor_finish","")=="tile":color=Color("b7c0b7")
			if o.get("floor_finish","")=="entry-stone":color=Color("919f94")
			Furniture.box(parts,Vector3(0,h*.5,0),Vector3(w,h,d),color)
		o.solid_parts=parts
	if o.has("solid_parts"):
		for part in o.solid_parts:
			o.size=o.size.max(Vector2(absf(part.at.x)+part.size.x*.5,absf(part.at.z)+part.size.z*.5)*2)
			o.height=maxf(o.height,part.at.y+part.size.y*.5)

static func ray(o: Dictionary,origin: Vector3,direction: Vector3,limit: float,radius: float) -> float:
	return float(hit(o,origin,direction,limit,radius).get("distance",INF))

static func hit(o: Dictionary,origin: Vector3,direction: Vector3,limit: float,radius: float,with_normal: bool=false,inside: Dictionary={},traveled: float=0) -> Dictionary:
	if o.get("metal_fence",false):return preload("res://scripts/metal_fence.gd").hit(o,origin,direction,limit,radius,with_normal)
	var result={}
	for index in range(o.solid_parts.size()):
		var part: Dictionary=o.solid_parts[index]
		if part.has("cell") and o.hp[part.cell]<=0:continue
		if float(inside.get(str(o.id)+":"+str(index),-1))>traveled:continue
		var half: Vector3=part.size*.5+Vector3.ONE*radius
		var distance=Aim.box_hit(origin,direction,part.at-half,part.at+half,limit)
		if distance<=limit:
			limit=distance;var cell=int(part.get("cell",0));result={"distance":distance,"col":cell%o.columns,"row":int(cell/o.columns),"piece":index}
			if with_normal:
				result.normal=Aim.box_normal(origin+direction*distance,part.at-half,part.at+half)
				result.exit_distance=Aim.box_span(origin,direction,part.at-half,part.at+half,INF).y
	return result

static func overlap(point: Vector2,center: Vector2,half: Vector2,radius: float) -> float:
	var relative=point-center;var closest=relative.clamp(-half,half);var distance=relative.distance_to(closest)
	return maxf(0,radius-distance) if distance>0 else radius+minf(half.x-absf(relative.x),half.y-absf(relative.y))

static func depth(o: Dictionary,point: Vector2,radius: float,base: float,height: float) -> float:
	var result=0.0
	for part in o.solid_parts:
		if part.has("cell") and o.hp[part.cell]<=0:continue
		if base>=part.at.y+part.size.y*.5-.001 or base+height<=part.at.y-part.size.y*.5+.001:continue
		result=maxf(result,overlap(point,Vector2(part.at.x,part.at.z),Vector2(part.size.x,part.size.z)*.5,radius))
	return result

static func support(o: Dictionary,point: Vector2,radius: float,below: float) -> float:
	var result=-INF
	for part in o.solid_parts:
		if part.has("cell") and o.hp[part.cell]<=0:continue
		var top=part.at.y+part.size.y*.5
		if top<=below and overlap(point,Vector2(part.at.x,part.at.z),Vector2(part.size.x,part.size.z)*.5,radius)>.001:result=maxf(result,top)
	return result
