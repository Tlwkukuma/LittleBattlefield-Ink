extends SceneTree
const Game=preload("res://scripts/proving_ground.gd")
var game
var failures=[]
var checks=0
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func shot(name: String):
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/tripo-"+name+".png")
func run():
	game=Game.new();game.qa_mode=true;root.add_child(game);game.set_process(false);game.set_physics_process(false);game.fx.set_process(false);game.ui.hide()
	var plan=game.catalog.range_plan();plan.instances=[];plan.looseSegments=[];plan.vehicles=[];plan.emplacements=[];plan.units.red=[];plan.godot3d.range=false;plan.deployment.player={"x":2000,"y":1400};game.rebuild(plan);game.fx.set_process(false)
	var u=game.world.player;game.world.invulnerable=false;u.position=Vector2.ZERO;u.facing=Vector2(.75,.66).normalized();u.aiming=true
	game.camera.size=3.7;game.camera.position=Vector3(0,4.5,5);game.camera.look_at(Vector3(0,1,0));game.update_views(0)
	var view=game.actors[u.id]
	check(view.get("tripo",false),"User FBX character is active")
	check(view.skeleton.get_bone_count()==41,"All source bones are preserved")
	check(view.helmet.visible,"Helmet starts attached")
	await shot("equipped")
	for stance in [0,1,2]:
		u.stance=stance;u.stance_blend=stance;game.update_views(0)
		for bone in range(view.skeleton.get_bone_count()):check(view.skeleton.get_bone_global_pose(bone).is_finite(),"Pose is finite: "+str(stance)+" / "+str(bone))
		var center=game.world.head_center(u)
		var hit=game.world.ray(Vector2(center.x,center.z+4),Vector2.UP,8,center.y,{"team":1,"source":-1})
		check(not hit.is_empty() and hit.get("region","")=="head","Head ray works for stance "+str(stance))
		await shot("stance-"+str(stance))
	u.stance=0;u.stance_blend=0;game.update_views(0)
	var chest_hit=game.world.ray(Vector2(0,4),Vector2.UP,8,.9,{"team":1,"source":-1})
	check(chest_hit.get("region","")=="body","Torso ray does not become a headshot")
	var w=game.world.weapon_for(u);game.world.damage_unit(u,10,Vector3(1,0,.3),w,false)
	check(view.helmet.visible and game.fx.helmets.is_empty(),"Body damage does not detach helmet")
	game.world.damage_unit(u,10,Vector3(-1.3,0,.4),w,false,true)
	check(u.helmet_lost and game.fx.helmets.size()==1 and not view.helmet.visible,"Head hit creates one detached helmet")
	if game.fx.helmets.is_empty():game.queue_free();quit(1);return
	var helmet=game.fx.helmets[0];var launch=helmet.node.global_position
	for i in range(18):game.fx._process(1.0/60)
	check(helmet.node.global_position.y>launch.y+.2,"Helmet rises after impact")
	check(Vector2(helmet.node.position.x,helmet.node.position.z).length()>.1,"Helmet moves with impact direction")
	await shot("helmet-airborne")
	game.world.damage_unit(u,1,Vector3.ZERO,w,false,true)
	check(game.fx.helmets.size()==1,"Repeated head hit cannot duplicate helmet")
	game.world.damage_unit(u,1000,Vector3(.4,0,0),w,false,true);game.update_views(0)
	check(game.fx.corpses.size()==1 and not game.fx.corpses[0].view.helmet.visible,"Headshot corpse remains bareheaded")
	for i in range(240):game.fx._process(1.0/60)
	check(helmet.settled and helmet.bounces>0,"Helmet bounces and settles")
	var minimum=INF
	for corner in range(8):minimum=minf(minimum,(helmet.node.global_transform*helmet.node.mesh.get_aabb().get_endpoint(corner)).y)
	check(minimum>=-.001,"Settled helmet stays above floor")
	await shot("helmet-ground")
	game.world.refill();game.update_views(0)
	check(not u.helmet_lost and view.helmet.visible,"Refill restores attached helmet")
	var shooter=u.duplicate(true);shooter.id=99;shooter.team=1;shooter.position=Vector2(0,4);shooter.aim_height=game.world.head_center(u).y;shooter.cooldown=0;shooter.reload=0
	var fired=game.world.fire(shooter,w,shooter,shooter.position,-PI*.5,1.35,u.position)
	check(fired,"Real projectile fires toward head")
	for i in range(60):game.world.update_projectiles(1.0/120)
	check(u.helmet_lost and game.fx.helmets.size()==2,"Actual projectile collision triggers helmet drop")
	print("TRIPO HEADSHOT: ",checks-failures.size(),"/",checks," passed. Failures: ",failures)
	game.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
