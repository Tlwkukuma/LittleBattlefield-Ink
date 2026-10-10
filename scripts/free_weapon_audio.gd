extends RefCounted
## Free firearm palette, with explicit user-requested ordnance restoration.
const Original=preload("res://scripts/source_weapon_audio.gd")
const Ordnance=preload("res://scripts/ordnance_audio.gd")
static var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/free-weapon-audio.json"))
static var profiles: Dictionary={}

static func profile(weapon: Dictionary) -> Dictionary:
	if Ordnance.applies(weapon):return Ordnance.profile(weapon)
	var original: Dictionary=Original.profile(weapon)
	var id=str(weapon.get("id",""))
	var mounted=str(weapon.get("mounted_fire_key",""))
	var bank_id=str(data.mounted.get(mounted,"")) if not mounted.is_empty() else str(data.weapons.get(id,""))
	# Future/unregistered items also use the free palette; never restore legacy WAVs.
	if bank_id.is_empty():bank_id=str(data.defaults.get(str(weapon.get("kind","bullet")),"ar15"))
	var key=bank_id+"/"+str(original.group)
	if not profiles.has(key):
		var bank: Dictionary=data.banks[bank_id];var result: Dictionary={"group":original.group}
		result.sample=bank.near[0];result.near_samples=bank.near;result.mid_samples=bank.mid
		result.gain=bank.gain;result.lowpass=bank.lowpass;result.recording_bank=bank_id
		profiles[key]=result
	return profiles[key]

static func samples(profile_data: Dictionary,distance: float,local: bool) -> Array:
	return profile_data.near_samples if local or distance<12.0 else profile_data.mid_samples
