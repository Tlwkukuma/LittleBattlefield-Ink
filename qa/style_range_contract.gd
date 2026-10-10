extends SceneTree
## Frozen resource checks: no input, world.step, movement, shooting or gameplay simulation.
var failed=false
func check(value: bool,description: String):
	if not value:failed=true;push_error("RANGE2_CONTRACT "+description)
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground_2.tscn").instantiate()
	game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 演武场2 · 静态资源检查（自动关闭）")
	check(game.is_style_range(),"Dedicated scene must select range 2")
	for instance in game.plan.instances:check(game.catalog.prefabs.has(instance.prefabId),"Every requested nature prefab must be registered")
	var components=[]
	for object in game.world.objects:components.append(object.component_id)
	for id in ["tree.dry-acacia","rock.sandstone-layers","rock.granite-low","wall.brick","wall.concrete","wall.wood-fence"]:check(id in components,"Compiled sample missing "+id)
	check(game.world.units.size()==8,"Player, five red and two blue samples")
	check(game.world.vehicles.size()==3,"Three real driveable vehicles")
	check(game.world.units[6].team==0 and game.world.units[1].team==1,"Explicit target teams")
	check(absf(game.world.terrain.height(Vector2(0,6)))<.001,"Spawn and painted floor must be level")
	check(game.world.terrain.height(Vector2(15,-4))>.02,"Nature edge keeps real dune relief")
	check(game.crowd_batches!=null and game.wall_batches!=null,"Existing crowd and damage batching")
	check(load("res://assets/range2/ink_wear.svg").get_image().has_mipmaps(),"Scratch tile must have mipmaps")
	check(load("res://assets/range2/depot-materials-v2.png").get_image().has_mipmaps(),"Material atlas must have mipmaps")
	var families={}
	for object in game.world.objects:families[object.range2_family]=true
	for kind in [1,2,3,4,6]:check(families.has(kind),"Material family "+str(kind)+" missing")
	# Compare detached geometry fixtures: tagging must not alter a real breach,
	# cutaway or damage variant's topology, normals or authored RGB.
	var geometry=preload("res://scripts/terrain_art.gd")
	for object in game.world.objects:
		if not object.component_id.begins_with("wall."):continue
		for cut in [INF,1.15]:
			var fixture=object.duplicate(true)
			for index in range(fixture.hp.size()):
				if index%5==2:fixture.hp[index]=0
			var tagged=geometry.wall_geometry(fixture,cut)
			fixture.erase("range2_family")
			var plain=geometry.wall_geometry(fixture,cut)
			check(tagged.v==plain.v and tagged.n==plain.n,"Material tags must preserve damaged geometry and normals")
			for index in range(tagged.c.size()):
				check(tagged.c[index].r==plain.c[index].r and tagged.c[index].g==plain.c[index].g and tagged.c[index].b==plain.c[index].b,"Material tags preserve authored RGB")
	var snapshot=[]
	for object in game.world.objects:snapshot.append([object.id,object.hp.duplicate(),object.position])
	var bodies=[]
	for actor in game.actors:
		var body=actor.model.find_child("Source_Body",true,false)
		check(body!=null and body.skin!=null,"Retain original skinned body")
		bodies.append(body.mesh)
		var helmet_parts=[]
		for surface in range(actor.helmet.mesh.get_surface_count()):helmet_parts.append(actor.helmet.get_active_material(surface).get_shader_parameter("range2_part"))
		helmet_parts.sort()
		check(helmet_parts==[1,2,3],"Imported helmet shell, stripe and rim retain explicit palette roles")
	for group_name in ["shared","helmets"]:
		var tags=game.crowd_batches.groups[group_name].instances.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
		var helmet_parts={}
		for i in range(0,tags.size(),4):
			if int(tags[i])==1:helmet_parts[int(tags[i+3])]=true
		check(helmet_parts.size()==3 and helmet_parts.has(1) and helmet_parts.has(2) and helmet_parts.has(3),"Worn and detached helmets preserve all material roles through batching")
	game.armory.hide();game._process(0)
	game.crowd_batches.refresh();game.vehicle_part_batches.refresh();game.rigid_batches.refresh();game.weapon_batches.refresh()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var readings=[]
	for style in [true,false,true]:
		game.graphic_style=style;RenderingServer.global_shader_parameter_set("range2_enabled",style)
		for i in range(36):
			await process_frame
			game.hud_batches.refresh()
		var samples=[]
		for i in range(36):
			await process_frame
			samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		samples.sort()
		var reading={"style":style,"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"gpu_median_ms":samples[18],"gpu_p95_ms":samples[34]}
		readings.append(reading)
		print("RANGE2_STATIC_RENDER "+JSON.stringify(reading))
	check(readings[0].draws==readings[1].draws and readings[1].draws==readings[2].draws,"A/B adds no submissions")
	if DisplayServer.get_name()!="headless":check(readings[0].draws<50,"Frozen range draw budget below 50")
	for i in range(snapshot.size()):
		var object=game.world.objects[i]
		check(snapshot[i]==[object.id,object.hp,object.position],"A/B cannot change destruction/collision state")
	for i in range(game.actors.size()):check(bodies[i]==game.actors[i].model.find_child("Source_Body",true,false).mesh,"A/B cannot replace models")
	check(game.world.time==0 and game.world.shots==0,"No gameplay simulation")
	# Rebuild frozen resources only: switching out must not tint the original range.
	var sample_plan=game.plan.duplicate(true);var launch_stamp=game.launch_stamp;var font=game.ui.theme.default_font
	game.rebuild(game.catalog.range_plan())
	check(not game.is_style_range() and not game.theme_uses_graphic,"Original range restores original material/UI mode")
	game.rebuild(sample_plan)
	check(game.launch_stamp==launch_stamp and game.ui.theme.default_font==font,"Switch/reset preserves launch identity and shared glyph font")
	check(game.world.time==0 and game.world.shots==0,"Resource rebuild does not play")
	print("RANGE2_CONTRACT "+JSON.stringify({"passed":not failed,"version":game.BUILD_VERSION,"title":root.title,"scene":game.plan.id,"units":game.world.units.size(),"vehicles":game.world.vehicles.size(),"objects":game.world.objects.size(),"simulation_time":game.world.time,"shots":game.world.shots}))
	game.free();quit(1 if failed else 0)
