extends SceneTree
const Validation = preload("res://scripts/editor_plan_validation.gd")
var failures = 0
var checks = 0

func _init():
	var minimal = {"world": {"w": 4000, "h": 2800}}
	check(Validation.error_for(minimal).is_empty(), "minimal plan")
	check(minimal.size() == 1, "validation leaves source untouched")
	for world in [null, [], "bad", {}, {"w": "4000", "h": 2800}, {"w": 0, "h": 2}, {"w": INF, "h": 2}]:
		check(not Validation.error_for({"world": world}).is_empty(), "reject malformed world")
	for key in ["instances", "looseSegments", "trees", "vehicles", "emplacements", "controlPoints"]:
		for bad in [null, {}, "bad", [null], ["bad"], [{"id": "a", "x": "bad", "y": 2}]]:
			var plan = minimal.duplicate(true);plan[key] = bad
			check(not Validation.error_for(plan).is_empty(), "reject malformed " + key)
	for key in ["deployment", "units", "godot3d", "objective", "editor"]:
		var plan = minimal.duplicate(true);plan[key] = []
		check(not Validation.error_for(plan).is_empty(), "reject malformed " + key)
	var unit_plan = minimal.duplicate(true);unit_plan.units = {"red": [{"x": 0, "y": 0}]}
	check(Validation.error_for(unit_plan).is_empty(), "finite zero coordinate")
	unit_plan.units.red[0].x = NAN
	check(not Validation.error_for(unit_plan).is_empty(), "reject NaN")
	var copied = JSON.stringify(minimal)
	Validation.error_for(minimal)
	check(JSON.stringify(minimal) == copied, "source is unchanged after validation")
	var entity = {"id": "a", "x": 10, "y": 20, "prefabId": "house"}
	var entity_plan = minimal.duplicate(true);entity_plan.instances = [entity]
	check(Validation.error_for(entity_plan).is_empty(), "valid entity")
	entity_plan.instances.append(entity.duplicate(true))
	check(not Validation.error_for(entity_plan).is_empty(), "reject duplicate entity IDs")
	entity_plan.instances.pop_back()
	for bad_scale in [0, -1, "1", INF]:
		entity.scale = bad_scale
		check(not Validation.error_for(entity_plan).is_empty(), "reject invalid scale")
	entity.erase("scale")
	entity.godot3d = []
	check(not Validation.error_for(entity_plan).is_empty(), "reject malformed godot3d")
	entity.godot3d = {"height": "three"}
	check(not Validation.error_for(entity_plan).is_empty(), "reject malformed height")
	var points_plan = minimal.duplicate(true)
	for bad_points in [null, {}, [null], [[1]], [[1, "2"]]]:
		points_plan.world.groundFeatures = [{"points": bad_points}]
		check(not Validation.error_for(points_plan).is_empty(), "reject malformed ground points")
	var original_path = "res://data/original/scenes.json"
	if FileAccess.file_exists(original_path):
		var scenes = JSON.parse_string(FileAccess.get_file_as_string(original_path))
		for scene in scenes.scenes:
			var error = Validation.error_for(scene)
			check(error.is_empty(), "original " + str(scene.id) + ": " + error)
	print("Editor plan validation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(passed: bool, label: String):
	checks += 1
	if not passed:failures += 1;push_error(label)
