extends RefCounted
## E selects one reachable world interaction. Vehicle control is exclusively F.
const RANGE=1.85
static func eligible(u: Dictionary) -> bool:
	return u.alive and u.mounted<0 and u.grounded and u.vault.is_empty()
static func nearest(world,entries: Array) -> Dictionary:
	var u: Dictionary=world.player
	if not eligible(u):return {}
	var found: Dictionary={};var nearest_distance=RANGE
	var origin=Vector3(u.position.x,u.elevation+.8,u.position.y)
	for entry in entries:
		var point: Vector3=entry.position;var distance=Vector2(point.x,point.z).distance_to(u.position)
		if distance>=nearest_distance or absf(point.y-origin.y)>1.2:continue
		var ray=point-origin
		if not world.trace_3d(origin,ray.normalized(),ray.length(),{},true).is_empty():continue
		found=entry;nearest_distance=distance
	return found
static func activate(game):
	if game.armory.visible or game.loot_open() or game.editing or game.paused or game.has_text_focus() or game.over_ui():return
	if preload("res://scripts/terrain_ladder.gd").interact(game.world):return
	if not eligible(game.world.player):return
	var target=nearest(game.world,game.interactions)
	if target.is_empty():game.message("靠近梯子或装备台按 E 交互；上下车使用 F");return
	match target.kind:
		"class":game.equip_class(target.class_id)
