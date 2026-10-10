extends RefCounted
## Empty off-map backdrop only. No geometry, collision or camera changes.
const LEGACY=Color("c0bbcc")
const GROUND=preload("res://scripts/terrain_ground.gd")
static func apply(environment: Environment,plan: Dictionary) -> void:
	if environment==null:return
	var chapter=int(plan.get("godot3d",{}).get("campaign_chapter",0))
	environment.background_color=GROUND.BASE.darkened(.12) if chapter>=2 and chapter<=10 else LEGACY
