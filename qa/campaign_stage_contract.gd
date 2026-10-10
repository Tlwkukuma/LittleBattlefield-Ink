extends SceneTree
## Direct rule-state contracts, not gameplay simulation.
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	var catalog=Catalog.new();var world=World.new();world.setup(draft_plan(catalog,2),catalog)
	var rules=world.campaign
	check(rules.points.size()==1 and rules.stage_index==0,"exactly one initial objective")
	var first=rules.points[0].id
	var previous_routes=world.campaign_ai.routes.duplicate(true)
	for unit in world.units:unit.ai_route_done=true;unit.ai_order={"goal":Vector2.ZERO};unit.path=[Vector2.ZERO]
	rules.points[0].owner=0;rules.points[0].progress=1.0;rules.advance_mission(world,.1)
	check(rules.stage_index==1 and rules.points.size()==1 and rules.points[0].id!=first,"capture activates next real point")
	check(world.plan.controlPoints[0].id==rules.points[0].id,"plan and rules share current objective")
	check(world.campaign_ai.routes!=previous_routes,"stage changes authored routes")
	check(world.campaign_ai.capture_cells.size()==1 and not world.campaign_ai.capture_cells[0].is_empty(),"capture cells refreshed")
	check(world.units.all(func(u):return not u.ai_route_done),"route completion invalidated")
	check(world.units.all(func(u):return u.path.is_empty()),"stale paths cleared")
	check(rules.phase=="playing","intermediate stage is not victory")
	rules.points[0].owner=0;rules.points[0].progress=1.0;rules.advance_mission(world,.1)
	check(rules.phase=="won","last capture completes chapter")
	check(is_zero_approx(world.time),"capture contract never runs combat")
	world.setup(draft_plan(catalog,7),catalog);rules=world.campaign
	rules.points[0].owner=0;rules.points[0].progress=1.0
	rules.advance_mission(world,12.0)
	check(rules.hold_elapsed==12.0 and rules.phase=="playing","hold accumulates while secured")
	rules.points[0].contested=true;rules.advance_mission(world,20.0)
	check(rules.hold_elapsed==12.0 and rules.phase=="playing","contest pauses hold")
	rules.points[0].contested=false;rules.points[0].owner=1;rules.advance_mission(world,1.0)
	check(is_zero_approx(rules.hold_elapsed),"enemy recapture resets hold")
	rules.points[0].owner=0;rules.advance_mission(world,39.0)
	check(rules.phase=="playing","hold does not finish early")
	rules.advance_mission(world,1.0)
	check(rules.phase=="won","full hold completes chapter")
	world.setup(draft_plan(catalog,7),catalog);rules=world.campaign
	for unit in world.units:
		if unit.team==1:unit.alive=false
	rules.reserves[1]=0;rules.tick(0.0)
	check(rules.phase=="won","exhausted enemies do not deadlock hold")
	world.setup(Chapters.plan(catalog,8),catalog);rules=world.campaign
	for unit in world.units:
		if unit.team==0:unit.alive=false
	rules.tick(0.0)
	check(rules.phase=="lost" and rules.reserves[0]>0,"no living ally still defeats despite reserves")
	check(is_zero_approx(world.time),"rule contract never runs combat")
	print("campaign_stage_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func draft_plan(catalog,number: int) -> Dictionary:
	# Exercise dormant general stage mechanics with the archived design fixture;
	# current source-faithful campaign chapters do not use timed hold sequences.
	var result=Chapters.plan(catalog,number)
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/drafts/chapters-designed-20261009-1402.json"))
	result.campaignMission.stages=fixture.chapters[number-1].stages.duplicate(true)
	Chapters.apply_stage(result,0)
	return result
