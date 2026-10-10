extends RefCounted
## Heightfield traversal with real vertical collision and a validated vault path.
const WALK_SPEED=3.4
const SPRINT_SPEED=5.8
const GRAVITY=18.0
const JUMP_SPEED=6.4
const MAX_VAULT_HEIGHT=2.1
const RADIUS=.28
const COLLISION_SKIN=.001
# The supplied chubby soldier, helmet and backpack extend beyond the walking capsule.
const VAULT_RADIUS=.64
const VAULT_TOP_CLEARANCE=.16

static func reset(u: Dictionary):
	u.elevation=0.0;u.vertical_speed=0.0;u.grounded=true;u.sprinting=false
	u.ladder={};u.vault={};u.vault_progress=0.0;u.landing=0.0;u.jump_cooldown=0.0;u.air_speed=WALK_SPEED
	u.last_clear={};u.recovery_after=0.0
	u.vehicle_push=Vector2.ZERO;u.vehicle_stagger=0.0;u.vehicle_contacts={}
	u.vehicle_flight={}
	u.erase("overlap_search")

static func remember_clear(world,u: Dictionary):
	if not world.blocked(u.position,RADIUS,world.collision_height(u),-1,u.elevation):
		u.last_clear={"position":u.position,"elevation":u.elevation}

static func escape_path_clear(world,u: Dictionary,to: Vector2,to_height: float) -> bool:
	# A recovery may leave existing overlap, but may never cross deeper into a wall.
	var height: float=world.collision_height(u)
	var depth: float=world.collision_depth(u.position,RADIUS,height,-1,u.elevation)
	var steps=maxi(1,ceili(maxf(u.position.distance_to(to),absf(u.elevation-to_height))/.025))
	for i in range(1,steps+1):
		var t=float(i)/steps
		var next: float=world.collision_depth(u.position.lerp(to,t),RADIUS,height,-1,lerpf(u.elevation,to_height,t))
		if next>depth+.00001:return false
		depth=next
	return depth<=COLLISION_SKIN

static func restore_clear(world,u: Dictionary,point: Vector2,elevation: float):
	u.position=point;u.elevation=elevation;u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO
	u.vertical_speed=0.0;u.grounded=absf(elevation-world.ground_height(point,RADIUS,elevation+COLLISION_SKIN))<.025
	u.last_clear={"position":point,"elevation":elevation}

static func recover_overlap(world,u: Dictionary):
	if not world.blocked(u.position,RADIUS,world.collision_height(u),-1,u.elevation):u.erase("overlap_search");return
	if not u.player and world.campaign_active():
		recover_overlap_incremental(world,u);return
	if world.time<float(u.get("recovery_after",0)):return
	u.recovery_after=world.time+.25
	var previous: Dictionary=u.get("last_clear",{})
	if not previous.is_empty() and u.position.distance_to(previous.position)<=1.0 and absf(u.elevation-previous.elevation)<=.35:
		if escape_path_clear(world,u,previous.position,previous.elevation):
			restore_clear(world,u,previous.position,previous.elevation);return
	# No valid history (e.g. moved geometry): only separate locally at the same height.
	# Search nearest first, with backwards preferred; never snap onto or across a wall.
	var backward: Vector2=-u.requested_velocity.normalized() if u.requested_velocity.length_squared()>.001 else -u.facing
	for ring in range(1,21):
		for i in range(16):
			var point: Vector2=u.position+backward.rotated(TAU*i/16)*(.04*ring)
			if world.blocked(point,RADIUS,world.collision_height(u),-1,u.elevation):continue
			if escape_path_clear(world,u,point,u.elevation):
				restore_clear(world,u,point,u.elevation);return

static func recover_overlap_incremental(world,u: Dictionary):
	# The old full 20-ring search could perform hundreds of body sweeps for each
	# trapped AI in one tick. Resume the identical ordered candidates across ticks.
	if world.overlap_budget_usec<=0:return
	var search: Dictionary=u.get("overlap_search",{})
	if not search.is_empty() and (search.position!=u.position or search.elevation!=u.elevation or search.revision!=world.topology_revision):search={}
	if search.is_empty():
		if world.time<float(u.get("recovery_after",0)):return
		search={"position":u.position,"elevation":u.elevation,"revision":world.topology_revision,"next":0,"backward":-u.requested_velocity.normalized() if u.requested_velocity.length_squared()>.001 else -u.facing}
		u.overlap_search=search
	var started=Time.get_ticks_usec();var deadline=started+int(world.overlap_budget_usec)
	if search.next==0:
		var previous: Dictionary=u.get("last_clear",{})
		if not previous.is_empty() and u.position.distance_to(previous.position)<=1.0 and absf(u.elevation-previous.elevation)<=.35 and escape_path_clear(world,u,previous.position,previous.elevation):
			restore_clear(world,u,previous.position,previous.elevation);u.erase("overlap_search")
			world.overlap_budget_usec-=Time.get_ticks_usec()-started;return
	for attempt in range(12):
		if search.next>=320 or Time.get_ticks_usec()>=deadline:break
		var index=int(search.next);search.next+=1
		var point: Vector2=search.position+Vector2(search.backward).rotated(TAU*(index%16)/16)*(.04*(1+int(index/16)))
		if world.blocked(point,RADIUS,world.collision_height(u),-1,u.elevation):continue
		if escape_path_clear(world,u,point,u.elevation):
			restore_clear(world,u,point,u.elevation);u.erase("overlap_search")
			world.overlap_budget_usec-=Time.get_ticks_usec()-started;return
	world.overlap_budget_usec-=Time.get_ticks_usec()-started
	if search.next>=320:u.erase("overlap_search");u.recovery_after=world.time+.25

static func stride(speed: float) -> float:
	return lerpf(1.2,1.9,clampf(speed/WALK_SPEED,0,1)) if speed<=WALK_SPEED else lerpf(1.9,2.35,clampf((speed-WALK_SPEED)/(SPRINT_SPEED-WALK_SPEED),0,1))

static func move(world,u: Dictionary,input: Vector2,delta: float,sprint: bool,jump: bool):
	if not u.get("ladder",{}).is_empty():
		preload("res://scripts/terrain_ladder.gd").move(world,u,input,delta,jump);return
	u.landing=maxf(0,u.landing-delta);u.jump_cooldown=maxf(0,u.jump_cooldown-delta)
	if not u.vault.is_empty():
		u.vault.exit_input=input.limit_length()
		advance_vault(world,u,delta);return
	u.sprinting=sprint and u.stance==0 and u.stance_blend<.1 and input.length_squared()>.1 and u.grounded
	var speed=SPRINT_SPEED if u.sprinting else [WALK_SPEED,1.65,.62][u.stance]
	if u.aiming:speed*=float(world.weapon_for(u).get("aimMoveMultiplier",.65))
	if jump and u.grounded and u.jump_cooldown<=0:
		if u.stance==2:
			world.event.emit({"type":"notice","text":"卧倒时请先按 Z 起身，再跳跃或翻越"})
		elif world.blocked(u.position,RADIUS,world.stance_height(0),-1,u.elevation):
			world.event.emit({"type":"notice","text":"上方空间不足，无法起跳"})
		else:
			u.stance=0
			var direction=input.normalized() if input.length_squared()>.01 else u.facing
			var vault=find_vault(world,u,direction)
			if not vault.is_empty():
				u.vault=vault;u.vault_progress=0.0;u.sprinting=false;u.grounded=false;u.vertical_speed=0
				u.reload=0.0
				u.facing=direction;u.velocity=Vector2.ZERO;u.requested_velocity=Vector2.ZERO
				world.event.emit({"type":"vault_start","unit":u});advance_vault(world,u,delta);return
			u.vertical_speed=JUMP_SPEED;u.grounded=false;u.air_speed=speed;u.jump_cooldown=.18
			world.event.emit({"type":"jump","unit":u})
	if not u.grounded:speed=u.air_speed
	else:speed*=world.terrain.speed_at(u.position)
	world.move_unit(u,input.limit_length()*speed,delta,3.0 if not u.grounded else 10.0 if u.sprinting else 8.0)
	vertical_step(world,u,delta)
	remember_clear(world,u)

static func vertical_step(world,u: Dictionary,delta: float):
	var before: float=u.elevation
	# The landing footprint must equal the moving body; a smaller probe lets its rim
	# fall inside a wall while every subsequent horizontal move remains blocked.
	var support: float=world.ground_height(u.position,RADIUS,before+COLLISION_SKIN)
	if u.grounded and absf(before-support)<.025:
		u.elevation=support;u.vertical_speed=0;return
	if u.grounded:u.air_speed=maxf(WALK_SPEED,u.velocity.length())
	u.grounded=false;u.vertical_speed-=GRAVITY*delta
	var next=before+u.vertical_speed*delta
	if u.vertical_speed>0 and world.blocked(u.position,RADIUS,world.collision_height(u),-1,next):
		# Find the highest non-overlapping point before a ceiling, then begin falling.
		var lo=before;var hi=next
		for i in range(8):
			var mid=(lo+hi)*.5
			if world.blocked(u.position,RADIUS,world.collision_height(u),-1,mid):hi=mid
			else:lo=mid
		u.elevation=lo;u.vertical_speed=0;return
	if u.vertical_speed<=0 and next<=support:
		u.elevation=support;land(world,u,absf(u.vertical_speed));return
	u.elevation=next

static func land(world,u: Dictionary,speed: float):
	u.grounded=true;u.vertical_speed=0;u.jump_cooldown=.12;u.landing=clampf(speed/18,.12,.32)
	world.event.emit({"type":"land","unit":u,"speed":speed})

static func find_vault(world,u: Dictionary,direction: Vector2) -> Dictionary:
	var best: Dictionary={};var nearest=1.0
	for o in world.candidates(u.position,u.position+direction*3.2,.4):
		if not o.alive or not o.collision or not o.component_id.begins_with("wall.") or o.elevation>u.elevation+.15:continue
		var local=(u.position-o.position).rotated(-o.angle);var dir=direction.rotated(-o.angle)
		if absf(dir.y)<.60 or o.size.y>1.40:continue
		var near_y=-signf(dir.y)*(o.size.y*.5+RADIUS+.04)
		var entry=(near_y-local.y)/dir.y
		if entry<-.06 or entry>nearest:continue
		var face_y=-signf(dir.y)*o.size.y*.5
		var crossing=local+dir*((face_y-local.y)/dir.y)
		if absf(crossing.x)>o.size.x*.5-VAULT_RADIUS:continue
		var top=0.0
		var c0=clampi(int((crossing.x-VAULT_RADIUS+o.size.x*.5)/o.cell_width),0,o.columns-1)
		var c1=clampi(int((crossing.x+VAULT_RADIUS+o.size.x*.5)/o.cell_width),0,o.columns-1)
		for col in range(c0,c1+1):
			for row in range(o.rows):
				if o.hp[row*o.columns+col]>0:top=maxf(top,o.elevation+(row+1)*o.cell_height)
		if top-u.elevation<.30 or top-u.elevation>MAX_VAULT_HEIGHT:continue
		# Approach with the walking footprint; do not make a soldier already at the
		# wall shuffle backwards just to inflate the airborne clearance envelope.
		var approach_distance=maxf(0,(-signf(dir.y)*(o.size.y*.5+RADIUS+.08)-local.y)/dir.y)
		var exit_distance=(signf(dir.y)*(o.size.y*.5+VAULT_RADIUS+.10)-local.y)/dir.y
		if exit_distance<=0 or exit_distance>4.2:continue
		var end: Vector2=u.position+direction*exit_distance
		var end_height: float=world.ground_height(end,VAULT_RADIUS,u.elevation+.2)
		if world.blocked(end,VAULT_RADIUS,world.stance_height(0),-1,end_height):continue
		var hand_point: Vector2=o.position+Vector2(crossing.x,face_y).rotated(o.angle)
		var rise=top-u.elevation
		var mode="step" if rise<=.85 else "vault" if rise<=1.35 else "climb"
		var duration=lerpf(.62,.79,inverse_lerp(.30,.85,rise)) if mode=="step" else lerpf(.92,1.12,inverse_lerp(.85,1.35,rise)) if mode=="vault" else lerpf(1.40,1.85,inverse_lerp(1.35,MAX_VAULT_HEIGHT,rise))
		var momentum=clampf(Vector2(u.velocity).dot(direction)/SPRINT_SPEED,0,1)
		duration*=lerpf(1.08,.88 if mode!="climb" else .95,momentum)
		duration+=sqrt(2*maxf(0,top+VAULT_TOP_CLEARANCE-end_height)/GRAVITY)
		var tangent=Vector2(cos(o.angle),sin(o.angle))
		if tangent.dot(Vector2(-direction.y,direction.x))<0:tangent=-tangent
		var normal=Vector2(0,signf(dir.y)).rotated(o.angle)
		var path={"mode":mode,"rise":rise,"width":o.size.y,"normal":normal,"tangent":tangent,"start":u.position,"approach":u.position+direction*approach_distance,"hand_point":hand_point,"end":end,"start_height":u.elevation,"end_height":end_height,"peak":top+VAULT_TOP_CLEARANCE,"duration":duration+o.size.y*.10+.12,"age":0.0,"wall":o.id,"height":top,"direction":direction,"momentum":momentum,"entry_speed":u.velocity.length(),"lead":float(u.get("traversal_lead",-1.0)),"exit_input":Vector2.ZERO}
		var clear=true
		for i in range(49):
			var sample=sample_vault(path,float(i)/48)
			if vault_blocked(world,sample):clear=false;break
		if clear:best=path;nearest=maxf(0,entry)
	return best

static func vault_timing(path: Dictionary) -> Vector3:
	var mode=str(path.get("mode","vault"))
	var rise=.32 if mode=="step" else .43 if mode=="vault" else .55
	var fall_seconds=sqrt(2*maxf(0,float(path.peak)-float(path.end_height))/GRAVITY)
	var across_end=vault_ground_time(path)-fall_seconds/float(path.duration)
	return Vector3(rise,rise,maxf(rise+.10,across_end))

static func vault_ground_time(path: Dictionary) -> float:
	return 1.0-.14/float(path.duration)

static func vault_window(t: float,a: float,b: float,c: float,d: float) -> float:
	return smoothstep(a,b,t)*(1-smoothstep(c,d,t))

static func vault_pose(path: Dictionary,t: float) -> Dictionary:
	# Contact intervals, physics and pose share one clock. These are authored for
	# this short-limbed source rig, not timings copied from PUBG's human skeleton.
	var mode=str(path.get("mode","vault"));var timing=vault_timing(path)
	var high=mode=="climb";var low=mode=="step";var ground=vault_ground_time(path)
	var plant=.24 if high else .14
	var release=.45 if high else .33 if not low else .26
	var load=vault_window(t,.0,.10,.16,.26)
	var compact=vault_window(t,.10,.30 if low else .43,timing.z-.07,.97)
	var impact=vault_window(t,ground-.025,ground+.02,minf(.985,ground+.035),1.0)
	return {"load":load,"compact":compact,"impact":impact,"reach":vault_window(t,.03,plant,release-.07,release),"stow":vault_window(t,.02,.14,ground-.035,1.0),"cross":smoothstep(timing.y,timing.z,t),"lead_lift":smoothstep(.10,.28 if low else .39,t),"trail_lift":smoothstep(.20,.37 if low else .50,t),"lead_land":smoothstep(timing.z-.03,ground,t),"trail_land":smoothstep(timing.z+.02,minf(.985,ground+.025),t),"wall_foot":vault_window(t,.13,.25,.34,.46) if high else 0.0,"ledge_foot":vault_window(t,.31,.49,.59,.72) if high else 0.0,"drop":load*.12+compact*(.28 if low else .26)+impact*.10,"lean":load*.30+compact*(.72 if low else .58 if not high else .48),"roll":sin(smoothstep(.13,.90,t)*PI)*(.19 if low else .13 if not high else .07)}

static func sample_vault(path: Dictionary,t: float) -> Dictionary:
	var mode=str(path.get("mode","vault"));var timing=vault_timing(path)
	var rise_end=timing.x;var across_start=timing.y;var across_end=timing.z
	var position: Vector2=path.start.lerp(path.approach,smoothstep(0,.13,t)) if t<across_start else path.approach.lerp(path.end,smoothstep(across_start,across_end,t))
	var elevation: float
	if mode=="climb" and t<rise_end:
		# Reach the ledge, pause briefly in the hang, then pull the hips over it.
		var hang=maxf(path.start_height,path.height-1.05)
		elevation=lerpf(path.start_height,hang,smoothstep(.06,.24,t)) if t<.28 else lerpf(hang,path.peak,smoothstep(.28,rise_end,t))
	else:elevation=lerpf(path.start_height,path.peak,smoothstep(.10,rise_end,t)) if t<rise_end else path.peak
	if t>=across_start and t<=across_end:
		elevation+=sin(smoothstep(across_start,across_end,t)*PI)*(.05 if mode=="climb" else .10)
	# Accelerate into the landing, then allow time for knee compression and recovery.
	# The old ease-out descent decelerated in mid-air and looked like an elevator.
	if t>across_end:
		var fall=clampf(inverse_lerp(across_end,vault_ground_time(path),t),0,1)
		elevation=lerpf(path.peak,path.end_height,fall*fall)
	# Collision and the visual root now use the same base height. Never let a virtual
	# leg tuck clear the collision test while the rendered body is still below the top.
	var radius=RADIUS if t<rise_end else VAULT_RADIUS
	return {"position":position,"elevation":elevation,"radius":radius}

static func vault_blocked(world,sample: Dictionary) -> bool:
	return world.blocked(sample.position,sample.radius,world.stance_height(0),-1,sample.elevation)

static func advance_vault(world,u: Dictionary,delta: float):
	var path: Dictionary=u.vault;path.age+=delta
	var t=clampf(path.age/path.duration,0,1);var next=sample_vault(path,t)
	# Recheck live geometry so editing/reset/vehicles cannot make a cached path tunnel.
	var clear=true;var steps=maxi(1,ceili((t-u.vault_progress)*48))
	for i in range(1,steps+1):
		if vault_blocked(world,sample_vault(path,lerpf(u.vault_progress,t,float(i)/steps))):clear=false;break
	if not clear:
		# Resume falling from the last real position; no synthetic upward teleport.
		if world.blocked(u.position,RADIUS,world.stance_height(0),-1,u.elevation):
			u.position=path.start;u.elevation=path.start_height
		u.ladder={};u.vault={};u.sprinting=false;u.grounded=false;u.vertical_speed=0
		world.event.emit({"type":"notice","text":"翻越路线被挡住，动作已中止"});return
	u.velocity=(next.position-u.position)/maxf(delta,.0001);u.position=next.position;u.elevation=next.elevation;u.vault_progress=t
	u.facing=path.direction;u.requested_velocity=Vector2.ZERO
	var supported=absf(u.elevation-world.ground_height(u.position,RADIUS,u.elevation+COLLISION_SKIN))<.025
	if not bool(path.get("landed",false)) and t>=vault_ground_time(path) and supported:
		path.landed=true
		var impact_speed=sqrt(2*GRAVITY*maxf(0,float(path.peak)-float(path.end_height)))
		u.landing=clampf(impact_speed/18,.12,.32)
		world.event.emit({"type":"land","unit":u,"speed":impact_speed})
	if t>=1:
		var exit_input: Vector2=path.get("exit_input",Vector2.ZERO)
		u.ladder={};u.vault={};u.velocity=exit_input*minf(WALK_SPEED,float(path.get("entry_speed",0))*.65) if exit_input.dot(path.direction)>.2 else Vector2.ZERO;u.grounded=false;u.vertical_speed=-1
		if bool(path.get("landed",false)) and supported:u.grounded=true;u.vertical_speed=0;u.jump_cooldown=.12
		else:vertical_step(world,u,delta)
		remember_clear(world,u)
