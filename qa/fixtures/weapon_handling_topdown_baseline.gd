extends RefCounted
## Game-tuned angular handling, not measurements of the corresponding real weapons.
const Profile=preload("res://scripts/weapon_profile.gd")
const FireControl=preload("res://scripts/weapon_fire_control.gd")
static var profiles: Dictionary={}
# Pitch/yaw in degrees, recovery rate, first-shot multiplier.
const TUNING={
	"m416":[.64,.12,5.8,1.22],"m16a4":[.59,.10,6.0,1.18],"scar-l":[.76,.12,5.6,1.20],
	"aug":[.58,.10,6.1,1.18],"famas":[.55,.17,5.8,1.12],"g36c":[.62,.11,5.9,1.20],
	"akm":[1.02,.20,4.6,1.35],"ak-47":[1.04,.22,4.5,1.36],"beryl-m762":[1.10,.25,4.4,1.30],
	"ace32":[.88,.18,4.9,1.28],"groza":[.83,.19,5.0,1.23],"mk47-mutant":[.94,.14,5.1,1.30],
	"vector":[.28,.08,8.8,1.08],"micro-uzi":[.29,.13,8.0,1.06],"mp5k":[.32,.07,8.2,1.10],
	"ump":[.41,.08,7.5,1.15],"ump-45":[.44,.09,7.3,1.16],"p90":[.31,.08,8.3,1.10],
	"mini14":[1.05,.12,5.9,1.05],"mk12":[1.15,.12,5.7,1.08],"sks":[1.55,.18,4.8,1.12],
	"slr":[1.80,.21,4.3,1.15],"mk14":[1.62,.25,4.5,1.15],"vss":[.58,.10,6.5,1.10],
	"kar98k":[2.5,.18,3.8,1.0],"m24":[2.7,.16,3.6,1.0],"awm":[3.3,.22,3.2,1.0],
	"awp":[3.1,.20,3.3,1.0],"ssg-08":[1.9,.14,4.5,1.0],"lynx-amr":[4.1,.32,2.8,1.0],
	"m249":[.61,.19,5.1,1.28],"mg3":[.72,.27,4.5,1.30],"negev":[.66,.23,4.8,1.25],
	"deagle":[2.1,.20,4.5,1.0],"r1895":[1.8,.16,4.8,1.0],"r8-revolver":[2.2,.19,4.2,1.0]}

static func profile(w: Dictionary) -> Dictionary:
	var id=str(w.get("mounted_fire_key",w.get("id",w.get("name",w.get("label",w.kind)))))
	if profiles.has(id):return profiles[id]
	var family=str(Profile.get_profile(w).family);var archetype=str(w.get("archetype",""))
	var strength=pow(clampf(float(w.get("recoil",.345))/.345,.25,4),.55)
	var source=maxf(.0001,float(w.get("spread",.008)))
	var p={"id":id,"family":family,"pitch":.0115*strength,"yaw":.0026*strength,"bloom":.0016,"max_bloom":.018,
		"return":5.5,"recover_delay":.13,"spread_return":.040,"scope":family=="sniper","scope_zoom":1.5,
		"visual":clampf(strength,.5,2.2),"first":1.25,"hip":source*.65,"ads":maxf(.0006,source*float(w.get("aimSpreadMultiplier",.42))*.22),
		"move":.022,"air":.08,"settle":.22,"pattern":float(posmod(id.hash(),997))*.013,"pellet":0.0}
	p.bipod=not w.has("mounted_fire_key") and id!="minigun" and (bool(w.get("mechanics",{}).get("model",{}).get("bipod",false)) or family=="heavy")
	p.sustain_return=0.0;p.max_pitch=.26;p.max_yaw=.11
	match family:
		"smg":p.pitch*=.65;p.yaw*=.85;p.bloom=.0012;p.max_bloom=.021;p.return=8.0;p.move=.014;p.settle=.16
		"pistol":p.pitch*=1.55;p.yaw*=.70;p.bloom=.0028;p.max_bloom=.027;p.return=6.5;p.move=.018;p.settle=.16
		"sniper":
			var dmr=archetype=="battleRifle"
			p.pitch*=1.40 if dmr else 2.1;p.yaw*=.6;p.return=4.3;p.recover_delay=.17 if dmr else .22
			p.hip=maxf(source*.85,.018 if dmr else .032);p.ads=maxf(.00032,source*(.075 if dmr else .10))
			p.move=.034 if dmr else .060;p.air=.13;p.settle=.35 if dmr else .48;p.scope_zoom=1.5 if dmr else 2.0
			p.bloom=.0028 if dmr else .003;p.max_bloom=.016;p.first=1.10
		"shotgun":
			p.pitch*=1.65;p.yaw*=.7;p.return=4.8;p.bloom=.003;p.hip=.018;p.ads=.0035;p.move=.025
			# Pellet dispersion belongs to the shell; ADS only steadies its axis.
			if int(w.get("pellets",1))>1:p.pellet=source*.62
		"heavy":p.yaw*=1.40;p.return=4.8;p.bloom=.0017;p.max_bloom=.023;p.move=.032;p.settle=.32
		"launcher","launcher_low":p.pitch=.020;p.yaw=.003;p.bloom=.003;p.return=4.0;p.hip=.018;p.ads=.004;p.move=.030
		"grenade","melee","mortar":p.pitch=0.0;p.yaw=0.0;p.bloom=0.0;p.scope=false
	if TUNING.has(id):
		var t: Array=TUNING[id];p.pitch=deg_to_rad(t[0]);p.yaw=deg_to_rad(t[1]);p.return=t[2];p.first=t[3]
	if w.has("mounted_fire_key") and w.kind=="bullet":
		var fixed=id=="hmg/primary"
		p.pitch=deg_to_rad(.085 if fixed else .12);p.yaw=deg_to_rad(.025 if fixed else .035)
		p.first=1.0;p.return=12.0;p.recover_delay=.045;p.sustain_return=4.0 if fixed else 3.2
		p.max_pitch=deg_to_rad(.75 if fixed else 1.0);p.max_yaw=deg_to_rad(.25 if fixed else .35)
		p.hip=.0030 if fixed else .0040;p.ads=.0018 if fixed else .0025
		p.bloom=.00018;p.max_bloom=.0025;p.spread_return=.05;p.move=.003;p.settle=.12
		p.scope=false;p.visual=.35
	# Orthographic carried firearms: keep the selected aim elevation; recoil is an
	# aim-relative shoulder deflection, shared by the rig and physical shot axis.
	p.topdown=is_topdown(w)
	if p.topdown:
		p.pitch*=.10
		p.yaw*=3.0
		p.max_pitch=clampf(p.pitch*3.0,.003,.007)
		p.max_yaw=clampf(p.yaw*18.0,.035,.085)
		p.shoulder_sign=-1.0 if posmod(id.hash(),2)==0 else 1.0
		p.vertical_spread=.004
		p.vertical_pellet=.006
	profiles[id]=p;return p

static func is_topdown(w: Dictionary) -> bool:
	return not w.has("mounted_fire_key") and str(w.get("kind","")) in ["bullet","hitscan","shotgun"]

static func braced(w: Dictionary,u: Dictionary) -> bool:
	return bool(profile(w).bipod) and int(u.get("mounted",-1))<0 and int(u.get("stance",0))==2 and float(u.get("stance_blend",0))>=1.95 and u.get("grounded",false) and Vector2(u.get("velocity",Vector2.ZERO)).length_squared()<.0144 and u.get("vault",{}).is_empty() and u.get("ladder",{}).is_empty()

static func support(w: Dictionary,u: Dictionary) -> float:
	return float(u.get("bipod_support",0)) if braced(w,u) else 0.0

static func reset(state: Dictionary):
	state.kick_angle=Vector2.ZERO;state.kick_velocity=Vector2.ZERO;state.recoil_target=Vector2.ZERO
	state.bloom=0.0;state.burst=0;state.shot_age=100.0;state.aim_time=0.0;state.motion_inaccuracy=0.0
	state.bipod_support=0.0

static func tick(state: Dictionary,w: Dictionary,delta: float):
	var p=profile(w)
	if state.get("handling_weapon","")!=p.id:reset(state);state.handling_weapon=p.id
	state.bipod_support=move_toward(float(state.get("bipod_support",0)),1.0 if braced(w,state) else 0.0,delta*3.5)
	var previous_age=float(state.shot_age)
	state.shot_age+=delta
	var interval=60.0/FireControl.rpm(w,state);var delay=maxf(float(p.recover_delay),minf(.18,interval*1.35))
	if p.topdown:
		# Split exactly at the recovery boundary; do not apply a whole frame of
		# recovery when only part of it occurred after the last-shot delay.
		var sustain_time=clampf(delay-previous_age,0,delta)
		var damping=maxf(float(p.sustain_return),support(w,state)*2.4)
		_follow_decaying_target(state,sustain_time,damping)
		if damping>0:state.bloom=move_toward(float(state.bloom),0,float(p.spread_return)*sustain_time*.35)
		var recovery_time=delta-sustain_time
		_follow_decaying_target(state,recovery_time,float(p.return))
		state.bloom=move_toward(float(state.bloom),0,float(p.spread_return)*recovery_time)
	else:
		# Preserve mounted and indirect-fire handling exactly.
		if state.shot_age>delay:
			state.recoil_target=Vector2(state.recoil_target)*exp(-float(p.return)*delta)
			state.bloom=move_toward(float(state.bloom),0,float(p.spread_return)*delta)
		else:
			var damping=maxf(float(p.sustain_return),support(w,state)*2.4)
			if damping>0:
				state.recoil_target=Vector2(state.recoil_target)*exp(-damping*delta)
				state.bloom=move_toward(float(state.bloom),0,float(p.spread_return)*delta*.35)
		_follow_target(state,delta)
	if state.shot_age>maxf(.28,interval*1.8):state.burst=0
	state.aim_time=float(state.aim_time)+delta if state.get("aiming",false) else 0.0
	var movement=clampf((Vector2(state.get("velocity",Vector2.ZERO)).length()-.08)/3.32,0,1.7)
	state.motion_inaccuracy=lerpf(float(state.motion_inaccuracy),movement,1-exp(-delta*(18 if movement>state.motion_inaccuracy else 7)))

# Exact critically damped response to an exponentially recovering target. This
# separates the true aim line (owned by the rig) from the recovery angle.
static func _follow_decaying_target(state: Dictionary,delta: float,rate: float):
	if delta<=0:return
	if rate==0:
		_follow_target(state,delta);return
	var omega=55.0
	var target=Vector2(state.recoil_target)
	var particular=target*(omega*omega/((omega-rate)*(omega-rate)))
	var initial=Vector2(state.kick_angle)-particular
	var coefficient=Vector2(state.kick_velocity)+particular*rate+initial*omega
	var spring_decay=exp(-omega*delta);var target_decay=exp(-rate*delta)
	state.kick_angle=(initial+coefficient*delta)*spring_decay+particular*target_decay
	state.kick_velocity=(coefficient-(initial+coefficient*delta)*omega)*spring_decay-particular*(rate*target_decay)
	state.recoil_target=target*target_decay

static func _follow_target(state: Dictionary,delta: float):
	var omega=55.0;var error=Vector2(state.kick_angle)-Vector2(state.recoil_target)
	var change=(Vector2(state.kick_velocity)+error*omega)*delta;var decay=exp(-omega*delta)
	state.kick_angle=Vector2(state.recoil_target)+(error+change)*decay
	state.kick_velocity=(Vector2(state.kick_velocity)-change*omega)*decay

static func aim_spread(w: Dictionary,state: Dictionary,u: Dictionary) -> float:
	if w.kind=="melee":return 0.0
	var p=profile(w);var stance=clampi(int(u.get("stance",0)),0,2)
	var ads=smoothstep(0,float(p.settle),float(state.get("aim_time",0))) if u.get("aiming",false) else 0.0
	var base=lerpf(float(p.hip),float(p.ads),ads)
	var move=float(state.get("motion_inaccuracy",0))*float(p.move)
	var bloom=float(state.get("bloom",0))*lerpf(1,.65,ads)
	var result=sqrt(base*base+move*move+bloom*bloom)*[1.0,.78,.58][stance]
	result*=lerpf(1.0,.60,support(w,u))
	if not u.get("grounded",true):result=sqrt(result*result+float(p.air)*float(p.air))
	return result

static func spread(w: Dictionary,state: Dictionary,u: Dictionary) -> float:
	return aim_spread(w,state,u)+float(profile(w).pellet)

static func offset(w: Dictionary,state: Dictionary,time: float) -> Vector2:
	var angle: Vector2=state.get("kick_angle",Vector2.ZERO)
	if profile(w).scope and state.get("aiming",false):
		var amplitude=lerpf(.0018,.00045,clampf(float(state.get("aim_time",0))/.7,0,1))*[1.0,.7,.4][clampi(int(state.get("stance",0)),0,2)]
		angle+=Vector2(sin(time*1.7),cos(time*1.23))*amplitude
	return angle

static func compensate(state: Dictionary,radians: float):
	if radians<=0 or not state.has("recoil_target"):return
	state.recoil_target.y=maxf(0,state.recoil_target.y-radians)
	state.kick_angle.y=maxf(0,state.kick_angle.y-radians)
	state.kick_velocity.y=minf(0,state.kick_velocity.y)

static func fired(state: Dictionary,w: Dictionary,u: Dictionary,random_sample: float=0.0):
	if not state.has("kick_angle"):reset(state)
	var p=profile(w);var stance=clampi(int(u.get("stance",0)),0,2)
	var control=[1.0,.80,.56][stance]*(.90 if u.get("aiming",false) else 1.0)
	var supported=support(w,u)
	control=lerpf(control,.18,supported)
	if not u.get("grounded",true):control*=1.5
	state.burst+=1;state.shot_age=0.0
	var sustained=smoothstep(2,9,float(state.burst))
	var horizontal=(sin(float(state.burst)*.58+float(p.pattern))*.75+random_sample*.25)*float(p.yaw)*lerpf(.35,1.0,sustained)
	if p.topdown:
		# A stable per-weapon shoulder direction; the old oscillation could cancel
		# consecutive shots. Pattern/rate/yaw still differ between source weapons.
		horizontal=float(p.shoulder_sign)*float(p.yaw)*lerpf(.35,1.0,sustained)*(1.0+.15*sin(float(state.burst)*.58+float(p.pattern))+.08*random_sample)
	var vertical=float(p.pitch)*(float(p.first) if state.burst==1 else lerpf(1.0,.80,sustained))*(1+random_sample*.06)
	var max_pitch=lerpf(float(p.max_pitch),minf(float(p.max_pitch),.003) if p.topdown else .030,supported);var max_yaw=lerpf(float(p.max_yaw),.020,supported)
	state.recoil_target=Vector2(clampf(state.recoil_target.x+horizontal*control,-max_yaw,max_yaw),minf(max_pitch,state.recoil_target.y+vertical*control))
	state.bloom=minf(float(p.max_bloom),float(state.bloom)+float(p.bloom)*lerpf(1.0,.35,supported))

static func cone_direction(forward: Vector3,spread_angle: float,azimuth: float,radius: float,vertical_angle: float=-1.0) -> Vector3:
	var basis=Basis.looking_at(forward.normalized(),Vector3.UP if absf(forward.normalized().y)<.98 else Vector3.FORWARD)
	var disk=Vector2(cos(azimuth),sin(azimuth))*tan(spread_angle)*sqrt(clampf(radius,0,1))
	if vertical_angle>=0:disk.y=sin(azimuth)*tan(vertical_angle)*sqrt(clampf(radius,0,1))
	return (basis*Vector3(disk.x,disk.y,-1)).normalized()

static func shot_direction(forward: Vector3,spread_angle: float,azimuth: float,sample: float,vertical_angle: float=-1.0) -> Vector3:
	# Bounded 2D Gaussian: dense centre with occasional edge shots.
	var radius=sqrt(-2*log(maxf(.0001,1-sample*(1-exp(-4.5)))))/3
	return cone_direction(forward,spread_angle,azimuth,radius*radius,vertical_angle)

# Cap only the vertical semi-axis, once, at the emission boundary. Horizontal
# source dispersion remains untouched. Pellets have their own shell envelope.
static func vertical_spread(w: Dictionary,angle: float,pellet: bool=false) -> float:
	var p=profile(w)
	if not p.topdown:return -1.0
	return minf(angle,float(p.vertical_pellet if pellet else p.vertical_spread))
