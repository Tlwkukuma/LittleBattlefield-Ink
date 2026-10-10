extends RefCounted
## Bounded physical placement; failure is data, never an unchecked fallback point.
const RADIUS=.31
const HEIGHT=1.95
const SPACING=.72
const MAX_GRADE=.75
const RING_STEP=.36
const RINGS=12
const DIRECTIONS=24
const MAX_DISTANCE=RING_STEP*RINGS
const MAX_ATTEMPTS=1+RINGS*DIRECTIONS

static func rejection(world,at: Vector2,reserved: Array=[]) -> String:
	if not at.is_finite():return "non_finite_source"
	if absf(at.x)+RADIUS>world.bounds.x or absf(at.y)+RADIUS>world.bounds.y:return "outside_world_bounds"
	if world.terrain.grade(at)>MAX_GRADE:return "terrain_grade"
	if world.blocked(at,RADIUS,HEIGHT,-1,world.terrain.height(at)):return "physical_collision"
	for other in world.units:
		if other.alive and at.distance_squared_to(other.position)<SPACING*SPACING:return "occupied_by_unit"
	for point in reserved:
		if at.distance_squared_to(point)<SPACING*SPACING:return "occupied_by_deployment"
	return ""

static func resolve(world,origin: Vector2,reserved: Array=[]) -> Dictionary:
	var reason=rejection(world,origin,reserved)
	if reason.is_empty():return {"ok":true,"position":origin,"origin":origin,"reason":"source_exact","attempts":1,"distance":0.0}
	if origin.is_finite():
		for ring in range(1,RINGS+1):
			for direction in range(DIRECTIONS):
				var at=origin+Vector2.from_angle(float(direction)*TAU/DIRECTIONS)*RING_STEP*ring
				if rejection(world,at,reserved).is_empty():
					return {"ok":true,"position":at,"origin":origin,"reason":reason,"attempts":1+(ring-1)*DIRECTIONS+direction+1,"distance":origin.distance_to(at)}
	return {"ok":false,"position":Vector2.INF,"origin":origin,"reason":reason,"attempts":MAX_ATTEMPTS if origin.is_finite() else 1,"distance":0.0,"max_distance":MAX_DISTANCE}

static func initial(world) -> Dictionary:
	var report={"ok":false,"placements":[],"corrections":[],"failures":[],"expected_counts":[0,0],"actual_counts":[0,0],"max_distance":MAX_DISTANCE}
	var records=[];var reserved=[]
	for team in range(2):
		var side="blue" if team==0 else "red"
		var deployment: Dictionary=world.plan.get("deployment",{}).get(side,{})
		var count=int(deployment.get("initialCount",30))
		var specs: Array=world.plan.get("units",{}).get(side,[])
		report.expected_counts[team]=count
		if count<1 or count>int(deployment.get("maxActive",30)) or count>int(deployment.get("totalForce",120)) or specs.size()!=count-(1 if team==0 else 0):
			report.failures.append({"team":team,"reason":"invalid_force_or_roster_count","expected":count,"spec_count":specs.size()});continue
		for slot in range(count):
			var controlled=team==0 and slot==0
			var spec: Dictionary=world.plan.deployment.get("player",{}) if controlled else specs[slot-1 if team==0 else slot]
			if not spec.has("x") or not spec.has("y"):
				report.failures.append({"team":team,"slot":slot,"reason":"missing_source_coordinate"});continue
			var origin: Vector2=world.catalog.position(spec,world.plan)
			var record={"team":team,"slot":slot,"controlled":controlled,"source_id":str(spec.get("id","player" if controlled else "%s-%d"%[side,slot])),"spec":spec,"source_position":origin,"source_angle":float(spec.get("angle",0))}
			var why=rejection(world,origin,reserved)
			if why.is_empty():
				record.merge({"ok":true,"position":origin,"origin":origin,"reason":"source_exact","attempts":1,"distance":0.0});reserved.append(origin)
			else:record.initial_rejection=why
			records.append(record)
	# Reserve every already-legal authored position before correcting any conflict.
	# A crowded early entry cannot steal a later soldier's original clear position.
	for record in records:
		if not record.has("ok"):
			record.merge(resolve(world,record.source_position,reserved))
			if record.ok:reserved.append(record.position)
		if not record.ok:
			report.failures.append(record.duplicate(true));continue
		report.placements.append(record)
		if record.reason!="source_exact":report.corrections.append(record.duplicate(true))
	report.ok=report.failures.is_empty() and report.placements.size()==int(report.expected_counts[0])+int(report.expected_counts[1])
	return report
