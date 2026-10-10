extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const AI=preload("res://scripts/campaign_ai.gd")
var checks=0
var failures=0

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func distance(path: Array) -> float:
	var total=0.0
	for i in range(1,path.size()):total+=path[i-1].distance_to(path[i])
	return total

func _initialize() -> void:
	var catalog=Catalog.new();var plan=catalog.range_plan()
	plan.world={"w":640,"h":480,"seed":42,"groundFeatures":[]};plan.instances=[];plan.trees=[];plan.vehicles=[];plan.emplacements=[];plan.units={"blue":[],"red":[]};plan.deployment.player={"x":160,"y":240}
	plan.looseSegments=[{"id":"nav-wall","componentId":"wall.brick","x1":320,"y1":80,"x2":320,"y2":400,"thickness":24,"godot3d":{"height":2.8}}]
	var world=World.new();world.setup(plan,catalog);world.campaign_ai.configure(world);world.campaign_ai.rebuild()
	var first=world.campaign_ai.path_between(Vector2(-4,0),Vector2(4,0))
	check(not first.is_empty() and first[-1].distance_to(Vector2(4,0))<.1,"route reaches other side via wall end")
	check(not AI.traversable(world,Vector2(-1,0),Vector2(1,0)),"wall blocks direct edge")
	for i in range(1,first.size()):check(AI.traversable(world,first[i-1],first[i]),"route edges body clear")
	var wall: Dictionary=world.objects[0]
	for row in range(wall.rows):
		for col in range(wall.columns):world.damage_cell(wall,col,row,wall.max_hp+1,Vector2(-2,0),false)
	check(world.navigation_dirty and world.topology_revision>0,"destruction invalidates paths")
	world.campaign_ai.rebuild()
	var breached=world.campaign_ai.path_between(Vector2(-4,0),Vector2(4,0))
	check(distance(breached)<distance(first)-2,"breach produces shorter route")
	var ally=world.add_unit(Vector2(-1,0),false);ally.team=0;ally.campaign_slot=1;ally.loadout=["scar-l","p92","army-knife","he-grenade"]
	var enemy=world.add_unit(Vector2(2,0),false);enemy.team=1;enemy.campaign_slot=0
	check(AI.select_target(world,ally).id==enemy.id,"blue soldier targets red")
	check(AI.select_target(world,enemy).id==ally.id,"red targets nearer ally rather than always player")
	ally.brain=0;world.campaign_ai.update(ally,0)
	check(ally.ai_target==enemy.id and ally.weapon_id=="scar-l","one decision preserves distinct loadout")
	# A sub-cell steep ridge has clear endpoint centers, but must still reject the edge.
	world.terrain.active=true
	for z in range(world.terrain.size.y+1):
		for x in range(world.terrain.size.x+1):
			var location=world.terrain.vertex(x,z)
			world.terrain.heights[z*(world.terrain.size.x+1)+x]=2.0 if absf(location.x)<.01 else 0.0
	check(is_zero_approx(world.terrain.height(Vector2(-1,0))) and is_zero_approx(world.terrain.height(Vector2(1,0))),"ridge endpoints flat")
	check(not AI.traversable(world,Vector2(-1,0),Vector2(1,0)),"edge rejects steep intermediate triangles")
	world.topology_revision+=1
	world.campaign_ai.rebuild()
	var no_cliff=world.campaign_ai.path_between(Vector2(-4,0),Vector2(4,0))
	check(no_cliff.is_empty() or no_cliff[-1].x<0,"no path crosses steep ridge")
	print("campaign_navigation_contract: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
