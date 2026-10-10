extends SceneTree
## Source-coordinate/route-choice state only. No World, geometry or battle steps.
const AI=preload("res://scripts/campaign_ai.gd")
const Plan=preload("res://scripts/campaign_plan.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/original/scenes.json"))
	var chapters: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/chapters.json"))
	var scenes={}
	for scene in source.scenes:scenes[scene.id]=scene
	var legacy={"godot3d":{"campaign_chapter":1}}
	check(Plan.mandatory_approach(legacy),"orchard keeps its authored mandatory approach")
	for chapter in chapters.chapters:
		if int(chapter.id)<=1:continue
		var scene: Dictionary=scenes[chapter.sourceSceneId];var stage: Dictionary=chapter.stages[0]
		var plan={"godot3d":{"campaign_chapter":chapter.id,"campaign_tactics":stage.tactics}}
		check(not Plan.mandatory_approach(plan),"derived spawn anchors are not mandatory tactical waypoints: "+str(chapter.id))
		var ai=AI.new();ai.routes=[[],[]]
		for route in stage.aiRoutes.blue:
			var points=[]
			for at in route:points.append(Vector2(float(at[0]),float(at[1]))/40.0)
			ai.routes[0].append(points)
		var goal=Vector2(float(stage.point.x),float(stage.point.y))/40.0
		var world={"campaign":{"points":[]}}
		for raw in scene.units.blue:
			for index in range(ai.routes[0].size()):
				var unit={"team":0,"position":Vector2(float(raw.x),float(raw.y))/40.0,"spawn":Vector2.ZERO,"elevation":0.0,"campaign_slot":0,"ai_order":{"goal":goal,"route_index":index,"mandatory_route":Plan.mandatory_approach(plan)}}
				var chosen=ai.objective_goal(world,unit)
				check(chosen.distance_to(goal)<=unit.position.distance_to(goal)+3.001,"derived entry does not march back to a distant spawn: %s/%s/%s"%[chapter.id,raw.id,index])
		plan.godot3d.campaign_tactics={"mandatory_approach":true}
		check(Plan.mandatory_approach(plan),"future explicitly authored approach can opt in")
	print("DERIVED_TACTICAL_ROUTES checks=%d failures=%d; source-coordinate state only"%[checks,failures])
	quit(0 if failures==0 else 1)
