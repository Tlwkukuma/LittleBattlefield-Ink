extends RefCounted
## Explicit user-requested restoration; ordinary gunshots keep the free palette.
const Original=preload("res://scripts/source_weapon_audio.gd")
const SOUNDS=["rocket","rocketLauncher","grenadeLauncher","grenadeLauncherAuto","mortar","fieldGun","tankCannon","heavyCannon","autocannon","vehicleCanister","vehicleGrenade","vehicleMortar"]
const FILES={"blast":"Explosion","restored_ordnance/rocket":"rocket","restored_ordnance/grenade_launcher":"grenade_launcher","restored_ordnance/cannon_shot":"cannon_shot","restored_ordnance/macrophage_shot":"macrophage_shot","restored_ordnance/shotgun":"shotgun"}
static var profiles: Dictionary={}

static func applies(weapon: Dictionary) -> bool:
	return str(weapon.get("sound","")) in SOUNDS

static func profile(weapon: Dictionary) -> Dictionary:
	var key=str(weapon.get("sound",""))
	if not profiles.has(key):
		var result: Dictionary=Original.profile(weapon).duplicate()
		result.sample="restored_ordnance/"+str(result.sample)
		result.near_samples=[result.sample];result.mid_samples=[result.sample]
		result.restored_ordnance=true;profiles[key]=result
	return profiles[key]

static func streams() -> Dictionary:
	var result: Dictionary={}
	for key in FILES:result[key]=load("res://assets/audio/restored-ordnance/"+FILES[key]+".wav") as AudioStreamWAV
	return result
