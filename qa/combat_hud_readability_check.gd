extends SceneTree
## Isolated text/geometry fixtures only. No scene, input or gameplay simulation.
const HUD=preload("res://scripts/combat_hud.gd")
const Batch=preload("res://scripts/canvas_mesh_batch.gd")
const Cues=preload("res://scripts/combat_cue_state.gd")
var checks=0
var failures=[]
func check(value: bool,label: String):
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize():
	var hud=HUD.new()
	hud.paint=Batch.new()
	for key in ["R","B","5"]:
		hud.text_commands.clear();hud.keycap(Vector2.ZERO,key)
		var cmd: Dictionary=hud.text_commands[0]
		var width=hud.get_theme_default_font().get_string_size(key,HORIZONTAL_ALIGNMENT_LEFT,-1,cmd.size).x
		check(cmd.size==14,"Readable existing keycap: "+key)
		check(is_equal_approx(cmd.at.x+width*.5,12),"Keycap remains centred: "+key)
	check(HUD.MODE_FONT_SIZE==14 and HUD.SLOT_FONT_SIZE==13,"Mode and shortcut labels have explicit modest sizes")
	for viewport in [Vector2(960,540),Vector2(1440,900),Vector2(1920,1080)]:
		var rect=Cues.card_rect(viewport)
		check(Rect2(Vector2.ZERO,viewport).encloses(rect),"Original card stays in viewport: "+str(viewport))
	var player={"mounted":-1,"healing":{},"medical_feedback":{}}
	check(not HUD.medical_graphics_active(player),"Idle HUD retains fixed geometry caching")
	player.medical_feedback={"kind":"full","time":.5}
	check(HUD.medical_graphics_active(player),"Full-health feedback follows projected actor")
	player.medical_feedback={"kind":"empty","time":.5}
	check(HUD.medical_graphics_active(player),"Empty-stock feedback follows projected actor")
	player.medical_feedback={};player.healing={"remaining":1.0,"duration":2.0}
	check(HUD.medical_graphics_active(player),"Active healing follows projected actor")
	player.mounted=0
	check(not HUD.medical_graphics_active(player),"Mounted state does not render a medical symbol")
	player.mounted=-1;player.healing={}
	check(not HUD.medical_graphics_active(player),"Completed/cancelled state returns to cached HUD")
	var source=FileAccess.get_file_as_string("res://scripts/combat_hud.gd")
	check(source.contains('game.world.player.get("medical_feedback",{}),game.interaction_hint.text'),"Feedback removal invalidates previous geometry")
	hud.free()
	print("COMBAT_HUD_READABILITY_CHECK ",checks-failures.size(),"/",checks," passed; isolated fixtures, no gameplay automation; failures=",failures)
	quit(0 if failures.is_empty() else 1)
