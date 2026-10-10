extends SceneTree
## Static scene/UI lifecycle only. Processing stays disabled: no movement,
## firing, battle simulation, screenshots, or visual acceptance.
const Game=preload("res://scripts/proving_ground.gd")
var checks=0
var failures: Array=[]
var game

func check(value: bool,label: String):
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize():run.call_deferred()

func check_campaign_entry():
	check(Engine.physics_ticks_per_second==60 and Engine.max_physics_steps_per_frame==2,"Campaign uses 60 Hz player ticks with bounded catch-up and staggered 30 Hz NPCs")
	check(game.world.campaign_active() and game.world.campaign.phase=="playing","Orchard creates a playing campaign in the same host")
	check(game.world.units.size()==60 and game.actors.size()==60,"All 60 stable unit slots have actor views")
	var blue=0;var red=0;var controlled=0;var bindings=true
	for i in range(game.world.units.size()):
		var u: Dictionary=game.world.units[i]
		blue+=1 if u.team==0 and u.alive else 0;red+=1 if u.team==1 and u.alive else 0
		controlled+=1 if u.player else 0
		bindings=bindings and u.id==i and game.actors[i].weapon==u.weapon_id and is_instance_valid(game.actors[i].skeleton)
	check(blue==30 and red==30 and controlled==1,"Initial forces are 30 per team with exactly one controlled soldier")
	check(bindings and game.fx.actor_views.size()==60,"Actor IDs, source skeletons, weapon bindings and FX slots match")
	check(game.world.player.get("loadout",[]).size()==4,"Controlled soldier has the four authored equipment slots")
	check(not game.world.invulnerable and not game.world.auto_targets and game.world.ai_enabled,"Campaign disables training invulnerability and automatic targets")
	check(not game.campaign_ui.training_box.visible and game.campaign_ui.equipment_box.visible,"Campaign replaces the training catalog with equipment UI")
	check(not game.campaign_ui.editor_button.visible and not game.campaign_ui.roof_button.visible,"Campaign hides the editor and roof override controls")
	check(game.campaign_ui.objective_views.size()==1 and is_instance_valid(game.campaign_ui.control_ring),"Objective and controlled-player marker are built")
	check(not game.campaign_ui.result_panel.visible and not game.paused and not game.editing,"Fresh campaign has no stale pause, result or editor state")

func run():
	game=Game.new();game.qa_mode=true;game.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	check(not game.world.campaign_active(),"Default entry still opens the unified training ground")
	check(game.campaign_ui.training_box.visible and not game.campaign_ui.equipment_box.visible,"Training UI is present before entering the level")
	var host_id=game.get_instance_id()
	var old_stage=game.stage;var old_reticle=game.crosshair.overlay;var old_preview=game.grenade_preview
	game.start_level01()
	check_campaign_entry()
	check(game.get_instance_id()==host_id,"Entering the level reuses the proving-ground host")
	await process_frame
	check(not is_instance_valid(old_stage) and not is_instance_valid(old_reticle) and not is_instance_valid(old_preview),"Switching frees the previous stage, trajectory and UI-owned weapon overlays")
	check(is_zero_approx(game.world.time),"Disabled processing does not advance battle time")
	var weapon=game.world.player.weapon_id;var mounted=game.world.player.mounted;var roof=game.roof_mode
	game.toggle_editor();game.cycle_roof();game.equip_index(0);game.trial_vehicle()
	check(not game.editing and game.roof_mode==roof and game.world.player.weapon_id==weapon and game.world.player.mounted==mounted,"Training actions are rejected by their shared campaign guards")
	game.toggle_armory();game.campaign_ui.refresh()
	check(game.armory.visible and game.campaign_ui.slots.size()==4 and not game.campaign_ui.slots[0].text.is_empty(),"Campaign Tab panel exposes readable four-slot equipment")
	game.toggle_armory()
	# Inject only terminal rule states to inspect presentation; never step a battle.
	game.world.campaign.phase="won";game.campaign_ui.refresh()
	check(game.paused and game.campaign_ui.result_panel.visible and not game.armory.visible,"Win presentation pauses input and closes the equipment panel")
	game.toggle_armory()
	check(not game.armory.visible,"Terminal state rejects reopening equipment")
	game.world.campaign.phase="lost";game.campaign_ui.refresh()
	check(game.campaign_ui.result_title.text.contains("战败"),"Loss presentation uses the same result panel")
	old_stage=game.stage;var old_ring=game.campaign_ui.control_ring
	game.reset_range();check_campaign_entry()
	await process_frame
	check(not is_instance_valid(old_stage) and not is_instance_valid(old_ring),"Restart discards old stage and objective/control markers")
	game.start_training()
	await process_frame
	check(game.get_instance_id()==host_id and not game.world.campaign_active(),"Return opens training inside the same proving-ground host")
	check(Engine.physics_ticks_per_second==60 and Engine.max_physics_steps_per_frame==8,"Returning restores the training timing defaults")
	check(game.campaign_ui.training_box.visible and not game.campaign_ui.equipment_box.visible and not game.campaign_ui.result_panel.visible,"Returning restores training UI without campaign result remnants")
	check(not game.paused and not game.editing and is_zero_approx(game.world.time),"Return clears terminal pause while processing remains disabled")
	check(game.world.event.is_connected(game.on_world_event),"World event presentation remains connected after all rebuilds")
	game.free()
	await process_frame
	print("ORCHARD_ENTRY_CONTRACT ",checks-failures.size(),"/",checks," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
