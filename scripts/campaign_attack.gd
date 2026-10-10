extends RefCounted
## Pure attack continuity rules. Arrival, damage and movement are real evidence.
const Zone=preload("res://scripts/capture_zone.gd")

static func foothold(units: Array,point: Dictionary) -> bool:
	for u in units:
		if u.alive and u.mounted<0 and Zone.contains(point,u.position,u.elevation):return true
	return false

static func entry_priority(units: Array,point: Dictionary) -> bool:
	if foothold(units,point):return true
	for u in units:
		if not u.alive or u.mounted>=0 or u.get("ai_order",{}).get("mandatory_route",false) and not u.get("ai_route_done",false):continue
		var goal: Vector2=u.get("ai_order",{}).get("goal",Vector2.INF)
		if goal.is_finite() and u.position.distance_squared_to(goal)<8*8 and float(u.get("ai_stress",0))<.62:return true
	return false

static func checkpoint(q: Dictionary,units: Array,point: Dictionary,now: float) -> bool:
	var previous: Dictionary=q.get("attack_progress",{});var snapshot={};var stalled=[]
	for u in units:
		if not u.alive or u.mounted>=0:continue
		var record=preload("res://scripts/campaign_member_progress.gd").sample(u,previous.get(u.id,{}),u.get("ai_order",{}).get("goal",point.position),now)
		snapshot[u.id]=record
		if Zone.contains(point,u.position,u.elevation):continue
		if now-float(record.at)>10 and now>=float(record.retry_at):
			stalled.append(u.id);record.retry_at=now+6
	q.attack_progress=snapshot;q.attack_stalled_ids=stalled
	return not stalled.is_empty()
