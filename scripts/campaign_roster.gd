extends RefCounted
## Stable infantry identity is independent of network slots and successive lives.
static func eligible(u: Dictionary,reserved: Dictionary) -> bool:
	return u.get("alive",false) and not u.get("player",false) and int(u.get("network_peer_id",0))==0 and int(u.get("mounted",-1))<0 and not reserved.has(u.id)

static func reconcile(state: Dictionary,units: Array,team: int,now: float,reserved: Dictionary,join_allowed: Callable=Callable()) -> void:
	var groups: Dictionary=state.squads;var assigned={};var size=int(state.size)
	for key in groups.keys():
		var q: Dictionary=groups[key];var remaining=[];var epochs: Dictionary=q.get("epochs",{})
		for id in q.members:
			if id<0 or id>=units.size():continue
			var u: Dictionary=units[id]
			if u.team!=team or not eligible(u,reserved) or int(epochs.get(id,-1))!=int(u.get("spawn_epoch",0)):continue
			remaining.append(id);assigned[id]=true
		q.members=remaining
		if remaining.is_empty():groups.erase(key)
	for u in units:
		if u.team!=team or not eligible(u,reserved) or assigned.has(u.id):continue
		var cohort=int(u.get("recruit_cohort",-1));var best: Dictionary={};var distance=4.5*4.5
		for q in groups.values():
			if q.members.size()>=size or (cohort>=0 and int(q.cohort)!=cohort):continue
			if cohort<0 and int(q.cohort)>=0:continue
			var close=true;var d=INF
			for id in q.members:
				var gap: float=Vector2(u.position).distance_squared_to(units[id].position)
				if gap>5.75*5.75:close=false;break
				d=minf(d,gap)
			if close and d<distance:best=q;distance=d
		if not best.is_empty() and join_allowed.is_valid() and not join_allowed.call(u.position,anchor(best,units)):best={}
		if best.is_empty():
			var slot=int(state.get("next_squad",0));state.next_squad=slot+1
			var key=("blue" if team==0 else "red")+"-"+str(slot)
			best={"id":key,"slot":slot,"members":[],"epochs":{},"cohort":cohort,"formed_at":now,"task":"","source":"fallback","issued_at":-100.0,"revision":0,"route":int(u.get("cohort_route",0)),"goal":Vector2(u.position),"confidence":0.0}
			groups[key]=best
		best.members.append(u.id);best.epochs[u.id]=int(u.get("spawn_epoch",0));u.squad_id=best.id
	for q in groups.values():
		for id in q.members:units[id].squad_id=q.id

static func anchor(q: Dictionary,units: Array) -> Vector2:
	var best=Vector2.ZERO;var score=INF
	for id in q.members:
		var at: Vector2=units[id].position;var cost=0.0
		for other in q.members:cost+=at.distance_squared_to(units[other].position)
		if cost<score:score=cost;best=at
	return best

static func cohort(ordinal: int) -> int:return int(ordinal/3)
