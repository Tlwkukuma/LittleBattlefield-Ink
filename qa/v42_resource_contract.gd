extends SceneTree
## Geometry, bounded hearing-query cache and resources only. No AI/game steps.
class HearingFixture:
	extends RefCounted
	var topology_revision=0
	var time=0.0
	var profile_ai=false
	var queries=0
	var blocked=false
	func trace_3d(_origin,_direction,_distance,_options,_walls):
		queries+=1
		return {"type":"object"} if blocked else {}
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
	var effects=preload("res://scripts/weapon_effects.gd")
	for weapon in game.catalog.weapons.values():
		if weapon.kind not in ["rocket","mortar","vehicleMortar","grenadeProjectile","grenade"]:continue
		var original=effects.projectile(game.stage,weapon,false)
		var compact=effects.projectile(game.stage,weapon,true)
		var points=PackedVector3Array()
		for node in original.find_children("*","MeshInstance3D",true,false):
			for surface in range(node.mesh.get_surface_count()):
				if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:continue
				var arrays=node.mesh.surface_get_arrays(surface);var indices=arrays[Mesh.ARRAY_INDEX]
				var frame=original.global_transform.affine_inverse()*node.global_transform
				if indices!=null and not indices.is_empty():
					for i in indices:points.append(frame*arrays[Mesh.ARRAY_VERTEX][i])
				else:
					for point in arrays[Mesh.ARRAY_VERTEX]:points.append(frame*point)
		var meshes=compact.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1,"one surface retains special projectile geometry")
		var actual=meshes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(actual.size()==points.size(),"all original projectile triangles retained")
		for i in range(mini(points.size(),actual.size())):check(points[i].distance_to(actual[i])<.000001,"grenade/rocket fin/tail geometry unchanged")
		game.weapon_batches.register_tree(compact)
		check(meshes[0].layers==0,"source submitted by shared atlas only")
		original.free();compact.free()
	var sensor=preload("res://scripts/campaign_perception.gd").new();var fixture=HearingFixture.new()
	for i in range(20):sensor.hearing_transmission(fixture,Vector3(i*5,1,0),Vector3(i*5,1,12))
	check(fixture.queries==4,"simultaneous sound queries capped at four per render frame")
	check(sensor.hearing_transmission(fixture,Vector3(0,1,0),Vector3(0,1,12))==1,"cached clear sector")
	check(fixture.queries==4,"cache adds no ray")
	fixture.topology_revision+=1;fixture.blocked=true;sensor.hearing_frame=-1
	check(sensor.hearing_transmission(fixture,Vector3(0,1,0),Vector3(0,1,12))==.4,"topology change invalidates auditory cache")
	check(fixture.queries==5,"topology queried once")
	fixture.time=1;sensor.hearing_frame=-1;fixture.blocked=false
	check(sensor.hearing_transmission(fixture,Vector3(0,1,0),Vector3(0,1,12))==1,"expired cache refreshes")
	check(not preload("res://scripts/campaign_directional_aim.gd").fresh({"source":"hearing","observed_at":1},1),"heard estimate never grants a visible fire target")
	check(game.world.time==0 and game.world.shots==0,"world stays frozen")
	print("V42_RESOURCE checks=",checks," failures=",failures," simulation_time=",game.world.time," shots=",game.world.shots)
	game.free();quit(0 if failures==0 else 1)
