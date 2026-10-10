extends SceneTree
const Game=preload("res://scripts/proving_ground.gd")
func _initialize():run.call_deferred()
static func count_meshes(node: Node) -> int:
	var count=0
	if node is Node3D and not node.visible:return 0
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var a=node.mesh.surface_get_arrays(surface);count+=(a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX]!=null else a[Mesh.ARRAY_VERTEX].size())/3
	for child in node.get_children():count+=count_meshes(child)
	return count
func run():
	var viewport=SubViewport.new();viewport.size=Vector2i(1600,1000);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	var stage=Node3D.new();viewport.add_child(stage)
	var environment=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("c6c4d8");environment.environment=env;stage.add_child(environment)
	Game.Art.box(stage,Vector3(0,-.06,0),Vector3(30,.1,30),Color("c6c4d8"),false)
	var camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.45;stage.add_child(camera);camera.position=Vector3(0,1.70,8);camera.look_at(Vector3(0,.96,0));camera.current=true
	var factory=Game.new();var catalog=factory.catalog;var world=Game.World.new();world.setup(catalog.range_plan(),catalog)
	var directions=[Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
	var names=["正面 · FRONT","左侧 · LEFT","背面 · BACK","右侧 · RIGHT"]
	for i in range(4):
		var view=Game.Art.soldier(stage,0,false,true);factory.replace_weapon(view,catalog.weapons.m416)
		var u=world.player.duplicate(true);u.position=Vector2(-2.04+i*1.36,0);u.facing=directions[i]
		view.root.position=Vector3(u.position.x,0,0);Game.Motion.update(view,u,0,0,2.1)
		var label=Label.new();label.text=names[i];label.add_theme_font_size_override("font_size",24);label.add_theme_color_override("font_color",Color("69687e"));label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.size=Vector2(340,44);label.position=Vector2(camera.unproject_position(view.root.position).x-170,822);viewport.add_child(label)
		if i==0:print("SOURCE_HERO_TRIANGLES=",count_meshes(view.body))
	var lod=Game.Art.soldier(stage,0,false,false);print("SOURCE_CROWD_TRIANGLES=",count_meshes(lod.body));lod.root.hide()
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://qa/character-turntable.png")
	print("TURNAROUND_CAPTURE res://qa/character-turntable.png")
	factory.free();viewport.queue_free();await process_frame;quit()
