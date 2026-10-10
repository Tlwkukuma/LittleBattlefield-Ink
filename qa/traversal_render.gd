extends SceneTree
const Game=preload("res://scripts/proving_ground.gd")
var game
var failures=[]
var count=0
func _initialize():run.call_deferred()
func check(value: bool,label: String):
	count+=1
	if not value:failures.append(label);push_error(label)
func shot(name: String):
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/traversal-"+name+".png")
func pose_camera(target: Vector3,size: float=5):
	game.camera.size=size;game.camera.position=target+Vector3(3,4,5);game.camera.look_at(target)
func tick(frames: int,move: Vector2=Vector2.ZERO,sprint: bool=false,jump: bool=false):
	for i in range(frames):
		game.world.step(1.0/60,move,game.world.player.position+Vector2.UP*10,false,false,false,false,sprint,jump and i==0)
		game.update_views(1.0/60)
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game=Game.new();game.qa_mode=true;root.add_child(game);game.set_physics_process(false);game.set_process(false)
	await create_timer(.2).timeout
	game.update_views(0);game.update_camera(0);await shot("course")
	game.ui.hide()
	tick(48,Vector2.UP,true)
	var u=game.world.player;var view=game.actors[0]
	pose_camera(Vector3(u.position.x,.85,u.position.y));await shot("sprint")
	check(view.sprint>.95,"Sprint pose blends to running")
	game.reset_range();u=game.world.player;tick(21,Vector2.ZERO,false,true)
	view=game.actors[0];pose_camera(Vector3(u.position.x,1.2,u.position.y),5.0);await shot("jump")
	check(u.elevation>1 and absf(view.root.position.y-u.elevation)<.001,"Visual root follows jump height")
	for marker in view.ground_markers:check(marker.node.global_position.y<.06,"Jump shadow remains on ground")
	check(not view.foot_contact[0] and not view.foot_contact[1],"Jump releases planted feet")
	for i in range(view.skeleton.get_bone_count()):check(view.skeleton.get_bone_global_pose(i).is_finite(),"Finite jump bone "+str(i))
	tick(22);pose_camera(Vector3(u.position.x,.85,u.position.y));await shot("land")
	for course in [0,1]:
		game.reset_range();u=game.world.player;u.position=Vector2(-8,7.6+7*course)
		pose_camera(Vector3(-8,1.1,6.5+7*course),5.8)
		tick(1,Vector2.UP,false,true)
		check(not u.vault.is_empty(),"Training wall starts vault "+str(course))
		if u.vault.is_empty():continue
		for phase in [.18,.50,.85,1.0]:
			while not u.vault.is_empty() and u.vault_progress<phase:tick(1)
			await shot("vault-"+str(course)+"-"+str(int(phase*100)))
			view=game.actors[0]
			for side in range(2):
				var foot=view.skeleton.find_bone("L_Foot" if side==0 else "R_Foot") if view.get("source_rig",false) else 5+side
				var ankle: Vector3=view.skeleton.to_global(view.skeleton.get_bone_global_pose(foot).origin)
				if phase==.5:check(ankle.y>[1.0,1.65][course]+.10,"Tucked boots clear wall "+str(course)+" side "+str(side))
		check(u.grounded and u.position.y<6.0+course*7,"Visible vault lands behind wall")
	game.reset_range();game.ui.show();u=game.world.player
	var key=InputEventKey.new();key.keycode=KEY_SPACE;key.physical_keycode=KEY_SPACE;key.pressed=true
	game._unhandled_input(key);check(game.jump_pressed,"Space input requests jump")
	game._physics_process(1.0/60);check(not u.grounded and not game.jump_pressed,"Input edge consumed once")
	key.echo=true;game._unhandled_input(key);check(not game.jump_pressed,"Keyboard repeat does not queue jump")
	key.echo=false;game.paused=true;game._unhandled_input(key);game._physics_process(1.0/60);check(not game.jump_pressed,"Pause blocks queued jump")
	game.paused=false;game.toggle_editor();game._unhandled_input(key);check(not game.jump_pressed,"Editor handles Space without player jump")
	game.toggle_editor();game.toggle_armory();game.weapon_search.grab_focus();await process_frame
	game._unhandled_input(key);check(not game.jump_pressed,"Typing cannot trigger jump")
	game.weapon_search.release_focus();game.armory.hide()
	var shift=InputEventKey.new();shift.keycode=KEY_SHIFT;shift.physical_keycode=KEY_SHIFT;shift.pressed=true
	var forward=InputEventKey.new();forward.keycode=KEY_W;forward.physical_keycode=KEY_W;forward.pressed=true
	Input.parse_input_event(shift);Input.parse_input_event(forward);Input.flush_buffered_events()
	for i in range(45):game._physics_process(1.0/60)
	check(game.world.player.sprinting and game.world.player.velocity.length()>5.7,"Physical Shift + W reaches sprint through game input")
	shift=shift.duplicate();forward=forward.duplicate();shift.pressed=false;forward.pressed=false;Input.parse_input_event(shift);Input.parse_input_event(forward);Input.flush_buffered_events()
	game.reset_range();game.world.invulnerable=false;u=game.world.player;tick(20,Vector2.ZERO,false,true)
	game.world.damage_unit(u,10000,Vector3.ZERO,game.world.weapon_for(u),false)
	check(game.fx.corpses.size()==1 and game.fx.corpses[0].view.root.position.y>1,"Airborne death starts at actual height")
	for i in range(90):game.fx._process(1.0/60)
	check(game.fx.corpses[0].view.root.position.y<.01,"Airborne corpse settles on ground")
	print("TRAVERSAL RENDER: ",count-failures.size(),"/",count," passed. Failures: ",failures)
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
