extends SceneTree
## Native UI lifecycle with the game process disabled; no movement/firing/world ticks.
var checks=0
var failures=0
const SAVE="/tmp/campaign-flow-contract.json"
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	change_scene_to_file("res://proving_ground.tscn")
	for frame in range(10):await process_frame
	var game=current_scene
	if game==null:printerr("FAIL scene unavailable");quit(2);return
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.campaign_progress=preload("res://scripts/campaign_progress.gd").new(SAVE)
	game.campaign_progress.unlocked=1;game.campaign_progress.completed=[]
	check(game.world.campaign_active() and game.armory.visible,"CLI chapter opens briefing")
	check(is_zero_approx(game.world.time),"briefing has zero battle time")
	check(game.plan.godot3d.campaign_chapter==1,"CLI chooses requested chapter")
	game.campaign_ui.plan_choice.select(2);game.campaign_ui.plan_choice.item_selected.emit(2)
	check(game.plan.godot3d.campaign_tactic=="T03" and game.world.campaign_director.plan_executor.tactic_id=="T03","pre-battle tactic reaches executor")
	game.reset_range()
	check(game.armory.visible and is_zero_approx(game.world.time),"retry returns to frozen briefing")
	check(game.world.campaign_director.plan_executor.tactic_id=="T03","retry preserves tactic")
	game.world.campaign.finish("won","contract state");game.campaign_ui.refresh()
	check(game.campaign_progress.unlocked==2 and game.campaign_progress.completed==[1],"win unlocks next chapter")
	check(game.campaign_ui.result_panel.visible and game.campaign_ui.result_next_button.visible,"win offers next chapter")
	game.next_campaign_chapter()
	check(game.plan.godot3d.campaign_chapter==2 and game.armory.visible,"next enters chapter two briefing")
	check(is_zero_approx(game.world.time),"next never auto-starts combat")
	check(game.campaign_ui.hud_summary.capture.name.begins_with("1/1 "),"normal HUD carries active stage")
	game.show_campaign_chapters()
	check(game.home_ui.page=="campaign" and game.home_ui.campaign_view.visible,"chapter menu visible after rebuild")
	check(game.home_ui.chapter_buttons[2].disabled and not game.home_ui.chapter_buttons[1].disabled,"chapter locks match progress")
	game.home_ui.hide_menu();game.show_campaign_chapters()
	check(game.home_ui.chapter_buttons.size()==10 and game.home_ui.chapter_title.text.contains("1 / 10"),"repeated menu entry keeps content")
	game.home_ui.hide_menu();game.world.campaign.finish("lost","无可接管的存活友军");game.campaign_ui.refresh()
	check(game.campaign_progress.unlocked==2 and not game.campaign_ui.result_next_button.visible,"loss does not unlock next")
	game.campaign_progress.unlocked=10;game.campaign_progress.completed=[1,2,3,4,5,6,7,8,9]
	game.start_campaign_chapter(10,"T02")
	check(game.armory.visible and is_zero_approx(game.world.time),"final chapter also waits in briefing")
	var flash_count=0
	for group in game.flash_batches.pool.groups.values():
		flash_count+=group.entries.size()
		for handle in group.entries:check(int(handle.slot)<group.instances.instance_count,"every native flash handle fits allocated storage")
	check(flash_count==435,"chapter ten registers all435 authored flash pieces")
	check(game.flash_batches.pool.capacity==880,"muzzle-specific storage covers the supported roster")
	print("NATIVE_FLASH_STORAGE pieces=%d capacity=%d"%[flash_count,game.flash_batches.pool.capacity])
	game.world.campaign.finish("won","全部阶段目标已完成");game.campaign_ui.refresh()
	check(game.campaign_progress.finished() and not game.campaign_progress.dirty,"final completion persisted")
	check(game.campaign_ui.result_title.text=="十章战役 · 完成","final ending shown")
	check(game.campaign_ui.result_next_button.text.contains("查看章节"),"ending does not invent chapter eleven")
	game.next_campaign_chapter()
	check(game.home_ui.page=="campaign","ending returns to chapter map")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(SAVE+suffix):DirAccess.remove_absolute(SAVE+suffix)
	print("campaign_flow_contract: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
