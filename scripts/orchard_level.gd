extends RefCounted
## Godot-only adaptation. Imported scene, source weapons and authored doors stay immutable.
const Prefabs=preload("res://scripts/orchard_prefabs.gd")
const RULES_PATH="res://data/campaign/level01_rules.json"
const ID="orchard-level-01"
const TRENCH_DEPTH=1.6
const TRENCH_PARAPET=.6
const TRENCH_STEP=.9
const TRENCH_POINTS=[[1000,1790],[1000,1480],[1210,1380],[1090,1200]]
const TRENCH_RAMPS=[{"points":[[1000,1790],[1280,1830]],"width_m":2.8,"landing_length_m":1.25},
	{"points":[[1090,1200],[920,970]],"width_m":2.8,"landing_length_m":1.25}]
const TREE_MOVES={
	"broadleaf-006":[818,1090],"broadleaf-008":[1158,1088],
	"broadleaf-010":[1340,1356],"broadleaf-013":[870,1460],
	"broadleaf-014":[1154,1551],"broadleaf-016":[1130,1611],
	"broadleaf-018":[1310,1705],"broadleaf-019":[1167,1680],
	"broadleaf-020":[1062,1918],"broadleaf-058":[870,1755],
	"broadleaf-059":[1000,1340]}

static func plan(catalog) -> Dictionary:
	var source: Dictionary={}
	for scene in catalog.scenes:
		if str(scene.id)=="level-01":source=scene;break
	if source.is_empty():push_error("Missing immutable level-01 source");return {}
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	var result=Prefabs.convert_plan(source,catalog)
	result.id=ID;result.title="第一关 · 石墙果园";result.levelId=1
	result.godot3d={"campaign":true,"range":false,"sourceSceneId":"level-01","source_scale":40,
		"layout_revision":2,"treeMoves":[],"sourceObjectMap":{},"aiRoutes":routes()}
	result.campaignRules=rules.rules.duplicate(true)
	result.campaignSource=rules.source.duplicate(true)
	result.units=rules.units.duplicate(true)
	result.deployment=rules.deployment.duplicate(true)
	result.objective=rules.objective.duplicate(true)
	result.controlPoints=rules.controlPoints.duplicate(true)
	for instance in result.instances:
		var prefab: Dictionary=catalog.prefabs.get(instance.prefabId,{})
		if not prefab.get("orchard",false):continue
		instance.godot3d.windows=false;instance.godot3d.elevation=0
		instance.source_ids=prefab.source_ids.duplicate()
		for source_id in prefab.source_ids:
			var children=[]
			for wall in catalog.templates[instance.prefabId].walls:
				if wall.get("source_id","")==source_id:children.append(str(instance.id)+"."+str(wall.id))
			result.godot3d.sourceObjectMap[source_id]={"instance":instance.id,"children":children,
				"opening":children.is_empty()}
	for tree in result.trees:
		if not TREE_MOVES.has(tree.id):continue
		var target: Array=TREE_MOVES[tree.id]
		result.godot3d.treeMoves.append({"source_id":tree.id,"from":[tree.x,tree.y],"to":target.duplicate(),
			"reason":"保留原树种和作者冠幅，将树干移出新增沟底、沟坡及坡道落脚通路"})
		tree.x=target[0];tree.y=target[1]
	add_terrain(result)
	preload("res://scripts/orchard_layout.gd").apply(result,catalog)
	return result

static func rectangle(x1: float,y1: float,x2: float,y2: float) -> Array:
	return [[x1,y1],[x2,y1],[x2,y2],[x1,y2]]

static func add_terrain(result: Dictionary):
	var ground: Array=result.world.groundFeatures
	for feature in ground:
		if feature.id not in ["orchard-main-road","farm-access-road"]:continue
		feature.level_height_m=0
		feature.level_width_m=6.5 if feature.id=="orchard-main-road" else 5.0
		feature.level_transition_m=1.0
	ground.append({"id":"orchard-west-hill","componentId":"landform.low-hill","kind":"area",
		"points":rectangle(0,480,800,1440),"height_m":1.5,"plateau_size_m":[1,2],
		"mapKitVisual":{"fill":"#898b65","alpha":.52}})
	ground.append({"id":"orchard-approach-trench","componentId":"landform.trench-network","kind":"path",
		"points":TRENCH_POINTS.duplicate(true),"depth_m":TRENCH_DEPTH,"bottom_width_m":2.4,
		"bank_run_m":1.0,"corner_radius_m":2.0,"corner_widen_m":.35,
		"parapet_height_m":TRENCH_PARAPET,"parados_height_m":.30,"parapet_side":1,
		"berm_inner_run_m":.65,"berm_crest_width_m":.8,"berm_outer_run_m":1.25,
		"ramps":TRENCH_RAMPS.duplicate(true),"connection_group":"orchard-approach",
		"mapKitVisual":{"fill":"#827a60","alpha":.85}})
	ground.append({"id":"orchard-north-flank-rise","componentId":"landform.low-hill","kind":"area",
		"points":rectangle(1780,390,2240,780),"height_m":.55,"plateau_size_m":[1.4,1.2]})
	ground.append({"id":"orchard-south-flank-rise","componentId":"landform.low-hill","kind":"area",
		"points":rectangle(1970,1400,2280,1680),"height_m":.45,"plateau_size_m":[1.2,1]})
	# No new soil reaches a building threshold, courtyard wall, flag or gun base.
	ground.append({"id":"orchard-yard-level","componentId":"landform.level-pad","kind":"area",
		"points":[[2330,500],[3090,500],[3090,1380],[2370,1380]],"height_m":0,"transition_m":.65})
	for mount in result.emplacements:
		ground.append({"id":"orchard-gun-level-"+str(mount.id),"componentId":"landform.level-pad","kind":"area",
			"points":rectangle(mount.x-90,mount.y-90,mount.x+90,mount.y+90),"height_m":0,"transition_m":.65})
	ground.append({"id":"orchard-jeep-apron","componentId":"landform.level-pad","kind":"area",
		"points":rectangle(1950,1780,2530,2090),"height_m":0,"transition_m":1})
	ground.append({"id":"orchard-jeep-link","componentId":"landform.level-pad","kind":"path",
		"points":[[2382,1984],[2170,1980],[2040,1840]],"width_m":6.5,"height_m":0,"transition_m":1})
	# Recessed travel lane stays behind a real soil breastwork. The optional ledge
	# restores a usable standing muzzle above the east parapet; crouching hides it.
	# AI routes use the unobstructed 1.5 m beside the ledge.
	ground.append({"id":"orchard-trench-step","componentId":"defense.trench-firing-step","kind":"path",
		"points":[[1030,1560],[1030,1720]],"elevation_m":-TRENCH_DEPTH,"step_height_m":TRENCH_STEP,
		"width_m":.9,"step_count":5,"step_run_m":.30})
	for spec in [{"id":"orchard-trench-revetment-west","points":[[950,1550],[950,1730]]},
		{"id":"orchard-trench-revetment-east","points":[[1050,1570],[1050,1710]]}]:
		ground.append({"id":spec.id,"componentId":"defense.trench-revetment","kind":"path",
			"points":spec.points,"elevation_m":-TRENCH_DEPTH,"height_m":TRENCH_DEPTH-.2,"width_m":.16,"material":"wood"})

static func route(points: Array) -> Array:
	var result=[]
	for point in points:result.append({"x":point[0],"y":point[1]})
	return result

static func routes() -> Dictionary:
	return {"blue":[
		route([[1810,1660],[1720,1480],[1630,1300],[1480,1090],[1710,990],[2110,995],[2340,1000],[2460,1000]]),
		route([[700,1540],[610,1440],[440,1210],[410,1020],[590,800],[830,860],[870,1000],[1100,980],[1540,990],[2110,995],[2340,1000],[2460,1000]]),
		route([[1400,1900],[1280,1830],[1000,1790],[975,1660],[975,1530],[1000,1480],[1170,1395],[1110,1280],[1090,1200],[920,970],[1100,980],[1540,990],[2110,995],[2340,1000],[2460,1000]])],
		"red":[
		route([[1570,470],[1740,870],[1950,950],[2340,1000],[2460,1000]]),
		route([[2220,420],[2160,750],[2220,980],[2340,1000],[2460,1000]])]}
