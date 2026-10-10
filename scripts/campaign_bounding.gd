extends RefCounted
## Squad-level fire-and-move window from observed fire, never hidden enemy state.
const SHOT_AGE=1.15
const REPORT_AGE=1.3
const WINDOW=2.4
const REPEAT_DELAY=.9

static func eligible(shooter: Dictionary,members: Array,objective: Dictionary,now: float) -> bool:
	if not shooter.get("alive",false) or shooter.get("player",false) or int(shooter.get("mounted",-1))>=0:return false
	if not shooter.get("ai_visible",false) or now-float(shooter.get("ai_last_shot_at",-100))>SHOT_AGE:return false
	if float(shooter.get("ai_stress",0))>.62:return false
	var target=int(shooter.get("ai_last_shot_target",-1))
	if target<0 or target!=int(shooter.get("ai_target",-2)):return false
	var report: Dictionary=shooter.get("ai_contacts",{}).get(target,{})
	if report.get("source","")!="vision" or now-float(report.get("observed_at",-100))>REPORT_AGE or float(report.get("confidence",0))<.4:return false
	var point: Vector2=objective.position
	if shooter.position.distance_to(point)<float(objective.radius)+5.0:return false
	for ally in members:
		if int(ally.id)==int(shooter.id) or not ally.get("alive",false) or ally.get("player",false) or int(ally.get("mounted",-1))>=0:continue
		if float(ally.get("ai_stress",0))>.62 or ally.position.distance_to(shooter.position)>7.0:continue
		if ally.position.distance_to(point)>float(objective.radius)+2.0:return true
	return false

static func choose(members: Array,objective: Dictionary,now: float,previous: Dictionary) -> Dictionary:
	var prior_id=int(previous.get("cover_id",-1))
	var last_id=int(previous.get("last_cover_id",prior_id))
	var candidates=[]
	for member in members:
		if eligible(member,members,objective,now):candidates.append(int(member.id))
	if prior_id in candidates and now<float(previous.get("until",0)):return previous
	var next_id=-1
	for id in candidates:
		if id!=last_id:next_id=id;break
	if next_id<0 and not candidates.is_empty() and now>=float(previous.get("next_at",0)):next_id=int(candidates[0])
	if next_id<0:return {"cover_id":-1,"last_cover_id":last_id,"until":0.0,"next_at":float(previous.get("next_at",0))}
	return {"cover_id":next_id,"last_cover_id":next_id,"until":now+WINDOW,"next_at":now+WINDOW+REPEAT_DELAY}
