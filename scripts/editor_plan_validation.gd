extends RefCounted
## Read-only boundary for editor JSON. Never compiles or changes the active plan.

static func error_for(source: Dictionary, catalog = null) -> String:
	if not source.get("world") is Dictionary:return "world 必须是对象"
	for key in ["w", "h"]:
		if not number(source.world.get(key)) or float(source.world[key]) <= 0:
			return "world." + key + " 必须是有限正数"
	for key in ["godot3d", "deployment", "units", "objective", "editor"]:
		if source.has(key) and not source[key] is Dictionary:return key + " 必须是对象"
	var error = tree_error(source, "场景")
	if not error.is_empty():return error
	for key in ["instances", "looseSegments", "trees", "vehicles", "emplacements", "controlPoints"]:
		error = object_array_error(source.get(key, []), key)
		if not error.is_empty():return error
		var seen = {}
		for item in source.get(key, []):
			if not item.get("id") is String or item.id.is_empty():return key + " 中的 id 必须是非空字符串"
			if seen.has(item.id):return key + " 中重复的 id：" + item.id
			seen[item.id] = true
			var coordinates = ["x1", "y1", "x2", "y2"] if key == "looseSegments" else ["x", "y"]
			for coordinate in coordinates:
				if not number(item.get(coordinate)):return key + "." + item.id + "." + coordinate + " 必须是有限数值"
			for numeric_key in ["angle", "rotation", "scale", "scaleX", "scaleY", "thickness", "radius", "r"]:
				if item.has(numeric_key) and not number(item[numeric_key]):return key + "." + numeric_key + " 必须是有限数值"
			for positive_key in ["scale", "scaleX", "scaleY", "thickness", "radius", "r"]:
				if item.has(positive_key) and float(item[positive_key]) <= 0:return key + "." + positive_key + " 必须大于零"
			if key == "instances":
				if not item.get("prefabId") is String:return "instances.prefabId 必须是字符串"
				if catalog != null and not catalog.prefabs.has(item.prefabId):return "未知预制体：" + item.prefabId
			elif key == "looseSegments":
				if not item.get("componentId") is String:return "looseSegments.componentId 必须是字符串"
				if catalog != null and not catalog.components.has(item.componentId):return "未知组件：" + item.componentId
			elif key in ["vehicles", "emplacements"]:
				if not item.get("type") is String:return key + ".type 必须是字符串"
				if catalog != null and not catalog.data.get(key, {}).has(item.type):return "未知载具 / 固定武器：" + item.type
	for team in ["blue", "red"]:
		error = object_array_error(source.get("units", {}).get(team, []), "units." + team)
		if not error.is_empty():return error
		for unit in source.get("units", {}).get(team, []):
			error = point_error(unit, "units." + team)
			if not error.is_empty():return error
		var deployment = source.get("deployment", {})
		if deployment.has(team):
			if not deployment[team] is Dictionary:return "deployment." + team + " 必须是对象"
			error = object_array_error(deployment[team].get("spawnPoints", []), "deployment." + team + ".spawnPoints")
			if not error.is_empty():return error
			for point in deployment[team].get("spawnPoints", []):
				error = point_error(point, "spawnPoints")
				if not error.is_empty():return error
	if source.get("deployment", {}).has("player"):
		error = point_error(source.deployment.player, "deployment.player")
		if not error.is_empty():return error
	error = object_array_error(source.world.get("groundFeatures", []), "world.groundFeatures")
	if not error.is_empty():return error
	for feature in source.world.get("groundFeatures", []):
		if feature.has("points"):
			if not feature.points is Array:return "groundFeatures.points 必须是数组"
			for point in feature.points:
				error = point_error(point, "groundFeatures.points")
				if not error.is_empty():return error
	return ""

static func number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func point_error(value, path: String) -> String:
	if value is Array:
		if value.size() == 2 and number(value[0]) and number(value[1]):return ""
	elif value is Dictionary:
		if number(value.get("x")) and number(value.get("y")):return ""
	return path + " 必须是有限的二维坐标"

static func object_array_error(value, path: String) -> String:
	if not value is Array:return path + " 必须是数组"
	for item in value:
		if not item is Dictionary:return path + " 数组只能包含对象"
	return ""

static func tree_error(value, path: String, depth: int = 0) -> String:
	# Bound pathological nesting before recursive copying/compilation.
	if depth > 64:return path + " 嵌套过深"
	if value is float and not is_finite(value):return path + " 包含非有限数值"
	if value is Dictionary:
		for key in value:
			if str(key) in ["godot3d", "mapKitVisual"] and not value[key] is Dictionary:return path + "." + str(key) + " 必须是对象"
			if str(key) == "godot3d":
				for numeric_key in ["height", "elevation", "health_scale"]:
					if value[key].has(numeric_key) and not number(value[key][numeric_key]):return path + ".godot3d." + numeric_key + " 必须是有限数值"
			var error = tree_error(value[key], path + "." + str(key), depth + 1)
			if not error.is_empty():return error
	elif value is Array:
		for item in value:
			var error = tree_error(item, path, depth + 1)
			if not error.is_empty():return error
	return ""
