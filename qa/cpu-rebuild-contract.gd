extends SceneTree
## Focused rebuild contract: independently owned rosters; no battle advancement.
const World=preload("res://scripts/proving_world.gd")
const Timing=preload("res://scripts/runtime_performance.gd")
class CountingIndex:
	extends "res://scripts/unit_ray_index.gd"
	var updates=0
	func update(unit: Dictionary):
		updates+=1
		super.update(unit)
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func ids(values: Array) -> Array:
	var result=[]
	for value in values:result.append(value.id)
	return result
func snapshot(world) -> Dictionary:
	var steering={}
	for key in world.unit_grid:steering[key]=ids(world.unit_grid[key])
	var tree={}
	for key in world.unit_ray_index.tree.entries:
		var entry=world.unit_ray_index.tree.entries[key]
		tree[key]={"bounds":entry.bounds,"id":entry.value.id,"node":entry.node,"slot":entry.slot}
	return {"steering":steering,"ray_grid":world.unit_ray_index.grid.duplicate(true),"tree":tree}
func compare(a,b,label: String):
	check(snapshot(a)==snapshot(b),label+" tree/grid/order")
	for i in range(80):
		var point=Vector2((i%10)*4-20,(i/10)*4-16)
		for radius in [.1,.6,1.0,4.0]:
			check(ids(a.unit_ray_index.query(point,point+Vector2(12 if i%2 else 40,3),radius))==ids(b.unit_ray_index.query(point,point+Vector2(12 if i%2 else 40,3),radius)),label+" ray query")
		check(ids(a.nearby_units(point,1))==ids(b.nearby_units(point,1)),label+" steering query")
		check(ids(a.nearby_units(point,6))==ids(b.nearby_units(point,6)),label+" tree query")
func _initialize():run.call_deferred()
func run():
	var source=FileAccess.get_file_as_string("res://scripts/proving_world.gd")
	var target="\t\tindex_unit(unit,false)"
	check(source.count(target)==1,"one build-only refresh bypass")
	# Explicitly reconstruct only the pre-change duplicate update call. This is
	# not a historical baseline file and shares all unrelated current code.
	var reference=GDScript.new();reference.source_code=source.replace(target,"\t\tindex_unit(unit)")
	if reference.reload()!=OK:check(false,"reference compiles");quit(1);return
	var a=reference.new();var b=World.new()
	for i in range(60):
		a.units.append({"id":i,"position":Vector2((i%10)*4-20,(i/10)*4-12),"alive":true,"elevation":2.0,"stance":0,"mounted":-1,"team":i%2,"velocity":Vector2.ZERO,"angle":0.0,"hit_shapes":[]})
	b.units=a.units.duplicate(true)
	check(not is_same(a.units[0],b.units[0]),"independent cloned roster dictionaries")
	a.unit_ray_index=CountingIndex.new();b.unit_ray_index=CountingIndex.new()
	a.build_unit_index();b.build_unit_index()
	check(a.unit_ray_index.updates==120 and b.unit_ray_index.updates==60,"60 units: 120 to 60 updates")
	compare(a,b,"initial")
	a.unit_ray_index.updates=0;b.unit_ray_index.updates=0
	a.build_unit_index();b.build_unit_index()
	check(a.unit_ray_index.updates==120 and b.unit_ray_index.updates==60,"persistent rebuild: 120 to 60 updates")
	for mode in range(6):
		for world in [a,b]:
			var u=world.units[7]
			match mode:
				0:u.position=Vector2(-3,-3)
				1:u.position=Vector2(200,200)
				2:u.alive=false
				3:u.alive=true;u.stance=2;u.elevation=4
				4:u.mounted=0
				5:u.mounted=-1;u.position=Vector2(4,4)
			world.index_unit(u)
		compare(a,b,"lifecycle "+str(mode))
	for world in [a,b]:
		var before=snapshot(world);var count=world.unit_ray_index.updates
		var clone=world.units[0].duplicate(true);clone.position=Vector2(999,999)
		world.index_unit(clone);world.index_unit(clone,false)
		check(snapshot(world)==before and world.unit_ray_index.updates==count,"prediction clone rejected with both flags")
		var added=world.units[0].duplicate(true);added.id=60;added.erase("steering_cell");world.units.append(added);world.index_unit(added)
	compare(a,b,"reinforcement")
	for world in [a,b]:
		var replacement=world.units[3].duplicate(true);replacement.position=Vector2(-30,7);replacement.erase("steering_cell");world.units[3]=replacement;world.build_unit_index()
	compare(a,b,"same-size identity replacement")
	# Equal-distance exact hit and existing last-unit tie order.
	var c=World.new();var d=reference.new()
	c.units=[a.units[0].duplicate(true),a.units[1].duplicate(true)]
	for i in range(2):
		var u=c.units[i];u.id=i;u.position=Vector2.ZERO;u.erase("steering_cell")
		u.hit_shapes=[{"a":Vector3(0,3,0),"b":Vector3(0,3,0),"radius":.3,"region":"head"}]
	d.units=c.units.duplicate(true);c.build_unit_index();d.build_unit_index()
	for world in [c,d]:
		var hit=world.trace_3d(Vector3(-2,3,0),Vector3.RIGHT,4)
		check(hit.get("target",{}).get("id",-1)==1,"equal-distance last unit wins")
		check(world.trace_3d(Vector3(-2,3,0),Vector3.RIGHT,4,{"hit":[1]}).get("target",{}).get("id",-1)==0,"hit exclusion retained")
	var timing=Timing.new();b.player=b.units[0]
	b.last_step_profile={"step_ms":1.5,"invalid_ms":{},"unit_rays":{"queries":2,"build_ms":.2,"quadtree":{"tests":3},"labels":[{"v":1}]},"ai_detail":{"rays":4,"vision_ms":.3,"nested":{"v":2},"invalid_ms":[]}}
	for i in range(2):timing.record_physics(Time.get_ticks_usec(),b)
	check(timing.unit_ray_totals=={"queries":4.0,"build_ms":.4},"only numeric ray totals")
	check(timing.ai_query_totals=={"rays":8.0},"only numeric AI totals")
	check(not timing.physics_stages.has("invalid_ms") and not timing.physics_stages.has("ai_invalid_ms"),"nonnumeric milliseconds skipped")
	b.last_step_profile.unit_rays.quadtree.tests=99;b.last_step_profile.unit_rays.labels[0].v=99;b.last_step_profile.ai_detail.nested.v=99
	check(timing.unit_ray_metadata.quadtree.tests==3 and timing.unit_ray_metadata.labels[0].v==1 and timing.ai_query_metadata.nested.v==2,"metadata deeply copied")
	timing.last_frame={"bad_ms":{},"good_ms":.1,"render_batches":{"bad":[],"good":1},"fx_detail":{"bad_ms":[],"good_ms":.2}}
	timing.report_started_usec=Time.get_ticks_usec();timing.record_frame(Time.get_ticks_usec(),.016,b,false)
	check(timing.stage_samples.keys().size()==3,"presentation numeric guards")
	timing.report_started_usec=Time.get_ticks_usec()-5000001;timing.record_frame(Time.get_ticks_usec(),.016,b,false)
	check(timing.unit_ray_metadata.is_empty() and timing.ai_query_metadata.is_empty() and timing.unit_ray_totals.is_empty() and timing.ai_query_totals.is_empty(),"report clears metadata and totals")
	var result={"checks":checks,"failures":failures,"units":60,"before_updates":120,"after_updates":60,"simulation_time":b.time}
	print("CPU_REBUILD_CONTRACT "+JSON.stringify(result));quit(0 if failures==0 else 1)
