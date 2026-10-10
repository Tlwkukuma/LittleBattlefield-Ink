extends SceneTree
## Actual chapter/rule/presentation/draw-data contracts. No world tick or input.
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Presentation=preload("res://scripts/campaign_presentation.gd")
const BattleHUD=preload("res://scripts/battle_status_hud.gd")
class Host extends RefCounted:
	var world
	var plan: Dictionary
	var armory={"visible":false}
	var campaign_ui
	func debug_open():return false
class Recorder extends RefCounted:
	const DANGER=Color("e8957d")
	const FOCUS=Color("afd1c1")
	var game
	var paint=preload("res://scripts/canvas_mesh_batch.gd").new()
	var texts=[]
	func get_viewport_rect():return Rect2(0,0,1440,900)
	func medical_cross(_at,_radius,_color):pass
	func text_at(_at,value,_size,_color):texts.append(str(value))
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new()
	for number in range(1,11):
		var host=Host.new();host.world=World.new();host.plan=Chapters.plan(catalog,number)
		host.world.setup(host.plan,catalog);host.plan=host.world.plan
		var ui=Presentation.new();ui.game=host;host.campaign_ui=ui
		var rules=host.world.campaign
		var stage_count=maxi(1,rules.mission.get("stages",[]).size())
		for stage_index in range(stage_count):
			# Prepare each authored stage directly; never play or tick the world.
			if not rules.mission.is_empty():
				rules.stage_index=stage_index;Chapters.apply_stage(host.plan,stage_index);rules.build_points(host.world)
			ui.refresh()
			var summary=ui.hud_summary
			if not rules.mission.is_empty():check(str(summary.capture.name).ends_with(str(rules.current_stage().point.label)),"HUD uses the actual current authored stage target")
			check(summary.has("capture") and summary.has("remaining") and summary.has("total"),"Chapter %d stage %d normal HUD fields"%[number,stage_index+1])
			var recorder=Recorder.new();recorder.game=host;BattleHUD.draw(recorder)
			check(recorder.texts.has(summary.capture.name),"Chapter %d stage %d objective reaches normal draw batch"%[number,stage_index+1])
			if not summary.capture.inside:
				check(recorder.texts.any(func(t):return t.ends_with(BattleHUD.objective_direction(host))),"Actual active objective bearing reaches normal HUD")
			check(recorder.texts.any(func(t):return t.begins_with(str(summary.capture.state))),"Chapter %d stage %d status reaches normal draw batch"%[number,stage_index+1])
			if not rules.mission.is_empty():
				check(str(summary.capture.name).begins_with("%d/%d "%[stage_index+1,stage_count]),"Visible stage count for chapter %d"%number)
				if str(rules.current_stage().get("mode","capture"))=="hold":
					rules.points[0].owner=0;rules.points[0].progress=1.0;rules.hold_elapsed=12.0
					for contested in [false,true]:
						rules.points[0].contested=contested;ui.refresh();recorder.texts.clear();BattleHUD.draw(recorder)
						check(recorder.texts.any(func(t):return t.contains("12/") and t.contains("秒") and t.begins_with("争夺" if contested else "守住")),"Hold time/contest reaches normal HUD in chapter %d"%number)
		check(is_zero_approx(host.world.time) and host.world.shots==0,"Chapter %d did not simulate gameplay"%number)
		host.campaign_ui=null;ui.game=null
	print("CAMPAIGN_HUD_READABILITY_CHECK ",checks-failures,"/",checks," passed; actual draw data, no gameplay simulation")
	quit(0 if failures==0 else 1)
