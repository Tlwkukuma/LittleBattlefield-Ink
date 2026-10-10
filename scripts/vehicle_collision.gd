extends RefCounted
## Tilted hulls meet the existing live wall cells and separate natural/furniture solids.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Offroad=preload("res://scripts/vehicle_offroad.gd")
const Person=preload("res://scripts/vehicle_person_contact.gd")
const PERSON_RADIUS=.28
const SKIN=.008

static func data(frame: Transform3D,low: Vector3,high: Vector3) -> Dictionary:
	var center=frame*((low+high)*.5);var extent=(high-low)*.5
	var world_extent=frame.basis.x.abs()*extent.x+frame.basis.y.abs()*extent.y+frame.basis.z.abs()*extent.z
	return {"center":center,"extent":extent,"basis":frame.basis,"min":center-world_extent,"max":center+world_extent}

static func shape_data(shape: Dictionary) -> Dictionary:
	var ends=Dimensions.limits(shape)
	return data(Dimensions.frame_for(shape),ends[0],ends[1])

static func shape_cache(v: Dictionary) -> Dictionary:
	Dimensions.hit_boxes(v)
	var cached: Dictionary=v.get("vehicle_sat_cache",{})
	if not cached.is_empty() and cached.pose==v.collision_pose and cached.height==v.collision_height_pose and cached.get("destroyed",false)==v.get("destroyed",false):return cached
	cached={"pose":v.collision_pose,"height":v.collision_height_pose,"destroyed":v.get("destroyed",false)};v.vehicle_sat_cache=cached
	return cached

static func body_shapes(v: Dictionary) -> Array:
	var cached=shape_cache(v)
	if not cached.has("body"):
		var result=[]
		for box in Dimensions.hit_boxes(v):result.append(shape_data(box))
		cached.body=result
	return cached.body

static func radius(box: Dictionary,axis: Vector3) -> float:
	return absf(box.basis.x.dot(axis))*box.extent.x+absf(box.basis.y.dot(axis))*box.extent.y+absf(box.basis.z.dot(axis))*box.extent.z

static func closest(box: Dictionary,point: Vector3) -> Vector3:
	var local: Vector3=box.basis.transposed()*(point-box.center)
	return box.center+box.basis*local.clamp(-box.extent,box.extent)

static func overlap(a: Dictionary,b: Dictionary,contact: Variant=null) -> bool:
	if a.has("min") and b.has("min"):
		for axis in range(3):
			if a.max[axis]<=b.min[axis]+SKIN or b.max[axis]<=a.min[axis]+SKIN:return false
	var delta: Vector3=b.center-a.center
	var depth=INF;var normal=Vector2.ZERO
	var axes=[a.basis.x,a.basis.y,a.basis.z,b.basis.x,b.basis.y,b.basis.z]
	for i in range(3):
		for j in range(3):axes.append(a.basis[i].cross(b.basis[j]))
	for raw in axes:
		if raw.length_squared()<.0000001:continue
		var axis: Vector3=raw.normalized()
		var projection=delta.dot(axis);var penetration=radius(a,axis)+radius(b,axis)-SKIN-absf(projection)
		if penetration<=0:return false
		if contact==null:continue
		var horizontal=Vector2(axis.x,axis.z);var length=horizontal.length()
		if length>.15 and penetration/length<depth:
			depth=penetration/length;normal=horizontal/length*(-1.0 if projection>=0 else 1.0)
	if contact!=null:
		contact.normal=normal;contact.depth=depth
		var point=closest(a,closest(b,a.center));contact.point=Vector2(point.x,point.z)
	return true

static func unique_axis(output: Array,axis: Vector3) -> void:
	if axis.length_squared()<.000001:return
	axis=axis.normalized()
	for old in output:
		if absf(old.dot(axis))>.9999:return
	output.append(axis)

static func natural_parts(o: Dictionary,frame: Transform3D) -> Array:
	if o.has("vehicle_contact_parts") and o.get("vehicle_contact_frame",Transform3D(Basis.IDENTITY,Vector3.INF))==frame:return o.vehicle_contact_parts
	var result=[]
	for part in o.nature_solids:
		var points=[];var axes=[];var edges=[]
		var low=Vector3(INF,INF,INF);var high=-low
		for point in part.vertices:
			var at=frame*point;points.append(at);low=low.min(at);high=high.max(at)
		for plane in part.planes:unique_axis(axes,frame.basis*plane.normal)
		for face in part.faces:
			for i in range(face.size()):unique_axis(edges,frame.basis*(part.vertices[face[i]]-part.vertices[face[(i+1)%face.size()]]))
		result.append({"points":points,"axes":axes,"edges":edges,"source":part,"min":low,"max":high})
	o.vehicle_contact_parts=result;o.vehicle_contact_frame=frame;return result

static func projections(part: Dictionary,frame: Basis) -> Array:
	# All hull sections share a few orientations. Project the immutable rock vertices
	# once per orientation, not once per section and again for every clearance lift.
	var entries: Array=part.get("projection_cache",[])
	for entry in entries:
		if entry.basis==frame:return entry.axes
	var axes=part.axes.duplicate();axes.append_array([frame.x,frame.y,frame.z])
	for i in range(3):
		for edge in part.edges:axes.append(frame[i].cross(edge))
	var result=[];var origin: Vector3=part.points[0]
	for raw in axes:
		if raw.length_squared()<.0000001:continue
		var axis: Vector3=raw.normalized();var low=INF;var high=-INF
		for point in part.points:
			var at: float=(point-origin).dot(axis);low=minf(low,at);high=maxf(high,at)
		result.append(Vector4(axis.x,axis.y,axis.z,low));result.append(high)
	if entries.size()>=3:entries.pop_front()
	entries.append({"basis":frame,"axes":result});part.projection_cache=entries
	return result

static func natural_overlap(box: Dictionary,part: Dictionary,contact: Variant=null) -> bool:
	if box.has("min") and part.has("min"):
		for axis in range(3):
			if box.max[axis]<=part.min[axis]+SKIN or part.max[axis]<=box.min[axis]+SKIN:return false
	var depth=INF;var normal=Vector2.ZERO
	var axes=projections(part,box.basis);var relative: Vector3=box.center-part.points[0]
	for i in range(0,axes.size(),2):
		var packed: Vector4=axes[i];var axis=Vector3(packed.x,packed.y,packed.z);var shift=relative.dot(axis)
		var low=packed.w-shift;var high=float(axes[i+1])-shift
		var extent=radius(box,axis)
		if low>=extent-SKIN or high<=-extent+SKIN:return false
		if contact==null:continue
		var horizontal=Vector2(axis.x,axis.z);var length=horizontal.length()
		var negative=extent-low-SKIN;var positive=extent+high-SKIN
		var penetration=minf(negative,positive)
		if length>.15 and penetration/length<depth:
			depth=penetration/length;normal=horizontal/length*(-1.0 if negative<=positive else 1.0)
	if contact!=null:
		contact.normal=normal;contact.depth=depth
		var center=Vector3.ZERO
		for point in part.points:center+=point
		var at=closest(box,center/part.points.size());contact.point=Vector2(at.x,at.z)
	return true

static func rock_hull(v: Dictionary) -> Array:
	var cached=shape_cache(v)
	if cached.has("rock"):return cached.rock
	var boxes=Dimensions.hit_boxes(v);var result=[]
	if not v.has("vehicle_rock_recipe"):
		var recipe=[];var clearance: float=Offroad.profile(v).clearance;var length: float=Dimensions.for_vehicle(v).half.x
		# Authoring-space cuts are fixed for this model; only their transforms change.
		for i in range(boxes.size()):
			var box: Dictionary=boxes[i]
			if box.get("gear",false):continue
			var ends=Dimensions.limits(box)
			if not box.get("body",false):recipe.append({"box":i,"low":ends[0],"high":ends[1]});continue
			var along: float=box.along
			for section in [[-length,-length*.84,.27],[-length*.84,-length*.62,.10],[-length*.62,length*.62,0.0],[length*.62,length*.84,.10],[length*.84,length,.27]]:
				var low=Vector3(maxf(ends[0].x,section[0]-along),maxf(ends[0].y,clearance+section[2]),ends[0].z)
				var high=Vector3(minf(ends[1].x,section[1]-along),ends[1].y,ends[1].z)
				if high.x>low.x and high.y>low.y:recipe.append({"box":i,"low":low,"high":high})
		v.vehicle_rock_recipe=recipe
	for part in v.vehicle_rock_recipe:result.append(data(Dimensions.frame_for(boxes[part.box]),part.low,part.high))
	cached.rock=result;return result

static func rock_penetration(shapes: Array,parts: Array,lift: float) -> bool:
	for original in shapes:
		var shape: Dictionary=original.duplicate();shape.center+=Vector3.UP*lift
		shape.min+=Vector3.UP*lift;shape.max+=Vector3.UP*lift
		for part in parts:
			if natural_overlap(shape,part):return true
	return false

static func rock_support_lift(v: Dictionary,rocks: Array,limit: float) -> float:
	if rocks.is_empty():return 0.0
	var parts=[]
	for rock in rocks:
		if not rock.alive:continue
		for part in natural_parts(rock,Transform3D(Basis(Vector3.UP,-rock.angle),Vector3(rock.position.x,rock.elevation,rock.position.y))):
			if Offroad.supports_part(rock,v,part.source):parts.append(part)
	var shapes=rock_hull(v)
	if not rock_penetration(shapes,parts,0):return 0.0
	if rock_penetration(shapes,parts,limit):return INF
	var low=0.0;var high=limit
	for i in range(6):
		var mid=(low+high)*.5
		if rock_penetration(shapes,parts,mid):low=mid
		else:high=mid
	return high+.001

static func blocked(world,v: Dictionary,contact: Variant=null,include_people: bool=true) -> bool:
	if contact!=null:contact.clear()
	var footprint=Dimensions.planar_bounds(v)
	for edge in [[-world.bounds.x-footprint.position.x,Vector2.RIGHT],[footprint.end.x-world.bounds.x,Vector2.LEFT],[-world.bounds.y-footprint.position.y,Vector2.DOWN],[footprint.end.y-world.bounds.y,Vector2.UP]]:
		if edge[0]<=0:continue
		if contact!=null:contact.normal=edge[1];contact.depth=edge[0];contact.point=v.position-edge[1]*Dimensions.for_vehicle(v).half.length();contact.kind="boundary"
		return true
	var shapes=body_shapes(v);var rock_shapes=[]
	for other in world.vehicle_candidates(footprint):
		if other.id==v.id or not footprint.intersects(Dimensions.planar_bounds(other)):continue
		for box in Dimensions.hit_boxes(other):
			var target=shape_data(box)
			for shape in shapes:
				if overlap(shape,target,contact):
					if contact!=null:contact.kind="vehicle";contact.target=other
					return true
	var reach=footprint.size.length()*.5+footprint.get_center().distance_to(v.position)
	var scenery=world.obstacle_tree.query(footprint,true,world.profile_ai)
	if contact!=null and scenery.size()>1:
		# Preserve the former grid's first-contact order at overlapping corners;
		# the broad phase may prune candidates without changing impact normals.
		var first=Vector2i(floori((v.position.x-reach)/4),floori((v.position.y-reach)/4))
		scenery.sort_custom(func(a: Dictionary,b: Dictionary):
			var ax=maxi(first.x,a.ray_index_span.x);var bx=maxi(first.x,b.ray_index_span.x)
			if ax!=bx:return ax<bx
			var ay=maxi(first.y,a.ray_index_span.z);var by=maxi(first.y,b.ray_index_span.z)
			return ay<by if ay!=by else a.collision_rank<b.collision_rank)
	for o in scenery:
		if not o.alive or not o.collision:continue
		var frame=Transform3D(Basis(Vector3.UP,-o.angle),Vector3(o.position.x,o.elevation,o.position.y))
		var broad=data(frame,Vector3(-o.size.x*.5,0,-o.size.y*.5),Vector3(o.size.x*.5,o.height,o.size.y*.5))
		if o.has("nature_solids"):
			var near=false
			for shape in shapes:
				if overlap(shape,broad):near=true;break
			if not near:continue
			# Keep the real belly clearance for every part of a climbable log.
			# Taller branches still collide with the hull, but not with empty space below it.
			var natural_shapes=shapes
			if Offroad.traversable(o,v):
				if rock_shapes.is_empty():rock_shapes=rock_hull(v)
				natural_shapes=rock_shapes
			for part in natural_parts(o,frame):
				for shape in natural_shapes:
					if natural_overlap(shape,part,contact):
						if contact!=null:contact.kind="nature";contact.target=o
						return true
			continue
		for shape in shapes:
			if not overlap(shape,broad):continue
			if o.has("solid_parts"):
				for part in o.solid_parts:
					if part.has("cell") and o.hp[part.cell]<=0:continue
					if overlap(shape,data(frame,part.at-part.size*.5,part.at+part.size*.5),contact):
						if contact!=null:contact.kind="solid";contact.target=o
						return true
			else:
				# Test only surviving cells. Broken windows, openings and wall breaches stay open.
				var inverse=frame.affine_inverse();var center: Vector3=inverse*shape.center
				var width=radius(shape,frame.basis.x);var height=radius(shape,Vector3.UP)
				var first_col=clampi(floori((center.x-width+o.size.x*.5)/o.cell_width),0,o.columns-1)
				var last_col=clampi(floori((center.x+width+o.size.x*.5)/o.cell_width),0,o.columns-1)
				var first_row=clampi(floori((center.y-height)/o.cell_height),0,o.rows-1)
				var last_row=clampi(floori((center.y+height)/o.cell_height),0,o.rows-1)
				for col in range(first_col,last_col+1):
					for row in range(first_row,last_row+1):
						if o.hp[row*o.columns+col]<=0:continue
						var low=Vector3(-o.size.x*.5+col*o.cell_width,row*o.cell_height,-o.size.y*.5)
						if overlap(shape,data(frame,low,low+Vector3(o.cell_width,o.cell_height,o.size.y)),contact):
							if contact!=null:contact.kind="wall";contact.target=o
							return true
	# Resolve scenery first: a body behind a wall must not receive a vehicle impact through it.
	if include_people and world.has_method("nearby_units"):
		for unit in world.nearby_units(v.position,reach+.85):
			if not unit.alive or unit.get("mounted",-1)==v.id or world.enclosed(unit):continue
			var person_radius=float(unit.vehicle_flight.radius) if not unit.get("vehicle_flight",{}).is_empty() else PERSON_RADIUS
			var hit=Person.contact(v,unit.position,person_radius,unit.elevation,world.collision_height(unit),true)
			if hit.is_empty():continue
			if contact!=null:
				contact.normal=-hit.normal;contact.depth=hit.depth;contact.point=hit.point;contact.kind="person";contact.target=unit;contact.gear=hit.gear
			return true
	return false
