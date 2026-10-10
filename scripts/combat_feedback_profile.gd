extends RefCounted
const Weapon=preload("res://scripts/weapon_profile.gd")
static var cache: Dictionary={}
static func profile(w: Dictionary) -> Dictionary:
	var key=str(w.get("mounted_fire_key",w.get("id",w.get("label",w.get("kind","bullet")))))
	if cache.has(key):return cache[key]
	var wp=Weapon.get_profile(w);var family=str(wp.family);var caliber=str(wp.flight_identity)
	var p={"power":1.0,"recover":.18,"shoulder":.022,"stroke":.022,"settle":.12,"body":0.0,"camera":0.0}
	match family:
		"pistol":p.power=.7;p.recover=.12;p.shoulder=.012
		"smg":p.power=.65;p.recover=.10;p.shoulder=.011
		"heavy":p.power=1.15;p.recover=.19;p.shoulder=.027
		"sniper":p.power=1.65;p.recover=.32;p.shoulder=.05
		"shotgun":p.power=1.50;p.recover=.29;p.shoulder=.043
	if wp.ammo_visual.key=="762":p.power*=1.12
	if caliber=="127":p.power=1.45;p.stroke=.035;p.settle=.17;p.shoulder=.035
	elif caliber in ["20","25"]:
		p.power=1.7 if caliber=="20" else 1.95;p.stroke=.065 if caliber=="20" else .085;p.settle=.20 if caliber=="20" else .25;p.body=.002
	elif w.kind in ["shell","canister"]:
		p.power={"45":1.7,"75":2.1,"88":2.5}.get(caliber,2.0);
		p.stroke={"45":.17,"75":.25,"88":.32}.get(caliber,.27);p.settle={"45":.36,"75":.48,"88":.61}.get(caliber,.52)
		p.body=.012 if caliber=="45" else .019 if caliber=="75" else .024;p.camera=.8 if caliber=="45" else 1.2 if caliber=="75" else 1.6
	elif w.kind in ["grenadeProjectile","vehicleGrenade"]:p.power=1.2;p.stroke=.045;p.settle=.22
	elif w.kind=="rocket":p.power=1.7
	elif w.kind in ["mortar","vehicleMortar"]:p.power=1.5;p.stroke=.035;p.settle=.23
	if w.has("mounted_fire_key") and w.kind=="bullet":
		p.stroke=.012 if caliber=="127" else .008;p.settle=.085;p.shoulder*=.35
	cache[key]=p;return p
static func pulse(age: float,rise: float,settle: float) -> float:
	if age<0 or age>=settle:return 0.0
	if age<rise:return sin(age/rise*PI*.5)
	return 1.0-smoothstep(rise,settle,age)
static func material(raw: String) -> String:
	if raw in ["unit","flesh"]:return "flesh"
	if "metal" in raw or raw in ["vehicle","wreck"]:return "metal"
	if "wood" in raw or "tree" in raw:return "wood"
	if "glass" in raw:return "glass"
	if raw in ["ground","terrain","earth","sand","snow"]:return "earth"
	return "stone"
