extends SceneTree
## Pure footprint/resource checks on a frozen entry. No battle/AI/input playback.
const Zone=preload("res://scripts/capture_zone.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	var world=game.world;var plan=game.plan;var catalog=game.catalog;var point: Dictionary=world.campaign.points[0]
	check(Zone.contains(point,point.position,point.elevation),"flag stands inside its capture zone")
	for raw in [[2450,1040],[2700,1100],[2590,1180]]:check(Zone.contains(point,catalog.position(raw,plan),0),"courtyard approach counts "+str(raw))
	for raw in [[2810,1040],[2610,1330],[2350,1100],[2480,720]]:check(not Zone.contains(point,catalog.position(raw,plan),0),"outside courtyard / building excluded "+str(raw))
	check(not Zone.contains(point,point.position,2.8),"rooftop cannot capture from above")
	check(not Zone.contains(point,point.position,-2.5),"underground cannot capture through ground")
	check(not world.blocked(point.position,.31,1.95,-1,point.elevation),"central flag position is reachable")
	var entry=catalog.position([2350,1100],plan)
	for raw in [[2450,1040],[2700,1100],[2590,1180]]:
		check(not world.campaign_ai.path_between(entry,catalog.position(raw,plan)).is_empty(),"entry reaches separate capture positions")
	for o in world.objects:
		if not str(o.owner).begins_with("orchard-objective-crate-"):continue
		check(o.height>=.85 and o.height<=1.05 and not o.hp.is_empty(),"low cover is real destructible geometry")
	var old_floor=catalog.position([2690,1120],plan)
	for feature in plan.world.groundFeatures:
		if feature.id not in preload("res://scripts/orchard_objective.gd").FLOORS:continue
		var polygon=PackedVector2Array()
		for p in feature.points:polygon.append(catalog.position(p,plan))
		check(not Geometry2D.is_point_in_polygon(old_floor,polygon),"old barn floor no longer paints through capture courtyard")
	var flag=game.campaign_ui.objective_views[0].flag
	check(flag.mesh.get_surface_count()==1,"flag plus boundary use one draw surface")
	check(flag.vertices.size()<2200,"flag geometry bounded")
	check(game.stage.find_children("ObjectiveLabelBatch","",true,false).is_empty(),"no giant world-space text label")
	game.armory.hide()
	for value in [-1.0,-.5,0.0,.5,1.0]:
		var snapshot=point.duplicate(true);snapshot.progress=value
		flag.point=snapshot;flag.refresh(game)
		check(is_equal_approx(float(flag.material.get_shader_parameter("control")),absf(value)),"physical flag height follows same capture progress")
		check(flag.material.get_shader_parameter("team_color").is_equal_approx(Zone.color(snapshot)),"physical flag team matches HUD")
	flag.point=point;flag.refresh(game)
	game._process(0)
	for i in range(4):await process_frame
	check(game.campaign_ui.hud_summary.capture.name=="果园指挥所","objective name exposed in normal HUD")
	check(not game.debug_open() and not game.performance_overlay.is_processing(),"diagnostics stay closed")
	check(world.time==0 and world.shots==0,"world stays frozen")
	print("CAPTURE_OBJECTIVE_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"flag_vertices":flag.vertices.size(),"world_time":world.time,"shots":world.shots,"title":root.title}))
	quit(0 if failures==0 else 1)
