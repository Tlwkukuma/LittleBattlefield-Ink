extends SceneTree
## Frozen resources and capsule mathematics. Never advances AI/gameplay/input.
const Pose=preload("res://scripts/combat_pose.gd")
const Geometry=preload("res://scripts/aim_geometry.gd")
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		if failures<8:push_error(message)
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.set_game_title("小小战地 · 轻量表现资源检查（自动关闭）")
	game.armory.hide();game._process(0)
	for i in range(8):await process_frame;game.hud_batches.refresh()
	var u=game.world.player.duplicate(true)
	var base=Pose.base(u)
	u.hit_shapes=[{"a":base+Vector3(0,.4,0),"b":base+Vector3(0,1.2,0),"radius":.3,"region":"body"},{"a":base+Vector3(0,1.5,0),"b":base+Vector3(0,1.7,0),"radius":.25,"region":"head"}]
	Pose.capture(u,{})
	var rng=RandomNumberGenerator.new();rng.seed=4140
	for i in range(1200):
		var translation=Vector3(rng.randf_range(-8,8),rng.randf_range(-2,2),rng.randf_range(-8,8))
		u.position=Vector2(base.x+translation.x,base.z+translation.z);u.elevation=base.y+translation.y
		check(Pose.head(u).is_equal_approx(u.hit_shapes[1].a+translation),"head follows current physics root")
		check(Pose.chest(u).is_equal_approx(u.hit_shapes[0].a.lerp(u.hit_shapes[0].b,.72)+translation),"body follows current physics root")
		var origin=base+translation+Vector3(rng.randf_range(-2,2),rng.randf_range(0,2),rng.randf_range(-2,2))
		var direction=(base+translation+Vector3(0,rng.randf_range(0,2),0)-origin).normalized()
		for shape in u.hit_shapes:
			var a=Geometry.capsule_hit(origin-Pose.shape_translation(u),direction,shape.a,shape.b,shape.radius)
			var b=Geometry.capsule_hit(origin,direction,shape.a+translation,shape.b+translation,shape.radius)
			if not (a==b or absf(a-b)<.00001):print("CAPSULE_DIFF ",a," ",b," delta=",absf(a-b))
			check(a==b or absf(a-b)<.0001,"lazy ray translation equals full capsule translation (0.1 mm float tolerance)")
	for weapon in game.catalog.weapons.values():
		var profile=preload("res://scripts/ammo_presentation.gd").profile(weapon)
		var mesh=preload("res://scripts/weapon_effects.gd").battle_casing_mesh(profile)
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==216,"72 triangle compact casing")
		check(mesh.get_aabb().size.z<=1.0001,"normalized case keeps caliber length")
	for group in game.crowd_batches.groups.values():check(group.node.material_override.next_pass==null,"crowd uses one skin pass")
	check(game.fx.instance_batches.case_material.next_pass==null,"cases have no second shell pass")
	var puffs=game.fx.puffs;var children=puffs.get_child_count();var particles=game.fx.particles.size()
	for i in range(300):game.fx.piece(Vector3(0,1,0),Vector3.ONE,Color.WHITE,Vector3.UP,.7,true,0,["smoke","fire","flash","spark"][i%4])
	puffs.advance(.001)
	check(puffs.get_child_count()==children and game.fx.particles.size()==particles,"300 decorative emissions create no CPU particles/nodes")
	check(puffs.writes==1,"300 emissions upload once")
	check(puffs.instances.instance_count==192,"bounded 192 cards")
	puffs.advance(1)
	check(puffs.instances.visible_instance_count==0,"expired effects stop drawing")
	var counts=[]
	for entry in game.crowd_batches.groups.values():
		var arrays=entry.instances.mesh.surface_get_arrays(0)
		counts.append({"name":entry.node.name,"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"triangles":arrays[Mesh.ARRAY_INDEX].size()/3,"active":entry.instances.visible_instance_count})
	check(game.world.time==0 and game.world.shots==0,"simulation remains stopped")
	print("V41_EFFECTS "+JSON.stringify({"checks":checks,"failures":failures,"title":root.title,"geometry":counts,"time":game.world.time,"shots":game.world.shots}))
	game.free();quit(0 if failures==0 else 1)
