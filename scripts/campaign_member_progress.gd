extends RefCounted
## Per-life, per-mission progress along a fixed route segment. Sideways motion and
## waypoint jitter cannot postpone recovery; another soldier never resets this clock.
static func sample(unit: Dictionary,record: Dictionary,goal: Vector2,now: float) -> Dictionary:
	var epoch=int(unit.get("spawn_epoch",0))
	var mission=str(unit.get("ai_order",{}).get("revision",0))+":"+str(unit.get("ai_order",{}).get("task",""))
	if record.is_empty() or int(record.get("epoch",-1))!=epoch or str(record.get("mission",""))!=mission:
		var next: Vector2=unit.path[0] if not unit.get("path",[]).is_empty() else goal
		return {"epoch":epoch,"mission":mission,"next":next,"best":unit.position.distance_to(next),"at":now,"retry_at":0.0}
	var distance: float=unit.position.distance_to(record.next)
	if distance<float(record.best)-.6:
		record.at=now;record.best=distance
	if distance<.4:
		var next=goal
		for waypoint in unit.get("path",[]):
			if unit.position.distance_to(waypoint)>=.4:next=waypoint;break
		# Reaching an unchanged endpoint is not renewed forward progress.
		if Vector2(next).distance_squared_to(record.next)>.16:record.next=next;record.best=unit.position.distance_to(next);record.at=now
	return record
