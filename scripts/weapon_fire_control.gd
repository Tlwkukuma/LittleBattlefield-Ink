extends RefCounted
## Trigger and ammunition state only; never creates projectiles or presentation nodes.
## PUBG-style mode sets; non-PUBG equipment uses explicit project analogues.
const MODES={
	"m16a4":["single","burst3"],"mk47-mutant":["single","burst2"],
	"m416":["single","auto"],"scar-l":["single","auto"],"g36c":["single","auto"],"qbz":["single","auto"],
	"k2":["single","burst3","auto"],"aug":["single","auto"],"famas":["single","burst3","auto"],
	"akm":["single","auto"],"beryl-m762":["single","burst3","auto"],"groza":["single","auto"],"ace32":["single","auto"],
	"mini14":["single"],"mk12":["single"],"sks":["single"],"slr":["single"],"dragunov":["single"],
	"mk14":["single","auto"],"vss":["single","auto"],
	"tommy-gun":["single","auto"],"ump":["single","burst3","auto"],"micro-uzi":["single","auto"],
	"vector":["single","burst3","auto"],"mp5k":["single","burst3","auto"],"mp9":["single","auto"],"p90":["single","auto"],"js9":["single","auto"],
	"kar98k":["single"],"m24":["single"],"awm":["single"],"win94":["single"],"lynx-amr":["single"],
	"s12k":["single"],"s1897":["single"],"s686":["single"],"dbs":["single"],"sawed-off":["single"],"o12":["single","burst3","auto"],
	"p18c":["single","auto"],"p92":["single"],"skorpion":["single","auto"],"deagle":["single"],"r1895":["single"],
	"m249":["auto"],"mg3":["auto660","auto990"],"rpd":["auto"],
	"ak-47":["single","auto"],"galil-ar":["single","auto"],"m4a4":["single","auto"],"m4a1-s":["single","auto"],"sg-553":["single","auto"],
	"awp":["single"],"ssg-08":["single"],"g3sg1":["single"],"scar-20":["single"],
	"mac-10":["single","auto"],"mp7":["single","auto"],"mp5-sd":["single","burst3","auto"],"ump-45":["single","burst3","auto"],"pp-bizon":["single","auto"],
	"nova":["single"],"xm1014":["single"],"mag-7":["single"],"negev":["auto"],
	"glock-18":["single","burst3"],"p2000":["single"],"usp-s":["single"],"p250":["single"],"five-seven":["single"],"tec-9":["single"],
	"cz75-auto":["single","auto"],"dual-berettas":["single"],"r8-revolver":["single"],
	"army-knife":["single"],"fire-axe":["single"],"katana":["single"],"minigun":["auto"],
	"anti-tank-launcher":["single"],"rpg":["single"],"grenade-launcher":["single"],"he-grenade":["single"],"smoke-grenade":["single"],"portable-mortar":["single"]}

const MOUNTED_MODES={
	"armedJeep/mg":["auto"],
	"scoutCar/autocannon":["auto"],"scoutCar/mg":["auto"],
	"apc/mg":["auto"],"apc/grenade":["single"],
	"ifv/autocannon":["auto"],"ifv/grenade":["auto"],
	"lightTank/mg":["auto"],"lightTank/cannon":["single"],
	"tank/cannon":["single"],"tank/mg":["auto"],"tank/mortar":["single"],
	"heavyTank/cannon":["single"],"heavyTank/mg":["auto"],"heavyTank/canister":["single"],
	"hmg/primary":["auto"],"fieldGun/primary":["single"],"portableMortar/primary":["single"]}

static func bind_mounted(data: Dictionary) -> void:
	# The imported vehicle catalog has neither handheld IDs nor automatic flags.
	# Bind once at catalog load so trigger logic, HUD and equipment UI share modes.
	for kind in data.vehicles:
		for slot in data.vehicles[kind].weapons:
			bind_mounted_weapon(data.vehicles[kind].weapons[slot],str(kind)+"/"+str(slot))
	for kind in data.emplacements:bind_mounted_weapon(data.emplacements[kind],str(kind)+"/primary")

static func bind_mounted_weapon(w: Dictionary,key: String) -> void:
	w.mounted_fire_key=key
	if not MOUNTED_MODES.has(key):push_error("Missing mounted fire-mode configuration: "+key)

static func modes(w: Dictionary) -> Array:
	if w.has("mounted_fire_key"):return MOUNTED_MODES.get(str(w.mounted_fire_key),["single"])
	var id=str(w.get("id",""))
	if MODES.has(id):return MODES[id]
	# Legacy fallback only; registered mounted weapons always use the explicit table.
	return ["auto"] if bool(w.get("automatic",false)) else ["single"]

static func default_mode(w: Dictionary) -> String:
	var id=str(w.get("id",""));var options=modes(w)
	if id in ["mk14","vss","glock-18"]:return "single"
	if id=="mg3":return "auto660"
	return str(options.back())

static func selected(state: Dictionary,w: Dictionary) -> String:
	var value=str(state.get("fire_mode",""))
	return value if value in modes(w) else default_mode(w)

static func reset(state: Dictionary,w: Dictionary) -> void:
	state.fire_mode=selected(state,w);state.fire_pending=0;state.fire_continuous=false;state.fire_lock=false

static func cancel(state: Dictionary,require_release: bool=false) -> void:
	state.fire_pending=0;state.fire_continuous=false
	state.cooldown=maxf(0,float(state.get("cooldown",0)))
	if require_release:state.fire_lock=true

static func cycle(state: Dictionary,w: Dictionary) -> bool:
	var options=modes(w)
	if options.size()<2:return false
	state.fire_mode=options[(options.find(selected(state,w))+1)%options.size()]
	cancel(state,true)
	return true

static func rpm(w: Dictionary,state: Dictionary) -> float:
	var mode=selected(state,w)
	if mode=="auto660":return 660.0
	if mode=="auto990":return 990.0
	return maxf(1,float(w.get("rpm",600)))

static func mode_label(w: Dictionary,mode: String) -> String:
	if mode=="single":
		if w.kind=="melee":return "挥击"
		if w.kind=="grenade":return "单次投掷"
		var action=str(w.get("mechanics",{}).get("action",""))
		if action=="manualBolt":return "单发·栓动"
		if action=="pump":return "单发·泵动"
		if action=="lever":return "单发·杠杆"
		if action in ["break","cylinder"]:return "单发"
		return "单发·半自动" if w.kind in ["bullet","hitscan"] else "单发"
	return {"burst2":"二连发","burst3":"三连发","auto":"全自动","auto660":"全自动 660","auto990":"全自动 990"}.get(mode,mode)

static func label(state: Dictionary,w: Dictionary) -> String:return mode_label(w,selected(state,w))
static func options_label(w: Dictionary) -> String:
	var labels: PackedStringArray=[]
	for mode in modes(w):labels.append(mode_label(w,mode))
	return " / ".join(labels)

static func tick_clock(state: Dictionary,delta: float) -> void:
	# Carry only one tick of overshoot during an active sequence. Avoid RPM quantization
	# (e.g. 800 RPM becoming 720 at 60 Hz) and never bank idle time for a later volley.
	var floor_time=-delta if state.get("fire_continuous",false) else 0.0
	state.cooldown=maxf(floor_time,float(state.get("cooldown",0))-delta)

static func wants_shot(state: Dictionary,w: Dictionary,held: bool,pressed: bool,allowed: bool=true) -> bool:
	if not held and not pressed:state.fire_lock=false
	if not allowed:
		cancel(state,true);return false
	if state.get("fire_lock",false):return false
	if float(state.get("reload",0))>0 or (int(state.get("ammo",0))<=0 and w.kind!="melee"):
		cancel(state);return false
	var mode=selected(state,w);var automatic=mode.begins_with("auto")
	if not automatic and pressed and int(state.get("fire_pending",0))==0 and float(state.cooldown)<=0:
		state.fire_pending=2 if mode=="burst2" else 3 if mode=="burst3" else 1
	var requested=(held or pressed) if automatic else int(state.get("fire_pending",0))>0
	if not requested:
		cancel(state);return false
	return float(state.cooldown)<=0

static func committed(state: Dictionary,w: Dictionary) -> void:
	var continued=bool(state.get("fire_continuous",false))
	state.fire_pending=maxi(0,int(state.get("fire_pending",0))-1)
	state.cooldown=(minf(0,float(state.cooldown)) if continued else 0.0)+60.0/rpm(w,state)
	state.fire_continuous=selected(state,w).begins_with("auto") or state.fire_pending>0

static func begin_reload(state: Dictionary,w: Dictionary) -> bool:
	if w.kind=="melee" or float(state.reload)>0 or int(state.ammo)>=int(w.mag) or int(state.reserve)<=0:return false
	cancel(state)
	state.reload_duration=maxf(.05,maxf(float(w.reload),float(state.cooldown)))
	state.reload=state.reload_duration
	return true

static func finish_reload(state: Dictionary,w: Dictionary) -> void:
	var amount=mini(maxi(0,int(w.mag)-int(state.ammo)),maxi(0,int(state.reserve)))
	state.ammo+=amount;state.reserve-=amount
	cancel(state)

static func needs_reload(state: Dictionary,w: Dictionary) -> bool:
	return w.kind!="melee" and int(state.ammo)<=0 and int(state.reserve)>0 and float(state.reload)<=0
