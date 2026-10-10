extends SceneTree
## Explicit post-round integration probe: real HTTP, frozen world, zero battle steps.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
var world
var director
var stage=0
var deadline=0
var evidence: Array=[]
var submitted=false
var failures=0

func _initialize():
	var catalog=Catalog.new();world=World.new();world.setup(Orchard.plan(catalog),catalog)
	director=world.campaign_director
	if not director.enabled:
		printerr("Live Laya probe requires explicit -- --laya; local mode sends no requests.");quit(2);return
	world.event.connect(func(event):
		if event.type=="ai_decision" or event.type=="ai_mission_applied":evidence.append(event.duplicate(true)))
	Engine.max_fps=30;deadline=Time.get_ticks_msec()+30000

func _process(_delta: float) -> bool:
	if stage>=4:
		finish();return false
	if Time.get_ticks_msec()>deadline:
		failures+=1;finish();return false
	var team=int(stage/2);var policy=stage%2==0
	if not submitted:
		var metadata={"phase":"policy" if policy else "mission","round":1}
		director.teams[team].round=1
		var squad=""
		if not policy:
			# A controlled crowded-assault observation checks raw/model calibration;
			# these are fixture orders only, no unit ever moves or fires.
			for group in director.teams[team].squads.values():group.task="attack:0"
			squad=director.teams[team].squads.keys()[0];metadata.squad_id=squad
		director.commander.submit(team,director.briefing(team,squad),director.policy_questions() if policy else director.mission_questions(),metadata)
		submitted=true
	director.commander.tick(0)
	for result in director.commander.drain_results():
		if result.source!="laya" or result.accepted.is_empty() or not str(result.reason).is_empty():failures+=1
		director.apply_result(result)
		stage+=1;submitted=false
	return false

func finish():
	director.cancel()
	if world.time!=0 or world.shots!=0:failures+=1
	var report={"purpose":"post-round live interface probe; NOT a battle or fourth round","simulation_time":world.time,"shots":world.shots,"completed_requests":stage,"failures":failures,"diagnostics":director.diagnostics(),"events":evidence}
	var file=FileAccess.open("res://qa/ai-review/post-round-connection.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("LIVE_CONNECTION requests=%d failures=%d simulation_time=%.1f shots=%d"%[stage,failures,world.time,world.shots])
	quit(0 if failures==0 else 1)
