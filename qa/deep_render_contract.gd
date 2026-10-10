extends SceneTree
## Frozen resource/geometry equivalence only; never steps a battle or sends input.
const OldFX=preload("res://qa/performance/deep-before-source/reference_fx.gd")
const FX=preload("res://scripts/proving_fx.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
var checks: int=0
var failures: int=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<10:push_error(label)
func floats(data) -> PackedFloat32Array:
	return data.to_float32_array() if data is PackedByteArray else data
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	await process_frame
	var renderer=game.crowd_batches;renderer.camera=null;renderer.refresh()
	var full: Array=renderer.groups.shared.instances.mesh.surface_get_arrays(0)
	var compact: Array=renderer.groups.helmets.instances.mesh.surface_get_arrays(0)
	var old_style:=floats(full[Mesh.ARRAY_CUSTOM0]);var style:=floats(compact[Mesh.ARRAY_CUSTOM0])
	var old_red:=floats(full[Mesh.ARRAY_CUSTOM1]);var red:=floats(compact[Mesh.ARRAY_CUSTOM1])
	var selected: Array=[]
	for index in full[Mesh.ARRAY_INDEX]:
		if old_style[index*4+1]>.5:selected.append(index)
	check(selected.size()==compact[Mesh.ARRAY_INDEX].size(),"every original helmet triangle retained")
	for i in range(selected.size()):
		var a: int=selected[i];var b: int=compact[Mesh.ARRAY_INDEX][i]
		for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV]:
			check(full[field][a]==compact[field][b],"unchanged helmet vertex/normal/pigment/UV")
		for component in range(4):
			check(old_style[a*4+component]==style[b*4+component] and old_red[a*4+component]==red[b*4+component],"same class selector and red/blue pigment")
			check(full[Mesh.ARRAY_BONES][a*4+component]==compact[Mesh.ARRAY_BONES][b*4+component] and full[Mesh.ARRAY_WEIGHTS][a*4+component]==compact[Mesh.ARRAY_WEIGHTS][b*4+component],"original head attachment weights")
	check(compact[Mesh.ARRAY_INDEX].size()<full[Mesh.ARRAY_INDEX].size()*.2,"detached helmets omit at least 80 percent of unused submitted triangles")
	var nodes: Array=[]
	var view: Dictionary=game.actors[0]
	for role in renderer.Classes.IDS:
		for team in [0,1]:
			renderer.Classes.apply(view,role,team);renderer.register(view,team)
			var node=MeshInstance3D.new();node.mesh=view.helmet.mesh;game.add_child(node)
			node.transform=Transform3D(Basis.from_euler(Vector3(.3,team*.4,.2)),Vector3(nodes.size(),2,0))
			check(renderer.register_helmet(node,view),"all classes/teams retain helmet submission")
			nodes.append(node)
	renderer.refresh()
	check(renderer.groups.shared.instances.visible_instance_count==60 and renderer.groups.helmets.instances.visible_instance_count==10,"dedicated dense pools")
	for node in nodes:
		var entry: Dictionary=renderer.entries[node.get_instance_id()]
		# The headless dummy renderer does not store MultiMesh GPU buffers. Verify
		# the exact submitted pose here; GPU readback needs the real renderer.
		var pose: Transform3D=entry.transform
		check(pose.is_equal_approx(node.global_transform*entry.local),"unchanged detached helmet transform")
		check(renderer.groups.helmets.instances.use_colors,"detached group retains explicit instance colors")
		var pixel: Color=renderer.palette.get_pixel(0,entry.slot*64+41)
		check(pixel==Color(1,0,0,0),"head palette is identity for rigid dropped helmet")
	nodes[3].free();renderer.refresh()
	check(renderer.groups.helmets.instances.visible_instance_count==9 and renderer.groups.shared.instances.visible_instance_count==60,"helmet deletion never evicts a body")
	var slots: Dictionary={}
	for entry in renderer.groups.helmets.entries:slots[entry.draw_index]=true
	check(slots.size()==9 and slots.has(0) and slots.has(8),"helmet pool stays dense after deletion")
	particle_resources(game)
	check(game.world.time==0 and game.world.shots==0,"no battle advancement")
	var result={"checks":checks,"failures":failures,"body_vertices":full[Mesh.ARRAY_VERTEX].size(),"helmet_vertices":compact[Mesh.ARRAY_VERTEX].size(),"body_indices":full[Mesh.ARRAY_INDEX].size(),"helmet_indices":compact[Mesh.ARRAY_INDEX].size(),"simulation_time":game.world.time,"shots":game.world.shots}
	print("DEEP_RENDER_CONTRACT "+JSON.stringify(result))
	FileAccess.open("res://qa/performance/deep-render.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	game.free();quit(0 if failures==0 else 1)
func particle_resources(game):
	var pair=[OldFX.new(),FX.new()]
	var weapon: Dictionary=game.world.weapon_for(game.world.units[0]);var presentation: Dictionary=Ammo.profile(weapon)
	for fx in pair:
		fx.world=game.world;fx.catalog=game.catalog;fx.silent=true;fx.process_mode=Node.PROCESS_MODE_DISABLED;game.add_child(fx)
		for i in range(8):
			fx.piece(Vector3(-60+i,3,0),presentation.case_size,presentation.case_color,Vector3(1,1,2),24,false,9.8,"case",presentation)
		fx.piece(Vector3(-60,1,0),Vector3(.1,.12,.15),Color.WHITE,Vector3(.2,-1,.5),2)
		fx.piece(Vector3(-60,1,0),Vector3(.4,.4,.4),Color(.3,.3,.3,.5),Vector3.UP,2,true,0,"smoke")
		var unit: Dictionary=game.world.units[0].duplicate(true);unit.reload=1
		fx.drop_magazine({"unit":unit,"weapon":weapon,"position":Vector3(-60,1,0),"angle":.4})
	# Advance only the cosmetic arithmetic on the frozen geometry resource.
	for frame in range(120):
		for fx in pair:fx._process(1.0/60)
		check(pair[0].particles.size()==pair[1].particles.size(),"same particle lifetimes/capacity")
		for i in range(pair[0].particles.size()):
			var a=pair[0].particles[i];var b=pair[1].particles[i]
			check(a.node.transform.is_equal_approx(b.node.transform),"same full FX transform including magazine/smoke")
			check(a.velocity.is_equal_approx(b.velocity) and a.spin.is_equal_approx(b.spin),"same full FX velocity/spin")
			check(bool(a.get("settled",false))==b.settled and a.kind==b.kind,"same full FX sleeping state/kind")
	for fx in pair:fx.free()
