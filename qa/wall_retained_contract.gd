extends SceneTree
## Frozen authored wall/HP fixtures only; no world.step, damage events or input.
const Terrain=preload("res://scripts/terrain_art.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize():run.call_deferred()
func compare(game,object):
	preload("res://qa/baked_wall_geometry.gd").compare(game,object,check)
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	var timing=[];var legacy=[];var max_cells=0
	for object in game.world.objects:
		if not game.wall_batches.members.has(object.id):continue
		compare(game,object)
		var index=-1
		for i in range(object.hp.size()):
			if object.hp[i]>0:index=i;break
		if index<0:continue
		var hp=object.hp.duplicate();var mesh_rid=game.wall_batches.sectors[Vector2i.ZERO].node.mesh.get_rid()
		for state in [0.4,0.0,1.0]:
			object.hp[index]=hp[index]*state
			var begin=Time.get_ticks_usec();game.wall_batches.changed(object);game.wall_batches.flush();timing.append((Time.get_ticks_usec()-begin)/1000.0);max_cells=maxi(max_cells,game.wall_batches.last_cells)
			compare(game,object);check(game.wall_batches.sectors[Vector2i.ZERO].node.mesh.get_rid()==mesh_rid,"retains GPU mesh resource")
			check(game.wall_batches.last_cells<=5,"only changed cell and exposed neighbours")
		game.object_views[object.id].cut_height=1.15;game.wall_batches.changed(object);game.wall_batches.flush();compare(game,object)
		game.object_views[object.id].cut_height=INF;game.wall_batches.changed(object);game.wall_batches.flush();compare(game,object)
		object.alive=false;game.wall_batches.changed(object);game.wall_batches.flush();compare(game,object)
		object.alive=true;game.wall_batches.changed(object);game.wall_batches.flush();compare(game,object)
		if legacy.size()<12:
			# Old four-quadrant algorithm, same current geometry and process.
			var before=Time.get_ticks_usec();var builder=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			for other in game.world.objects:
				if not game.wall_batches.members.has(other.id) or (other.position.x>=0)!=(object.position.x>=0) or (other.position.y>=0)!=(object.position.y>=0):continue
				var view=game.object_views[other.id].mesh
				if view.mesh.get_surface_count()>0:builder.append_from(view.mesh,0,view.global_transform)
			builder.commit();legacy.append((Time.get_ticks_usec()-before)/1000.0)
	check(game.world.time==0 and game.world.shots==0,"no battle advancement")
	var result={"checks":checks,"failures":failures,"cell_update_ms":preload("res://scripts/runtime_performance.gd").summary(timing),"legacy_sector_merge_ms":preload("res://scripts/runtime_performance.gd").summary(legacy),"max_cells":max_cells,"time":game.world.time,"shots":game.world.shots}
	FileAccess.open("res://qa/performance/wall-retained-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("WALL_RETAINED "+JSON.stringify(result))
	game.free();quit(0 if failures==0 else 1)
