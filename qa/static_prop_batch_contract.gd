extends SceneTree
## Fixed geometry and destruction state only; no battle tick or input.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const Props=preload("res://scripts/proving_art.gd")
const Batch=preload("res://scripts/static_prop_batches.gd")
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func count_vertices(mesh: Mesh,surface: int) -> int:
	var data=mesh.surface_get_arrays(surface)
	return data[Mesh.ARRAY_INDEX].size() if data[Mesh.ARRAY_INDEX]!=null and not data[Mesh.ARRAY_INDEX].is_empty() else data[Mesh.ARRAY_VERTEX].size()
func source_count(batch) -> int:
	var count=0
	for member in batch.members.values():
		if member.alive:
			for part in member.parts:count+=count_vertices(part.mesh,part.surface)
	return count
func baked_count(batch) -> int:
	var count=0
	for sector in batch.sectors.values():
		for node in sector.nodes.values():count+=count_vertices(node.mesh,0)
	return count
func run():
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	var parent=Node3D.new();root.add_child(parent);var views={}
	for object in world.objects:views[object.id]=Props.object(parent,object)
	var batch=Batch.new();parent.add_child(batch);batch.configure(world.objects,views)
	var stats=batch.stats()
	check(stats.props>=140 and stats.baked_surfaces<stats.source_surfaces/2,"Real orchard props consolidate into spatial sectors")
	check(source_count(batch)==baked_count(batch),"Baking preserves every triangle/line index")
	for object in world.objects:
		if object.component_id.begins_with("wall."):check(not batch.members.has(object.id) and views[object.id].mesh.visible,"Each destructible wall retains its live cell renderer")
	for member in batch.members.values():
		for part in member.parts:
			var node: MeshInstance3D=batch.sectors[member.cell].nodes[part.key]
			var source_bounds: AABB=part.pose*part.mesh.get_aabb()
			check(node.mesh.get_aabb().grow(.001).encloses(source_bounds),"Sector bounds contain original transformed geometry")
	var id=batch.members.keys()[0];var member: Dictionary=batch.members[id];var cell=member.cell;var builds={}
	for key in batch.sectors:builds[key]=batch.sectors[key].builds
	var object: Dictionary={}
	for entry in world.objects:
		if entry.id==id:object=entry;break
	world.damage_cell(object,0,0,100000,object.position,false);batch.changed(object);batch.flush()
	check(not object.alive and not member.alive,"Destroyed prop disappears using the actual gameplay destruction state")
	check(source_count(batch)==baked_count(batch),"Dirty sector removes only destroyed geometry")
	var isolated=true
	for key in batch.sectors:isolated=isolated and batch.sectors[key].builds==builds[key]+(1 if key==cell else 0)
	check(isolated,"Only the affected sector is rebaked")
	check(world.time==0 and world.shots==0,"No battle or model execution")
	var file=FileAccess.open("res://qa/performance/static-prop-batches.json",FileAccess.WRITE);file.store_string(JSON.stringify(stats,"\t"));file.close()
	print("STATIC_PROP_BATCH_CONTRACT ",checks-failures.size(),"/",checks," passed; stats=",JSON.stringify(stats)," failures=",failures)
	parent.free();quit(0 if failures.is_empty() else 1)
