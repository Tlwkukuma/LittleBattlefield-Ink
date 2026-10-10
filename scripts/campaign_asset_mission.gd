extends RefCounted
## Read-only mission geometry, sliced by the caller. Never drives or fires.
const Ground=preload("res://scripts/vehicle_grounding.gd")
const Collision=preload("res://scripts/vehicle_collision.gd")
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")

static func pose_clear(world,v: Dictionary,at: Vector2,angle: float) -> bool:
	var support=Ground.sample(world.terrain,v,at,angle,false,world)
	if not support.passable:return false
	var probe=v.duplicate();probe.position=at;probe.angle=angle
	probe.pose_basis=Ground.basis(angle,support.normal);probe.elevation=support.height
	# Bodies are transient traffic, not permanent navigation islands. Real driving
	# still checks people on every movement step through the default collider.
	return not Collision.blocked(world,probe,null,false)

static func firing_lane(world,v: Dictionary,at: Vector2,focus: Vector2) -> bool:
	var origin=Vector3(at.x,world.terrain.height(at)+(1.16 if v.emplacement else 1.5),at.y)
	var mark=Vector3(focus.x,world.terrain.height(focus)+.95,focus.y);var ray=mark-origin
	if ray.length()<2:return false
	return world.trace_3d(origin,ray.normalized(),ray.length(),{"mount":v.id},true).is_empty()

static func begin(world,v: Dictionary,road: Array,focus: Vector2) -> Dictionary:
	var choices=[]
	var approach=Vector2.RIGHT
	if int(world.plan.get("godot3d",{}).get("campaign_chapter",1))>1:
		approach=(focus-Vector2(v.position)).normalized()
		if approach.is_zero_approx():approach=Vector2.from_angle(float(v.angle))
	# Screen the actual gate frontage, rather than aiming at a flag behind the
	# intact 2.2 m walls. Equipment coordinates and the road itself stay unchanged.
	for offset in [Vector2(-5,0),Vector2(-6,3),Vector2(-6,-3),Vector2(-9,5),Vector2(-9,-5)]:
		var post=focus+approach*offset.x+approach.orthogonal()*offset.y
		for exit in range(road.size()):
			var route=[];var nearest=0;var distance=INF
			for i in range(road.size()):
				var d: float=v.position.distance_squared_to(road[i])
				if d<distance:distance=d;nearest=i
			var direction=1 if exit>=nearest else -1
			for i in range(nearest,exit+direction,direction):route.append(road[i])
			route.append(post)
			var cost=0.0;var previous: Vector2=v.position
			for p in route:cost+=previous.distance_to(p);previous=p
			choices.append({"route":route,"goal":post,"cost":cost+absf(offset.y)*.2})
	choices.sort_custom(func(a,b):return a.cost<b.cost)
	return {"choices":choices,"choice":0,"segment":0,"step":0,"previous":v.position,"heading":float(v.angle),"initial_heading":float(v.angle),"origin":v.position,"revision":world.topology_revision,"done":false,"result":{},"samples":0,"focus":focus}

static func pump(world,v: Dictionary,job: Dictionary,budget_usec: int=350,max_samples: int=2) -> void:
	var started=Time.get_ticks_usec();var worked=0
	while not job.done and worked<max_samples and Time.get_ticks_usec()-started<budget_usec:
		if int(job.choice)>=job.choices.size():job.done=true;return
		var choice: Dictionary=job.choices[job.choice];var route: Array=choice.route
		if int(job.segment)>=route.size():
			if firing_lane(world,v,choice.goal,job.focus):job.result=choice;job.done=true;return
			reject(job);continue
		var end: Vector2=route[job.segment];var offset: Vector2=end-job.previous
		var heading=offset.angle() if offset.length()>.02 else float(job.heading)
		var turn=wrapf(heading-float(job.heading),-PI,PI);var turns=maxi(1,ceili(absf(turn)/.12))
		var steps=maxi(1,ceili(offset.length()/.4));var index=int(job.step)
		var at: Vector2=job.previous if index<turns else Vector2(job.previous).lerp(end,float(index-turns+1)/steps)
		var angle=float(job.heading)+turn*float(index+1)/turns if index<turns else heading
		job.samples+=1;worked+=1
		if not pose_clear(world,v,at,angle):reject(job);continue
		job.step=index+1
		if int(job.step)>=turns+steps:job.previous=end;job.heading=heading;job.segment+=1;job.step=0

static func reject(job: Dictionary):
	job.choice+=1;job.segment=0;job.step=0;job.previous=job.origin
	job.heading=job.get("initial_heading",job.heading)

static func begin_sector(v: Dictionary,focus: Vector2) -> Dictionary:
	# The initial fast probes already covered center/frontage and both half-arcs.
	# Complete the remaining legal quarters/endpoints through the same job queue.
	var bearings=[]
	for fraction in [.25,-.25,.75,-.75,1.0,-1.0]:
		var bearing=float(v.angle)+float(v.profile.traverse)*fraction
		bearings.append({"angle":bearing,"cost":absf(wrapf(bearing-(focus-Vector2(v.position)).angle(),-PI,PI))})
	bearings.sort_custom(func(a,b):return a.cost<b.cost)
	return {"kind":"sector","vehicle":int(v.id),"source_id":str(v.get("source_id","")),"origin":Vector2(v.position),"base_angle":float(v.angle),"traverse":float(v.profile.traverse),"bearings":bearings,"next":0,"samples":0,"done":false,"result":{}}

static func pump_sector(world,v: Dictionary,job: Dictionary,budget_usec: int=350) -> void:
	if job.done or budget_usec<=0:return
	if int(v.id)!=int(job.vehicle) or str(v.get("source_id",""))!=str(job.source_id) or Vector2(v.position).distance_squared_to(job.origin)>.000001 or absf(wrapf(float(v.angle)-float(job.base_angle),-PI,PI))>.00001 or not is_equal_approx(float(v.profile.traverse),float(job.traverse)):
		job.invalidated=true;job.done=true;job.result={};return
	if v.destroyed or int(job.next)>=job.bearings.size():job.done=true;return
	# Exactly one atomic lane query per scheduler visit; never a full arc sweep.
	var bearing=float(job.bearings[int(job.next)].angle);job.next+=1;job.samples+=1
	var target=Vector2(v.position)+Vector2.from_angle(bearing)*6.0
	if firing_lane(world,v,v.position,target):
		job.result={"goal":v.position,"route":[],"focus":target};job.done=true
	elif int(job.next)>=job.bearings.size():job.done=true
