extends SceneTree
## Authored route and candidate math only; no world.step or geometry simulation.
const AI=preload("res://scripts/campaign_ai.gd")
const Mission=preload("res://scripts/campaign_asset_mission.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():
	var ai=AI.new();ai.routes=[[[]],[]]
	var world={"topology_revision":0,"campaign":{"points":[]},"plan":{"godot3d":{}}}
	var unit={"team":0,"position":Vector2.ZERO,"spawn":Vector2.ZERO,"elevation":0.0,"campaign_slot":0,"ai_order":{"goal":Vector2(9,4),"route_index":0}}
	check(ai.objective_goal(world,unit)==Vector2(9,4),"empty authored route falls back to actual mission destination")
	check(unit.ai_route_done,"empty route is complete without indexing a missing waypoint")
	ai.routes[0]=[[Vector2(4,0)]];unit.ai_route_done=false
	check(ai.objective_goal(world,unit)==Vector2(4,0),"single-waypoint route remains usable")
	var vehicle={"position":Vector2(0,10),"angle":-PI*.5}
	var road=[Vector2(0,8),Vector2(0,4)]
	var original=Mission.begin(world,vehicle,road,Vector2.ZERO)
	check(original.choices.size()==10,"five fixed candidate posts retain bounded road combinations")
	for candidate in original.choices:check(candidate.goal.x<0,"legacy orchard posts stay west of frontage")
	world.plan.godot3d.campaign_chapter=2
	var generic=Mission.begin(world,vehicle,road,Vector2.ZERO)
	check(generic.choices.size()==original.choices.size(),"generic orientation does not expand candidate budget")
	for candidate in generic.choices:check(candidate.goal.y>0,"southern approach parks before frontage instead of always west")
	vehicle.position=Vector2.ZERO
	var coincident=Mission.begin(world,vehicle,road,Vector2.ZERO)
	for candidate in coincident.choices:check(Vector2(candidate.goal).is_finite(),"coincident frontage uses finite vehicle heading")
	print("AI_ROUTE_EDGE checks=%d failures=%d; candidate math only"%[checks,failures])
	quit(0 if failures==0 else 1)
