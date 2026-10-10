extends RefCounted
## One triangulated surface for rendering, walking, picking and projectile cover.
const Ground=preload("res://scripts/terrain_ground.gd")
const Art=preload("res://scripts/terrain_art.gd")
const Shapes=preload("res://scripts/terrain_biome_shapes.gd")
const Paths=preload("res://scripts/terrain_paths.gd")
const Landforms=preload("res://scripts/terrain_landforms.gd")
const Border=preload("res://scripts/battlefield_border.gd")
var border_enabled:=false
var bounds:=Vector2(50,35)
var cell:=.5
var size:=Vector2i.ZERO
var heights:=PackedFloat32Array()
var smooth_normals:=PackedVector3Array()
var features: Array=[]
var active:=false
var range2_materials:=false
var ladders: Array=[]
var conflicts: Array=[]
var material_grid: Dictionary={}
var speed_cache: Dictionary={}
const RAY_BLOCK_CELLS=8
var ray_block_size:=Vector2i.ZERO
var ray_block_max:=PackedFloat32Array()

func configure(compiled: Dictionary,catalog,plan: Dictionary):
	border_enabled=bool(plan.get("godot3d",{}).get("battlefield_border",false))
	range2_materials=bool(plan.get("godot3d",{}).get("style_range",false))
	bounds=compiled.bounds;features=[];active=border_enabled;ladders=[]
	for source in compiled.ground:
		var f=source.duplicate(true);var points=PackedVector2Array()
		for p in f.get("points",[]):points.append(catalog.position_point(catalog.v(p),plan))
		if points.is_empty() and f.has("x"):
			var at=catalog.position(f,plan);var extent=Vector2(float(f.get("w",f.get("width",120))),float(f.get("h",f.get("height",120))))/40
			points=PackedVector2Array([at,at+Vector2(extent.x,0),at+extent,at+Vector2(0,extent.y)])
		f.source_id=f.get("id","")
		f.points=points;f.width=float(f.get("width",80))/40
		f.id=str(f.get("componentId",f.get("mapKitComponentId",f.get("kind","soil"))))
		f.color=Paths.color(f,Ground.color_for(f.id))
		Paths.prepare(f);Landforms.prepare(f,catalog,plan)
		if Shapes.is_relief(f.id):f.biome_frame=Shapes.frame(f)
		if f.id.begins_with("landform.") or Shapes.is_relief(f.id) or f.has("level_height_m"):active=true
		features.append(f)
	features.append_array(Landforms.landings(features))
	build_material_index()
	cell=maxf(.5,ceilf(sqrt(bounds.x*bounds.y/18000.0)*2)/2)
	conflicts=Landforms.conflicts(features,cell*sqrt(2.0))
	size=Vector2i(ceili(bounds.x*2/cell),ceili(bounds.y*2/cell))
	heights.resize((size.x+1)*(size.y+1));heights.fill(0)
	if active:
		for z in range(size.y+1):
			for x in range(size.x+1):heights[z*(size.x+1)+x]=analytic(Vector2(x,z)*cell-bounds)
	rebuild_ray_index()
	smooth_normals.resize(heights.size())
	for z in range(size.y+1):
		for x in range(size.x+1):
			var left=heights[z*(size.x+1)+maxi(0,x-1)];var right=heights[z*(size.x+1)+mini(size.x,x+1)]
			var back=heights[maxi(0,z-1)*(size.x+1)+x];var front=heights[mini(size.y,z+1)*(size.x+1)+x]
			smooth_normals[z*(size.x+1)+x]=Vector3(left-right,cell*2,back-front).normalized()
	for spec in compiled.get("ladders",[]):
		var a: Vector2=spec.a;var b: Vector2=spec.b
		var low=Vector3(a.x,height(a),a.y);var high=Vector3(b.x,height(b),b.y)
		if high.y<low.y:var swap=low;low=high;high=swap
		if high.y-low.y<.35:continue
		# Body follows a straight, clear incline alongside the rung plane.
		ladders.append({"id":spec.id,"low":low,"high":high,"width":spec.width,"length":low.distance_to(high)})

func analytic(point: Vector2) -> float:
	var result=0.0;var excavation=0.0;var earthwork=0.0;var excavation_weight=0.0
	for f in features:
		if f.id=="landform.low-hill":result+=Landforms.hill(f,point);continue
		if f.id=="landform.trench-network":
			var cut=Landforms.trench(f,point);excavation=maxf(excavation,cut)
			excavation_weight=maxf(excavation_weight,cut/maxf(.001,float(f.depth_m)))
			earthwork=maxf(earthwork,Landforms.berm(f,point));continue
		if f.id=="landform.level-pad":continue
		if Shapes.is_relief(f.id):result+=float(Shapes.sample(f,point).height);continue
		if not f.id.begins_with("landform.") or f.points.size()<2:continue
		var a: Vector2=f.points[0];var b: Vector2=f.points[1];var length=a.distance_to(b)
		var local=(point-(a+b)*.5).rotated(-(b-a).angle());var width: float=f.width
		if absf(local.x)>=length*.5 or absf(local.y)>=width*.5:continue
		var height_value=absf(float(f.get("godot3d",{}).get("height",3.4 if "mountain" in f.id else 1.65)))
		if "trench" in f.id:
			var end=clampf((length*.5-absf(local.x))/3.5,0,1)
			var side=clampf((width*.5-absf(local.y))/.65,0,1)
			result-=height_value*minf(end,side)
		else:
			# Broad southern walking slope, craggy steep north face and a flat crest.
			var across=clampf((width*.5-local.y)/(width*.43),0,1) if local.y>=0 else clampf((width*.5+local.y)/(width*.13),0,1)
			var end=clampf((length*.5-absf(local.x))/(length*.3),0,1)
			result+=height_value*minf(across,end)
	# The diagonal-cell safety margin keeps whole rendered triangles level inside the
	# requested vehicle corridor, including samples falling between grid vertices.
	var base=Landforms.flatten(features,point,result+earthwork*(1-excavation_weight)-excavation,cell*sqrt(2.0))
	return base+(Border.relief(point,bounds) if border_enabled else 0.0)

func vertex(x: int,z: int) -> Vector3:
	return Vector3(x*cell-bounds.x,heights[z*(size.x+1)+x],z*cell-bounds.y)

func triangle(point: Vector2) -> Array:
	var grid=(point+bounds)/cell
	var x=clampi(floori(grid.x),0,size.x-1);var z=clampi(floori(grid.y),0,size.y-1)
	return [vertex(x,z),vertex(x,z+1),vertex(x+1,z)] if grid.x-x+grid.y-z<=1 else [vertex(x+1,z),vertex(x,z+1),vertex(x+1,z+1)]

func height(point: Vector2) -> float:
	if not active:return 0.0
	var grid:=(point+bounds)/cell
	var x:=clampi(floori(grid.x),0,size.x-1);var z:=clampi(floori(grid.y),0,size.y-1)
	var u:=grid.x-x;var v:=grid.y-z;var index:=z*(size.x+1)+x
	var b:=heights[index+1];var d:=heights[index+size.x+1]
	if u+v<=1:
		var a:=heights[index];return a+(b-a)*u+(d-a)*v
	var c:=heights[index+size.x+2];return c+(d-c)*(1-u)+(b-c)*(1-v)

func grade(point: Vector2) -> float:
	if not active:return 0.0
	var grid:=(point+bounds)/cell
	var x:=clampi(floori(grid.x),0,size.x-1);var z:=clampi(floori(grid.y),0,size.y-1);var index:=z*(size.x+1)+x
	var b:=heights[index+1];var d:=heights[index+size.x+1]
	var corner:=heights[index] if grid.x-x+grid.y-z<=1 else heights[index+size.x+2]
	return Vector2(b-corner,d-corner).length()/cell

func rebuild_ray_index():
	# Conservative upper bounds only. Narrow phase keeps the exact rendered triangles.
	ray_block_size=Vector2i(ceili(float(size.x)/RAY_BLOCK_CELLS),ceili(float(size.y)/RAY_BLOCK_CELLS))
	ray_block_max.resize(ray_block_size.x*ray_block_size.y);ray_block_max.fill(-INF)
	for bz in range(ray_block_size.y):
		for bx in range(ray_block_size.x):
			var highest=-INF
			for z in range(bz*RAY_BLOCK_CELLS,mini(size.y,(bz+1)*RAY_BLOCK_CELLS)+1):
				for x in range(bx*RAY_BLOCK_CELLS,mini(size.x,(bx+1)*RAY_BLOCK_CELLS)+1):highest=maxf(highest,heights[z*(size.x+1)+x])
			ray_block_max[bz*ray_block_size.x+bx]=highest

func walkable(a: Vector2,b: Vector2) -> bool:
	if not active:return true
	return grade((a+b)*.5)<=.82 and grade(b)<=.82 and absf(height(b)-height(a))<=a.distance_to(b)*.85+.008

func walkable_with_heights(a: Vector2,b: Vector2,ha: float,hb: float) -> bool:
	if not active:return true
	return grade((a+b)*.5)<=.82 and grade(b)<=.82 and absf(hb-ha)<=a.distance_to(b)*.85+.008

func contains(f: Dictionary,point: Vector2) -> bool:
	var points: PackedVector2Array=f.points
	if points.size()<2:return false
	if f.id=="landform.trench-network":return Landforms.trench(f,point)>.001 or Landforms.berm(f,point)>.001
	if f.id=="landform.low-hill":return Landforms.hill(f,point)>.001
	if f.id=="landform.level-pad":return false # Height constraint, not a painted road.
	if f.has("path_lengths"):return Paths.contains(f,point)
	if f.get("kind","") in ["path","road"] or points.size()==2:
		for i in range(points.size()-1):
			var a=points[i];var b=points[i+1];var along=clampf((point-a).dot(b-a)/maxf(.0001,(b-a).length_squared()),0,1)
			if point.distance_to(a.lerp(b,along))<=f.width*.5:return true
		return false
	return Geometry2D.is_point_in_polygon(point,points)

func build_material_index():
	material_grid.clear();speed_cache.clear()
	for f in features:
		if f.points.size()<2:continue
		var rect=Rect2(f.points[0],Vector2.ZERO)
		for p in f.points:rect=rect.expand(p)
		rect=rect.grow(float(f.width)*.5+.001)
		if f.has("path_bounds"):rect=rect.merge(f.path_bounds)
		if f.has("trench_bounds"):rect=rect.merge(f.trench_bounds)
		if f.has("hill_center"):
			var half: Vector2=f.hill_size*.5
			for x in [-1,1]:
				for y in [-1,1]:rect=rect.expand(f.hill_center+Vector2(x*half.x,y*half.y).rotated(f.hill_angle))
		for x in range(floori(rect.position.x/4),floori(rect.end.x/4)+1):
			for y in range(floori(rect.position.y/4),floori(rect.end.y/4)+1):
				var key=Vector2i(x,y)
				if not material_grid.has(key):material_grid[key]=[]
				material_grid[key].append(f)

func material_features(point: Vector2) -> Array:
	# Manually constructed test surfaces may not have been configured yet.
	if material_grid.is_empty():return features
	return material_grid.get(Vector2i(floori(point.x/4),floori(point.y/4)),[])

func material_at(point: Vector2) -> String:
	var nearby=material_features(point)
	for i in range(nearby.size()-1,-1,-1):
		if contains(nearby[i],point):return nearby[i].id
	return "grass"

func profile_at(point: Vector2) -> Dictionary:
	var id=material_at(point)
	for i in range(features.size()-1,-1,-1):
		var f: Dictionary=features[i]
		if f.id!=id or not Shapes.is_relief(id) or not contains(f,point):continue
		var result=Shapes.sample(f,point);result.id=id;return result
	return {"id":id,"height":0.0,"cover":0.0,"softness":0.0,"trail":0.0}

func speed_at(point: Vector2) -> float:
	if speed_cache.has(point):return speed_cache[point]
	var id=material_at(point);var speed=1.0
	if "snow" in id:speed=lerpf(.98,.64,float(profile_at(point).softness))
	elif "desert" in id:speed=lerpf(.96,.73,float(profile_at(point).softness))
	elif "sand" in id:speed=.82
	elif "trench" in id or "red-earth" in id:speed=.94
	if speed_cache.size()>=4096:speed_cache.clear()
	speed_cache[point]=speed;return speed

func color_at(point: Vector2) -> Color:
	var color=Ground.BASE;var id="grass"
	for f in features:
		if contains(f,point):
			color=f.color;id=f.id
			if Shapes.is_relief(id):
				var profile=Shapes.sample(f,point)
				var fresh=Color("e8ede7") if id=="terrain.snow" else Color("d9c397")
				var packed=Color("aabec0") if id=="terrain.snow" else Color("b9a17b")
				color=Ground.BASE.lerp(packed.lerp(fresh,profile.softness),profile.cover)
	var h=height(point);var slope=grade(point)
	if "mountain" in id:color=Color("969d92").lerp(Color("c3c5b6"),clampf(h/3.4,0,1))
	if "trench" in id:color=Color("a47b60").darkened(clampf(-h*.12,0,.22)).lightened(clampf(h*.10,0,.075))
	var grain=sin(point.x*1.13+point.y*.3)*cos(point.y*1.79)*.025
	if "desert" in id or "sand" in id:grain+=sin(point.x*.9+sin(point.y*.6)*1.1)*.026
	if "snow" in id:grain*=.5
	color=color.lightened(maxf(0,grain)).darkened(maxf(0,-grain)+minf(.12,slope*.035))
	color.a=.25 if id=="terrain.snow" else .5 if id=="terrain.desert" else 1.0
	if range2_materials:color.a=.9 if "concrete" in id else 1.0 if "asphalt" in id else .8
	if border_enabled:color=color.lerp(Border.pigment(point),Border.weight(point,bounds))
	return color

func mesh() -> ArrayMesh:
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	# Bake shared samples once. Trench soil and its grass rim must not acquire a
	# different pigment / lighting normal on every half-cell. Physics triangles stay
	# exactly the same; the extra arrays are temporary, with no per-frame work.
	var colors=PackedColorArray();colors.resize(heights.size())
	var soft=PackedByteArray();soft.resize(heights.size())
	for z in range(size.y+1):
		for x in range(size.x+1):
			var index=z*(size.x+1)+x;var point=Vector2(x,z)*cell-bounds
			colors[index]=color_at(point)
			var id=material_at(point)
			soft[index]=1 if "trench" in id or "snow" in id else 0
	for z in range(size.y):
		for x in range(size.x):
			var base=z*(size.x+1)+x
			for indices in [[base,base+size.x+1,base+1],[base+1,base+size.x+1,base+size.x+2]]:
				var tri=[];var blend=false
				for index in indices:
					tri.append(vertex(index%(size.x+1),index/(size.x+1)))
					blend=blend or soft[index]!=0
				var normal=(tri[1]-tri[0]).cross(tri[2]-tri[0]).normalized()
				var center=(tri[0]+tri[1]+tri[2])/3;var color=color_at(Vector2(center.x,center.z))
				for i in range(3):
					var index: int=indices[i];var pigment: Color=colors[index] if blend else color
					# Alpha encodes biome shader selection, not paint opacity. Keep it
					# per-face so soil/grass blending cannot accidentally add dune ribs.
					pigment.a=color.a
					v.append(tri[i]);c.append(pigment)
					n.append(smooth_normals[index] if blend else normal)
	if border_enabled:Border.append_exterior(self,v,n,c)
	return Art.mesh_from(v,n,c)

static func triangle_hit(origin: Vector3,direction: Vector3,a: Vector3,b: Vector3,c: Vector3) -> float:
	var edge:=b-a;var other:=c-a;var cross:=direction.cross(other);var det:=edge.dot(cross)
	# Only entering the solid ground is an impact. A blast starting on the surface
	# must be able to travel upward without the ground shielding it at distance zero.
	if det<.000001:return INF
	var inverse:=1.0/det;var offset:=origin-a;var u:=offset.dot(cross)*inverse
	if u<-.00001 or u>1.00001:return INF
	var q:=offset.cross(edge);var v:=direction.dot(q)*inverse
	if v<-.00001 or u+v>1.00001:return INF
	var t:=other.dot(q)*inverse
	return maxf(0,t) if t>=-.00001 else INF

func ray(origin: Vector3,direction: Vector3,distance: float) -> Dictionary:
	var hit:=INF
	if not active:
		if origin.y<=-.001:hit=0.0
		elif direction.y<-.000001:hit=-origin.y/direction.y
	else:
		var enter:=0.0;var leave:=distance
		for axis in [0,2]:
			var bound:=bounds.x if axis==0 else bounds.y
			if absf(direction[axis])<.000001:
				if absf(origin[axis])>bound:return {}
			else:
				var t0:=(-bound-origin[axis])/direction[axis];var t1:=(bound-origin[axis])/direction[axis]
				enter=maxf(enter,minf(t0,t1));leave=minf(leave,maxf(t0,t1))
		if leave<enter:return {}
		var start:=origin+direction*enter
		if start.y<height(Vector2(start.x,start.z))-.002:hit=enter
		else:
			hit=ray_blocks(origin,direction,enter,leave)
	if hit>distance:return {}
	var at:=origin+direction*hit
	return {"type":"terrain","distance":hit,"target":{"material":"ground","component_id":material_at(Vector2(at.x,at.z)),"transmission":.06}}

func ray_blocks(origin: Vector3,direction: Vector3,enter: float,leave: float) -> float:
	if ray_block_max.is_empty():return ray_cells(origin,direction,enter,leave)
	var width:=cell*RAY_BLOCK_CELLS;var start:=origin+direction*enter
	var grid:=(Vector2(start.x,start.z)+bounds)/width
	var x:=clampi(floori(grid.x),0,ray_block_size.x-1);var z:=clampi(floori(grid.y),0,ray_block_size.y-1)
	var sx:=1 if direction.x>=0 else -1;var sz:=1 if direction.z>=0 else -1
	var dx:=width/absf(direction.x) if absf(direction.x)>.000001 else INF
	var dz:=width/absf(direction.z) if absf(direction.z)>.000001 else INF
	var tx:=((x+(1 if sx>0 else 0))*width-bounds.x-origin.x)/direction.x if dx<INF else INF
	var tz:=((z+(1 if sz>0 else 0))*width-bounds.y-origin.z)/direction.z if dz<INF else INF
	while x>=0 and x<ray_block_size.x and z>=0 and z<ray_block_size.y and enter<=leave+.00001:
		var end:=minf(leave,minf(tx,tz))
		if minf(origin.y+direction.y*enter,origin.y+direction.y*end)<=ray_block_max[z*ray_block_size.x+x]+.0001:
			var hit:=ray_cells(origin,direction,enter,end)
			if hit<INF:return hit
		if tx==INF and tz==INF:break
		if tx<tz:enter=tx;x+=sx;tx+=dx
		else:enter=tz;z+=sz;tz+=dz
	return INF

func ray_cells(origin: Vector3,direction: Vector3,enter: float,leave: float) -> float:
	var start:=origin+direction*enter
	var grid:=(Vector2(start.x,start.z)+bounds)/cell
	var x:=clampi(floori(grid.x),0,size.x-1);var z:=clampi(floori(grid.y),0,size.y-1)
	var sx:=1 if direction.x>=0 else -1;var sz:=1 if direction.z>=0 else -1
	var dx:=cell/absf(direction.x) if absf(direction.x)>.000001 else INF
	var dz:=cell/absf(direction.z) if absf(direction.z)>.000001 else INF
	var tx:=((x+(1 if sx>0 else 0))*cell-bounds.x-origin.x)/direction.x if dx<INF else INF
	var tz:=((z+(1 if sz>0 else 0))*cell-bounds.y-origin.z)/direction.z if dz<INF else INF
	while x>=0 and x<size.x and z>=0 and z<size.y and enter<=leave+.00001:
		var a:=vertex(x,z);var b:=vertex(x+1,z);var d:=vertex(x,z+1);var c:=vertex(x+1,z+1)
		var t:=minf(triangle_hit(origin,direction,a,d,b),triangle_hit(origin,direction,b,d,c))
		if t>=enter-.0001 and t<=minf(leave,minf(tx,tz))+.0001:return t
		if tx==INF and tz==INF:break
		if tx<tz:enter=tx;x+=sx;tx+=dx
		else:enter=tz;z+=sz;tz+=dz
	return INF
