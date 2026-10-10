extends RefCounted
## One authored roster, four real soldiers per truck. No spawning or replenishment.
const Truck=preload("res://scripts/hanlue_truck.gd")
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
var world_ref: WeakRef
var trucks: Array=[]
var last_error=""

func configure(world) -> bool:
	world_ref=weakref(world);trucks.clear();last_error=""
	var settings: Dictionary=world.plan.get("hanlueMission",{})
	var by_source={}
	for u in world.units:by_source[str(u.get("campaign_source_id",""))]=u
	var assignments: Array=settings.get("convoyAssignments",[])
	if assignments.size()!=3:last_error="车队配置必须为三辆卡车";return false
	var claimed_units={};var claimed_trucks={}
	for assignment in assignments:
		var source=str(assignment.get("vehicleId",""))
		var found=false
		for v in world.vehicles:
			if v.type==Truck.KIND and v.source_id==source:found=true;break
		if not found or claimed_trucks.has(source) or assignment.get("unitIds",[]).size()!=4:last_error="车队车辆或四人乘员配置无效";return false
		claimed_trucks[source]=true
		for unit_source in assignment.unitIds:
			var u: Dictionary=by_source.get(str(unit_source),{})
			if u.is_empty() or not u.alive or u.player or int(u.team)!=1 or u.mounted>=0 or claimed_units.has(str(unit_source)):last_error="车队乘员缺失或重复";return false
			claimed_units[str(unit_source)]=true
	for assignment in assignments:
		if trucks.size()>=3:break
		var v: Dictionary={}
		for candidate in world.vehicles:
			if candidate.type==Truck.KIND and candidate.source_id==assignment.vehicleId:v=candidate;break
		if v.is_empty():continue
		v.hanlue_transport=true;v.hanlue_crew=[];v.passenger_ids=[];v.hanlue_route=[]
		v.hanlue_waypoint=0;v.hanlue_stuck=0.0;v.hanlue_progress=v.position
		v.hanlue_observe_at=0.5+trucks.size()*.2;v.hanlue_observer=0
		v.hanlue_abandoned=false;v.hanlue_next_exit=world.time+float(trucks.size())*.12
		v.ai_controlled=true
		for source in settings.get("convoyRoute",[]):
			var point: Vector2=world.catalog.position(source,world.plan)
			# The authored straight road is eastbound. Never steer to a passed point.
			if (point-Vector2(v.position)).dot(Vector2.from_angle(v.angle))>.5:v.hanlue_route.append(point)
		var seat_index=0
		for source in assignment.get("unitIds",[]):
			if seat_index>=4:break
			var u: Dictionary=by_source.get(str(source),{})
			if u.is_empty() or not u.alive or u.mounted>=0 or u.player:continue
			world.Traversal.reset(u);u.mounted=v.id;u.hanlue_seat=seat_index
			u.hanlue_passenger=seat_index>0;u.stance=1 if seat_index>0 else 0;u.stance_blend=float(u.stance);u.path=[];u.repath=0.0
			u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;u.aim_valid=false;u.aiming=false
			v.hanlue_crew.append(u.id)
			if seat_index==0:v.driver_id=u.id;v.driver=true
			else:v.passenger_ids.append(u.id)
			seat_index+=1
		trucks.append(v);sync_passengers(v)
	return true

func observe_event(data: Dictionary) -> void:
	var kind=str(data.get("type",""));var point=Vector2.INF;var radius=0.0
	if kind=="shot":
		var source: Dictionary=data.get("unit",{})
		if source.is_empty():return
		point=source.position;radius=42.0
	elif kind=="explosion":point=data.position;radius=minf(55.0,25.0+float(data.get("radius",0))*4.0)
	elif kind=="vehicle_damage":
		var vehicle: Dictionary=data.get("vehicle",{})
		if vehicle.get("hanlue_transport",false):vehicle.hanlue_alerted=true
		return
	elif kind=="damage":
		var unit: Dictionary=data.get("unit",{})
		if int(unit.get("mounted",-1))<0:return
		for vehicle in trucks:
			if int(vehicle.id)==int(unit.mounted):vehicle.hanlue_alerted=true
		return
	else:return
	# Hearing gives a local alarm, never a hidden enemy location or firing target.
	for vehicle in trucks:
		if vehicle.position.distance_squared_to(point)<=radius*radius:vehicle.hanlue_alerted=true

func sync_passengers(v: Dictionary) -> void:
	var world=world_ref.get_ref()
	for uid in v.get("hanlue_crew",[]):
		var u: Dictionary=world.units[int(uid)]
		if not u.alive or u.mounted!=v.id:continue
		var point=Vector3(v.position.x,v.elevation,v.position.y)+Dimensions.body_basis(v)*Truck.seat(int(u.get("hanlue_seat",0)))
		u.position=Vector2(point.x,point.z);u.elevation=point.y;u.facing=Vector2.from_angle(v.angle)
		u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO;u.aim_valid=false;u.aiming=false
		world.index_unit(u);world.RenderMotion.after_unit(u,world.time,0.0)

func update_vehicle(v: Dictionary,delta: float) -> void:
	var world=world_ref.get_ref()
	if not v.get("hanlue_transport",false):return
	if v.get("hanlue_escaped",false):retire_escaped(v);return
	if not v.destroyed:observe_road(v)
	if v.destroyed:
		if v.get("airborne",false) or absf(float(v.get("fall_speed",0)))>.001:
			var support=world.VehicleGround.sample(world.terrain,v,v.position,v.angle,true,world)
			v.ground=preload("res://scripts/vehicle_vertical_motion.gd").settle(world,v,support,delta)
		return
	var stage=str(world.campaign.hanlue.stage) if world.campaign.hanlue!=null else "concealed"
	var moving=stage in ["convoy","ambush","withdrawal"]
	var driver_id=int(v.get("driver_id",-1))
	var driver_ok=driver_id>=0 and driver_id<world.units.size() and world.units[driver_id].alive and world.units[driver_id].mounted==v.id
	if not driver_ok:
		v.driver=false;v.driver_id=-1
		if v.ai_controlled:v.ai_controlled=false;navigation_changed(v)
	v.passenger_ids=v.passenger_ids.filter(func(uid):return world.units[int(uid)].alive and world.units[int(uid)].mounted==v.id)
	var unload=(v.get("hanlue_alerted",false) or not driver_ok or v.hanlue_abandoned) and not v.passenger_ids.is_empty()
	var index=int(v.hanlue_waypoint)
	while index<v.hanlue_route.size() and v.position.distance_to(v.hanlue_route[index])<1.2:index+=1
	v.hanlue_waypoint=index
	var stop=not moving or not driver_ok or unload or v.hanlue_abandoned or index>=v.hanlue_route.size()
	# Only the finite three convoy trucks participate in spacing; all collision is
	# still handled by drive(), including people, world geometry and wrecks.
	var traffic=false
	if not stop:
		for other in trucks:
			if other.id==v.id or other.get("hanlue_escaped",false):continue
			var offset: Vector2=other.position-v.position
			var forward=Vector2.from_angle(v.angle)
			if offset.dot(forward)>0 and offset.dot(forward)<6.2 and absf(offset.cross(forward))<2.3:traffic=true;break
	var request=Vector2.ZERO
	if not stop and not traffic:
		var offset: Vector2=v.hanlue_route[index]-v.position
		var error=wrapf(offset.angle()-float(v.angle),-PI,PI)
		request=Vector2(.65*clampf(1.0-absf(error)/PI,.25,1.0),clampf(error*1.6,-1,1))
	if not stop:
		if v.position.distance_to(v.hanlue_progress)>.30:v.hanlue_progress=v.position;v.hanlue_stuck=0.0
		else:v.hanlue_stuck+=delta
		# No infinite reverse/replan loop or bypass of a genuine road obstruction.
		if float(v.hanlue_stuck)>9.0:
			v.hanlue_abandoned=true;v.ai_controlled=false;stop=true;request=Vector2.ZERO
			navigation_changed(v)
	world.drive(v,request.x,request.y,delta,false,false,stop or traffic)
	v.turret_angle=v.angle
	sync_passengers(v)
	if (unload or v.hanlue_abandoned or not driver_ok) and absf(float(v.speed))<.45 and not v.get("airborne",false) and world.time>=float(v.hanlue_next_exit):
		v.hanlue_next_exit=world.time+.45
		var uid=int(v.passenger_ids[0]) if not v.passenger_ids.is_empty() else driver_id
		if uid>=0:leave(world.units[uid],v)

func observe_road(v: Dictionary) -> void:
	var world=world_ref.get_ref()
	if v.get("hanlue_alerted",false) or world.time<float(v.hanlue_observe_at) or world.ai_budget_usec<=0:return
	v.hanlue_observe_at=world.time+.7
	var crew: Array=v.hanlue_crew
	if crew.is_empty():return
	var unit: Dictionary=world.units[int(crew[int(v.hanlue_observer)%crew.size()])]
	v.hanlue_observer=int(v.hanlue_observer)+1
	if not unit.alive or unit.mounted!=v.id:return
	var started=Time.get_ticks_usec()
	# One existing perception refresh shares the ordinary global AI budget/ray
	# cap. Real line of sight may reveal an exposed ambusher before any gunshot.
	var report: Dictionary=world.campaign_ai.perception.refresh(unit,2)
	world.ai_budget_usec-=Time.get_ticks_usec()-started
	if not report.is_empty():
		v.hanlue_alerted=true
		if world.campaign.hanlue.is_concealed():world.campaign.hanlue.begin_ambush("detected")

func leave(u: Dictionary,v: Dictionary) -> bool:
	var world=world_ref.get_ref()
	if not u.alive or u.mounted!=v.id:return false
	var start: Vector2=u.position
	# Bounded eight exit locations. No forced spawn fallback and no wall teleport.
	for i in range(8):
		var point=Dimensions.exit_point(v,Vector2.from_angle(v.angle+PI*.5+i*TAU/8),.65)
		var height: float=world.ground_height(point,.31,float(v.elevation)+.65)
		if absf(height-float(v.elevation))>1.0 or world.terrain.grade(point)>.65 or world.blocked(point,.31,1.95,-1,height):continue
		var occupied=false
		for other in world.nearby_units(point,.75):
			if other.alive and other.id!=u.id and other.mounted<0 and point.distance_to(other.position)<.64:occupied=true;break
		if occupied:continue
		var clear=true
		for step in range(1,7):
			var t=float(step)/6.0
			if world.blocked(start.lerp(point,t),.31,1.4,int(v.id),lerpf(float(u.elevation),height,t)):clear=false;break
		if not clear:continue
		if int(v.driver_id)==int(u.id):v.driver=false;v.driver_id=-1
		v.passenger_ids.erase(u.id);u.mounted=-1;u.hanlue_passenger=false
		world.Traversal.reset(u);u.position=point;u.elevation=height;u.path=[];u.repath=0.0
		u.ai_vehicle_retry_at=INF;u.guard_until=0.0;u.ai_state="seek-cover"
		world.campaign_ai.select_weapon(world,u,0.0)
		world.index_unit(u);world.RenderMotion.after_unit(u,world.time,0.0)
		navigation_changed(v)
		return true
	return false

func destroyed(v: Dictionary) -> void:
	var world=world_ref.get_ref()
	navigation_changed(v)
	for uid in v.get("hanlue_crew",[]):
		var u: Dictionary=world.units[int(uid)]
		if not u.alive or u.mounted!=v.id:continue
		if not leave(u,v):
			# A physically trapped occupant is a casualty, never a relocated clone.
			world.damage_unit(u,u.max_health+1,Vector3.UP,{"kind":"shell"},true)
	v.driver=false;v.driver_id=-1;v.passenger_ids=[]

func navigation_changed(v: Dictionary) -> void:
	var world=world_ref.get_ref();var radius=float(v.dimensions.half.length())+1.4
	world.campaign_ai.invalidate_bounds(v.position-Vector2.ONE*radius,v.position+Vector2.ONE*radius)
	world.navigation_dirty=true

func retire_escaped(v: Dictionary) -> void:
	if v.get("hanlue_retired",false):return
	var world=world_ref.get_ref()
	# A real zone arrival retires the existing actors, never creates casualty credit.
	for uid in v.get("hanlue_crew",[]):
		var u: Dictionary=world.units[int(uid)]
		if u.alive and u.mounted==v.id:world.retire_mission_unit(u,"escaped")
	v.driver=false;v.driver_id=-1;v.passenger_ids=[];v.hanlue_retired=true
	world.VehicleDynamics.reset(v);world.index_vehicle(v);navigation_changed(v)
