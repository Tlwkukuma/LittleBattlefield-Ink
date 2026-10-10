extends RefCounted
## Presentation dimensions are deliberately enlarged for the orthographic game camera.
## They describe visible projectiles, not real-world ammunition measurements.
const Ammo=preload("res://scripts/ammo_presentation.gd")
static var cache: Dictionary={}
static func get_profile(w: Dictionary) -> Dictionary:
	var key=str(w.get("mounted_fire_key",w.get("id",w.get("name",str(w.get("label",w.get("kind","bullet")))+"/"+str(w.get("projectileSpeed",0))))))
	if cache.has(key):return cache[key]
	var kind=str(w.get("kind","bullet"));var family=str(w.get("archetype",kind));var ammo=str(w.get("ammunition",""));var id=str(w.get("id",""))
	var p={"family":"rifle","radius":.014,"length":.14,"speed":float(w.get("projectileSpeed",w.get("speed",1770)))/40.0,"flash_length":.24,"flash_width":.075,"flash_time":.065,"recoil":.055,"kick":.035,"recover":.19,"offset":Vector3(0,-.025,0),"grip":Vector3(.025,-.085,.025),"support":Vector3(-.025,-.035,-.28),"color":Color("d6bd83"),"suppressed":false}
	if ammo.contains("7.62") or id in ["ak-47","g3sg1","scar-20"]:p.radius=.018;p.length=.19
	if bool(w.get("mechanics",{}).get("pistol",false)):
		p.family="pistol";p.radius=.015;p.length=.10;p.flash_length=.15;p.flash_width=.052;p.recoil=.045;p.kick=.075;p.offset=Vector3(-.025,-.04,-.10);p.grip=Vector3(.025,-.08,.01);p.support=Vector3(-.055,-.095,.035)
	elif family=="smg":p.family="smg";p.radius=.014;p.length=.11;p.flash_length=.19;p.recoil=.038;p.support=Vector3(-.025,-.045,-.19)
	elif family in ["sniper","antimaterial","battleRifle"]:
		p.family="sniper";p.radius=.021;p.length=.23;p.flash_length=.40;p.flash_width=.105;p.flash_time=.09;p.recoil=.11;p.kick=.055;p.recover=.34;p.offset=Vector3(-.025,.065,.065);p.support=Vector3(-.025,-.045,-.36)
		if kind=="hitscan":p.speed=105.0
		if ammo.contains(".300") or id=="awp":p.radius=.025;p.length=.28;p.speed=115.0
		if family=="antimaterial":p.radius=.034;p.length=.35;p.flash_length=.52;p.recoil=.15;p.kick=.085;p.recover=.44;p.speed=125.0
	elif family in ["shotgun","autoShotgun"]:
		p.family="shotgun";p.radius=.012 if int(w.get("pellets",1))>1 else .024;p.length=.07 if int(w.get("pellets",1))>1 else .16;p.flash_length=.35;p.flash_width=.14;p.recoil=.115;p.kick=.065;p.recover=.30
	elif family in ["lmg","minigun"]:
		p.family="heavy";p.radius=.019;p.length=.20;p.flash_length=.32;p.flash_width=.10;p.offset=Vector3(.035,-.10,.04);p.support=Vector3(-.04,-.07,-.34);p.recoil=.075
	if id=="minigun":
		p.grip=preload("res://scripts/minigun_visual.gd").GRIP;p.support=preload("res://scripts/minigun_visual.gd").SUPPORT
		p.offset=Vector3(.045,-.13,.04)
		p.flash_width=.035;p.flash_length=.22;p.flash_time=.026
	if kind=="rocket":
		p.family="launcher";p.radius=.082;p.length=.62;p.flash_length=.35;p.flash_width=.15;p.flash_time=.13;p.offset=Vector3(.12,.17,.10);p.grip=Vector3(.04,-.145,.02);p.support=Vector3(-.025,-.085,-.25);p.recoil=.055;p.kick=.018;p.recover=.45;p.color=Color("aaa183")
	elif kind in ["grenadeProjectile","vehicleGrenade"]:
		p.family="launcher_low";p.radius=.052;p.length=.17;p.flash_length=.24;p.flash_width=.12;p.recoil=.095;p.kick=.09;p.offset=Vector3(.03,-.065,.04)
	elif kind in ["shell","autocannon","canister"]:
		p.radius=.065 if kind=="shell" else .033;p.length=.36 if kind=="shell" else .23;p.flash_length=.65;p.flash_width=.20;p.flash_time=.12
	elif kind in ["mortar","vehicleMortar"]:
		p.family="mortar";p.radius=.07;p.length=.33;p.flash_length=.27;p.flash_width=.14;p.offset=Vector3(.03,-.22,-.03);p.grip=Vector3(.08,-.10,.06);p.support=Vector3(-.06,.04,-.12)
	elif kind in ["grenade","melee"]:p.family=kind;p.radius=.065;p.length=.12;p.flash_length=0;p.recoil=0;p.kick=0
	if kind=="rocket":p.grip=Vector3(.025,-.13,.035);p.support=Vector3(-.050,-.09,-.15)
	elif kind=="grenadeProjectile":p.grip=Vector3(0,-.10,.04);p.support=Vector3(-.015,-.065,-.21)
	elif kind=="mortar":p.grip=Vector3(.09,.48,-.25);p.support=Vector3(-.085,.42,-.22)
	if ammo.contains(".45") and p.family in ["pistol","smg"]:p.radius=.019;p.length=.12
	p.suppressed=id in ["vss","m4a1-s","mp5-sd","usp-s"]
	if p.suppressed:p.flash_length*=.30;p.flash_width*=.45;p.flash_time=.045
	p.ammo_visual=Ammo.profile(w)
	if p.family=="shotgun":
		p.flash_length=.24 if p.ammo_visual.round_shape=="pellet" else .32
		p.flash_width=.16 if p.ammo_visual.round_shape=="pellet" else .11
		p.flash_time=.050
	# Keep physical sweeps independent from the enlarged camera-readable caliber.
	p.collision_radius=p.radius
	preload("res://scripts/projectile_identity.gd").apply(w,p)
	cache[key]=p;return p
