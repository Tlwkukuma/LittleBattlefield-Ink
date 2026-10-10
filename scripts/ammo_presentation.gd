extends RefCounted
const CaseSizes=preload("res://scripts/spent_case_sizes.gd")
## Readable orthographic presentation, separate from damage, collision and ammo counts.
static var cache: Dictionary={}
const FALLBACK={"ak-47":"7.62","galil-ar":"5.56","m4a4":"5.56","m4a1-s":"5.56","sg-553":"5.56",
	"awp":".300","ssg-08":"7.62","g3sg1":"7.62","scar-20":"7.62","mac-10":".45","mp7":"4.6",
	"mp5-sd":"9mm","ump-45":".45","pp-bizon":"9mm","glock-18":"9mm","p2000":"9mm","usp-s":".45",
	"p250":"9mm","five-seven":"5.7","tec-9":"9mm","cz75-auto":"9mm","dual-berettas":"9mm","r8-revolver":".357"}

static func profile(w: Dictionary) -> Dictionary:
	var id=str(w.get("mounted_fire_key",w.get("id",w.get("kind","bullet"))))
	if cache.has(id):return cache[id]
	var ammo=str(w.get("ammunition",FALLBACK.get(id,"5.56")));var family=str(w.get("archetype",""));var kind=str(w.kind)
	var a={"key":"556","label":"小口径步枪弹","case_shape":"bottleneck","case_size":Vector3(.050,.050,.19),
		"case_color":Color("c79a49"),"rim_color":Color("efd18a"),"round_shape":"pointed","round_color":Color("e4a453"),
		"tip_color":Color("fff3c9"),"round_ratio":Vector2(1,1),"aspect":2.4,"pixels":4.8,"case_pixels":4.2}
	if ammo.contains("9mm") or ammo.contains(".45") or ammo.contains(".357"):
		a.key="45" if ammo.contains(".45") else "9";a.label="粗短手枪弹" if a.key=="45" else "手枪 / 冲锋枪弹"
		a.case_shape="straight";a.case_size=Vector3(.059,.059,.119) if a.key=="45" else Vector3(.046,.046,.112)
		a.round_shape="roundnose";a.round_color=Color("e9b168");a.tip_color=Color("fff0be");a.pixels=4.6;a.aspect=1.6
		if a.key=="45":a.pixels=4.9;a.case_pixels=4.6
		# VSS uses its existing 9 mm gameplay ammo, but a long suppressed-rifle cartridge silhouette.
		if id=="vss":a.key="vss";a.case_shape="bottleneck";a.case_size=Vector3(.058,.058,.19);a.round_shape="pointed";a.round_color=Color("bcc8be")
	elif ammo.contains("5.7") or ammo.contains("4.6"):
		a.key="pdw";a.label="细长 PDW 弹";a.case_size=Vector3(.041,.041,.14);a.round_color=Color("ebc97c");a.pixels=4.3;a.case_pixels=3.8;a.aspect=2.5
	elif ammo.contains("7.62"):
		a.key="762";a.label="大口径步枪弹";a.case_size=Vector3(.063,.063,.235);a.case_color=Color("b39051");a.round_color=Color("df9c61");a.pixels=5.2;a.case_pixels=4.8;a.aspect=3.0
	elif ammo.contains(".300"):
		a.key="magnum";a.label="马格南长弹";a.case_size=Vector3(.072,.072,.29);a.round_color=Color("e7bd75");a.tip_color=Color("fff5d8");a.pixels=5.8;a.case_pixels=5.2;a.aspect=3.5
	elif ammo.contains(".50") or family=="antimaterial":
		a.key="50";a.label="反器材重弹";a.case_size=Vector3(.10,.10,.37);a.round_color=Color("c9bda5");a.tip_color=Color("fff4d5");a.pixels=6.3;a.case_pixels=5.8;a.aspect=3.8
	if family in ["shotgun","autoShotgun"] or ammo.contains("Gauge"):
		var slug=int(w.get("pellets",1))==1
		a.key="slug" if slug else "buckshot";a.label="独头弹 / 绿色霰弹壳" if slug else "霰弹丸簇 / 红色霰弹壳"
		a.case_shape="shell";a.case_size=Vector3(.084,.084,.205);a.case_color=Color("547563") if slug else Color("ae4b3b")
		a.rim_color=Color("e2b969");a.round_shape="slug" if slug else "pellet";a.round_ratio=Vector2(.85,.78) if slug else Vector2(.38,.17)
		a.round_color=Color("b9b7a8") if slug else Color("a7b4bd");a.tip_color=Color("fff0c8") if slug else Color("f8edd0")
		a.pixels=5.0 if slug else 3.1;a.case_pixels=5.0;a.aspect=1.85 if slug else 1.12
	if kind in ["autocannon","canister","shell"]:
		a.key="cannon/"+kind;a.case_shape="bottleneck";a.case_size=Vector3(.105,.105,.36);a.round_color=Color("b8a279");a.pixels=6.3;a.aspect=3.3
		if kind=="shell":a.round_shape="shell";a.round_color=Color("858973");a.tip_color=Color("d6bd85");a.aspect=3.1;a.pixels=7.0
	if kind not in ["bullet","hitscan","autocannon","canister","shell"]:a.case_shape="none"
	# Empty cases have their own weight and sound; these are project tuning values.
	a.bounce=.25;a.ground_drag=.52;a.spin_drag=.42;a.sound_pitch=1.0
	a.eject_speed=Vector2(1.5,2.25);a.eject_lift=Vector2(1.5,2.15);a.spin=7.0
	if a.case_shape=="straight":a.bounce=.32;a.sound_pitch=1.20;a.spin=9.0
	if a.key in ["magnum","50"]:a.bounce=.21;a.sound_pitch=.80;a.eject_speed=Vector2(1.05,1.65);a.spin=5.5
	if a.case_shape=="shell":a.bounce=.18;a.ground_drag=.39;a.sound_pitch=.71;a.eject_speed=Vector2(1.2,1.8);a.eject_lift=Vector2(1.15,1.7);a.spin=6.0
	CaseSizes.apply(a,id,family,ammo)
	cache[id]=a;return a

static func case_scale(a: Dictionary,pixel: float) -> Vector3:
	var size: Vector3=a.case_size
	# Uniform scale preserves short pistol vs long rifle vs broad shell proportions.
	if size.x<=0:return Vector3.ZERO
	return size*clampf(pixel*float(a.case_pixels)/size.x,1.0,float(a.get("case_max_scale",1.6)))

static func round_dimensions(a: Dictionary,pixel: float) -> Vector2:
	var size: Vector3=a.get("round_size",a.case_size);var ratio: Vector2=a.round_ratio
	var diameter=maxf(size.x*ratio.x,pixel*float(a.pixels))
	var length=diameter*float(a.get("aspect",(size.z*ratio.y)/(size.x*ratio.x)))
	return Vector2(diameter*.5,length)
