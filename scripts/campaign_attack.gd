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
	var previous: Dictionary=q.get("attack_progress",{});var progressed=false;var snapshot={}
	for u in units:
		if not u.alive or u.mounted>=0:continue
		var epoch=int(u.get("spawn_epoch",0));var old: Dictionary=previous.get(u.id,{})
		var next: Vector2=u.path[0] if not u.get("path",[]).is_empty() else u.get("ai_goal",point.position)
		if not old.is_empty() and int(old.epoch)==epoch:
			var moved: Vector2=u.position-old.position
			progressed=progressed or (moved.length()>.6 and moved.dot((Vector2(old.next)-Vector2(old.position)).normalized())>.35)
			if not progressed and moved.length()<=.6:snapshot[u.id]=old;continue
		snapshot[u.id]={"epoch":epoch,"position":u.position,"next":next}
	q.attack_progress=snapshot
	if not q.has("attack_progress_at") or progressed or foothold(units,point):q.attack_progress_at=now
	if now-float(q.attack_progress_at)<=10 or now<float(q.get("attack_retry_at",0)):return false
	q.attack_progress_at=now;q.attack_retry_at=now+6
	return true
