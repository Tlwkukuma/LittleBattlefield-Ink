extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Level=preload("res://scripts/orchard_level.gd")
var failures=0
var checks=0

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize() -> void:
	var catalog=Catalog.new();var plan=Level.plan(catalog);var world=World.new();world.setup(plan,catalog)
	print("campaign initial graph build ms=",world.campaign_ai.last_rebuild_ms," nodes=",world.campaign_ai.graph.get_point_count())
	var destination: Vector2=world.campaign.points[0].position
	for unit in world.units:
		check(not world.blocked(unit.position,.30,1.95,-1,unit.elevation),"unit "+str(unit.id)+" initial clearance")
		var path=world.campaign_ai.path_between(unit.position,destination)
		check(not path.is_empty() and path[-1].distance_to(destination)<4.5,"unit "+str(unit.id)+" reaches B ring")
	for team in range(2):
		var key="blue" if team==0 else "red"
		for index in range(world.campaign_ai.routes[team].size()):
			var route: Array=world.campaign_ai.routes[team][index]
			for i in range(route.size()):
				var raw=world.catalog.original_point(route[i],plan)
				check(not world.blocked(route[i],.30,1.95,-1,world.terrain.height(route[i])),"%s route %s waypoint %s %s clear"%[key,index,i,raw])
				if i==0:continue
				var path=world.campaign_ai.path_between(route[i-1],route[i])
				check(not path.is_empty() and path[-1].distance_to(route[i])<1.4,"%s route %s segment %s to %s reaches"%[key,index,i,raw])
		for spawn in plan.deployment[key].spawnPoints:
			var at=world.catalog.position(spawn,plan);var path=world.campaign_ai.path_between(at,destination)
			check(not path.is_empty() and path[-1].distance_to(destination)<4.5,"%s reinforcement %s reaches B"%[key,spawn.id])
	# Destruction refresh is local; compare against a fresh graph to audit boundary edges.
	var wall: Dictionary={}
	for object in world.objects:
		if object.component_id.begins_with("wall.") and (wall.is_empty() or object.size.x>wall.size.x):wall=object
	world.damage_cell(wall,0,0,wall.max_hp+1,wall.position,false);world.rebuild_navigation()
	print("campaign longest-wall incremental ms=",world.campaign_ai.last_rebuild_ms," cells=",world.campaign_ai.last_rebuild_cells)
	check(world.campaign_ai.last_rebuild_cells<=6,"wall update obeys per-step budget")
	check(world.navigation_dirty,"unfinished refresh stays scheduled")
	for cell in world.campaign_ai.dirty_cells:
		var id=world.campaign_ai.cell_id(cell)
		if world.campaign_ai.graph.has_point(id):check(world.campaign_ai.graph.is_point_disabled(id),"pending node is unavailable to paths")
	var jeep: Dictionary=world.vehicles[0];var old_position: Vector2=jeep.position
	jeep.position+=Vector2(-7,0);world.campaign_ai.invalidate_vehicle(jeep);world.rebuild_navigation()
	print("campaign vehicle incremental ms=",world.campaign_ai.last_rebuild_ms," cells=",world.campaign_ai.last_rebuild_cells)
	check(jeep.navigation_position!=old_position,"moving jeep invalidates old and new positions")
	var batches=0
	while world.navigation_dirty and batches<100:
		world.rebuild_navigation();batches+=1
	check(not world.navigation_dirty and batches>0,"budgeted refresh drains without battle steps")
	var signature=graph_signature(world.campaign_ai)
	world.campaign_ai.graph_ready=false;world.rebuild_navigation()
	check(signature==graph_signature(world.campaign_ai),"incremental graph equals full rebuild after wall and vehicle change")
	print("campaign_level_navigation_contract: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

func graph_signature(ai) -> Dictionary:
	var result={}
	for id in ai.graph.get_point_ids():
		var connections=ai.graph.get_point_connections(id);connections.sort();result[id]=connections
	return result
