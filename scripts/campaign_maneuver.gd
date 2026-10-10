extends RefCounted
## Value-only coordinator: candidates come from budgeted physical stance/cover checks.
const DEPLOY_TIMEOUT=3.0
const MOVE_TIMEOUT=5.0
const ARRIVAL=.5

static func usable(u: Dictionary) -> bool:
	return u.get("alive",false) and not u.get("player",false) and int(u.get("mounted",-1))<0 and float(u.get("ai_stress",0))<.62

static func fire_ready(u: Dictionary,now: float) -> bool:
	return usable(u) and bool(u.get("ai_support_capable",true)) and int(u.get("ammo",0))>0 and float(u.get("reload",0))<=0 and bool(u.get("ai_support_ready",false)) and now-float(u.get("ai_support_checked_at",-100))<.85 and not contact(u,now).is_empty()

static func contact(u: Dictionary,now: float) -> Dictionary:
	var report: Dictionary=u.get("ai_contacts",{}).get(int(u.get("ai_target",-1)),{})
	return report if report.get("source","")=="vision" and now-float(report.get("observed_at",-100))<1.3 and float(report.get("confidence",0))>=.4 else {}

static func arrived(u: Dictionary,goal: Vector2) -> bool:
	return bool(u.get("grounded",true)) and Vector2(u.position).distance_squared_to(goal)<=ARRIVAL*ARRIVAL

static func advance(previous: Dictionary,members: Array,now: float) -> Dictionary:
	var state=previous.duplicate(true);var phase=str(state.get("phase","idle"));var by_id={}
	for u in members:by_id[int(u.id)]=u
	if phase=="recover":
		if now<float(state.get("until",0)):return state
		phase="idle";state.phase=phase
	if phase=="idle":
		if now<float(state.get("next_at",0)) or members.size()<2:return state
		var best: Dictionary={};var score=-INF
		for u in members:
			if not usable(u) or not u.get("ai_support_capable",true) or int(u.get("ammo",0))<=0 or float(u.get("reload",0))>0 or contact(u,now).is_empty():continue
			var near=false
			for other in members:
				if other.id!=u.id and usable(other) and Vector2(u.position).distance_squared_to(other.position)<49:near=true;break
			if not near:continue
			var value=(2.0 if u.get("class_id","")=="support" else 0.0)+(1.0 if now-float(u.get("ai_last_shot_at",-100))<1.15 else 0.0)
			if int(state.get("last_cover_id",-1))==u.id:value-=2.0
			if value>score:best=u;score=value
		if best.is_empty():return state
		return {"phase":"deploy","cover_id":int(best.id),"cover_epoch":int(best.get("spawn_epoch",0)),"at":now,"goals":{},"last_cover_id":state.get("last_cover_id",-1),"threat":Vector2(contact(best,now).position),"effect":"unconfirmed"}
	var cover: Dictionary=by_id.get(int(state.get("cover_id",-1)),{})
	if cover.is_empty() or not usable(cover) or int(cover.get("spawn_epoch",0))!=int(state.get("cover_epoch",0)):
		return recover(state,now,"support-lost")
	if phase=="deploy":
		if now-float(state.at)>DEPLOY_TIMEOUT:return recover(state,now,"deployment-timeout")
		if not fire_ready(cover,now):return state
		# A shot is active cover, not proof that the opponent has been suppressed.
		if now-float(cover.get("ai_last_shot_at",-100))>1.15:return state
		var goals={}
		for u in members:
			if u.id==cover.id or not usable(u) or Vector2(u.position).distance_squared_to(cover.position)>49:continue
			var goal: Vector2=u.get("ai_bound_candidate",Vector2.INF)
			if not goal.is_finite() or now-float(u.get("ai_bound_candidate_at",-100))>1.2:continue
			var protected=bool(u.get("ai_bound_protected",false))
			var limit=5.0 if protected else 3.0
			if Vector2(u.position).distance_to(goal)>.65 and Vector2(u.position).distance_to(goal)<=limit:goals[u.id]=goal
		if goals.is_empty():return state
		state.goals=goals;state.phase="bound";state.at=now
		state.effect="observed-hit" if now-float(cover.get("ai_effect_at",-100))<1.3 and Vector2(cover.get("ai_effect_position",Vector2.INF)).distance_to(state.threat)<3 else "cover-active"
		return state
	if phase in ["bound","handoff"]:
		if now-float(state.at)>MOVE_TIMEOUT:return recover(state,now,"movement-timeout")
		if not fire_ready(cover,now):return recover(state,now,"support-not-ready")
		var all_arrived=true;var next: Dictionary={}
		for id in state.goals.keys():
			var u: Dictionary=by_id.get(int(id),{})
			if u.is_empty() or not usable(u):state.goals.erase(id);continue
			if now-float(u.get("ai_incoming_at",-100))<.45 and float(u.get("ai_stress",0))>.62:return recover(state,now,"incoming-fire")
			if not arrived(u,state.goals[id]):all_arrived=false
			elif fire_ready(u,now) and not contact(u,now).is_empty():next=u
		if state.goals.is_empty():return recover(state,now,"movers-lost")
		if phase=="bound" and all_arrived and not next.is_empty():
			state.phase="handoff";state.at=now;state.previous_cover=int(cover.id)
			var offset=(Vector2(next.position)-Vector2(cover.position)).normalized().orthogonal()*.9
			state.cover_id=int(next.id);state.cover_epoch=int(next.get("spawn_epoch",0));state.goals={cover.id:Vector2(next.position)+offset}
			state.last_cover_id=int(cover.id)
		elif phase=="handoff" and all_arrived:
			return {"phase":"idle","next_at":now+.8,"last_cover_id":int(cover.id),"reason":"arrival-and-handoff-complete"}
	return state

static func recover(state: Dictionary,now: float,reason: String) -> Dictionary:
	return {"phase":"recover","until":now+.65,"next_at":now+1.0,"last_cover_id":int(state.get("cover_id",-1)),"reason":reason}
