extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const DT=1.0/30.0
var world
var round_id=""
var directory=""
var events
var samples
var started=0
var setup_ms=0.0
var frames=0
var next_sample=0.0
var next_progress=10.0
var counts={}
var first={}
var timings: Array=[]
var slowest: Array=[]
var life_still={}
var active_seconds=[0.0,0.0]
var blocked_seconds=[0.0,0.0]
var trench=[{},{}]
var hill=[{},{}]
var entered=[{},{}]
var source_hashes={}
var done=false
var director_supported=false

func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--round="):round_id=arg.trim_prefix("--round=")
	if round_id not in ["1","2","3"]:printerr("Require --round=1, 2, or 3");quit(2);return
	directory="res://qa/ai-review/round-"+round_id
	if FileAccess.file_exists(directory+"/summary.json") or FileAccess.file_exists(directory+"/events.jsonl"):
		printerr("Refusing to overwrite or rerun an existing round");quit(2);return
	DirAccess.make_dir_recursive_absolute(directory)
	events=FileAccess.open(directory+"/events.jsonl",FileAccess.WRITE)
	samples=FileAccess.open(directory+"/samples.jsonl",FileAccess.WRITE)
	for path in ["scripts/proving_world.gd","scripts/campaign_ai.gd","scripts/campaign_rules.gd","scripts/orchard_level.gd","scripts/campaign_director.gd","scripts/campaign_commander.gd","scripts/campaign_perception.gd","scripts/campaign_tactics.gd","qa/ai_campaign_round.gd"]:
		if FileAccess.file_exists("res://"+path):source_hashes[path]=FileAccess.get_sha256("res://"+path)
	Engine.physics_ticks_per_second=30;Engine.max_fps=30
	var begin=Time.get_ticks_usec();var catalog=Catalog.new();world=World.new()
	world.event.connect(record_event)
	world.setup(Orchard.plan(catalog),catalog)
	world.profile_ai=true
	setup_ms=(Time.get_ticks_usec()-begin)/1000.0
	for property in world.get_property_list():
		if property.name=="campaign_director":director_supported=true
	started=Time.get_ticks_msec()
	print("AI_ROUND_START round=%s seed=%s units=%d real_time=30Hz limit=120s render=false setup_ms=%.1f"%[round_id,str(world.plan.world.seed),world.units.size(),setup_ms])
	sample()

func _physics_process(_delta: float) -> bool:
	if world==null or done:return false
	var before=Time.get_ticks_usec()
	world.step(DT,Vector2.ZERO,world.player.position+world.player.facing*3,false,false)
	var ms=(Time.get_ticks_usec()-before)/1000.0
	timings.append(ms);frames+=1
	if ms>33.333:
		slowest.append({"at":world.time,"ms":ms,"projectiles":world.projectiles.size(),"broken":world.broken,"nav_cells":world.campaign_ai.last_rebuild_cells,"nav_ms":world.campaign_ai.last_rebuild_ms,"profile":world.last_step_profile.duplicate()})
		if slowest.size()>15:slowest.sort_custom(func(a,b):return a.ms>b.ms);slowest.resize(15)
	for unit in world.units:
		if not unit.alive or unit.player:continue
		var team=int(unit.team);active_seconds[team]+=DT
		var excluded=unit.reload>0 or world.time<float(unit.get("guard_until",0)) or str(unit.get("ai_state","")) in ["hold","cover","reload","suppressed"]
		var stalled=not excluded and unit.requested_velocity.length()>.3 and unit.velocity.length()<.09
		life_still[unit.id]=float(life_still.get(unit.id,0))+DT if stalled else 0.0
		if float(life_still[unit.id])>=2:blocked_seconds[team]+=DT
		var ground=world.terrain.height(unit.position)
		if ground<-.45:trench[team][unit.id]=true
		if ground>.7 and unit.position.x<-20:hill[team][unit.id]=true
		var point: Dictionary=world.campaign.points[0]
		if unit.position.distance_to(point.position)<point.radius:
			entered[team][unit.id]=true
			if not first.has("entry_"+str(team)):first["entry_"+str(team)]=world.time
	if world.time>=next_sample:sample();next_sample=world.time+2.0
	if world.time>=next_progress:
		print("AI_ROUND_PROGRESS round=%s sim=%.1f shots=%d casualties=%s B=%.3f"%[round_id,world.time,world.shots,str(world.campaign.casualties),world.campaign.points[0].progress]);next_progress+=10
	if world.campaign.phase!="playing":finish("match-ended")
	elif frames>=3600:finish("time-limit")
	elif Time.get_ticks_msec()-started>360000:finish("wall-timeout")
	return false

func serial(value):
	if value is Vector2:return [value.x,value.y]
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Dictionary:
		var result={}
		for key in value:result[str(key)]=serial(value[key])
		return result
	if value is Array:
		var result=[]
		for item in value:result.append(serial(item))
		return result
	return value

func record_event(event: Dictionary):
	var kind=str(event.get("type","unknown"));counts[kind]=int(counts.get(kind,0))+1
	var at=float(world.time) if world!=null else 0.0
	if not first.has(kind):first[kind]=at
	var row={"type":kind,"at":at}
	for key in event:
		if key in ["unit","previous"]:
			row[key+"_id"]=event[key].get("id",-1);row[key+"_team"]=event[key].get("team",-1)
		elif key=="weapon":row.weapon=event.weapon.get("id",event.weapon.get("name",""))
		elif key in ["object","vehicle","state","projectile"]:
			if event[key] is Dictionary:row[key+"_id"]=event[key].get("id",-1)
		else:row[key]=serial(event[key])
	if kind=="respawn":life_still[event.unit.id]=0.0
	events.store_line(JSON.stringify(row))

func sample():
	var units=[]
	for unit in world.units:
		var row={"id":unit.id,"team":unit.team,"alive":unit.alive,"player":unit.player,"position":unit.position,"elevation":unit.elevation,"health":unit.health,"weapon":unit.weapon_id,"ammo":unit.ammo,"reserve":unit.reserve,"reload":unit.reload,"velocity":unit.velocity,"requested_velocity":unit.requested_velocity,"path_size":unit.path.size(),"next_waypoint":unit.path[0] if not unit.path.is_empty() else null}
		for key in ["stance","ai_target","ai_visible","ai_route_index","ai_route_done","ai_stuck","ai_state","ai_task","ai_stress","ai_goal","ai_contact_source","ai_last_progress_at","ai_order","squad_id","ai_contacts","ai_visible_ids"]:
			if unit.has(key):row[key]=unit[key]
		units.append(row)
	var row={"at":world.time,"phase":world.campaign.phase,"active":world.campaign.active_counts(),"reserves":world.campaign.reserves,"casualties":world.campaign.casualties,"points":world.campaign.points,"shots":world.shots,"hits":world.hits,"broken":world.broken,"units":units}
	if director_supported:row.director=world.campaign_director.diagnostics()
	samples.store_line(JSON.stringify(serial(row)));samples.flush();events.flush()

func percentile(sorted: Array,fraction: float) -> float:
	return float(sorted[clampi(int(ceil(sorted.size()*fraction))-1,0,sorted.size()-1)]) if not sorted.is_empty() else 0.0

func finish(reason: String):
	done=true;sample()
	var raw_timings=FileAccess.open(directory+"/step-times-ms.json",FileAccess.WRITE);raw_timings.store_string(JSON.stringify(timings));raw_timings.close()
	timings.sort()
	var report={"round":round_id,"reason":reason,"seed":world.plan.world.seed,"frames":frames,"sim_seconds":world.time,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"setup_ms":setup_ms,"render":false,"muzzle":"world analytic geometry, no actor bone provider","player_policy":"stationary, no shots, original handoff","phase":world.campaign.phase,"active":world.campaign.active_counts(),"reserves":world.campaign.reserves,"casualties":world.campaign.casualties,"points":world.campaign.points,"shots":world.shots,"hits":world.hits,"kills":world.kills,"damage":world.damage_total,"broken":world.broken,"events":counts,"first":first,"active_ai_seconds":active_seconds,"blocked_ai_seconds":blocked_seconds,"trench_unique_units":[trench[0].size(),trench[1].size()],"hill_unique_units":[hill[0].size(),hill[1].size()],"point_unique_units":[entered[0].size(),entered[1].size()],"step_ms":{"p50":percentile(timings,.5),"p95":percentile(timings,.95),"p99":percentile(timings,.99),"max":timings[-1] if not timings.is_empty() else 0},"slowest_steps":slowest,"source_hashes":source_hashes,"director_supported":director_supported}
	if director_supported:report.director=world.campaign_director.diagnostics();world.campaign_director.cancel()
	var output=FileAccess.open(directory+"/summary.json",FileAccess.WRITE);output.store_string(JSON.stringify(serial(report),"\t"));output.close()
	events.close();samples.close()
	print("AI_ROUND_COMPLETE "+JSON.stringify(serial(report)))
	quit(0 if reason!="wall-timeout" else 3)
