extends SceneTree
## Real native entry, retry and render retirement; simulation disabled before ready.
var checks=0
var failures=0
func _initialize():call_deferred("run")
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func run():
	create_timer(240).timeout.connect(func():printerr("H01 entry startup timeout");quit(2))
	var game=load("res://scripts/proving_ground.gd").new()
	game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	while game.home_ui==null or game.loading_active:
		if game.loading_ui!=null and game.loading_ui.state in ["failed","cancelled"]:printerr("H01 startup failed");quit(2);return
		await process_frame
	var before=game.campaign_progress.completed.duplicate()
	await game.start_campaign_chapter(101,"H01")
	check(game.world.is_hanlue() and game.plan.id=="hanlue-h01","independent H01 entry")
	check(game.armory.visible and game.world.time==0,"entry frozen in briefing")
	check(game.home_ui.main_view.has_node("HistoricalCampaign"),"native historical entry button")
	check(game.campaign_ui.hanlue_actions.visible and not game.campaign_ui.plan_choice.visible,"mission controls replace irrelevant capture tactics")
	check(game.campaign_ui.hanlue_markers.size()==2,"two actual extraction markers")
	check(game.world.units.size()==24 and game.world.vehicles.size()==3,"entry roster exact")
	game.update_views(0)
	for vehicle in game.world.vehicles:
		check(game.vehicle_views[vehicle.id].channels.is_empty(),"no visual gun channels")
		for id in vehicle.passenger_ids:check(game.actors[id].root.visible,"open truck passenger visible")
	# Real posed skeleton capsules, not only the no-view simulation fallback.
	var truck: Dictionary=game.world.vehicles[0]
	var observer: Dictionary=game.world.units[truck.passenger_ids[0]]
	for group in game.world.hanlue_tactics.groups:
		var target: Dictionary=group.members[1]
		var source=game.catalog.original_point(target.position,game.plan)
		truck.position=game.catalog.position([source.x,1120],game.plan)
		game.world.VehicleGround.initialize(game.world.terrain,truck,game.world);game.world.hanlue_transport.sync_passengers(truck)
		observer.facing=(target.position-observer.position).normalized()
		target.stance=2;target.stance_blend=2.0;game.actors[target.id].erase("pose_ready");game.update_views(0)
		check(not target.get("hit_shapes",[]).is_empty() and not observer.get("hit_shapes",[]).is_empty(),"real frozen skeleton capsules available "+str(group.id))
		check(not game.world.campaign_ai.perception.can_see(observer,target),"posed prone head concealed "+str(group.id))
		target.stance=0;target.stance_blend=0.0;game.actors[target.id].erase("pose_ready");game.update_views(0)
		check(game.world.campaign_ai.perception.can_see(observer,target),"posed standing head exposed "+str(group.id))
	var unit: Dictionary=game.world.units[1];var inventory=unit.inventory.duplicate(true)
	game.world.retire_mission_unit(unit,"extracted");game.update_views(0)
	game.crowd_batches.refresh();game.rigid_batches.refresh();game.weapon_batches.refresh();game.flash_batches.refresh()
	var view: Dictionary=game.actors[unit.id]
	check(not view.root.visible and unit.alive and unit.inventory==inventory,"living retired actor hidden with equipment retained")
	if game.crowd_batches.entries.has(view.root.get_instance_id()):
		var entry: Dictionary=game.crowd_batches.entries[view.root.get_instance_id()]
		check(entry.draw_index==-1,"retired actor removed from crowd batch")
		check(not view.shadow.is_visible_in_tree(),"retired actor shadow source hidden")
		# Headless dummy renderer does not expose reliable MultiMesh transform readback.
		# The shared batch refresh reads this exact visibility to submit a zero transform.
	var weapon_handles=0
	for id in game.weapon_batches.entries:
		var entry: Dictionary=game.weapon_batches.entries[id]
		if view.root.is_ancestor_of(entry.source):
			for handle in entry.handles:
				weapon_handles+=1;check(handle.index==-1,"retired weapon atlas hidden")
	for id in game.rigid_batches.entries:
		var entry: Dictionary=game.rigid_batches.entries[id]
		if view.root.is_ancestor_of(entry.source):
			for handle in entry.handles:
				weapon_handles+=1;check(handle.pose.basis.determinant()==0,"retired rigid weapon part hidden")
	game.vehicle_part_batches.refresh()
	for entry in game.vehicle_part_batches.entries:
		if view.root.is_ancestor_of(entry.source):
			weapon_handles+=1;check(entry.pose.basis.determinant()==0,"retired palette weapon part hidden")
	check(weapon_handles>0,"retired weapon test covered actual registered parts")
	await game.start_campaign_chapter(101,"H01")
	check(game.world.units.size()==24 and game.world.vehicles.size()==3 and game.world.campaign.hanlue.extracted.is_empty(),"retry reconstructs exactly one finite roster")
	check(game.campaign_progress.completed==before and not game.plan.godot3d.campaign_checkpoint,"H01 preserves ten-chapter progress")
	check(game.world.time==0 and game.world.simulation_tick==0 and game.world.shots==0,"zero battle ticks throughout entry/retry")
	print("HANLUE_ENTRY checks=%d failures=%d; no gameplay inputs/ticks"%[checks,failures]);quit(1 if failures else 0)
