extends SceneTree
## Numeric GPU readback of original vs batched materials in the frozen entry.
## No saved screenshots, alternate gameplay scene, input or battle simulation.
func _initialize():run.call_deferred()
func capture(game,original: bool,part_type: int=-1) -> Image:
	game.crowd_batches.visible=not original
	for actor in game.actors:
		for part in game.crowd_batches.parts(actor):part.node.layers=1 if original and (part_type<0 or part.type==part_type) else 0
		actor.shadow.layers=1 if original and part_type<0 else 0
	game.crowd_batches.get_node("CrowdShadows").visible=part_type<0
	for frame in range(4):await process_frame
	return root.get_texture().get_image()
func difference(a: Image,b: Image) -> Dictionary:
	var ab=a.get_data();var bb=b.get_data();var channels=a.get_data().size()/(a.get_width()*a.get_height())
	var changed=0;var total=0.0;var count=0;var maximum=0
	for offset in range(0,ab.size(),channels):
		var error=maxi(absi(int(ab[offset])-int(bb[offset])),maxi(absi(int(ab[offset+1])-int(bb[offset+1])),absi(int(ab[offset+2])-int(bb[offset+2]))))
		if error>4:changed+=1;total+=error;maximum=maxi(maximum,error)
		count+=1
	return {"changed_pixels":changed,"error_sum":total,"average_changed_error":total/maxi(1,changed),"max_channel_error":maximum,"pixels":count}
func run():
	if DisplayServer.get_name()=="headless":quit(2);return
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 第一关 · 头盔材质资源检查（自动关闭）");print("APPEARANCE_WINDOW ",root.title)
	# Complete imported skin/attachment initialization before comparing poses.
	for frame in range(2):await process_frame
	game._process(0);game.ui.hide();game.crowd_batches.refresh();game.vehicle_part_batches.refresh();game.rigid_batches.refresh()
	var original=await capture(game,true);var before=await capture(game,false)
	print("APPEARANCE_BASELINE ",difference(original,before))
	var material: ShaderMaterial=game.crowd_batches.groups.shared.node.material_override
	var shaded=material.shader.code;var outlined=material.next_pass.shader.code
	var mm: MultiMesh=game.crowd_batches.groups.shared.instances;var failures=0
	for index in range(mm.instance_count):
		if not mm.use_colors or not mm.get_instance_color(index).is_equal_approx(Color.WHITE):failures+=1
	for kind in [0,1,2]:
		var shader=Shader.new();shader.code=shaded.replace("void fragment() {","void fragment() {if(abs(crowd_style.x-%d.0)>.1)discard;"%kind);material.shader=shader
		var outline=Shader.new();outline.code=outlined.replace("void fragment() {","void fragment() {if(abs(crowd_style.x-%d.0)>.1)discard;"%kind);material.next_pass.shader=outline
		var expected=await capture(game,true,kind);var actual=await capture(game,false,kind)
		var fixed=difference(expected,actual)
		print("APPEARANCE_PART ",kind," ",fixed)
		if kind>0:
			# Reproduce the original zero-tint failure as a negative control. The
			# comparison is against original native materials, not another shader
			# implementing the same batching logic. Never treats a blank render as pass.
			for index in range(mm.instance_count):mm.set_instance_color(index,Color.BLACK)
			var broken=await capture(game,false,kind);var regression=difference(expected,broken)
			print("APPEARANCE_ZERO_TINT_CONTROL ",kind," ",regression)
			if regression.changed_pixels<100 or fixed.error_sum>regression.error_sum*.1:failures+=1
			for index in range(mm.instance_count):mm.set_instance_color(index,Color.WHITE)
	print("APPEARANCE_WORLD time=",game.world.time," shots=",game.world.shots)
	if game.world.time!=0 or game.world.shots!=0:failures+=1
	print("APPEARANCE_CONTRACT failures=",failures)
	game.free();quit(0 if failures==0 else 1)
