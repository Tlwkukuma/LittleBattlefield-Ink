extends SceneTree
const Background=preload("res://scripts/campaign_background.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	var environment=Environment.new();environment.background_color=Background.LEGACY
	for chapter in [2,1,9,0,10,1]:
		var plan={"godot3d":{"campaign_chapter":chapter}}
		var copy=plan.duplicate(true)
		Background.apply(environment,plan)
		check(environment.background_color==(Background.GROUND.BASE.darkened(.12) if chapter>=2 else Background.LEGACY),"chapter background updates and resets on every rebuild")
		check(plan==copy,"source plan remains unchanged")
	check(Background.GROUND.BASE.darkened(.12)!=Background.GROUND.BASE,"off-map backdrop retains visible contrast")
	var script=FileAccess.get_file_as_string("res://scripts/proving_ground.gd")
	check(script.contains('plan=source.duplicate(true)\n\tpreload("res://scripts/campaign_background.gd").apply(scene_environment,plan)'),"actual rebuild applies backdrop after plan replacement")
	print("campaign_background_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
