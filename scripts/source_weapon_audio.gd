extends RefCounted
## Source audio.js profiles, never inferred from visual caliber/recoil.
static var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/source-weapon-audio.json"))

static func profile(w: Dictionary) -> Dictionary:
	var key=str(w.get("sound","rifle"));key=str(data.aliases.get(key,key))
	return data.profiles.get(key,data.profiles.assaultRifle)

static func spatial_range(w: Dictionary) -> Vector2:
	# x = audible radius in meters; y = source call-site volume multiplier.
	var mounted=str(w.get("mounted_fire_key",""));var kind=str(w.get("kind","bullet"))
	if not mounted.is_empty():
		if mounted=="portableMortar/primary":return Vector2(1420*1.12/40.0,1)
		if mounted.begins_with("hmg/"):return Vector2(1750/40.0,1)
		if mounted.begins_with("fieldGun/"):return Vector2(2600/40.0,1)
		match kind:
			"vehicleMortar":return Vector2(2600/40.0,1.12)
			"canister":return Vector2(2350/40.0,1.24)
			"shell":return Vector2(3050/40.0,1.32)
			"vehicleGrenade":return Vector2(2250/40.0,1.08)
			"autocannon":return Vector2(2150/40.0,1.16)
		return Vector2(1850/40.0,1)
	var radius=1250.0
	match str(w.get("archetype","assault")):
		"sniper","antimaterial":radius=2050
		"rocket","grenadeLauncher":radius=1750
		"lmg","hmg","minigun":radius=1500
		"shotgun","autoShotgun":radius=1280
		"pistol","machinePistol":radius=820
		"smg":radius=980
		"flame":radius=460
	if kind=="mortar":radius=1420
	elif kind=="tesla":radius=760
	return Vector2(radius*1.12/40.0,1)
