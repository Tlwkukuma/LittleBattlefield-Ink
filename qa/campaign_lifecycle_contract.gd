extends SceneTree
## Bounded real-scene rebuild cleanup; no gameplay ticks, movement or firing.
## Run only in the coordinated heavy slot, after other current milestone tests.
const SAVE="/tmp/campaign-lifecycle-contract.json"
var checks=0
var failures=0
var baselines={}
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func settle():
	for frame in range(3):await process_frame
func descendants(node: Node) -> int:
	var count=1
	for child in node.get_children():count+=descendants(child)
	return count
func counts(game) -> Dictionary:
	var pieces=0
	for group in game.flash_batches.pool.groups.values():
		pieces+=group.entries.size()
		check(group.instances.visible_instance_count==group.entries.size(),"visible registration count stays dense")
		for handle in group.entries:check(int(handle.slot)<group.instances.instance_count,"retained handle fits current pool")
	return {"stage_nodes":descendants(game.stage),"actors":game.actors.size(),"units":game.world.units.size(),"vehicles":game.vehicle_views.size(),"flash_roots":game.flash_batches.entries.size(),"flash_pieces":pieces}
func _initialize():call_deferred("run")
func run():
	change_scene_to_file("res://proving_ground.tscn")
	for frame in range(10):await process_frame
	var game=current_scene
	if game==null:printerr("FAIL native scene unavailable");quit(2);return
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.campaign_progress=preload("res://scripts/campaign_progress.gd").new(SAVE)
	game.campaign_progress.completed=[1,2,3,4,5,6,7,8,9];game.campaign_progress.unlocked=10
	for iteration in range(2):
		for chapter in [1,10]:
			var old_stage=weakref(game.stage)
			for unit in game.world.units:unit.ai_order={"lifecycle_test_sentinel":true}
			game.trigger_pressed=true;game.jump_pressed=true;game.weapon_input_latched=false
			game.start_campaign_chapter(chapter,"T03" if chapter==1 else "T02")
			await settle()
			check(old_stage.get_ref()==null,"old scene stage is actually freed after queued boundary")
			check(game.armory.visible and is_zero_approx(game.world.time),"rebuild stays in zero-tick briefing")
			check(not game.trigger_pressed and not game.jump_pressed and game.weapon_input_latched,"transient input cleared and held-fire safely gated")
			check(game.world.units.all(func(unit):return not unit.get("ai_order",{}).get("lifecycle_test_sentinel",false)),"old life/order dictionaries do not survive rebuild")
			check(game.world.campaign_director.plan_executor.tactic_id==("T03" if chapter==1 else "T02"),"chapter tactic reaches fresh executor")
			var snapshot=counts(game)
			if baselines.has(chapter):check(snapshot==baselines[chapter],"same chapter rebuild has stable logical instance counts")
			else:baselines[chapter]=snapshot
			var before_stage=weakref(game.stage)
			game.show_campaign_chapters();await settle()
			check(game.home_ui.chapter_buttons.size()==10,"chapter menu has no duplicate buttons")
			game.home_ui.hide_menu()
			if iteration==0:
				# Construct result states to test the advertised key, not combat wins.
				game.world.campaign.finish("won" if chapter==1 else "lost","lifecycle result fixture")
				game.campaign_ui.refresh()
				check(game.campaign_ui.result_panel.visible,"result UI exposes retry before keyboard action")
			var key=InputEventKey.new();key.keycode=KEY_F5;key.pressed=true
			game._unhandled_input(key);await settle()
			check(before_stage.get_ref()==null,"actual F5 path frees prior stage")
			check(counts(game)==baselines[chapter],"retry retains exact per-chapter logical counts")
			check(game.armory.visible and is_zero_approx(game.world.time),"actual F5 remains frozen")
			check(game.campaign_progress.completed==[1,2,3,4,5,6,7,8,9] and game.campaign_progress.unlocked==10,"entry/menu/retry never fabricates wins")
			print("LIFECYCLE iteration=%d chapter=%d counts=%s"%[iteration,chapter,JSON.stringify(snapshot)])
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix):DirAccess.remove_absolute(SAVE+suffix)
	print("campaign_lifecycle_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
