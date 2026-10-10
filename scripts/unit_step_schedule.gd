extends RefCounted
## Keep 30 Hz NPC simulation, distributed across adjacent 60 Hz player ticks.
static func elapsed(unit: Dictionary,delta: float,tick: int,staggered: bool) -> float:
	if unit.player or int(unit.get("network_peer_id",0))>0 or not staggered:
		var pending=float(unit.get("simulation_pending",0));unit.simulation_pending=0.0
		return delta+pending
	unit.simulation_pending=float(unit.get("simulation_pending",0))+delta
	if int(unit.id)%2!=tick%2:return 0.0
	var result=float(unit.simulation_pending);unit.simulation_pending=0.0
	return result

## Reuse integer storage, never clone the actor dictionaries. Repeating a start
## for two ticks gives both original 30 Hz parity groups their turn at the front.
static func fill_offline_order(units: Array,tick: int,order: Array) -> void:
	var count=units.size();order.resize(count)
	if count==0:return
	var write=0
	for index in range(count):
		var unit: Dictionary=units[index]
		if unit.player or int(unit.get("network_peer_id",0))>0:
			order[write]=index;write+=1
	var start=posmod(int((tick-1)/2),count)
	for offset in range(count):
		var index=(start+offset)%count;var unit: Dictionary=units[index]
		if unit.player or int(unit.get("network_peer_id",0))>0:continue
		order[write]=index;write+=1

static func use_offline_order(campaign: bool,offline: bool,remote_inputs: Dictionary) -> bool:
	return campaign and offline and remote_inputs.is_empty()
