extends SceneTree
## Frozen authored geometry/HP fixtures. No inputs, damage events or world.step.
const OldWalls=preload("res://qa/performance/frame-budget-v43-source/wall_batches.gd")
const Terrain=preload("res://scripts/terrain_art.gd")
const Summary=preload("res://scripts/runtime_performance.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<8:push_error(label)
func _initialize():run.call_deferred()
func compare(game,object):
	preload("res://qa/baked_wall_geometry.gd").compare(game,object,check)
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 墙体烘焙资源检查（自动关闭）")
	var current=game.wall_batches;var old=OldWalls.new();game.stage.add_child(old);old.configure(game.world.objects,game.object_views)
	var objects=[];var cells: int=0
	for object in game.world.objects:
		if current.members.has(object.id) and object.rows>2:
			objects.append(object);cells+=object.hp.size()
			if cells>=216:break
	var timings={"damage":[[],[]],"cut":[[],[]],"hole":[[],[]]};var upload=[0,0]
	for repeat: int in range(6):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var batch=old if mode==0 else current
			for ratio: float in [.75,.35,1.0]:
				for object in objects:
					for index: int in range(object.hp.size()):
						if not object.get("opening_cells",{}).has(index):object.hp[index]=object.max_hp*ratio
					batch.changed(object)
				var start=Time.get_ticks_usec();batch.flush();timings.damage[mode].append((Time.get_ticks_usec()-start)/1000.0);upload[mode]+=batch.last_bytes
			for cut: float in [1.15,INF]:
				for object in objects:game.object_views[object.id].cut_height=cut;batch.changed(object)
				var start=Time.get_ticks_usec();batch.flush();timings.cut[mode].append((Time.get_ticks_usec()-start)/1000.0)
			for alive: bool in [false,true]:
				for object in objects:object.alive=alive;batch.changed(object)
				var start=Time.get_ticks_usec();batch.flush();timings.hole[mode].append((Time.get_ticks_usec()-start)/1000.0)
	# Geometry contract checks cover quantised damage, adjacent holes and both cuts.
	for ratio: float in [1.0,.75,.35]:
		for object in objects:
			for index: int in range(object.hp.size()):object.hp[index]=object.max_hp*ratio if index%5!=2 and not object.get("opening_cells",{}).has(index) else 0
		for cut: float in [INF,1.15]:
			for object in objects:game.object_views[object.id].cut_height=cut;current.changed(object)
			current.flush()
			for object in objects:compare(game,object)
	var materials={}
	for sample in game.world.objects:
		if not current.members.has(sample.id):continue
		var kind=str(sample.material)+("/fence" if sample.get("metal_fence",false) else "")
		if materials.has(kind):continue
		materials[kind]=true
		for ratio: float in [1.0,.75,.35]:
			for index: int in range(sample.hp.size()):sample.hp[index]=sample.max_hp*ratio if index%5!=2 and not sample.get("opening_cells",{}).has(index) else 0
			for cut: float in [INF,1.15]:
				game.object_views[sample.id].cut_height=cut;current.changed(sample);current.flush();compare(game,sample)
	var object: Dictionary=objects[0];var member: Dictionary=current.members[object.id];var index: int=0
	object.hp[index]=object.max_hp;object.impact_marks={index:[Vector3(-object.size.x*.5+object.cell_width*.5,.1,1)]}
	current.changed(object);current.flush()
	check(current.impacts.active.has(member.mark_offset),"impact mark visible on surviving cell")
	var expected=member.pose*Vector3(object.impact_marks[index][0].x,.1,object.size.y*.5+.012)
	if DisplayServer.get_name()!="headless":check(current.impacts.multimesh.get_instance_transform(member.mark_offset).origin.is_equal_approx(expected),"impact mark keeps wall position/rotation/elevation")
	object.hp[index]=0;current.changed(object);current.flush();check(not current.impacts.active.has(member.mark_offset),"impact removed with cell")
	object.hp[index]=object.max_hp;game.object_views[object.id].cut_height=.075;current.changed(object);current.flush()
	check(current.last_fallbacks==1 and game.object_views[object.id].mesh.layers>0,"custom editor cut uses original precise geometry")
	check(not current.impacts.active.has(member.mark_offset),"fallback has no duplicate decal")
	game.object_views[object.id].cut_height=INF;current.changed(object);current.flush()
	check(current.last_fallbacks==0 and game.object_views[object.id].mesh.layers==0,"standard cut returns to batching")
	var before: int=current.sectors[Vector2i.ZERO].surface.uploaded_bytes
	object.hp[index]=object.max_hp*.98;current.changed(object);current.flush()
	check(current.sectors[Vector2i.ZERO].surface.uploaded_bytes==before,"same appearance bucket does not upload wall data")
	if DisplayServer.get_name()!="headless":
		await process_frame;await process_frame
		var surface=current.sectors[Vector2i.ZERO].surface
		var indices: PackedInt32Array=surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		for sample in objects:
			for chunk in current.members[sample.id].chunks:
				for i: int in range(chunk.capacity):check(indices[chunk.offset+i]==(chunk.data.offset+i if chunk.selected>=0 and i<chunk.data.v.size() else 0),"actual GPU buffer follows damage and cut selections")
	check(game.world.time==0 and game.world.shots==0,"no battle simulation")
	var result={"checks":checks,"failures":failures,"cells":cells,"materials":materials.keys(),"damage_upload_bytes":upload,"simulation_time":game.world.time,"shots":game.world.shots,"title":root.title,"baked_vertices":current.sectors[Vector2i.ZERO].surface.vertex_count,"submitted_indices":current.sectors[Vector2i.ZERO].surface.index_count}
	for kind in timings:result[kind]={"before":Summary.summary(timings[kind][0]),"after":Summary.summary(timings[kind][1])}
	print("BAKED_WALL_CONTRACT "+JSON.stringify(result))
	FileAccess.open("res://qa/performance/baked-wall-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	game.free();quit(0 if failures==0 else 1)
