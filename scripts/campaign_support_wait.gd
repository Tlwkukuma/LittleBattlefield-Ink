extends RefCounted
## Waiting requires real, relevant fire. Geometry permissions alone are not fire.
const WAIT_LIMIT=3.0
const RESUME_WINDOW=4.0
static func effective(unit: Dictionary,contact: Dictionary,now: float) -> bool:
	return contact.get("source","")=="vision" and now-float(contact.get("observed_at",-100))<1.3 and bool(unit.get("ai_fire_clear",false)) and bool(unit.get("ai_support_ray_clear",false)) and int(unit.get("ammo",0))>0 and float(unit.get("reload",0))<=0 and now-float(unit.get("ai_last_shot_at",-100))<1.15 and int(unit.get("ai_last_shot_target",-1))==int(contact.get("id",-2)) and int(unit.get("ai_last_shot_target_epoch",-1))==int(contact.get("spawn_epoch",0)) and int(unit.get("ai_last_shot_epoch",-1))==int(unit.get("spawn_epoch",0))
static func resume(unit: Dictionary,contact: Dictionary,waiting: bool,now: float) -> bool:
	var key=str(unit.get("spawn_epoch",0))+":"+str(unit.get("ai_order",{}).get("revision",0))+":"+str(unit.get("ai_task",""))
	if str(unit.get("ai_support_wait_key",""))!=key:
		unit.ai_support_wait_key=key;unit.ai_support_wait_since=now;unit.ai_support_resume_until=0.0
	if now<float(unit.get("ai_support_resume_until",0)):return true
	if not waiting or effective(unit,contact,now):unit.ai_support_wait_since=now;return false
	if now-float(unit.get("ai_support_wait_since",now))<WAIT_LIMIT:return false
	unit.ai_support_resume_until=now+RESUME_WINDOW;unit.ai_support_wait_since=now
	return true
