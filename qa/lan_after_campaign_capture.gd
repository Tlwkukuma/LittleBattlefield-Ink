extends SceneTree
## Checks the in-game route that first revealed the blank menu.
func _initialize():call_deferred("run_check")

func bright_content(image: Image,rect: Rect2) -> bool:
	var count=0
	for y in range(int(rect.position.y)+5,int(rect.end.y)-5):
		for x in range(int(rect.position.x)+5,int(rect.end.x)-5):
			var color=image.get_pixel(x,y)
			if color.r>.65 and color.g>.65 and color.b>.65:
				count+=1
				if count>12:return true
	return false

func run_check():
	change_scene_to_file("res://proving_ground.tscn")
	for index in range(4):await process_frame
	var game=current_scene
	if game==null or not game.is_node_ready():printerr("LAN_MENU scene failed");quit(2);return
	game.start_level01()
	game.show_home()
	for index in range(25):await process_frame
	await RenderingServer.frame_post_draw
	var home=game.home_ui
	var image=game.get_viewport().get_texture().get_image()
	var rect=home.play_button.get_global_rect()
	image.save_png("res://qa/lan-after-campaign-home.png")
	if not bright_content(image,rect):
		printerr("LAN_MENU campaign home button did not render");quit(2);return
	home.open_lan()
	home=game.home_ui
	for index in range(25):await process_frame
	await RenderingServer.frame_post_draw
	image=game.get_viewport().get_texture().get_image()
	rect=home.host_button.get_global_rect()
	image.save_png("res://qa/lan-after-campaign-lan.png")
	if not bright_content(image,rect):
		printerr("LAN_MENU campaign LAN button did not render");quit(2);return
	home.hide_menu()
	game.show_home()
	game.home_ui.open_lan()
	home=game.home_ui
	for index in range(25):await process_frame
	await RenderingServer.frame_post_draw
	image=game.get_viewport().get_texture().get_image()
	if not bright_content(image,home.host_button.get_global_rect()):
		printerr("LAN_MENU reopened LAN button did not render");quit(2);return
	print("LAN_MENU_AFTER_CAMPAIGN_OK version=",game.BUILD_VERSION," title=",game.get_window().title)
	quit()
