extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	game.update_camera(0);game.update_views(1.0/60)
	var u: Dictionary=game.world.units[1];var view: Dictionary=game.actors[1]
	var at: Vector3=u.hit_shapes[0].a
	view.pose_wait=10;u.position+=Vector2(.2,.1);game.update_views(.001)
	check(u.hit_shapes[0].a.distance_to(at+Vector3(.2,0,.1))<.0001,"skipped animation preserves current world-space body position")
	game.resolve_muzzle(u,game.world.weapon_for(u),-1)
	at=u.hit_shapes[0].a;view.pose_wait=10;game.update_views(.001)
	check(u.hit_shapes[0].a.distance_to(at)<.0001,"fresh physical muzzle pose is never translated twice")
	check(u.hit_shapes.size()>2,"original limb hit shapes retained")
	game.fx.death(u,Vector3.ZERO)
	for i in range(10):game.fx._process(.5)
	var corpse: Dictionary=game.fx.corpses[0]
	check(corpse.get("pose_finished",false),"completed original death clip sleeps")
	var clip_position=corpse.view.animator.current_animation_position;var body=corpse.view.body.transform
	game.fx._process(.016)
	check(corpse.view.animator.current_animation_position==clip_position and corpse.view.body.transform==body,"settled corpse retains its exact final pose")
	var w=game.world;var wall: Dictionary={};var normal=Vector2.ZERO
	for object in w.objects:
		if not object.collision or object.whole or object.size.x<=3 or object.height<=1.5:continue
		for sign_value in [1,-1]:
			var direction=Vector2(0,sign_value).rotated(object.angle)
			u.position=object.position+direction*(object.size.y*.5+.15);u.elevation=w.terrain.height(u.position)
			if w.blocked(u.position,Traversal.RADIUS,w.collision_height(u),-1,u.elevation) and Traversal.escape_path_clear(w,u,u.position+direction*.5,u.elevation):wall=object;normal=direction;break
		if not wall.is_empty():break
	check(not wall.is_empty(),"recovery fixture has a real orchard wall")
	if wall.is_empty():game.free();quit(1);return
	u.position=wall.position+normal*(wall.size.y*.5+.15);u.elevation=w.terrain.height(u.position);u.facing=-normal;u.requested_velocity=Vector2.ZERO;u.last_clear={};u.recovery_after=0
	var initial=u.position
	check(w.blocked(u.position,Traversal.RADIUS,w.collision_height(u),-1,u.elevation),"fixture starts with a shallow physical overlap")
	w.overlap_budget_usec=0;Traversal.recover_overlap(w,u)
	check(u.position==initial,"exhausted shared budget defers search without teleporting")
	for i in range(45):
		w.overlap_budget_usec=2000;Traversal.recover_overlap(w,u)
		if not w.blocked(u.position,Traversal.RADIUS,w.collision_height(u),-1,u.elevation):break
	check(not w.blocked(u.position,Traversal.RADIUS,w.collision_height(u),-1,u.elevation),"resumed ordered search eventually clears overlap")
	check(u.position.distance_to(initial)<=.8 and (u.position-wall.position).dot(normal)>0,"recovery stays local and on original wall side")
	u.overlap_search={"next":140};Traversal.reset(u)
	check(not u.has("overlap_search"),"new life clears deferred recovery state")
	check(w.time==0 and w.shots==0,"fixture never advances a battle or fires")
	print("PERFORMANCE_EXECUTION checks=%d failures=%d"%[checks,failures]);game.free();quit(0 if failures==0 else 1)
