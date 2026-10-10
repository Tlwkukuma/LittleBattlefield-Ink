extends SceneTree
## Registry, static capsules and bounded visibility queries. No battle steps or input.
const Catalog=preload("res://scripts/source_catalog.gd")
const Rules=preload("res://scripts/cover_rules.gd")
const Pose=preload("res://scripts/combat_pose.gd")
const Perception=preload("res://scripts/campaign_perception.gd")
const DirectionalAim=preload("res://scripts/campaign_directional_aim.gd")
var checks=0
var failures: Array[String]=[]

class CountingWorld:
	extends "res://scripts/proving_world.gd"
	var query_count=0
	func trace_3d(origin: Vector3,direction: Vector3,distance: float,p: Dictionary={},walls_only: bool=false) -> Dictionary:
		query_count+=1
		return super.trace_3d(origin,direction,distance,p,walls_only)

func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)

func _initialize():run.call_deferred()

func silhouette(u: Dictionary,stance: int,view: Dictionary):
	u.stance=stance;u.stance_blend=float(stance);u.elevation=0
	var origin=Pose.base(u)
	var head=origin+Vector3(0,Pose.HEAD_CENTER[stance],0)
	u.hit_shapes=[{"a":origin+Vector3.UP*.35,"b":head-Vector3.UP*.30,"radius":.25,"region":"body"},{"a":head,"b":head,"radius":.25,"region":"head"}]
	view.root.position=origin;view.muzzle_socket.position=Vector3(.9,Pose.MUZZLE_HEIGHT[stance],0)
	Pose.capture(u,view)

func run():
	var catalog=Catalog.new();var second=Catalog.new()
	check(Rules.load_count==1,"multiple catalog instances parse material data only once")
	check(Rules.errors.is_empty(),"every registered component and weapon has an explicit family")
	check(Rules.materials.size()==16,"all 16 materials compiled")
	check(Rules.component_ids.size()==catalog.components.size(),"all registered component IDs mapped")
	for id in catalog.weapons:
		var w: Dictionary=catalog.weapons[id]
		check(w.has("cover_ammo") and w.cover_ammo.id==Rules.weapon_ids[id],"weapon binding "+id)
	var mounted=0
	for vehicle in catalog.data.vehicles.values():
		for weapon in vehicle.weapons.values():mounted+=1;check(weapon.has("cover_ammo"),"vehicle mode has compiled table")
	for weapon in catalog.data.emplacements.values():mounted+=1;check(weapon.has("cover_ammo"),"emplacement has compiled table")
	check(mounted==17,"17 mounted modes")
	check(absf(catalog.weapons.m416.cover_ammo.damage[Rules.materials.brick.index]-100.0/48)<.00001,"compiled brick response matches approved proposal")
	check(float(catalog.weapons.m416.damage)==28,"registry leaves current flesh damage intact")
	var plan={"world":{"w":1600,"h":1600,"groundFeatures":[]},"instances":[],"looseSegments":[{"id":"cover","componentId":"wall.brick","x1":880,"y1":680,"x2":880,"y2":920,"thickness":12,"godot3d":{"height":1.25}}],"trees":[],"deployment":{"player":{"x":800,"y":800}}}
	var world=CountingWorld.new();world.setup(plan,catalog)
	var shooter: Dictionary=world.player;shooter.position=Vector2.ZERO;shooter.facing=Vector2.RIGHT
	var target: Dictionary=world.add_unit(Vector2(4,0),false);target.facing=Vector2.LEFT
	var node=Node3D.new();root.add_child(node);var socket=Node3D.new();node.add_child(socket)
	var view={"root":node,"muzzle_socket":socket}
	silhouette(shooter,0,view);silhouette(target,1,view)
	var perception=Perception.new();perception.configure(world)
	world.query_count=0
	check(not perception.can_see(shooter,target),"crouched actual capsule stays behind a 1.25m wall")
	check(world.query_count==1,"blocked perception uses one silhouette ray")
	silhouette(target,0,view);world.query_count=0
	check(perception.can_see(shooter,target),"standing head can be seen above the same wall")
	check(world.query_count==1,"exposed perception uses one silhouette ray")
	world.campaign_ai.configure(world);world.query_count=0
	var contact={"source":"vision","observed_at":0.0,"position":target.position,"elevation":target.elevation,"stance":target.stance}
	DirectionalAim.observe(shooter,contact,catalog.weapons.m416,Vector2.ZERO)
	check(shooter.ai_aim_mark.y<1.25,"directional AI does not select the exposed head over low cover")
	check(world.query_count==0,"directional firing aim casts no extra rays")
	var cached_head: Vector3=Pose.head(target)
	for shape in target.hit_shapes:shape.a+=Vector3(0,0,.3);shape.b+=Vector3(0,0,.3)
	check(Pose.head(target).distance_to(cached_head+Vector3(0,0,.3))<.000001,"pose query follows shared capsule translation without animation sampling")
	DirectionalAim.observe(shooter,contact,catalog.weapons.m416,Vector2.ZERO)
	check(absf(shooter.ai_aim_mark.z-target.position.y)<.000001,"AI aim ignores fine limb offsets; physical capsules remain exact")
	check(absf(Pose.candidate_head(Vector2.ZERO,0,1).y-1.195)<.000001,"hypothetical crouch cover includes the head top")
	var loads=Rules.load_count
	for i in range(1000):Pose.head(target);Pose.chest(target);Pose.eye(target);Pose.muzzle(target)
	check(Rules.load_count==loads,"repeated pose queries never reload material resources")
	check(world.shots==0 and world.time==0,"no firing or battle progression")
	node.free()
	print(JSON.stringify({"suite":"cover_foundation","checks":checks,"failures":failures,"registry_loads":Rules.load_count,"battle_steps":0,"shots":world.shots}))
	quit(0 if failures.is_empty() else 1)
