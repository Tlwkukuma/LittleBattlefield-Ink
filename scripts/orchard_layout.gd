extends RefCounted
## Runtime-only revision: immutable imported layout/prefab wall data stays intact.
const CAMERA_SIZE=25.0
const COMPOUND_WALL_HEIGHT=2.2
const HOUSE_CENTERS={"orchard-house-a":Vector2(2490,700),"orchard-house-b":Vector2(2900,700),"orchard-house-c":Vector2(2900,980),"orchard-barn":Vector2(2610,1350)}
const JEEP_ROAD=[[2382,1984],[2170,1980],[2040,1840],[1775,1580],[1555,1305]]

static func apply(plan: Dictionary,catalog):
	plan.world.h=2300
	plan.godot3d.battlefield_border=true
	plan.godot3d.layout_revision=7;plan.godot3d.combat_camera_size=CAMERA_SIZE
	plan.godot3d.layout_notes={"field_m":Vector2(82.5,57.5),"main_combat_m":Vector2(56,36),"vehicle_route":"original-main-road"}
	for instance in plan.instances:
		if HOUSE_CENTERS.has(instance.id):
			var at: Vector2=HOUSE_CENTERS[instance.id];instance.x=at.x;instance.y=at.y
		elif instance.id=="orchard-compound":
			instance.x=2670;instance.y=1020;instance.scale=1.35
			instance.prefabId="rural.orchard-stone-yard"
			instance.godot3d.height=COMPOUND_WALL_HEIGHT
	# Remove the features themselves: paint, shoulders, and terrain flattening agree.
	plan.world.groundFeatures=plan.world.groundFeatures.filter(func(f):return f.id not in ["farm-access-road","orchard-perimeter-lane"])
	for f in plan.world.groundFeatures:
		if f.id=="orchard-yard-level":f.points=[[2190,460],[3170,460],[3170,1580],[2190,1580]]
	for s in plan.looseSegments:
		if s.id=="field-wall-south":s.x1=1830;s.y1=1260;s.x2=1970;s.y2=1260
	# Gun positions and adjacent sandbags now retain their imported coordinates.
	# Keep the tree population, clearing only the occupied courtyard and deployment.
	var moved=0
	for tree in plan.trees:
		var at=Vector2(tree.x,tree.y)
		if Rect2(2190,460,980,1120).has_point(at) or Rect2(1330,1810,700,380).has_point(at):
			var target=Vector2(140+float(moved%6)*98,410+float(moved/6)*105)
			plan.godot3d.treeMoves.append({"source_id":tree.id,"from":[tree.x,tree.y],"to":[target.x,target.y],"reason":"clear courtyard and deployment"})
			tree.x=target.x;tree.y=target.y;moved+=1
	plan.deployment.player.x=1740;plan.deployment.player.y=1910
	var blue=[Vector2(1440,2020),Vector2(1710,2020),Vector2(1920,2020),Vector2(1800,1770),Vector2(1280,1830),Vector2(1630,1600)]
	var red=[Vector2(2620,1030),Vector2(2820,875),Vector2(2930,1300),Vector2(1830,720),Vector2(1780,470),Vector2(2700,350)]
	for team in ["blue","red"]:
		var centers=blue if team=="blue" else red
		for i in range(plan.units[team].size()):
			var p: Vector2=centers[mini(i/5,centers.size()-1)]+Vector2((i%5-2)*43,(i%2)*46)
			plan.units[team][i].x=p.x;plan.units[team][i].y=p.y
		plan.deployment[team].spawnPoints=[]
		for i in range(8):plan.deployment[team].spawnPoints.append({"id":team+"-farm-spawn-"+str(i),"x":1390+i*75 if team=="blue" else 2300+i*100,"y":2160 if team=="blue" else 230})
	preload("res://scripts/orchard_objective.gd").apply(plan,catalog)
	# convert_plan already deep-copies the original roster, spawn coordinates,
	# heading and ownership. Only enable the existing AI boarding capability.
	for vehicle in plan.vehicles:
		vehicle.aiControlled=true
	for mount in plan.emplacements:
		mount.aiControlled=true
	plan.godot3d.vehicleRoutes={"vehicle-001":JEEP_ROAD}
	for instance in plan.instances:
		for source_id in instance.get("source_ids",[]):
			var children=[]
			for wall in catalog.templates[instance.prefabId].walls:
				if wall.get("source_id","")==source_id:children.append(str(instance.id)+"."+str(wall.id))
			plan.godot3d.sourceObjectMap[source_id]={"instance":instance.id,"children":children,"opening":children.is_empty()}
	# The south approach goes around the closed southwest corner to the original
	# west entrance. No authored waypoint leads soldiers into the former opening.
	plan.godot3d.aiRoutes={"blue":[points([[1740,1910],[1800,1640],[1800,1410],[1800,1050],[2100,1100],[2350,1100],[2590,1090]]),points([[1280,1830],[1000,1790],[975,1530],[1170,1395],[1090,1200],[920,970],[1450,1000],[1900,1050],[2350,1100],[2590,1090]]),points([[1920,2020],[2140,1770],[2190,1630],[2140,1350],[2110,1100],[2350,1100],[2590,1090]])],"red":[points([[1830,720],[1900,850],[2100,1040],[2350,1100],[2600,1060]]),points([[2700,350],[2450,390],[2140,650],[2180,1090],[2350,1100],[2600,1060]])]}

static func points(raw: Array) -> Array:
	var result=[]
	for p in raw:result.append({"x":p[0],"y":p[1]})
	return result
