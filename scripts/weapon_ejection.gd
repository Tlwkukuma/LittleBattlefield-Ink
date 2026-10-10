extends RefCounted
## Pure presentation scheduling. One shell per discharged cartridge, not per pellet.
static func shot(w: Dictionary,retained: int) -> Dictionary:
	var m: Dictionary=w.get("mechanics",{});var action=str(m.get("action","auto"))
	if w.kind not in ["bullet","hitscan","autocannon","canister"] or action=="none":return {"retained":retained,"count":0,"delay":0.0}
	if action in ["break","cylinder"]:return {"retained":retained+1,"count":0,"delay":0.0}
	var count=1
	if str(w.get("id",""))=="dbs":
		if retained+1<2:return {"retained":retained+1,"count":0,"delay":0.0}
		count=retained+1
	var delay=0.0
	if action in ["pump","manualBolt","lever"]:
		delay=minf(60.0/maxf(1,float(w.rpm))*.72,maxf(.16,float(m.get("cycleDuration",m.get("duration",.35)))*.32))
	return {"retained":0,"count":count,"delay":delay}

static func reload_cases(w: Dictionary,retained: int) -> int:
	var action=str(w.get("mechanics",{}).get("action",""))
	return retained if action in ["break","cylinder"] or str(w.get("id",""))=="dbs" else 0
