extends SceneTree
## Actual world initialization and placement only. No step(), AI update or combat ticks.
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Placement=preload("res://scripts/campaign_placement.gd")
var checks=0
var failures=0
var results=[]

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)

func coordinates(at: Vector2) -> Array:return [at.x,at.y]

func _initialize():call_deferred("run")

func run():
	var catalog=Catalog.new();var original=JSON.stringify(catalog.scenes)
	var orchard=preload("res://scripts/orchard_level.gd").plan(catalog)
	var orchard_before=JSON.stringify(orchard)
	var total=0
	for number in range(1,11):
		var source: Dictionary=catalog.scenes[number-1]
		var plan=Chapters.plan(catalog,number)
		for key in ["world","instances","looseSegments","trees","vehicles"]:
			check(plan[key]==source[key],"%02d original %s"%[number,key])
		check(plan.controlPoints[0].x==source.controlPoints[0].x and plan.controlPoints[0].y==source.controlPoints[0].y,"%02d source objective center"%number)
		for side in ["blue","red"]:
			check(plan.deployment[side].spawnPoints==source.deployment[side].spawnPoints,"%02d %s every original anchor"%[number,side])
			for key in ["initialCount","maxActive","totalForce"]:check(plan.deployment[side][key]==source.deployment[side][key],"%02d %s %s"%[number,side,key])
		var world=World.new();var compiled=world.setup(plan,catalog)
		check(world.setup_ok and compiled.setup_ok and world.campaign.phase=="playing","%02d initialization succeeds"%number)
		check(world.placement_report.ok and world.last_spawn_failure.is_empty(),"%02d explicit success"%number)
		if not world.setup_ok:
			printerr(JSON.stringify(world.last_spawn_failure));continue
		check(world.bounds==Vector2(source.world.w,source.world.h)/80.0,"%02d real source bounds"%number)
		var expected=[int(source.deployment.blue.initialCount),int(source.deployment.red.initialCount)]
		check(world.campaign.active_counts()==expected and world.campaign.deployed==expected,"%02d exact initial roster counts"%number)
		check(world.placement_report.actual_counts==expected,"%02d report counts"%number)
		var detail={"chapter":number,"counts":expected,"anchors":[source.deployment.blue.spawnPoints.size(),source.deployment.red.spawnPoints.size()],"bounds":coordinates(world.bounds),"corrections":[]}
		for unit in world.units:
			var team=int(unit.team);var slot=int(unit.campaign_slot)
			var spec: Dictionary=source.deployment.player if team==0 and slot==0 else source.units["blue" if team==0 else "red"][slot-1 if team==0 else slot]
			var origin=catalog.position(spec,source)
			var record: Dictionary=unit.spawn_placement
			check(unit.campaign_source_id==str(spec.get("id","player")),"%02d identity %d"%[number,unit.id])
			check(unit.campaign_source.x==spec.x and unit.campaign_source.y==spec.y,"%02d retained source coordinates %d"%[number,unit.id])
			check(unit.facing.is_equal_approx(Vector2.from_angle(float(spec.get("angle",0)))),"%02d original facing %d"%[number,unit.id])
			check(unit.position.is_finite() and absf(unit.position.x)+Placement.RADIUS<=world.bounds.x and absf(unit.position.y)+Placement.RADIUS<=world.bounds.y,"%02d in bounds %d"%[number,unit.id])
			check(not world.blocked(unit.position,Placement.RADIUS,Placement.HEIGHT,-1,unit.elevation),"%02d real collision clear %d"%[number,unit.id])
			check(world.terrain.grade(unit.position)<=Placement.MAX_GRADE,"%02d slope clear %d"%[number,unit.id])
			check(unit.position.distance_to(origin)<=Placement.MAX_DISTANCE+.00001,"%02d bounded correction %d"%[number,unit.id])
			check(record.source_position==origin and record.position==unit.position,"%02d placement report matches body %d"%[number,unit.id])
			if record.reason=="source_exact":check(unit.position==origin,"%02d exact source placement %d"%[number,unit.id])
			else:
				check(unit.position!=origin and record.reason in ["outside_world_bounds","terrain_grade","physical_collision","occupied_by_unit","occupied_by_deployment"],"%02d justified correction %d"%[number,unit.id])
				detail.corrections.append({"source_id":unit.campaign_source_id,"team":team,"source_pixels":[spec.x,spec.y],"source_m":coordinates(origin),"actual_m":coordinates(unit.position),"distance_m":unit.position.distance_to(origin),"reason":record.reason,"attempts":record.attempts})
			for other in world.units:
				if int(other.id)<=int(unit.id):continue
				check(unit.position.distance_to(other.position)>=Placement.SPACING-.00001,"%02d no body overlap %d/%d"%[number,unit.id,other.id])
		check(is_zero_approx(world.time) and world.simulation_tick==0 and world.shots==0,"%02d zero simulation"%number)
		if number==1:
			check(detail.anchors==[10,10] and world.bounds==Vector2(41.25,26.25),"first source map and ten anchors per side")
			check(world.player.position==catalog.position(source.deployment.player,source),"first source player actual exact position")
			check(not plan.godot3d.get("battlefield_border",false) and not plan.godot3d.has("treeMoves"),"no orchard terrain overlay")
			check(not preload("res://scripts/campaign_plan.gd").mandatory_approach(plan),"source first chapter has no missing orchard trench requirement")
			verify_failed_reinforcement(world)
		total+=world.units.size();results.append(detail)
		print("SOURCE_PLACEMENT "+JSON.stringify(detail))
	check(total==680,"all 680 original active actors retained")
	check(JSON.stringify(catalog.scenes)==original,"immutable source catalog")
	check(JSON.stringify(preload("res://scripts/orchard_level.gd").plan(catalog))==orchard_before,"LAN orchard plan unchanged")
	verify_failed_initialization(catalog)
	var file=FileAccess.open("res://qa/campaign_source_placement_results.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"simulation_ticks":0,"max_correction_m":Placement.MAX_DISTANCE,"chapters":results},"\t"));file.close()
	print("campaign_source_placement_contract: %d checks, %d failures; zero simulation ticks"%[checks,failures])
	quit(1 if failures else 0)

func verify_failed_reinforcement(world):
	var unit: Dictionary=world.units[1]
	unit.alive=false;unit.death_age=1.0
	var before=unit.duplicate(true)
	var reserves=world.campaign.reserves.duplicate();var deployed=world.campaign.deployed.duplicate();var cursor=world.campaign.replacement_cursor.duplicate()
	var anchors: Array=world.plan.deployment.blue.spawnPoints
	world.plan.deployment.blue.spawnPoints=[]
	var reinforced=world.campaign.reinforce(world,0,1)
	check(reinforced.is_empty(),"failed reinforcement returns no unit")
	check(unit==before,"failed reinforcement leaves complete dead actor unchanged")
	check(world.campaign.reserves==reserves and world.campaign.deployed==deployed and world.campaign.replacement_cursor==cursor,"failed reinforcement consumes no force or cohort")
	check(world.campaign.last_spawn_failure.reason=="missing_spawn_anchors" and world.last_spawn_failure==world.campaign.last_spawn_failure,"failed reinforcement is reported")
	world.plan.deployment.blue.spawnPoints=anchors
	unit.facing=Vector2.LEFT
	reinforced=world.campaign.reinforce(world,0,1)
	check(not reinforced.is_empty() and reinforced.id==before.id,"retry revives same source identity")
	check(unit.campaign_source==before.campaign_source and unit.campaign_source_id==before.campaign_source_id,"reinforcement preserves original soldier record")
	check(unit.facing.is_equal_approx(Vector2.from_angle(float(before.campaign_source.get("angle",0)))),"reinforcement restores original source facing")
	check(world.campaign.reserves[0]==reserves[0]-1 and world.campaign.deployed[0]==deployed[0]+1 and world.campaign.replacement_cursor[0]==cursor[0]+1,"successful retry consumes exactly one reserve")
	var report: Dictionary=unit.spawn_placement
	check(report.get("stage","")=="reinforcement" and report.get("position",Vector2.INF)==unit.position,"reinforcement records actual placement")
	if report.has("anchor_index") and int(report.anchor_index)>=0:
		var anchor: Dictionary=anchors[int(report.anchor_index)]
		check(report.anchor_id==anchor.id and report.anchor_source==anchor,"reinforcement reports chosen original anchor")
		check(unit.position.distance_to(world.catalog.position(anchor,world.plan))<=Placement.MAX_DISTANCE+.00001,"reinforcement is bounded from original anchor")
	else:check(false,"ordinary reinforcement uses source anchor")
	check(world.last_spawn_failure.is_empty() and world.campaign.last_spawn_failure.is_empty(),"successful retry clears stale failure")

func verify_failed_initialization(catalog):
	var broken=Chapters.plan(catalog,1)
	broken.deployment.player.x=100000000
	var world=World.new();var compiled=world.setup(broken,catalog)
	check(not compiled.setup_ok and not world.setup_ok,"unplaceable initialization explicitly fails")
	check(world.campaign.phase=="placement_failed" and not world.campaign.reason.is_empty(),"loading rollback failure phase/reason")
	check(not world.campaign.active and not world.ai_enabled and world.units.is_empty() and world.player.is_empty(),"failed initialization commits no partial roster")
	check(not world.last_spawn_failure.is_empty() and not world.placement_report.failures.is_empty(),"failed initialization diagnostic")
	check(world.campaign.deployed==[0,0] and world.campaign.replacement_cursor==[0,0],"failed initialization spends no force")
	check(not world.campaign.clear_position(world,Vector2(100000000,0),0,false).is_finite(),"legacy non-strict API cannot return an illegal fallback")
	check(is_zero_approx(world.time) and world.simulation_tick==0,"failure never simulates")
	var invalid=Chapters.plan(catalog,1);invalid.deployment.red.initialCount=31
	compiled=world.setup(invalid,catalog)
	check(not compiled.setup_ok and world.units.is_empty(),"invalid force mismatch never silently shrinks or repeats roster")
