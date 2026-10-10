extends RefCounted
const Paths=preload("res://scripts/terrain_paths.gd")
const IDS=["landform.low-hill","landform.trench-network","landform.level-pad"]

static func register(catalog):
	for i in range(IDS.size()):
		var id: String=IDS[i]
		catalog.components[id]={"id":id,"label":["可调果园低丘","连续折线战壕","道路 / 平台保平"][i],"primitive":"segment","material":"ground","defaults":{"length":800,"thickness":800},"runtime":{"output":"ground","collision":false,"blocksProjectiles":false,"damageable":false}}

static func param(f: Dictionary,key: String,fallback):
	return f.get(key,f.get("godot3d",{}).get(key,fallback))

static func rounded(points: PackedVector2Array,radius: float) -> PackedVector2Array:
	if points.size()<3 or radius<=0:return points.duplicate()
	var result=PackedVector2Array([points[0]])
	for i in range(1,points.size()-1):
		var p=points[i];var before=points[i-1];var after=points[i+1]
		var incoming=(p-before).normalized();var outgoing=(after-p).normalized()
		var sweep=atan2(incoming.cross(outgoing),incoming.dot(outgoing))
		if absf(sweep)<.001 or absf(sweep)>PI-.01:result.append(p);continue
		var tangent=tan(absf(sweep)*.5);var trim=minf(radius*tangent,minf(p.distance_to(before),p.distance_to(after))*.4)
		var actual_radius=trim/tangent;var a=p-incoming*trim
		var normal=Vector2(-incoming.y,incoming.x)*signf(sweep);var center=a+normal*actual_radius
		var start_angle=(a-center).angle();var steps=maxi(2,ceili(absf(sweep)*actual_radius/.25))
		result.append(a)
		for j in range(1,steps+1):result.append(center+Vector2.from_angle(start_angle+sweep*float(j)/steps)*actual_radius)
	result.append(points[-1]);return result

static func prepare(f: Dictionary,catalog,plan):
	if f.id not in IDS:return
	# Explicit metre parameters can be at feature root or under godot3d.
	for key in f.get("godot3d",{}):
		if not f.has(key):f[key]=f.godot3d[key]
	if f.id=="landform.low-hill":
		if f.points.size()<2:return
		var a: Vector2=f.points[0];var b: Vector2=f.points[1]
		var width: float=f.width;var center=(a+b)*.5
		if f.points.size()>=4:width=b.distance_to(f.points[2]);center=(a+f.points[2])*.5
		f.hill_center=center;f.hill_angle=(b-a).angle();f.hill_size=Vector2(a.distance_to(b),width)
		var top=param(f,"plateau_size_m",[2,2]);f.hill_plateau=Vector2(float(top[0]),float(top[1])).min(f.hill_size*.8)
		f.height_m=float(param(f,"height_m",param(f,"height",1.5)))
	elif f.id=="landform.trench-network":
		f.original_points=f.points.duplicate();f.points=rounded(f.points,float(param(f,"corner_radius_m",2)))
		f.depth_m=absf(float(param(f,"depth_m",param(f,"depth",1.3))))
		f.bottom_width_m=maxf(.5,float(param(f,"bottom_width_m",2.4)));f.bank_run_m=maxf(.25,float(param(f,"bank_run_m",1)))
		f.corner_widen_m=maxf(0,float(param(f,"corner_widen_m",.35)))
		# Optional excavated-soil parapet and lower rear bank. Defaults preserve
		# existing plain trenches; authored defensive trenches opt into real relief.
		f.parapet_height_m=maxf(0,float(param(f,"parapet_height_m",0)))
		f.parados_height_m=maxf(0,float(param(f,"parados_height_m",0)))
		f.parapet_side=1 if float(param(f,"parapet_side",1))>=0 else -1
		f.berm_inner_run_m=maxf(.4,float(param(f,"berm_inner_run_m",.65)))
		f.berm_crest_width_m=maxf(.5,float(param(f,"berm_crest_width_m",.8)))
		f.berm_outer_run_m=maxf(.5,float(param(f,"berm_outer_run_m",1.25)))
		f.trench_ramps=[]
		for source in param(f,"ramps",[]):
			var ramp=source.duplicate(true);var points=PackedVector2Array()
			for p in source.get("points",[]):points.append(catalog.position_point(catalog.v(p),plan))
			if points.size()<2:continue
			ramp.points=points;ramp.width_m=float(source.get("width_m",f.bottom_width_m+.4));ramp.landing_length_m=float(source.get("landing_length_m",1.25))
			f.trench_ramps.append(ramp)
		var rect=Rect2(f.points[0],Vector2.ZERO)
		for p in f.points:rect=rect.expand(p)
		for ramp in f.trench_ramps:
			for p in ramp.points:rect=rect.expand(p)
		f.trench_bounds=rect.grow(f.bottom_width_m*.5+f.bank_run_m+f.corner_widen_m+maxf(3,f.berm_inner_run_m+f.berm_crest_width_m+f.berm_outer_run_m))

static func hill(f: Dictionary,point: Vector2) -> float:
	if not f.has("hill_center"):return 0
	var p=(point-f.hill_center).rotated(-float(f.hill_angle));var half: Vector2=f.hill_size*.5
	if absf(p.x)>half.x or absf(p.y)>half.y:return 0
	var default_runs=[half.x-f.hill_plateau.x*.5,half.x-f.hill_plateau.x*.5,half.y-f.hill_plateau.y*.5,half.y-f.hill_plateau.y*.5]
	var runs=param(f,"slope_runs_m",default_runs)
	var x=clampf((half.x-absf(p.x))/maxf(.25,float(runs[0 if p.x<0 else 1])),0,1)
	var y=clampf((half.y-absf(p.y))/maxf(.25,float(runs[2 if p.y<0 else 3])),0,1)
	# Linear slopes preserve the specified grade; final render/physics uses the grid.
	return float(f.height_m)*minf(x,y)

static func trench_half_width(f: Dictionary,point: Vector2) -> float:
	var half=float(f.bottom_width_m)*.5
	for i in range(1,f.original_points.size()-1):
		var distance=point.distance_to(f.original_points[i]);var radius=maxf(1,float(param(f,"corner_radius_m",2)))
		half=maxf(half,float(f.bottom_width_m)*.5+float(f.corner_widen_m)*clampf(1-distance/(radius+half),0,1))
	return half

static func berm(f: Dictionary,point: Vector2) -> float:
	if not f.has("trench_bounds") or not f.trench_bounds.has_point(point):return 0
	if maxf(float(f.parapet_height_m),float(f.parados_height_m))<=0:return 0
	var nearest=Paths.nearest(f.points,point);var i: int=nearest.segment
	var a: Vector2=f.points[i];var b: Vector2=f.points[i+1];var center=a.lerp(b,float(nearest.ratio))
	var side=1 if (b-a).cross(point-center)>=0 else -1
	var height=float(f.parapet_height_m if side==int(f.parapet_side) else f.parados_height_m)
	var outside=float(nearest.distance)-trench_half_width(f,point)-float(f.bank_run_m)
	if outside<=0:return 0
	var inner=float(f.berm_inner_run_m);var crest=float(f.berm_crest_width_m);var outer=float(f.berm_outer_run_m)
	var profile=minf(clampf(outside/inner,0,1),clampf((inner+crest+outer-outside)/outer,0,1))
	# Open terminations and broad ramp cutouts keep soil from sealing either exit.
	var taper=clampf(minf(float(nearest.along),float(nearest.length)-float(nearest.along))/1.5,0,1)
	for ramp in f.trench_ramps:
		var near=Paths.nearest(ramp.points,point)
		taper=minf(taper,clampf((float(near.distance)-float(ramp.width_m)*.5-.7)/.8,0,1))
	return height*profile*taper

static func trench(f: Dictionary,point: Vector2) -> float:
	if not f.has("trench_bounds") or not f.trench_bounds.has_point(point):return 0
	var nearest=Paths.nearest(f.points,point);var half=trench_half_width(f,point)
	var amount=clampf((half+float(f.bank_run_m)-float(nearest.distance))/float(f.bank_run_m),0,1)
	# Continuous side ramps excavate the same bottom field once; no overlapping sum.
	for ramp in f.trench_ramps:
		var near=Paths.nearest(ramp.points,point)
		var side=clampf((float(ramp.width_m)*.5+float(f.bank_run_m)-float(near.distance))/float(f.bank_run_m),0,1)
		var end=clampf(1-float(near.along)/maxf(.01,float(near.length)),0,1)
		# A ramp must replace the circular end-cap's steep bank inside its clear
		# lane, otherwise max(union) retains a vertical shoulder at the deep end.
		if float(near.along)>.0001:amount=minf(amount,end+1-side)
		amount=maxf(amount,side*end)
	return amount*float(f.depth_m)

static func pad_weight(f: Dictionary,point: Vector2,margin: float=0) -> float:
	var transition=maxf(.001,float(param(f,"transition_m",param(f,"level_transition_m",1))))
	var distance=INF
	if Paths.is_path(f):
		if f.has("path_bounds") and not f.path_bounds.has_point(point):return 0
		var width=float(param(f,"width_m",param(f,"level_width_m",f.get("shoulder_m",f.width))))
		distance=float(Paths.nearest(f.points,point).distance)-width*.5-margin
	elif f.points.size()>=3:
		if Geometry2D.is_point_in_polygon(point,f.points):return 1
		var ring: PackedVector2Array=f.points.duplicate();ring.append(ring[0]);distance=float(Paths.nearest(ring,point).distance)-margin
	return clampf(1-maxf(0,distance)/transition,0,1)

static func is_pad(f: Dictionary) -> bool:return f.id=="landform.level-pad" or f.has("level_height_m")

static func landings(features: Array) -> Array:
	var result=[]
	for f in features:
		if f.id!="landform.trench-network":continue
		for i in range(f.trench_ramps.size()):
			var ramp: Dictionary=f.trench_ramps[i];var b: Vector2=ramp.points[-1]
			var direction=(b-ramp.points[-2]).normalized();var side=direction.orthogonal()*float(ramp.width_m)*.5
			var end=b+direction*maxf(0,float(ramp.landing_length_m))
			if b.distance_to(end)<.01:continue
			result.append({"id":"landform.level-pad","source_id":str(f.get("source_id","trench"))+".landing-"+str(i),"points":PackedVector2Array([b-side,b+side,end+side,end-side]),"width":float(ramp.width_m),"height_m":float(ramp.get("surface_height_m",0)),"transition_m":.5,"landing":true,"color":Color("a7af97")})
	return result

static func flatten(features: Array,point: Vector2,base: float,margin: float=0) -> float:
	var weight=0.0;var target=0.0
	for f in features:
		if not is_pad(f):continue
		var w=pad_weight(f,point,margin)
		if w>weight:weight=w;target=float(param(f,"level_height_m",param(f,"height_m",param(f,"height",0))))
	return lerpf(base,target,weight)

static func conflicts(features: Array,grid_margin: float=0) -> Array:
	var result=[]
	for trench_feature in features:
		if trench_feature.id!="landform.trench-network":continue
		for pad in features:
			if not is_pad(pad):continue
			if pad.get("landing",false):continue
			var samples: PackedVector2Array=trench_feature.points.duplicate()
			for ramp in trench_feature.trench_ramps:
				for i in range(ramp.points.size()-1):
					for j in range(9):samples.append(ramp.points[i].lerp(ramp.points[i+1],float(j)/8))
			for point in samples:
				if pad_weight(pad,point,float(trench_feature.bottom_width_m)*.5+grid_margin)>.01:
					result.append({"type":"trench-pad-overlap","trench":trench_feature.get("source_id","trench"),"pad":pad.get("source_id","pad"),"point":point});break
	return result

static func ground_objects(compiled: Dictionary,terrain):
	# Call immediately after terrain.configure, before HP generation/indexing. Mutate
	# the same Array so world.objects and compiled.objects keep the same reference.
	if not terrain.active:return
	var grounded=[]
	for o in compiled.objects:
		if o.get("terrain_relative",false) and not o.get("terrain_grounded",false):
			o.elevation+=terrain.height(o.position);o.terrain_grounded=true;grounded.append(o);continue
		if o.get("terrain_grounded",false) or o.output=="natural" or o.has("house") or o.get("terrain_absolute",false) or terrain.material_at(o.position) in ["terrain.snow","terrain.desert"]:
			grounded.append(o);continue
		if o.output=="tree" or str(o.component_id).begins_with("obstacle.rock"):
			o.elevation+=terrain.height(o.position);o.terrain_grounded=true;grounded.append(o);continue
		if not str(o.component_id).begins_with("wall."):
			grounded.append(o);continue
		var along=Vector2.RIGHT.rotated(o.angle);var across=Vector2.DOWN.rotated(o.angle)
		var start: Vector2=o.position-along*o.size.x*.5;var count=maxi(1,ceili(o.size.x/.55))
		var low=INF;var high=-INF
		for i in range(count+1):
			for side in [-.5,.5]:
				var sample=terrain.height(start+along*(o.size.x*i/count)+across*o.size.y*side);low=minf(low,sample);high=maxf(high,sample)
		if high-low<.035:
			o.elevation+=low;o.height+=high-low;o.terrain_grounded=true;grounded.append(o);continue
		for i in range(count):
			var part=o.duplicate(true);part.id=str(o.id)+".grade-"+str(i);part.source_id=o.get("source_id",o.id)
			part.size.x=o.size.x/count;part.position=start+along*(i+.5)*part.size.x
			var base=INF;var top=-INF
			for x in [-.5,0,.5]:
				for z in [-.5,.5]:
					var sample=terrain.height(part.position+along*part.size.x*x+across*part.size.y*z);base=minf(base,sample);top=maxf(top,sample)
			part.elevation+=base;part.height+=top-base;part.terrain_grounded=true;grounded.append(part)
	compiled.objects.assign(grounded)
