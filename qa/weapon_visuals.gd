extends SceneTree
const Game=preload("res://scripts/proving_ground.gd")
const Props=preload("res://scripts/proving_art.gd")
var failures: Array=[]
func _initialize():run.call_deferred()
func run():
	var game=Game.new();game.qa_mode=true;root.add_child(game);game.set_physics_process(false);game.set_process(false)
	var holder=Node3D.new();root.add_child(holder);holder.hide()
	for w in game.catalog.data.weapons:
		var model=Props.weapon(holder,w)
		if model.get_child_count()==0:failures.append("Empty weapon "+w.id)
		if w.shapes!=null and Props.weapon_cache[w.id].get_surface_count()==0:failures.append("Empty extruded mesh "+w.id)
	holder.queue_free()
	game.ui.hide();game.world.player.position=Vector2(0,5);game.world.player.facing=Vector2(.65,.76);game.camera.size=4.5;game.camera.position=Vector3(0,4.8,10);game.camera.look_at(Vector3(0,.9,5))
	for id in ["p92","he-grenade","katana"]:
		game.world.equip(id);game.world.player.last_shot=game.world.time-.2;game.update_views(0)
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://qa/weapon-"+id+".png")
	print("WEAPON_MESHES 84 built; failures: ",failures);quit(0 if failures.is_empty() else 1)
