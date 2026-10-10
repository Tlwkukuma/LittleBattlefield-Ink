extends RefCounted
## Area fire into a recently observed sector; no target-body or world query.
const MEMORY=1.8
const YAW_CONE=.40
const PITCH_CONE=.22
static func machinegun(weapon: Dictionary) -> bool:
	var mounted=str(weapon.get("mounted_fire_key",""))
	return mounted.ends_with("/mg") or mounted=="hmg/primary" or (mounted.is_empty() and weapon.get("archetype","") in ["lmg","hmg","minigun"])

static func known(contact: Dictionary,now: float) -> bool:
	var age=now-float(contact.get("observed_at",contact.get("at",-100)))
	return contact.get("source","")=="vision" and age>=0 and age<=MEMORY and float(contact.get("confidence",1.0))>=.24

static func in_sector(yaw_error: float,pitch_error: float=0.0) -> bool:
	return absf(wrapf(yaw_error,-PI,PI))<=YAW_CONE and absf(pitch_error)<=PITCH_CONE

static func burst(now: float,slot: int) -> bool:
	return fmod(now+float(slot)*.37,1.20)<.90
