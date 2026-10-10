extends SceneTree
## Pure synthetic rule fixtures only: no scene, world.step(), AI, bullets or movement.
## Prepared for the parent to run during the authorized consolidated engine check.
const Mission=preload("res://scripts/hanlue_mission.gd")

class FakeCatalog extends RefCounted:
	func position(source: Dictionary,_plan: Dictionary) -> Vector2:
		return Vector2(float(source.x),float(source.y))/40.0

class FakeTerrain extends RefCounted:
	func height(_at: Vector2) -> float:return 0.0

class FakeCampaign extends RefCounted:
	var phase="playing"
	var reason=""
	func finish(value: String,text: String) -> void:phase=value;reason=text

class FakeWorld extends RefCounted:
	signal event(data: Dictionary)
	var hanlue_transport=null
	var campaign=FakeCampaign.new()
	var catalog=FakeCatalog.new()
	var terrain=FakeTerrain.new()
	var units: Array=[]
	var vehicles: Array=[]
	var plan={"hanlueMission":{"convoyIds":["a","b","c"],"extractionZones":[{"id":"exit","x":4000,"y":0,"r":200}],
		"escapeZones":[{"id":"escape","x":10000,"y":0,"r":100}]}}
	func _init() -> void:
		for i in range(24):
			units.append({"id":i,"team":0 if i<12 else 1,"alive":true,"health":100.0,"position":Vector2.ZERO,
				"elevation":0.0,"mounted":-1,"vault":{},"ladder":{}})
		for i in range(3):
			vehicles.append({"id":i,"source_id":["a","b","c"][i],"position":Vector2(10+i*5,0),
				"health":100.0,"max_health":100.0,"track_health":100.0,"max_track":100.0,"destroyed":false})
	func index_vehicle(_vehicle: Dictionary) -> void:pass
	func retire_mission_unit(unit: Dictionary,reason: String) -> void:
		unit["hanlue_"+reason]=true

var checks=0
var failures: Array=[]

func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:failures.append(label);push_error(label)

func setup(world):
	var mission=Mission.new()
	check(mission.configure(world),"valid finite synthetic fixture configures")
	return mission

func reach_exit(world) -> void:
	for i in range(12):world.units[i].position=Vector2(100,0)

func dwell(mission) -> void:
	for i in range(5):mission.tick(.25)

func _initialize() -> void:
	# Early voluntary exit resolves without pretending that the objective passed.
	var world=FakeWorld.new();var mission=setup(world)
	check(mission.request_withdrawal(),"withdrawal allowed during concealment")
	reach_exit(world);dwell(mission)
	check(world.campaign.phase=="lost" and mission.result.code=="withdrawn","early withdrawal is an explicit unsuccessful result")
	check(mission.extracted.size()==12 and world.units.all(func(u):return u.alive),"retirement preserves every real life flag")
	# Waiting for a physically departed convoy has a terminal result.
	world=FakeWorld.new();mission=setup(world);mission.tick(12)
	check(mission.stage=="convoy" and world.campaign.phase=="playing","mission stages do not overwrite campaign playing phase")
	for v in world.vehicles:v.position=Vector2(250,0)
	mission.tick(.25)
	check(world.campaign.phase=="lost" and mission.result.code=="missed_convoy","departed finite convoy ends concealment")
	world=FakeWorld.new();mission=setup(world);mission.tick(12);mission.tick(150)
	check(mission.result.code=="missed_window","stalled convoy cannot make no-signal branch infinite")
	# Real event payloads distinguish weapon input from an actual emitted attack.
	world=FakeWorld.new();mission=setup(world)
	mission.observe_event({"type":"shot","unit":world.units[0]})
	check(mission.stage=="ambush" and mission.fired_early,"actual premature shot starts combat")
	check(not mission.begin_ambush(),"ambush cannot be restarted")
	world=FakeWorld.new();mission=setup(world)
	mission.observe_event({"type":"damage","source_id":0,"amount":5.0,"unit":world.units[12]})
	check(mission.stage=="ambush","attributed melee damage cannot remain concealed")
	world=FakeWorld.new();mission=setup(world);mission.request_withdrawal();mission.tick(1)
	mission.observe_event({"type":"shot","unit":world.units[0]})
	check(mission.stage=="withdrawal" and mission.stage_elapsed==1 and mission.trigger=="early_fire","first attack during retreat reveals without resetting withdrawal")
	# Effective damage and extraction win with all opposing soldiers still alive.
	world=FakeWorld.new();mission=setup(world);mission.begin_ambush()
	world.vehicles[0].health=65.0;world.vehicles[1].track_health=35.0
	mission.tick(.25);mission.request_withdrawal();reach_exit(world)
	mission.tick(.25)
	check(mission.extracted.is_empty(),"touching an exit without the full dwell does not extract")
	for i in range(4):mission.tick(.25)
	check(world.campaign.phase=="won" and mission.remaining_blue()==0,"last actual extraction resolves the mission")
	check(mission.enemy_losses()==0 and world.units.all(func(u):return u.alive),"success never requires enemy annihilation or fake deaths")
	# One disrupted endpoint is insufficient even with extreme synthetic losses.
	world=FakeWorld.new();mission=setup(world);mission.begin_ambush();world.vehicles[0].health=50.0
	for i in range(12,24):world.units[i].alive=false
	mission.tick(.25);mission.request_withdrawal();reach_exit(world);dwell(mission)
	check(world.campaign.phase=="lost" and not mission.result.objectives.block_complete,"one-truck branch does not bypass obstruction objective")
	# An unreachable exit has a finite failure, with no fabricated arrivals.
	world=FakeWorld.new();mission=setup(world);mission.request_withdrawal();mission.tick(90)
	check(mission.result.code=="withdrawal_timeout" and mission.extracted.is_empty(),"blocked withdrawal does not softlock or fabricate extraction")
	# The same object is safely reusable with the next freshly constructed world.
	world=FakeWorld.new();check(mission.configure(world),"fresh mission reload configures")
	check(mission.stage=="concealed" and mission.result.is_empty() and mission.extracted.is_empty(),"reload clears old outcome and extraction state")
	print("HANLUE_RULE_CONTRACT checks=%d failures=%d (synthetic rules only)"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
