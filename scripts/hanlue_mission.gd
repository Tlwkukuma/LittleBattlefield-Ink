extends RefCounted
## H01 outcome rules only. No spawning, movement, damage, target knowledge or ammo.
## campaign.phase remains playing until finish(); stage is the mission's own clock.
const SAMPLE_SECONDS=0.2
var world_ref: WeakRef
var active=false
var stage="concealed"
var elapsed=0.0
var stage_elapsed=0.0
var config: Dictionary={}
var extraction_zones: Array=[]
var escape_zones: Array=[]
var blue: Array=[]
var red: Array=[]
var convoy: Array=[]
var extracted: Dictionary={}
var escaped: Dictionary={}
var disrupted: Dictionary={}
var extraction_since: Dictionary={}
var sample_clock=0.0
var fired_early=false
var trigger=""
var result: Dictionary={}

func configure(world) -> bool:
	world_ref=weakref(world);active=false;stage="concealed";elapsed=0.0;stage_elapsed=0.0
	config=world.plan.get("hanlueMission",{}).duplicate(true)
	blue.clear();red.clear();convoy.clear();extracted.clear();escaped.clear();disrupted.clear()
	extraction_since.clear();extraction_zones.clear();escape_zones.clear();result.clear()
	sample_clock=0.0;fired_early=false;trigger=""
	if config.is_empty():return false
	for unit in world.units:
		if int(unit.team)==0:blue.append(unit)
		elif int(unit.team)==1:red.append(unit)
	for vehicle in world.vehicles:
		if str(vehicle.get("source_id","")) in config.get("convoyIds",[]):convoy.append(vehicle)
	for source in config.get("extractionZones",[]):extraction_zones.append(make_zone(world,source))
	for source in config.get("escapeZones",[]):escape_zones.append(make_zone(world,source))
	# A malformed authored mission fails explicitly instead of waiting forever.
	active=true
	if blue.is_empty() or convoy.is_empty() or extraction_zones.is_empty() or escape_zones.is_empty() or convoy.size()!=config.get("convoyIds",[]).size():
		finish("invalid_setup","关卡配置不完整，请返回菜单重载");return false
	return true

func make_zone(world,source: Dictionary) -> Dictionary:
	return {"id":str(source.get("id","zone")),"position":world.catalog.position(source,world.plan),"radius":maxf(.5,float(source.get("r",160))/40.0)}

func is_concealed() -> bool:
	return active and stage in ["concealed","convoy"]

func begin_ambush(cause: String="signal") -> bool:
	if not is_concealed():return false
	fired_early=stage=="concealed" or cause!="signal"
	trigger=cause
	set_stage("ambush","伏击开始 · 完成打击后向南北撤离点转移")
	return true

func observe_event(event: Dictionary) -> void:
	if not active or stage=="result" or not trigger.is_empty():return
	var kind=str(event.get("type",""))
	if kind in ["shot","grenade_throw"]:
		var unit: Dictionary=event.get("unit",{})
		if not unit.is_empty() and int(unit.get("team",-1))==0:expose("early_fire")
	elif kind=="damage" and float(event.get("amount",0))>0:
		# Melee has no unit-bearing swing event. Actual attributed damage is
		# sufficient evidence of an attack, without synthesizing a fake shot.
		var source=int(event.get("source_id",-1))
		for unit in blue:
			if int(unit.id)==source:expose("early_attack");return

func expose(cause: String) -> void:
	if stage!="withdrawal":begin_ambush(cause);return
	# A first real attack during an early retreat reveals the force, but must
	# not restart the fight clock or grant another withdrawal window.
	trigger=cause;fired_early=true

func request_withdrawal() -> bool:
	if not active or stage in ["withdrawal","result"]:return false
	set_stage("withdrawal","开始撤离 · 存活人员须实际到达南北撤离点")
	return true

func tick(delta: float) -> void:
	if not active or stage=="result":return
	var world=world_ref.get_ref()
	if world==null or world.campaign.phase!="playing":return
	elapsed+=maxf(0,delta);stage_elapsed+=maxf(0,delta);sample_clock-=maxf(0,delta)
	if sample_clock<=0:
		sample_clock=SAMPLE_SECONDS
		measure_convoy()
		if stage=="withdrawal":measure_extraction()
		if living_blue()==0:
			finish("no_survivors","无存活人员撤出");return
		if stage=="withdrawal" and remaining_blue()==0:
			finish("withdrawn","所有存活人员已撤出");return
		if stage in ["concealed","convoy"] and escaped.size()==convoy.size():
			finish("missed_convoy","车队已离开，未发起伏击");return
	if stage=="concealed" and stage_elapsed>=seconds("prepareSeconds",12):
		set_stage("convoy","车队进入 · 等待合适时机发出伏击信号")
	elif stage=="convoy" and stage_elapsed>=seconds("convoyDeadlineSeconds",150):
		finish("missed_window","未在时限内发起伏击，任务未达成")
	elif stage=="ambush" and stage_elapsed>=seconds("combatSeconds",180):
		set_stage("withdrawal","转移时限已到 · 立即向南北撤离点撤离")
	elif stage=="withdrawal" and stage_elapsed>=seconds("withdrawalSeconds",90):
		finish("withdrawal_timeout","撤离窗口结束，未到达者不计入撤出人数")

func seconds(key: String,fallback: float) -> float:
	return maxf(1,float(config.get(key,fallback)))

func measure_convoy() -> void:
	if stage=="concealed":return
	for vehicle in convoy:
		var id=int(vehicle.id)
		if escaped.has(id):continue
		var hull=float(vehicle.get("health",0))/maxf(1,float(vehicle.get("max_health",1)))
		var gear=float(vehicle.get("track_health",1))/maxf(1,float(vehicle.get("max_track",1)))
		# Read the same real durability as driving and damage. A queue or an AI
		# pause is never credited as disabling a truck; severe gear damage still
		# allows the engine's slow movement and does not claim immobilization.
		if bool(vehicle.get("destroyed",false)) or hull<=.65 or (float(vehicle.get("max_track",0))>0 and gear<=.35):
			disrupted[id]=true
		if bool(vehicle.get("destroyed",false)):continue
		if zone_index(vehicle.position,escape_zones)>=0:
			escaped[id]=true;vehicle.hanlue_escaped=true
			# The final escaped truck can end the mission this same tick, so
			# retire its real crew now rather than relying on a later vehicle step.
			var world=world_ref.get_ref()
			if world.hanlue_transport!=null:world.hanlue_transport.retire_escaped(vehicle)
			world.index_vehicle(vehicle)
			# A damaged vehicle which subsequently escapes is not a blocked one.
			disrupted.erase(id)

func measure_extraction() -> void:
	var world=world_ref.get_ref()
	for unit in blue:
		var id=int(unit.id)
		if extracted.has(id) or not bool(unit.alive):continue
		var grounded=absf(float(unit.elevation)-float(world.terrain.height(unit.position)))<=1.3
		var in_zone=zone_index(unit.position,extraction_zones)>=0
		if not in_zone or not grounded or int(unit.get("mounted",-1))>=0 or not unit.get("vault",{}).is_empty() or not unit.get("ladder",{}).is_empty():
			extraction_since.erase(id);continue
		if not extraction_since.has(id):extraction_since[id]=elapsed
		if elapsed-float(extraction_since[id])<1.0:continue
		# This is a living person reaching a real exit. Preserve health, life,
		# weapons and finite inventory; the shared world retires its activity.
		extracted[id]={"at":elapsed,"health":float(unit.health),"position":unit.position}
		world.retire_mission_unit(unit,"extracted")

func extraction_goal(unit: Dictionary) -> Vector2:
	var best=Vector2.INF;var distance=INF
	for zone in extraction_zones:
		var d: float=Vector2(unit.position).distance_squared_to(zone.position)
		if d<distance:distance=d;best=zone.position
	return best

static func zone_index(at: Vector2,zones: Array) -> int:
	for i in range(zones.size()):
		if at.distance_squared_to(zones[i].position)<=float(zones[i].radius)*float(zones[i].radius):return i
	return -1

func living_blue() -> int:
	var count=0
	for unit in blue:
		if bool(unit.alive):count+=1
	return count

func remaining_blue() -> int:
	var count=0
	for unit in blue:
		if bool(unit.alive) and not extracted.has(int(unit.id)):count+=1
	return count

func enemy_losses() -> int:
	var count=0
	for unit in red:
		if not bool(unit.alive):count+=1
	return count

func objectives() -> Dictionary:
	var block_required=maxi(1,int(config.get("disruptedRequired",2)))
	var strike_required=maxi(1,int(config.get("strikeRequired",4)))
	var extract_required=maxi(1,int(config.get("extractedRequired",4)))
	var strike=enemy_losses()+disrupted.size()*2
	return {"disrupted":disrupted.size(),"disrupted_required":block_required,"strike":strike,"strike_required":strike_required,
		"extracted":extracted.size(),"extracted_required":extract_required,
		"block_complete":disrupted.size()>=block_required,"strike_complete":strike>=strike_required,"extraction_complete":extracted.size()>=extract_required}

func summary() -> Dictionary:
	var value=objectives()
	value.merge({"id":"H01","stage":stage,"elapsed":elapsed,"stage_elapsed":stage_elapsed,"fired_early":fired_early,"trigger":trigger,
		"blue_total":blue.size(),"red_total":red.size(),"convoy_total":convoy.size(),"living":living_blue(),"remaining":remaining_blue(),
		"enemy_losses":enemy_losses(),"escaped":escaped.size(),"result":result.duplicate(true)})
	return value

func objective_text() -> String:
	var value=objectives()
	match stage:
		"concealed":return "隐蔽准备 · 等待车队，按伏击信号开始"
		"convoy":return "车队进入 · 发出伏击信号或提前开火"
		"ambush":return "重创车队 %d/%d · 打击 %d/%d · 可随时下令撤离"%[value.disrupted,value.disrupted_required,value.strike,value.strike_required]
		"withdrawal":
			var world=world_ref.get_ref();var goal=extraction_goal(world.player);var direction="北" if goal.y<world.player.position.y else "南"
			return "撤出 %d/%d · %s侧绿圈 %d m · 剩余 %d 秒"%[value.extracted,value.extracted_required,direction,int(world.player.position.distance_to(goal)),ceili(maxf(0,seconds("withdrawalSeconds",90)-stage_elapsed))]
		_:return str(result.get("description","任务结束"))

func set_stage(next: String,notice: String) -> void:
	stage=next;stage_elapsed=0.0;sample_clock=0.0
	var world=world_ref.get_ref()
	world.event.emit({"type":"hanlue_stage_changed","stage":stage})
	world.event.emit({"type":"notice","text":notice})

func finish(code: String,description: String) -> void:
	if stage=="result":return
	var value=objectives()
	var won=bool(value.block_complete) and bool(value.strike_complete) and bool(value.extraction_complete)
	if code in ["invalid_setup","missed_convoy","missed_window","no_survivors"]:won=false
	var detail="重创车队 %d/%d · 打击 %d/%d · 撤出 %d/%d"%[value.disrupted,value.disrupted_required,value.strike,value.strike_required,value.extracted,value.extracted_required]
	result={"code":code,"won":won,"description":description,"objectives":value.duplicate(true),"elapsed":elapsed}
	stage="result";active=false
	var world=world_ref.get_ref()
	world.campaign.finish("won" if won else "lost",("伏击完成 · " if won else "任务未达成 · ")+description+" · "+detail)
