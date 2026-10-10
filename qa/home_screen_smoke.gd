extends SceneTree

func _initialize():call_deferred("check_home")

func check_home():
	change_scene_to_file("res://proving_ground.tscn")
	for i in range(10):await process_frame
	var game=current_scene
	print("HOME_SCREEN_READY args=",OS.get_cmdline_user_args()," visible=",game.home_ui.overlay.visible," campaign=",game.world.campaign_active()," page=",game.home_ui.page," version=",game.BUILD_VERSION)
	quit(0 if game.home_ui.overlay.visible else 2)
