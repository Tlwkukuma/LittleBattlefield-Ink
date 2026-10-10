extends RefCounted
## Art dimensions for the game camera, not real cartridge measurements.
## Cases are selected by mount + weapon mode, independently of projectile visuals.
const Emplacement=preload("res://scripts/emplacement_profile.gd")
const CaseSizes=preload("res://scripts/spent_case_sizes.gd")
const TYPES={
	"armedJeep":{"mg":"127"},
	"scoutCar":{"autocannon":"20","mg":"762"},
	"apc":{"mg":"127","grenade":"40"},
	"ifv":{"autocannon":"25","grenade":"40"},
	"lightTank":{"mg":"762","cannon":"45"},
	"tank":{"cannon":"75","mg":"762","mortar":"none"},
	"heavyTank":{"cannon":"88","mg":"762","canister":"88"},
	"hmg":{"primary":"127"},"fieldGun":{"primary":"field"}}
const SPECS={
	"762":{"label":"7.62 同轴机枪弹壳","size":Vector3(.063,.063,.235),"shape":"bottleneck","color":"b39051","rim":"efd18a","pixels":4.8,"max_scale":1.7},
	"127":{"label":"重机枪长弹壳","size":Vector3(.10,.10,.37),"shape":"heavy_bottleneck","color":"a9854d","rim":"d7bd80","pixels":5.7,"max_scale":1.25},
	"20":{"label":"20 mm 机关炮弹壳","size":Vector3(.115,.115,.39),"shape":"autocannon","color":"969070","rim":"c6af79","pixels":6.0,"max_scale":1.2},
	"25":{"label":"25 mm 机关炮弹壳","size":Vector3(.13,.13,.44),"shape":"autocannon","color":"858b76","rim":"c7b88d","pixels":6.4,"max_scale":1.2},
	"40":{"label":"40 mm 榴弹短壳","size":Vector3(.15,.15,.20),"shape":"grenade_case","color":"a3a99e","rim":"cfba88","pixels":6.3,"max_scale":1.15},
	"45":{"label":"45 mm 炮壳","size":Vector3(.15,.15,.45),"shape":"artillery","color":"b18b54","rim":"d2b97e","pixels":6.4,"max_scale":1.15},
	"75":{"label":"75 mm 炮壳","size":Vector3(.20,.20,.59),"shape":"artillery","color":"a78a58","rim":"d4bd83","pixels":7.0,"max_scale":1.1},
	"88":{"label":"88 mm 炮壳","size":Vector3(.235,.235,.68),"shape":"artillery","color":"9d8151","rim":"d6bd84","pixels":7.5,"max_scale":1.1},
	"field":{"label":"野战炮退壳","size":Vector3(.16,.16,.48),"shape":"artillery","color":"ab8c56","rim":"d7bf87","pixels":6.6,"max_scale":1.15},
	"none":{"label":"无独立抛出弹壳","size":Vector3.ZERO,"shape":"none","color":"888888","rim":"888888","pixels":0.0,"max_scale":1.0}}
static var cache: Dictionary={}

static func profile(mount_type: String,mode: String) -> Dictionary:
	var caliber: String=TYPES.get(mount_type,{}).get(mode,"none")
	var key="mounted/"+caliber
	if cache.has(key):return cache[key]
	var s: Dictionary=SPECS[caliber]
	var heavy: bool=s.shape=="artillery"
	var size=CaseSizes.mounted_size(caliber,s.size)
	var a={"key":key,"label":s.label,"case_shape":s.shape,"case_size":size,"case_color":Color(s.color),"rim_color":Color(s.rim),
		"case_pixels":1.8*size.x/.028,"case_max_scale":1.6 if caliber in ["762","127"] else 1.10,"mounted":true,
		"eject_axis":Vector3.BACK if heavy else Vector3.RIGHT,"eject_speed":Vector2(.65,1.0) if heavy else Vector2(1.2,1.8),
		"eject_lift":Vector2(.12,.26) if heavy else Vector2(.8,1.35),"spin":1.8 if heavy else 4.0,
		"bounce":.12 if heavy else .19,"ground_drag":.34 if heavy else .42,"spin_drag":.24 if heavy else .30,
		"sound_pitch":.62 if heavy else .83,"life":30.0 if heavy else 24.0}
	if caliber=="762":a.eject_speed=Vector2(1.7,2.4);a.eject_lift=Vector2(1.5,2.1);a.spin=5.5;a.bounce=.25;a.sound_pitch=.95
	if caliber=="40":a.eject_speed=Vector2(.8,1.25);a.eject_lift=Vector2(.5,.9);a.spin=3.0;a.sound_pitch=.72
	cache[key]=a
	return a

static func schedule(mount_type: String,mode: String,external: bool) -> Dictionary:
	var a=profile(mount_type,mode)
	return {"count":1 if external and a.case_shape!="none" else 0,
		"delay":.065 if a.case_shape=="grenade_case" else .025,
		"reload_phase":Emplacement.CASE_EJECT_PHASE if mount_type=="fieldGun" else -1.0,"presentation":a}
