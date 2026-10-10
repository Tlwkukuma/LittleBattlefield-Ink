extends RefCounted
## Project readability and gameplay speeds, not real-world ballistic measurements.
const MOUNTED={
	"armedJeep/mg":"127","scoutCar/mg":"762","apc/mg":"127",
	"lightTank/mg":"762","tank/mg":"762","heavyTank/mg":"762","hmg/primary":"127",
	"scoutCar/autocannon":"20","ifv/autocannon":"25",
	"apc/grenade":"40","ifv/grenade":"40_auto","lightTank/cannon":"45",
	"tank/cannon":"75","heavyTank/cannon":"88","tank/mortar":"mortar_heavy",
	"heavyTank/canister":"canister","fieldGun/primary":"field"}
const HANDHELD={"grenade-launcher":"40","rpg":"rpg","anti-tank-launcher":"rocket_fast","portable-mortar":"mortar"}
# speed m/s, visible radius / length m, light-trace width / length px, trace color,
# projectile body / nose / band. Same caliber shares one appearance across teams.
const SPECS={
	"556":[64,.014,.14,3.4,15,"eee2a7","a6a27a","e9e1ba","ae905b"],
	"762":[58,.019,.20,4.6,20,"efb45c","ad955d","ecd19a","946445"],
	"127":[72,.028,.29,6.4,25,"f08248","8c806b","eddac0","9d6848"],
	"20":[96,.037,.27,7.5,27,"efcd68","ad9559","ead49e","685f43"],
	"25":[88,.046,.32,9.0,30,"ed7849","926551","edb98b","dac077"],
	"40":[14,.061,.19,0,0,"e3bc72","769578","d4dcd1","ddbc64"],
	"40_auto":[18,.061,.19,0,0,"e3bc72","769578","d4dcd1","ddbc64"],
	"45":[62,.074,.34,0,0,"c3dedc","789c9b","d9e7de","bca16d"],
	"75":[74,.104,.46,0,0,"d4b875","b09660","e5d4a1","64694e"],
	"88":[86,.126,.57,0,0,"c98b76","9e6354","debaa0","ddba6d"],
	"field":[54,.095,.43,0,0,"b9c5a3","7d8b66","d3d5bc","c7a368"],
	"mortar":[13,.080,.36,0,0,"b9c3c7","83909a","d3dbd8","c6b16f"],
	"mortar_heavy":[17,.106,.47,0,0,"b9c3c7","83909a","d3dbd8","c6b16f"],
	"rpg":[26,.094,.69,0,0,"9cb374","77914c","c8d0a8","b88952"],
	"rocket_fast":[38,.079,.76,0,0,"c7baa2","aa9873","d9dbcf","706b54"],
	"canister":[48,.013,.065,3.2,7,"bdccdb","929da6","d8e1e6","898c83"]}

static func apply(w: Dictionary,p: Dictionary) -> void:
	var key=str(MOUNTED.get(str(w.get("mounted_fire_key","")),HANDHELD.get(str(w.get("id","")),"")))
	var a: Dictionary=p.ammo_visual
	if key.is_empty() and str(w.get("archetype","")) in ["lmg","minigun"]:
		key="762" if a.key=="762" else "556"
	p.flight_identity=key;p.flight_pixels=4.0;p.flight_color=Color("e9ce90");p.flight_length=18.0
	# Ordinary firearms keep their existing ballistics; the color/width also track caliber.
	if a.key=="762":p.flight_pixels=4.6;p.flight_color=Color("efb45c");p.flight_length=20.0
	elif a.key in ["50","magnum"]:p.flight_pixels=6.0;p.flight_color=Color("c6dbe5");p.flight_length=27.0
	elif a.key in ["9","45","pdw","vss"]:p.flight_pixels=3.2;p.flight_color=Color("e5d6b3");p.flight_length=13.0
	elif a.key=="556":p.flight_pixels=3.4;p.flight_color=Color("eee2a7");p.flight_length=15.0
	if key.is_empty():return
	var s: Array=SPECS[key]
	p.speed=float(s[0]);p.radius=float(s[1]);p.length=float(s[2]);p.flight_pixels=float(s[3]);p.flight_length=float(s[4]);p.flight_color=Color(s[5])
	p.body_color=Color(s[6]);p.nose_color=Color(s[7]);p.band_color=Color(s[8])
	if key in ["mortar","mortar_heavy"]:p.mortar_speed=p.speed
