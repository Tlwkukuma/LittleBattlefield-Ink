extends SceneTree
const Game=preload("res://scripts/proving_ground.gd")
var game
var failures: Array=[]
func _initialize():run.call_deferred()
func check(value: bool,text: String):
	if not value:failures.append(text);push_error(text)
func shot(name: String):
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/"+name+".png")
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game=Game.new();game.qa_mode=true;root.add_child(game)
	game.set_physics_process(false)
	await create_timer(.5).timeout
	game.toggle_armory();await shot("range-armory")
	check(game.armory.get_global_rect().end.y<root.size.y-90,"Armory fits above HUD")
	check(game.weapon_list.item_count==84,"All weapons listed")
	for i in range(7):
		game.weapon_filter.select(i);game.refresh_weapons();check(game.weapon_list.item_count>0,"Weapon filter "+str(i))
	game.weapon_filter.select(0);game.refresh_weapons();game.armory.hide()
	var plant_errors=[]
	for i in range(150):
		game.world.step(1.0/60,Vector2.RIGHT,game.world.player.position+Vector2.RIGHT*8,false,false)
		game.update_views(1.0/60)
		var view: Dictionary=game.actors[0]
		for side in range(2):
			if view.foot_contact[side]:
				var actual: Vector3=view.body.global_transform*view.skeleton.get_bone_global_pose(5+side).origin
				plant_errors.append(actual.distance_to(view.foot_plants[side]))
	plant_errors.sort()
	print("PLANTED_FOOT_ERROR_M: p95=",plant_errors[int(plant_errors.size()*.95)]," max=",plant_errors[-1])
	check(plant_errors[int(plant_errors.size()*.95)]<.06,"Planted foot stays within 6cm of ground anchor")
	game.reset_range()
	game.set_process(false);game.ui.hide()
	game.world.player.position=Vector2(0,5);game.world.player.facing=Vector2(.78,-.63);var player=game.world.player
	game.camera.size=4.0;game.camera.position=Vector3(0,5.0,10.0);game.camera.look_at(Vector3(0,.65,5))
	for stance in range(3):
		player.stance=stance;player.stance_blend=stance;player.velocity=Vector2.ZERO;game.update_views(0)
		await shot("stance-"+str(stance))
	player.stance=0;player.stance_blend=0;player.velocity=Vector2(2.5,0);player.walk=1.6;game.update_views(0);await shot("walk-stride")
	game.ui.show();game.set_process(true);game.zoom=20;game.world.player.position=Vector2(0,6.5);player.velocity=Vector2.ZERO
	game.world.equip("rpg");game.aim=Vector2(-7.4,-.25)
	game.world.fire(player,game.world.weapon_for(player),player,player.position,(game.aim-player.position).angle(),1.35,game.aim)
	for i in range(210):game.world.step(1.0/60,Vector2.ZERO,game.aim,false,false);await process_frame
	game.world.fire(player,game.world.weapon_for(player),player,player.position,(game.aim-player.position).angle(),1.35,game.aim)
	for i in range(65):game.world.step(1.0/60,Vector2.ZERO,game.aim,false,false);await process_frame
	await shot("range-explosion")
	for i in range(150):game.world.step(1.0/60,Vector2.ZERO,game.aim,false,false);await process_frame
	await create_timer(2).timeout
	await shot("range-destruction")
	check(game.world.broken>0,"Repeated RPG fire makes a rendered breach")
	game.world.player.position=Vector2(-6.5,-3);game.aim=Vector2(-6.5,-8);game.world.equip("awm")
	game.world.fire(player,game.world.weapon_for(player),player,player.position,-PI/2,1.35,game.aim)
	for i in range(65):game.world.step(1.0/60,Vector2.ZERO,game.aim,false,false);await process_frame
	await create_timer(.8).timeout
	await shot("range-corpse");check(game.fx.corpses.size()>0,"Rendered death reaction")
	game.world.enter_vehicle(5);game.zoom=13
	for i in range(40):game.world.step(1.0/60,Vector2(0,-1),Vector2(-25,-5),false,false);await process_frame
	await shot("range-vehicle")
	game.toggle_editor();game.zoom=35;game.editor_focus=Vector2.ZERO
	var ed=game.editor;var initial=ed.plan.instances.size();ed.palette_kind="prefab";ed.palette_id="building.barracks";ed.place(Vector2(7,8))
	check(ed.plan.instances.size()==initial+1,"Editor prefab placement")
	ed.move_selected(Vector2(1,2));ed.height_field.value=3.6;ed.apply_properties()
	check(ed.find_item().godot3d.height==3.6,"Editor 3D metadata")
	var selected=ed.selected;ed.duplicate_selected();check(ed.plan.instances.size()==initial+2,"Editor duplicate")
	ed.delete_selected();check(ed.plan.instances.size()==initial+1,"Editor delete")
	ed.undo();check(ed.plan.instances.size()==initial+2,"Editor undo")
	ed.redo();check(ed.plan.instances.size()==initial+1,"Editor redo")
	ed.selected=selected;ed.refresh_selection();ed.palette_id=""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://exports"))
	check(ed.save("res://exports/qa-editor-roundtrip.json"),"Editor saves JSON")
	var saved=ed.plan.duplicate(true);check(ed.load_file("res://exports/qa-editor-roundtrip.json"),"Editor loads JSON")
	var normalized=JSON.parse_string(JSON.stringify(saved))
	check(ed.plan.instances==normalized.instances and ed.plan.looseSegments==normalized.looseSegments,"Editor round trip preserves 2D and 3D")
	game.editor_focus=Vector2.ZERO;await shot("range-editor")
	check(ed.panel.get_global_rect().end.y<root.size.y-90,"Editor scroll panel fits above HUD")
	game.toggle_editor();check(not game.editing and game.world.objects.size()>15,"Editor playtest rebuilds authored scene")
	ed.load_plan(game.catalog.scenes[0]);game.toggle_editor();game.zoom=45;game.editor_focus=Vector2.ZERO;await shot("range-source-scene")
	print("RENDER / EDITOR FAILURES: ",failures)
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
