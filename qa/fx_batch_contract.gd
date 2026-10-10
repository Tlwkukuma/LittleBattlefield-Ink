extends SceneTree
## Cosmetic math/resource contract, never a battle or automated game input.
const FX=preload("res://scripts/proving_fx.gd")
const Pool=preload("res://scripts/fx_instance_batches.gd")
const Catalog=preload("res://scripts/source_catalog.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
class TerrainFixture extends RefCounted:
	var floor_height=0.0
	func height(_at):return floor_height
	func material_at(_at):return "concrete"
class WorldFixture extends RefCounted:
	var terrain=TerrainFixture.new()
	var bounds=Vector2(100,100)
	var vehicles=[]
	var topology_revision=0
	var profile_ai=false
	var queries=0
	func ground_height(_at,_radius,_below):queries+=1;return terrain.floor_height
	func trace_3d(_at,_dir,_length,_options,_walls):return {}
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
	if DisplayServer.get_name()=="headless":
		printerr("This resource check requires the real OpenGL driver; headless uses Dummy and cannot read GPU instance transforms.");quit(2);return
	root.title="v%s · 弹壳与弹匣资源检查（自动关闭） · 启动 %s · PID %d"%[preload("res://scripts/proving_ground.gd").BUILD_VERSION,Time.get_datetime_string_from_system(false,true),OS.get_process_id()]
	print("RESOURCE_WINDOW "+root.title)
	var pool=Pool.new();root.add_child(pool);var mesh=BoxMesh.new();var mat=StandardMaterial3D.new();var handles=[]
	for i in range(8):handles.append(pool.add(mesh,mat,Transform3D(Basis.IDENTITY,Vector3(i,0,0))))
	pool.release([handles[3]])
	check(pool.stats().instances==7 and handles[7].slot==3,"Swap removal repairs the moved instance handle")
	pool.sync([handles[7]],Transform3D(Basis.IDENTITY,Vector3(20,2,1)))
	check(pool.groups[handles[7].key].instances.get_instance_transform(3).origin==Vector3(20,2,1),"Compacted instance still updates its own GPU slot")
	var uploads=pool.writes;pool.sync([handles[7]],Transform3D(Basis.IDENTITY,Vector3(20,2,1)))
	check(pool.writes==uploads,"Unchanged transforms do not upload again")
	pool.free()
	var world=WorldFixture.new();var catalog=Catalog.new();var fx=FX.new();fx.world=world;fx.catalog=catalog;fx.silent=true;fx.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(fx)
	var camera=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=20;fx.camera=camera
	for i in range(12):
		var a=Ammo.profile(catalog.weapons[["m416","akm","s1897","o12"][i%4]])
		fx.piece(Vector3(i*.2,1,0),a.case_size,a.case_color,Vector3(.4,1,.2),100,false,9.8,"case",a)
	for i in range(2):fx.drop_magazine({"unit":{"id":-1,"alive":true,"reload":1,"weapon_id":"m416"},"weapon":catalog.weapons.m416,"position":Vector3(i,1,2),"angle":0})
	for i in range(300):fx._process(1.0/60)
	check(fx.batching_stats().resting==14,"Cases and magazines retain their bounce then settle")
	check(fx.batching_stats().batches==2 and fx.instance_batches.case_sources.size()==4,"Four exact cartridge meshes share one atlas batch beside the magazine batch")
	for p in fx.particles:
		check(not p.node is MeshInstance3D and p.node.get_child_count()==0,"Motion proxies have no separate render geometry")
		for handle in p.batch:check(pool_pose(fx,handle).is_equal_approx(p.node.transform*Transform3D(handle.local)),"GPU pose matches the original object geometry transform")
	world.queries=0;uploads=fx.instance_batches.writes
	for i in range(120):fx._process(1.0/60)
	check(world.queries==0 and fx.instance_batches.writes==uploads,"Unchanged sleeping scene performs zero support probes and zero uploads")
	camera.size=8;fx._process(1.0/60)
	check(world.queries==0 and fx.instance_batches.writes>uploads,"Zoom preserves case readability without waking contact simulation")
	world.terrain.floor_height=-1;world.topology_revision+=1
	for i in range(180):fx._process(1.0/60)
	for p in fx.particles:check(p.settled and p.node.position.y<-.5,"Destruction wakes settled items and they land on the lower support")
	world.vehicles=[{"position":Vector2.ZERO,"angle":0.0,"turret_angle":0.0,"elevation":0.0,"destroyed":false}]
	world.queries=0;fx._process(1.0/60)
	check(world.queries>0 and fx.support_checks<=16,"Vehicle support changes invalidate sleepers with bounded checks")
	for i in range(420):fx.piece(Vector3(0,2,0),Vector3.ONE*.02,Color.WHITE,Vector3.ZERO,1,false,0,"flash")
	check(fx.particles.size()==360 and fx.instance_batches.stats().instances==360,"Full pool evicts oldest items without overflowing GPU capacity")
	fx._process(1.1)
	check(fx.particles.is_empty() and fx.instance_batches.stats().instances==0 and fx.instance_batches.stats().batches==0,"Expiry releases every dense slot without ghost geometry")
	fx.free();camera.free()
	print("FX_BATCH_CONTRACT ",checks-failures.size(),"/",checks," passed; failures=",failures);quit(0 if failures.is_empty() else 1)
func pool_pose(fx,handle) -> Transform3D:return fx.instance_batches.groups[handle.key].instances.get_instance_transform(handle.slot)
