extends RefCounted
## Sparse claims: one objective endpoint per live soldier, no all-map occupancy grid.
var claims: Dictionary={}
static func mission(order: Dictionary) -> String:return str(order.get("task",""))+":"+str(order.get("revision",0))
func prune(units: Array,now: float) -> void:
	for id in claims.keys():
		var c: Dictionary=claims[id]
		if int(id)<0 or int(id)>=units.size():claims.erase(id);continue
		var u: Dictionary=units[id]
		if not u.get("alive",false) or u.get("player",false) or int(u.get("network_peer_id",0))>0 or int(u.get("mounted",-1))>=0 or int(u.get("spawn_epoch",0))!=int(c.epoch) or now>=float(c.until) or mission(u.get("ai_order",{}))!=str(c.mission):claims.erase(id);continue
		if Vector2(u.position).distance_squared_to(c.point)<1.0:c.arrived=true
		elif bool(c.arrived) and Vector2(u.position).distance_squared_to(c.point)>4.0:claims.erase(id)
func available(point: Vector2,id: int) -> bool:
	for owner in claims:
		if int(owner)!=id and Vector2(claims[owner].point).distance_squared_to(point)<1.0:return false
	return true
func reserve(unit: Dictionary,point: Vector2,task_key: String,now: float) -> bool:
	if not available(point,int(unit.id)):return false
	var old: Dictionary=claims.get(unit.id,{})
	var same=not old.is_empty() and int(old.epoch)==int(unit.get("spawn_epoch",0)) and str(old.mission)==task_key and Vector2(old.point).distance_squared_to(point)<.01
	claims[unit.id]={"point":point,"epoch":int(unit.get("spawn_epoch",0)),"mission":task_key,"until":now+3.0,"arrived":(same and bool(old.arrived)) or Vector2(unit.position).distance_squared_to(point)<1.0}
	return true
