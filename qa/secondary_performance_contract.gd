extends SceneTree
## Frozen geometry/motion arithmetic only: no world.step, AI, shots or input.
const World=preload("res://scripts/proving_world.gd")
const OldWorld=preload("res://qa/performance/secondary-before-source/proving_world.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Terrain=preload("res://scripts/terrain_art.gd")
const OldTerrain=preload("res://qa/performance/secondary-before-source/terrain_art.gd")
const Blood=preload("res://scripts/blood_effects.gd")
const FX=preload("res://scripts/proving_fx.gd")
const OldFX=preload("res://qa/performance/secondary-before-source/proving_fx.gd")
const Summary=preload("res://scripts/runtime_performance.gd")
var checks=0
var failures=0
var result={}
class SupportWorld extends RefCounted:
	var topology_revision=0
	var vehicles=[{"position":Vector2.ZERO,"angle":0.0,"turret_angle":0.0,"destroyed":false}]
	var floor_height=0.0
	var calls=0
	func ground_height(_point: Vector2,_radius: float,_below: float) -> float:
		calls+=1;return floor_height
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<12:push_error(label)
func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new();var current=World.new();var old=OldWorld.new()
	current.setup(Level.plan(catalog),catalog);old.setup(Level.plan(catalog),catalog)
	current.unit_grid_active=false;old.unit_grid_active=false
	var rng=RandomNumberGenerator.new();rng.seed=280937
	var fixtures=[];var fast=0
	for i in range(1800):
		var unit=current.units[i%current.units.size()].duplicate(true)
		var point: Vector2
		if i%4==0:point=current.objects[i%current.objects.size()].position+Vector2(rng.randf_range(-3,3),rng.randf_range(-3,3))
		elif i%4==1:point=current.vehicles[i%current.vehicles.size()].position+Vector2(rng.randf_range(-5,5),rng.randf_range(-5,5))
		elif i%4==2:point=unit.position
		else:point=Vector2(rng.randf_range(-current.bounds.x-.3,current.bounds.x+.3),rng.randf_range(-current.bounds.y-.3,current.bounds.y+.3))
		unit.position=point;unit.elevation=current.terrain.height(point)+(rng.randf_range(-.3,1.5) if i%5==0 else 0.0)
		unit.grounded=i%7!=0;unit.stance=i%3;unit.walk=0.0;unit.last_clear={}
		unit.requested_velocity=Vector2(rng.randf_range(-7,7),rng.randf_range(-7,7))
		var velocity=Vector2(rng.randf_range(-7,7),rng.randf_range(-7,7));var delta=[1.0/60,1.0/30,.12][i%3]
		fixtures.append({"unit":unit,"velocity":velocity,"delta":delta})
		if current.terrain_only_motion(point,point+unit.requested_velocity*delta,.28):fast+=1
	# Verify authored terrain, wall edges, body overlap recovery and nearby vehicles.
	for f in fixtures:
		var a=f.unit.duplicate(true);var b=f.unit.duplicate(true)
		# Compare the same ordered recovery candidates, not a wall-clock deadline.
		old.overlap_budget_usec=1000000;current.overlap_budget_usec=1000000
		old.move_unit(a,f.velocity,f.delta);current.move_unit(b,f.velocity,f.delta)
		check(a.position.is_equal_approx(b.position),"movement position")
		check(is_equal_approx(a.elevation,b.elevation),"movement elevation")
		check(a.velocity.is_equal_approx(b.velocity) and is_equal_approx(a.walk,b.walk),"movement velocity/stride")
		check(a.last_clear==b.last_clear,"movement last-clear support")
	# Identical static movement batches; alternate order in one process.
	var move_times=[[],[]]
	old.overlap_budget_usec=0;current.overlap_budget_usec=0
	for repeat in range(10):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var world=old if mode==0 else current;var begin=Time.get_ticks_usec()
			for f in fixtures:world.move_unit(f.unit.duplicate(true),f.velocity,f.delta)
			move_times[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	result.movement={"fixtures":fixtures.size(),"terrain_only_candidates":fast,"before":Summary.summary(move_times[0]),"after":Summary.summary(move_times[1])}
	# Compare exact per-cell geometry after HP, cutaway and collapse changes.
	var wall_jobs=[]
	for o in current.objects:
		if not o.has("hp") or o.hp.is_empty() or o.has("nature_solids") or o.has("solid_parts"):continue
		for state in [1.0,.4,0.0]:
			var sample=o.duplicate(true)
			for cell in range(sample.hp.size()):
				if cell%3==0:sample.hp[cell]*=state
			for cell in range(sample.hp.size()):
				var cut=1.15 if cell%5==0 else INF
				var a=OldTerrain.wall_geometry(sample,cut,cell);var b=Terrain.wall_geometry(sample,cut,cell)
				check(a==b,"exact wall cell vertices/normals/colours")
				wall_jobs.append({"object":sample,"cell":cell,"cut":cut})
	var wall_times=[[],[]]
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var begin=Time.get_ticks_usec()
			for job in wall_jobs:
				if mode==0:OldTerrain.wall_geometry(job.object,job.cut,job.cell)
				else:Terrain.wall_geometry(job.object,job.cut,job.cell)
			wall_times[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	result.wall_cells={"jobs":wall_jobs.size(),"before":Summary.summary(wall_times[0]),"after":Summary.summary(wall_times[1])}
	check(current.time==0 and old.time==0 and current.shots==0 and old.shots==0,"no battle advancement")
	blood_contract();crater_contract();support_contract()
	result.checks=checks;result.failures=failures
	FileAccess.open("res://qa/performance/secondary-performance.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SECONDARY_CONTRACT "+JSON.stringify(result));quit(0 if failures==0 else 1)

func legacy_stains(blood):
	for i in range(blood.stains.size()):
		var s: Dictionary=blood.stains[i];var basis=Basis(Vector3.UP,s.angle)*Basis(Vector3.RIGHT,-PI*.5)*Basis.from_scale(Vector3(s.radius,s.radius*.65,1))
		blood.stain_mesh.set_instance_transform(i,Transform3D(basis,s.position));blood.stain_mesh.set_instance_color(i,Color("752a38"))
		blood.stain_mesh.set_instance_custom_data(i,Color((1-smoothstep(float(s.life)-2,s.life,s.age))*.78,s.seed,1,0))
	blood.stain_mesh.visible_instance_count=blood.stains.size()

func blood_contract():
	var blood=Blood.new();blood.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(blood)
	blood.warming=false
	for i in range(96):blood.add_stain({"radius":.07,"landing":Vector3(i*.2,0,0),"seed":i/96.0})
	blood.write_batches();var uploads=blood.stain_uploads
	for i in range(90):blood.write_batches()
	check(blood.stain_uploads==uploads,"static stains send no transforms/colours/fade data")
	# GPU clock preserves the final two-second fade without per-stain writes.
	blood.advance(9.5);blood.write_batches();check(blood.stain_uploads==uploads,"fading uses GPU clock without per-stain uploads")
	blood.advance(5.0);check(blood.stains.is_empty() and blood.stain_mesh.visible_instance_count==0,"expired stains removed")
	for i in range(120):blood.add_stain({"radius":.07,"landing":Vector3(i*.2,0,0),"seed":i/120.0})
	check(blood.stains.size()==96 and blood.gpu.free_stains.is_empty(),"bounded eviction reuses fixed GPU slots")
	blood.write_batches();var timing=[[],[]]
	for repeat in range(12):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var begin=Time.get_ticks_usec()
			for frame in range(120):
				if mode==0:legacy_stains(blood)
				else:blood.write_batches()
			timing[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	result.stains={"stains":96,"frames_per_batch":120,"before":Summary.summary(timing[0]),"after":Summary.summary(timing[1])}
	blood.free()

func crater_contract():
	var fx=FX.new();fx.instance_batches=preload("res://scripts/fx_instance_batches.gd").new();fx.add_child(fx.instance_batches)
	for i in range(120):fx.decal(Vector2(i*.1,2),.7+i*.001,Color("807786"))
	check(fx.decals.size()==100,"crater retention unchanged")
	var stats=fx.instance_batches.stats()
	check(stats.instances==100 and stats.surface_passes==1,"100 craters share one surface pass")
	var unit_mesh: SphereMesh=fx.meshes.crater
	for i in range(100):
		var entry=fx.decals[i];var radius=.7+(i+20)*.001
		var reference=SphereMesh.new();reference.radius=radius;reference.height=radius*2;reference.radial_segments=20;reference.rings=10
		var old_pose=entry.node.transform;old_pose.basis=old_pose.basis*Basis.from_scale(Vector3.ONE/radius)
		var a=old_pose*reference.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
		var b=entry.node.transform*unit_mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
		for vertex in range(a.size()):check(a[vertex].is_equal_approx(b[vertex]),"crater world-space geometry unchanged")
		var handle: Dictionary=entry.batch[0]
		check(fx.instance_batches.groups[handle.key].entries[handle.slot]==handle and handle.pose==entry.node.transform,"crater dense slot and transform")
	result.craters={"retained":100,"surface_passes":stats.surface_passes,"old_render_objects":100}
	fx.free()

func support_fixture(script):
	var fx=script.new();fx.world=SupportWorld.new()
	fx.instance_batches=preload("res://scripts/fx_instance_batches.gd").new();fx.add_child(fx.instance_batches)
	for i in range(360):
		var node=Node3D.new();fx.add_child(node);node.position=Vector3(i,0.04,0)
		var data={"node":node,"kind":"case" if i<160 else ("magazine" if i<192 else "debris"),"settled":true,"floor":0.0,"support_stamp":-1,"rolling":false,"gravity":0.0}
		fx.particles.append(FX.Particle.new(data) if script==FX else data)
	return fx

func support_contract():
	var old=support_fixture(OldFX);var current=support_fixture(FX)
	for phase in range(4):
		if phase==1:
			# Moving support and its new height, without a topology edit.
			for fx in [old,current]:fx.world.vehicles[0].position.x+=1;fx.world.floor_height=.2
		elif phase==2:
			for fx in [old,current]:fx.world.topology_revision+=1;fx.world.floor_height=-.5
		for frame in range(16):
			old.refresh_resting_support();current.refresh_resting_support()
			check(current.support_checks<=16,"support refresh keeps its per-frame query cap")
			for i in range(360):
				var a: Dictionary=old.particles[i];var b=current.particles[i]
				check(a.settled==b.settled and a.floor==b.floor and a.node.position==b.node.position,"support wake/raise matches original across budget frames")
	check(current.support_scanned==0 and not current.support_pending,"stable support finishes its backlog and stops scanning")
	# Reset to a stationary, fully supported fixture for the paired timing batch.
	for fx in [old,current]:
		for p in fx.particles:p.settled=true;p.support_stamp=fx.support_stamp
	var times=[[],[]]
	for repeat in range(8):
		for mode in ([0,1] if repeat%2==0 else [1,0]):
			var fx=old if mode==0 else current;var begin=Time.get_ticks_usec()
			for frame in range(240):fx.refresh_resting_support()
			times[mode].append((Time.get_ticks_usec()-begin)/1000.0)
	result.resting_support={"particles":360,"frames_per_batch":240,"before":Summary.summary(times[0]),"after":Summary.summary(times[1])}
	old.free();current.free()
