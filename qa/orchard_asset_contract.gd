extends SceneTree
## Static geometry/data checks only; no game window or simulated combat loop.
const Catalog=preload("res://scripts/source_catalog.gd")
const Orchard=preload("res://scripts/orchard_prefabs.gd")
const Surface=preload("res://scripts/terrain_surface.gd")
const Landforms=preload("res://scripts/terrain_landforms.gd")
const Paths=preload("res://scripts/terrain_paths.gd")
const House=preload("res://scripts/house_geometry.gd")
const Art=preload("res://scripts/terrain_art.gd")
var checks=0
var failures=[]
var catalog=Catalog.new()

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)

func empty() -> Dictionary:
	return {"world":{"w":1600,"h":1600,"groundFeatures":[]},"instances":[],"looseSegments":[],"trees":[]}

func fixture(features: Array) -> Dictionary:
	var plan=empty();plan.world.groundFeatures=features;var compiled=catalog.compile(plan);var terrain=Surface.new();terrain.configure(compiled,catalog,plan)
	return {"plan":plan,"compiled":compiled,"terrain":terrain}

func _initialize():run.call_deferred()
func run():
	var original: Dictionary={}
	for scene in catalog.scenes:
		if scene.id=="level-01":original=scene.duplicate(true)
	var snapshot=JSON.stringify(original);var converted=Orchard.convert_plan(original,catalog)
	check(JSON.stringify(original)==snapshot,"conversion leaves immutable source plan untouched")
	check(converted.instances.size()==5 and original.instances.is_empty(),"five authored groups become reusable instances")
	check(Orchard.convert_plan(converted,catalog)==converted,"conversion is idempotent")
	check(converted.trees==original.trees and converted.world==original.world,"140 tree positions/radii and original ground remain unchanged")
	var before=catalog.compile(original);var after=catalog.compile(converted)
	for prefab_id in Orchard.GROUPS.values():
		var p: Dictionary=catalog.prefabs[prefab_id]
		check(p.source_origin.size()==2 and not p.source_ids.is_empty(),"source metadata "+prefab_id)
		for wall in catalog.templates[prefab_id].walls:
			var old=before.objects.filter(func(o):return o.id==wall.id)
			var fresh=after.objects.filter(func(o):return o.id.ends_with("."+wall.id))
			check(old.size()==1 and fresh.size()==1,"source wall bijection "+wall.id)
			if old.is_empty() or fresh.is_empty():continue
			check(old[0].position.distance_to(fresh[0].position)<.00002 and old[0].size.distance_to(fresh[0].size)<.00002 and absf(old[0].angle-fresh[0].angle)<.00001,"exact wall extents/opening intervals "+wall.id)
			check(not fresh[0].windows,"no unsolicited windows "+wall.id)
	check(after.roofs.size()==4,"four house/barn roofs, open courtyard")
	check(catalog.default_height("tree.broadleaf")>catalog.default_height("tree.broadleaf-small")+.9,"two authored orchard tree height classes")
	for tree in after.objects.filter(func(o):return o.output=="tree"):
		var source=original.trees.filter(func(t):return tree.owner==t.id)
		check(source.size()==1 and is_equal_approx(tree.crown_radius,float(source[0].radius)/40),"authored tree crown radius "+tree.owner)
	var hills=[{"id":"hill","componentId":"landform.low-hill","points":[[200,360],[980,360],[980,1240],[200,1240]],"height_m":1.5,"plateau_size_m":[2,2]}]
	var f=fixture(hills);var terrain=f.terrain
	check(absf(terrain.height(Vector2(-5.25,0))-1.5)<.001,"1.5m orchard crest")
	var slope_ok=true
	for i in range(1,9):
		var grade=terrain.grade(Vector2(-15+i,0));slope_ok=slope_ok and grade<=tan(deg_to_rad(12.0))+.005
	check(slope_ok,"final triangulated west walking slope remains under 12 degrees")
	var trench={"id":"zigzag","componentId":"landform.trench-network","points":[[440,1200],[440,880],[680,760],[600,480]],"depth_m":1.3,"bottom_width_m":2.4,"bank_run_m":1,"corner_radius_m":2,"ramps":[{"points":[[440,1200],[720,1240]]},{"points":[[600,480],[320,400]]}]}
	f=fixture([trench]);terrain=f.terrain
	var tf: Dictionary=terrain.features[0]
	var connected=true
	for i in range(tf.points.size()-1):
		for j in range(5):
			var p: Vector2=tf.points[i].lerp(tf.points[i+1],float(j)/4);connected=connected and absf(terrain.height(p)+1.3)<.08
	check(connected,"all curved trench segments share one connected deep floor")
	var duplicate=trench.duplicate(true);duplicate.id="overlap"
	var union_fixture=fixture([trench,duplicate])
	check(absf(union_fixture.terrain.height(Vector2(-9,5))+1.3)<.001,"overlapping trench networks excavate once, never double depth")
	check(terrain.height(Vector2(-8.3,8))< -1.25 and terrain.height(Vector2(-5.5,8))>-.1,"2.4m clear floor plus separately measured bank")
	for ramp in tf.trench_ramps:
		var a: Vector2=ramp.points[0];var b: Vector2=ramp.points[-1];var monotonic=true;var previous=-1.4;var max_grade=0.0
		for i in range(31):
			var p=a.lerp(b,float(i)/30);var h=terrain.height(p)
			monotonic=monotonic and h>=previous-.025;previous=h;max_grade=maxf(max_grade,terrain.grade(p))
		check(monotonic and absf(terrain.height(b))<.06 and max_grade<.45,"side ramp reaches surface continuously with walkable mesh slope")
	check(not terrain.ray(Vector3(-9,-.6,8),Vector3.RIGHT,8).is_empty(),"real soil bank blocks a below-grade horizontal shot")
	var road={"id":"road","kind":"path","pathMode":"spline","surface":"track","points":[[200,400],[560,760],[1020,790],[1480,1400]],"width":194,"shoulderWidth":224,"level_height_m":0,"level_width_m":6,"level_transition_m":1}
	f=fixture(hills+[road]);terrain=f.terrain
	var rf: Dictionary=terrain.features[-1];var level=true;var road_max_height=0.0;var road_max_grade=0.0
	for i in range(rf.points.size()-1):
		var a: Vector2=rf.points[i];var b: Vector2=rf.points[i+1];var side=(b-a).orthogonal().normalized()
		for edge in [-2.8,0,2.8]:
			var p=(a+b)*.5+side*edge;level=level and absf(terrain.height(p))<.005 and terrain.grade(p)<.01
			road_max_height=maxf(road_max_height,absf(terrain.height(p)));road_max_grade=maxf(road_max_grade,terrain.grade(p))
	check(level,"entire six-metre curved vehicle corridor remains y=0 on actual triangles")
	check(rf.points.size()==55 and rf.points[0]==Vector2(-15,-10) and rf.points[-1]==Vector2(17,15),"source-compatible Catmull-Rom preserves endpoints and 18 samples per span")
	check(rf.points[9].distance_to(Vector2(-11.21875,-5.546875))<.001,"Catmull-Rom interior sample matches source polynomial")
	var crossing=road.duplicate(true);crossing.points=[[200,900],[700,900]];crossing.pathMode="polyline"
	check(not fixture([trench,crossing]).terrain.conflicts.is_empty(),"trench/road corridor conflicts are exposed to level author")
	var plan=empty();plan.world.groundFeatures=hills
	plan.trees=[{"id":"tree","mapKitComponentId":"tree.broadleaf","x":500,"y":800,"radius":75}]
	plan.looseSegments=[{"id":"slope-wall","componentId":"wall.stone","x1":280,"y1":700,"x2":650,"y2":700,"thickness":24}]
	var compiled=catalog.compile(plan);terrain=Surface.new();terrain.configure(compiled,catalog,plan);var same_array: Array=compiled.objects
	Landforms.ground_objects(compiled,terrain)
	check(same_array.size()==compiled.objects.size() and compiled.objects.size()>10,"grounding preserves world array reference while splitting slope walls")
	var grounded_tree=compiled.objects.filter(func(o):return o.output=="tree")[0]
	check(is_equal_approx(grounded_tree.elevation,terrain.height(grounded_tree.position)),"ordinary orchard tree roots sit on actual terrain")
	var seated=true
	for o in compiled.objects.filter(func(o):return o.component_id=="wall.stone"):
		var low=terrain.height(o.position-Vector2.RIGHT*o.size.x*.5);var high=terrain.height(o.position+Vector2.RIGHT*o.size.x*.5)
		seated=seated and o.elevation<=minf(low,high)+.001 and o.elevation+o.height>=maxf(low,high)+1.099
	check(seated,"slope wall columns have buried feet and full cover height, no floating ends")
	var snapshot_grounded=compiled.objects.duplicate(true);Landforms.ground_objects(compiled,terrain)
	check(compiled.objects==snapshot_grounded,"grounding is idempotent")
	f=fixture([{"id":"step","componentId":"defense.trench-firing-step","points":[[700,800],[900,800]],"elevation_m":-1.3,"step_height_m":.36,"width_m":.9,"step_count":3},{"id":"revetment","componentId":"defense.trench-revetment","points":[[700,900],[900,900]],"elevation_m":-1.3,"height_m":1.1}])
	var steps=f.compiled.objects.filter(func(o):return o.owner=="step");steps.sort_custom(func(a,b):return a.position.x<b.position.x)
	check(steps.size()==5,"firing platform has three ascending/descending levels at both ends")
	var prior=0.0;var real_support=true
	for o in steps:
		House.prepare(o);real_support=real_support and absf(o.height-prior)<=.181 and absf(House.support(o,Vector2.ZERO,.1,INF)-o.height)<.0001;prior=o.height
	check(real_support and prior<=.181,"firing step uses shared real support and walkable 0.12m rises")
	check(f.compiled.objects[-1].component_id=="wall.wood-fence" and f.compiled.objects[-1].destructible,"revetment keeps destructible wall-cell implementation")
	for angle in [.47,1.12,PI*.5]:
		var rotated=trench.duplicate(true)
		for i in range(rotated.points.size()):
			var p=(catalog.v(rotated.points[i])-Vector2(800,800)).rotated(angle)+Vector2(800,800);rotated.points[i]=[p.x,p.y]
		for ramp in rotated.ramps:
			for i in range(ramp.points.size()):
				var p=(catalog.v(ramp.points[i])-Vector2(800,800)).rotated(angle)+Vector2(800,800);ramp.points[i]=[p.x,p.y]
		var rotated_fixture=fixture([rotated]);var rt=rotated_fixture.terrain;var field: Dictionary=rt.features[0]
		var floor_continuous=true;var ramp_walkable=true
		for point in field.points:floor_continuous=floor_continuous and absf(rt.height(point)+1.3)<.12
		for ramp in field.trench_ramps:
			for i in range(31):
				var p: Vector2=ramp.points[0].lerp(ramp.points[-1],float(i)/30);ramp_walkable=ramp_walkable and rt.grade(p)<.65
			var landing_end: Vector2=ramp.points[-1]+(ramp.points[-1]-ramp.points[-2]).normalized()*1.1
			check(absf(rt.height(landing_end))<.001,"rotated ramp has physical flat landing "+str(angle))
		check(floor_continuous and ramp_walkable,"rotated trench floor and dual ramps stay connected "+str(angle))
	print("ORCHARD_ASSET_CONTRACT ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
