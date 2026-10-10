extends Node3D
## Pure presentation state. The world owns health, ammunition and movement.
const Style = preload("res://scripts/vehicle_style.gd")
var vehicle: Dictionary = {}
var wear: Array = []
var broken_tracks: Array = []
var intact_tracks: Array = []
var damage_level: int = -1
var face_material: ShaderMaterial
var edge_material: ShaderMaterial

func prepare_materials() -> void:
	var team=Style.Livery.team_id(vehicle.get("team",-1))
	face_material = Style.material(false,team)
	edge_material = Style.material(true,team)

func finish_group(group: Node3D, keep: Array = []) -> void:
	Style.finish_group(group,keep,face_material,edge_material)

func _process(_delta: float) -> void:
	sync()

func sync() -> void:
	if vehicle.is_empty(): return
	var ratio: float = vehicle.health / maxf(1.0, vehicle.max_health)
	var level: int = 3 if vehicle.destroyed else 2 if ratio <= 0.35 else 1 if ratio <= 0.68 else 0
	if level != damage_level:
		damage_level = level
		var amount: float = [0.0, 0.18, 0.42, 1.0][level]
		face_material.set_shader_parameter("damage", amount)
		edge_material.set_shader_parameter("damage", amount)
		for i in range(wear.size()): wear[i].visible = level > i
	var broken: bool = vehicle.max_track > 0 and (vehicle.track_health <= 0 or vehicle.destroyed)
	for track in broken_tracks: track.visible = broken
	for track in intact_tracks: track.visible = not broken
