extends SceneTree
## Frozen original entry scene; checks actual GPU submissions without playing.
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 第一关 · 渲染资源检查（自动关闭）")
	# The scene stays disabled throughout. Exclude the briefing's native menu
	# controls so the counter measures the same HUD as the battle screenshots.
	game.armory.hide()
	game._process(0);game.crowd_batches.refresh();game.vehicle_part_batches.refresh();game.rigid_batches.refresh();game.weapon_batches.refresh()
	for view in game.campaign_ui.objective_views:view.flag.refresh(game)
	for i in range(80):
		await process_frame
		game.hud_batches.refresh()
	print("GPU_RENDER_CONTRACT "+JSON.stringify({"version":game.BUILD_VERSION,"title":root.title,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"simulation_time":game.world.time,"shots":game.world.shots,"crowd_groups":game.crowd_batches.groups.size(),"rigid_active":game.rigid_batches.active_groups,"palette_active":game.vehicle_part_batches.active_groups}))
	var outline_contract=true;var shared_outlines=0
	for key in game.vehicle_part_batches.groups:
		var group: Dictionary=game.vehicle_part_batches.groups[key]
		if str(key).begins_with("outline/"):shared_outlines+=1
		if group.get("split_outline",false):
			outline_contract=outline_contract and group.batched_material.next_pass==null
			group.material.set_shader_parameter("damage",.42)
			game.vehicle_part_batches.refresh()
			outline_contract=outline_contract and is_equal_approx(float(group.batched_material.get_shader_parameter("damage")),.42)
			group.material.set_shader_parameter("damage",0.0)
	game.vehicle_part_batches.refresh()
	print("GPU_VEHICLE_CONTOURS groups=",shared_outlines," independent_damage=",outline_contract)
	# Static render-resource stress: show existing flash parts and allocate bounded
	# cosmetic meshes only. No unit damage, shots, AI, navigation or world.step.
	for actor in game.actors:actor.muzzle.show()
	for i in range(18):game.fx.death(game.world.units[i*3],Vector3.ZERO)
	for i in range(12):game.fx.detach_helmet(game.actors[i],Vector3.ZERO)
	var ammo=preload("res://scripts/ammo_presentation.gd")
	var at=Vector3(game.world.player.position.x,game.world.player.elevation+.1,game.world.player.position.y)
	for i in range(120):
		var profile=ammo.profile(game.catalog.weapons[["m416","akm","s1897","o12","awm","p92"][i%6]])
		game.fx.piece(at+Vector3((i%12)*.05,0,(i/12)*.05),profile.case_size,profile.case_color,Vector3.ZERO,120,false,9.8,"case",profile)
	for i in range(6):
		var unit=game.world.units[i].duplicate(true);unit.reload=1;game.fx.drop_magazine({"unit":unit,"weapon":game.catalog.weapons[unit.weapon_id],"position":at,"angle":0})
	game.fx.blood.queue_hit({"unit":game.world.player,"amount":25,"point":at+Vector3.UP,"incoming":Vector3.FORWARD});game.fx.blood.advance(.001)
	game.fx.blood.add_stain({"radius":.1,"landing":at,"seed":.5});game.fx.blood.write_batches()
	var blood_slots_valid=true
	for i in range(288):blood_slots_valid=blood_slots_valid and int(game.fx.blood.spray_mesh.get_instance_custom_data(i).r)==i
	print("GPU_BLOOD_SLOTS valid=",blood_slots_valid," slots=288")
	# Activate original resources directly; these do not insert bullets/loot into
	# the world, apply damage, or advance any battle/AI state.
	game.loot_visual.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,at));game.loot_visual.multimesh.visible_instance_count=1
	game.bullet_flight_batch.instances.set_instance_transform(0,Transform3D(Basis.IDENTITY,at+Vector3.UP));game.bullet_flight_batch.instances.set_instance_color(0,Color("f5b16b"));game.bullet_flight_batch.instances.set_instance_custom_data(0,Color(.27,1,0,0));game.bullet_flight_batch.instances.visible_instance_count=1
	game.fx.vehicle_destruction.spawn(at,Vector3.ONE,Color("514a50"),0,2.4)
	game.fx.vehicle_destruction.spawn(at,Vector3.ONE*.1,Color("49434a"),4,.65)
	game.fx.piece(at,Vector3.ONE*.1,Color("b59266"),Vector3.ZERO,5,false,0,"debris")
	game.fx.piece(at,Vector3.ONE,Color("ffbb44"),Vector3.ZERO,5,true,0,"flash")
	# Activate the shared wall-ink resource without simulating a hit.
	var wall_ink=game.wall_batches.impacts
	wall_ink.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,at+Vector3.UP))
	wall_ink.multimesh.set_instance_color(0,Color("585d57"));wall_ink.multimesh.visible_instance_count=1
	if game.fx.get("puffs")!=null:game.fx.puffs.advance(.001)
	# Heavy ordnance is also presentation-only: no projectile enters the world.
	for weapon in game.catalog.weapons.values():
		if weapon.kind not in ["rocket","mortar","vehicleMortar","grenadeProjectile","grenade"]:continue
		var resource=preload("res://scripts/weapon_effects.gd").projectile(game.stage,weapon,true)
		resource.position=at+Vector3.UP*2;game.weapon_batches.register_tree(resource)
	for copy in game.player_occlusion.copies:copy.show()
	game.player_occlusion.material.set_shader_parameter("visibility",1.0)
	game.player_occlusion.marker.show();game.player_occlusion.marker.position=at
	game.player_occlusion.marker_material.set_shader_parameter("visibility",1.0)
	for i in range(30):
		var label=Label3D.new();label.text=str(10+i);label.font_size=42;label.pixel_size=.006;label.modulate=Color("f4d7d3");label.outline_modulate=Color("6c4059");label.layers=0;game.stage.add_child(label);label.position=at+Vector3((i%6)*.4,1.5,(i/6)*.4);game.damage_labels.append({"node":label,"age":0.0})
	game.damage_number_batch.refresh()
	game.crowd_batches.refresh();game.rigid_batches.refresh();game.flash_batches.refresh()
	var maximum=0
	for size in [22,44,96]:
		game.camera.size=size
		game.crowd_batches.refresh();game.damage_number_batch.refresh();game.weapon_batches.refresh()
		for i in range(8):await process_frame
		maximum=maxi(maximum,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		print("GPU_FX_RESOURCE draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," camera_size=",size," flash_roots=",game.flash_batches.active," rigid_groups=",game.rigid_batches.active_groups," cosmetics=",game.fx.batching_stats())
	var passed=maximum<50 and game.world.time==0 and game.world.shots==0 and blood_slots_valid and outline_contract and shared_outlines==1
	# Replace render resources across the entire catalogue; this does not equip,
	# move, fire or advance units. Covers the old fallback after wave/weapon changes.
	var weapons=game.catalog.weapons.values()
	for offset in [0,60]:
		for i in range(game.actors.size()):game.replace_weapon(game.actors[i],weapons[(i+offset)%weapons.size()])
		for i in range(2):await process_frame
		game.weapon_batches.refresh();game.vehicle_part_batches.refresh();game.rigid_batches.refresh();game.flash_batches.refresh()
		for i in range(8):await process_frame
		var draws=int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));maximum=maxi(maximum,draws)
		print("GPU_WEAPON_REPLACEMENT draws=",draws," groups=",game.weapon_batches.active_groups," atlas_vertices=",game.weapon_batches.cursor/3," offset=",offset)
	passed=passed and maximum<50
	# Exercise every objective state without changing the campaign's rules/state.
	for progress in [-1.0,-.5,0.0,.5,1.0]:
		for view in game.campaign_ui.objective_views:
			var snapshot: Dictionary=view.point.duplicate(true);snapshot.progress=progress
			view.flag.point=snapshot;view.flag.refresh(game)
		for i in range(3):await process_frame
		maximum=maxi(maximum,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	for view in game.campaign_ui.objective_views:view.flag.point=view.point;view.flag.refresh(game)
	passed=passed and maximum<50
	print("GPU_RESOURCE_BUDGET maximum=",maximum," passed=",passed," simulation_time=",game.world.time," shots=",game.world.shots)
	game.free();quit(0 if passed else 1)
