extends SceneTree
## Authorized bounded headless battle diagnostic. Analytic muzzle, no rendering.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const Zone=preload("res://scripts/capture_zone.gd")
var hz=60
var step_delta=1.0/60.0
var cadence=[]
var world
var output=""
var chapter=1
var seconds=120.0
var started=0
var frames=0
var next_sample=0.0
var previous_sample_time=0.0
var event_counts={}
var previous_ammo={}
var start_positions={}
var last_positions={}
var still={}
var moved={}
var covered={}
var entered={}
var peak_stall={}
var errors=[]
var records=[]
var maxima={"shots":0,"projectiles":0,"mounted":0}
var stopped=false
var trace_profile=false
var source_hashes={}
var last_process_frame=-1
var steps_in_frame=0
var catchup_steps=0
var max_steps_in_frame=0
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--chapter="):chapter=int(arg.trim_prefix("--chapter="))
		if arg=="--profile":trace_profile=true
		if arg.begins_with("--hz="):hz=int(arg.trim_prefix("--hz="))
		if arg.begins_with("--seconds="):seconds=float(arg.trim_prefix("--seconds="))
	if output.is_empty() or FileAccess.file_exists(output):printerr("Output required and must not already exist");quit(2);return
	step_delta=1.0/float(hz);Engine.physics_ticks_per_second=hz;Engine.max_fps=hz
	var catalog=Catalog.new();world=World.new()
	var plan=Orchard.plan(catalog) if chapter==1 else load("res://scripts/campaign_catalog.gd").plan(catalog,chapter)
	world.setup(plan,catalog);world.event.connect(on_event);world.profile_ai=trace_profile
	for path in ["scripts/proving_world.gd","scripts/campaign_ai.gd","scripts/campaign_rules.gd","scripts/campaign_tactics.gd","scripts/campaign_vehicle_ai.gd","scripts/campaign_directional_aim.gd","data/campaign/chapters.json"]:
		if FileAccess.file_exists("res://"+path):source_hashes[path]=FileAccess.get_sha256("res://"+path)
	started=Time.get_ticks_msec();sample()
	print("PLAYCHECK_START chapter=%d units=%d limit=%.0f fixed_dt=%dHz render=false"%[chapter,world.units.size(),seconds,hz])
func on_event(event: Dictionary):
	var key=str(event.get("type","unknown"));event_counts[key]=int(event_counts.get(key,0))+1
func _physics_process(_delta: float) -> bool:
	if world==null or stopped:return false
	var process_frame=Engine.get_process_frames()
	if process_frame!=last_process_frame:last_process_frame=process_frame;steps_in_frame=0
	steps_in_frame+=1;max_steps_in_frame=maxi(max_steps_in_frame,steps_in_frame)
	if steps_in_frame>1:catchup_steps+=1
	var physics_frame=Engine.get_physics_frames();var before_budget=int(world.ai_budget_usec);var reset_due=int(world.ai_budget_frame)!=process_frame
	world.step(step_delta,Vector2.ZERO,world.player.position+world.player.facing*3,false,false)
	cadence.append({"process":process_frame,"physics":physics_frame,"budget_before":before_budget,"reset_due":reset_due,"budget_after":world.ai_budget_usec})
	frames+=1
	maxima.shots=world.shots;maxima.projectiles=maxi(int(maxima.projectiles),world.projectiles.size())
	if world.time>=next_sample:
		sample();next_sample=world.time+2.0
		if int(world.time)%10<2:print("PLAYCHECK_PROGRESS chapter=%d sim=%.1f shots=%d casualties=%s progress=%.3f"%[chapter,world.time,world.shots,str(world.campaign.casualties),world.campaign.points[0].progress])
	if world.campaign.phase!="playing":finish("match-ended")
	elif world.time>=seconds:finish("sample-window-complete")
	elif Time.get_ticks_msec()-started>360000:finish("wall-timeout")
	return false
func sample():
	var rows=[];var mounted=0;var elapsed=maxf(0.0,float(world.time)-previous_sample_time)
	previous_sample_time=world.time
	for u in world.units:
		if not u.alive:continue
		var key=str(u.id)+":"+str(u.get("spawn_epoch",0))
		if not Vector2(u.position).is_finite() or not is_finite(float(u.elevation)):errors.append({"kind":"nonfinite","unit":key,"at":world.time})
		if absf(float(u.position.x))>world.bounds.x+1 or absf(float(u.position.y))>world.bounds.y+1:errors.append({"kind":"outside-world","unit":key,"at":world.time})
		if not start_positions.has(key):start_positions[key]=u.position;last_positions[key]=u.position
		if Vector2(start_positions[key]).distance_to(u.position)>2:moved[key]=true
		var state=str(u.get("ai_state",""))
		if state in ["cover","advance-cover","bound-overwatch","peek","low-displacement"]:covered[key]=true
		if Zone.contains(world.campaign.points[0],u.position,u.elevation):entered[key]=true
		if u.mounted>=0:mounted+=1
		var blocked=not u.player and Vector2(u.requested_velocity).length()>.3 and Vector2(last_positions[key]).distance_to(u.position)<.10
		still[key]=float(still.get(key,0))+elapsed if blocked else 0.0
		peak_stall[key]=maxf(float(peak_stall.get(key,0)),float(still[key]));last_positions[key]=u.position
		var ammo_key=key+":"+str(u.weapon_id);var ammo=int(u.ammo)+int(u.reserve)
		if previous_ammo.has(ammo_key) and ammo>int(previous_ammo[ammo_key]):errors.append({"kind":"carried-ammo-increase","unit":key,"weapon":u.weapon_id,"before":previous_ammo[ammo_key],"after":ammo,"at":world.time})
		previous_ammo[ammo_key]=ammo
		var row={"id":key,"team":u.team,"player":u.player,"position":[u.position.x,u.position.y],"state":state,"weapon":u.weapon_id,"ammo":u.ammo,"reserve":u.reserve,"mounted":u.mounted,"target":u.get("ai_target",-1),"path":u.path.size()}
		for field in ["ai_visible","ai_fire_clear","ai_fire_contact_id","ai_fire_contact_epoch","ai_fire_observed_at","ai_fire_weapon_id","ai_reaction","ai_state","ai_aim_contact_id","ai_aim_observed_at","ai_tactic_signature"]:
			if u.has(field):row[field]=u[field]
		var report: Dictionary=u.get("ai_contacts",{}).get(int(u.get("ai_target",-1)),{})
		if not report.is_empty():row.report={"id":report.get("id",-1),"epoch":report.get("spawn_epoch",0),"observed_at":report.get("observed_at",-1)}
		rows.append(row)
	for v in world.vehicles:
		for mode in v.states:
			var key="vehicle:"+str(v.id)+":"+str(mode);var ammo=int(v.states[mode].ammo)+int(v.states[mode].reserve)
			if previous_ammo.has(key) and ammo>int(previous_ammo[key]):errors.append({"kind":"mounted-ammo-increase","vehicle":v.id,"at":world.time})
			previous_ammo[key]=ammo
	maxima.mounted=maxi(int(maxima.mounted),mounted)
	records.append({"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"budget_usec":world.ai_budget_usec,"profile":world.last_step_profile.duplicate(true) if trace_profile else {},"at":world.time,"shots":world.shots,"active":world.campaign.active_counts(),"reserves":world.campaign.reserves.duplicate(),"progress":world.campaign.points[0].progress,"units":rows})
	var live=FileAccess.open(output+".live.json",FileAccess.WRITE)
	if live!=null:live.store_string(JSON.stringify(records[-1]));live.close()
func finish(reason: String):
	stopped=true;sample()
	var stalled=[]
	for key in peak_stall:
		if float(peak_stall[key])>=6:stalled.append({"unit":key,"max_seconds":peak_stall[key]})
	var summary={"hz":hz,"callback":"_physics_process","catchup_steps":catchup_steps,"max_steps_in_process_frame":max_steps_in_frame,"chapter":chapter,"reason":reason,"sim_seconds":world.time,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"frames":frames,"phase":world.campaign.phase,"shots":world.shots,"hits":world.hits,"casualties":world.campaign.casualties,"reserves":world.campaign.reserves,"progress":world.campaign.points[0].progress,"moved_lives":moved.size(),"cover_lives":covered.size(),"entered_lives":entered.size(),"maxima":maxima,"stalls_over_6s":stalled,"errors":errors,"event_counts":event_counts,"source_hashes":source_hashes,"limitations":"Single bounded headless sample; stationary player; analytic muzzle, no actor bone provider; no rendering, FPS, win-rate or visual acceptance claim"}
	var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"summary":summary,"samples":records,"cadence":cadence},"\t"));file.close()
	world.campaign_director.cancel();print("PLAYCHECK_COMPLETE "+JSON.stringify(summary));quit(0 if errors.is_empty() and reason!="wall-timeout" else 1)
