extends RefCounted
## Same frozen computation in editor runner and Windows Release; no battle/input.
const World=preload("res://scripts/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Case=preload("res://scripts/spent_case_motion.gd")
const Particle=preload("res://scripts/fx_particle_state.gd")
const Summary=preload("res://scripts/runtime_performance.gd")
func run() -> Dictionary:
	var catalog=Catalog.new();var world=World.new();world.setup(Level.plan(catalog),catalog);world.unit_grid_active=false;world.overlap_budget_usec=0
	var motion=Case.new();var states: Array[Particle]=[]
	for i in range(160):
		var p=Particle.new();p.node=Node3D.new();p.node.scale=Vector3(.02,.02,.07)
		p.presentation={"case_shape":"bottleneck"};states.append(p)
	var costs={"movement":[],"rays":[],"cases":[]}
	for repeat in range(6):
		var begin=Time.get_ticks_usec()
		for i in range(1800):world.move_unit(world.units[i%60].duplicate(true),Vector2(1.2,-2.5),1.0/30)
		costs.movement.append((Time.get_ticks_usec()-begin)/1000.0);begin=Time.get_ticks_usec()
		for i in range(1800):
			var u: Dictionary=world.units[i%60]
			world.trace_3d(Vector3(u.position.x,u.elevation+1.1,u.position.y),Vector3(sin(i*.3),-.13,cos(i*.3)).normalized(),20,{"radius":.025},true)
		costs.rays.append((Time.get_ticks_usec()-begin)/1000.0);begin=Time.get_ticks_usec()
		for frame in range(12):
			motion.begin_frame()
			for i in range(160):
				var p: Particle=states[i];var u: Dictionary=world.units[i%60]
				p.node.position=Vector3(u.position.x,u.elevation+1.3,u.position.y);p.velocity=Vector3(1,-1,2);p.spin=Vector3(3,4,2);p.settled=false;p.rolling=false;p.gravity=9.8
				motion.advance_particle(p,1.0/30,world)
		costs.cases.append((Time.get_ticks_usec()-begin)/1000.0)
	for p in states:p.node.free()
	var result={"debug_build":OS.is_debug_build(),"editor_runner":OS.has_feature("editor"),"simulation_time":world.time,"shots":world.shots}
	for key in costs:result[key]=Summary.summary(costs[key])
	return result
