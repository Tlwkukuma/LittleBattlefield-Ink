extends SceneTree
## Static geometry/data checks only; no game window or simulated combat loop.
const Catalog=preload("res://scripts/source_catalog.gd")
const Surface=preload("res://scripts/terrain_surface.gd")
const Landforms=preload("res://scripts/terrain_landforms.gd")
const Paths=preload("res://scripts/terrain_paths.gd")
const House=preload("res://scripts/house_geometry.gd")
const World=preload("res://scripts/proving_world.gd")
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
	# Direct wall state changes verify geometry ownership; this is not a game playtest.
	var plan=empty();plan.deployment={"player":{"x":800,"y":1100}};plan.world.groundFeatures=[{"id":"wall","componentId":"defense.trench-revetment","points":[[700,800],[900,800]],"elevation_m":0,"height_m":1.1,"material":"stone","width_m":.25}]
	var world=World.new();world.setup(plan,catalog);var wall: Dictionary=world.objects[0]
	check(world.blocked(Vector2.ZERO,.25,1.95),"intact stone revetment blocks physical passage")
	var full_mesh=Art.wall_mesh(wall);var full_vertices=full_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size();var col=int(wall.columns/2)
	for x in range(maxi(0,col-1),mini(wall.columns,col+2)):
		for row in range(wall.rows):world.damage_cell(wall,x,row,10000,Vector2(0,1),true)
	world.resolve_support()
	check(not world.blocked(Vector2.ZERO,.25,1.95) and world.navigation_dirty,"blasted stone revetment opens passage and invalidates navigation")
	check(world.ray(Vector2(0,1),Vector2.UP,2,.55,{},true).is_empty(),"blasted revetment opens actual bullet ray")
	var broken_mesh=Art.wall_mesh(wall)
	check(broken_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()<full_vertices,"stone faces disappear with removed physical wall cells")
	for x in range(wall.columns):
		for row in range(wall.rows):world.damage_cell(wall,x,row,10000,Vector2.ZERO,true)
	check(Art.wall_mesh(wall).get_surface_count()==0,"destroyed stone wall leaves no floating mortar or face decorations")
	print("ORCHARD_WALL_CONTRACT ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
