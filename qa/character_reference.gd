extends SceneTree
const Game=preload("res://scripts/proving_ground.gd")
var game
var viewport: SubViewport
var failures=[]
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	if not ok:failures.append(label);push_error(label)
func shot(name: String):
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://qa/character-"+name+".png")
func run():
	viewport=SubViewport.new();viewport.size=Vector2i(1024,1280);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_4X;root.add_child(viewport)
	game=Game.new();game.qa_mode=true;viewport.add_child(game);game.set_physics_process(false);game.set_process(false);game.ui.hide()
	var p=game.catalog.range_plan();p.instances=[];p.looseSegments=[];p.vehicles=[];p.emplacements=[];p.units.red=[];p.godot3d.range=false;p.deployment.player={"x":2000,"y":1400};game.rebuild(p)
	var u=game.world.player;var view=game.actors[0]
	game.camera.size=2.65;game.camera.position=Vector3(0,5.65,5.7);game.camera.look_at(Vector3(0,.95,0))
	u.facing=Vector2(.75,.66).normalized();game.update_views(0);await shot("painted-front")
	check(view.animator.current_animation=="Rifle_idle","Idle uses original idle with upper-body rifle layer")
	u.aiming=true;game.update_views(0);await shot("painted-aim")
	check(view.animator.current_animation=="Rifle_idle","Aiming preserves the original lower-body pose")
	u.aiming=false;u.flash=.05;game.update_views(0)
	check(view.muzzle.visible,"Firing displays muzzle flash")
	for bone in ["L_Hand","R_Hand","L_Foot","R_Foot","L_ToeBase","R_ToeBase"]:
		check(view.skeleton.find_bone(bone)>=0,"Original named bone retained: "+bone)
	u.flash=0;game.update_views(0)
	check(view.skeleton.get_bone_count()==41,"All original 41 bones retained")
	check(view.get("source_rig",false),"Original Tripo skeleton and animations are active")
	check(view.has("helmet") and view.helmet.visible,"Independent helmet is visible")
	var character_mesh: MeshInstance3D=view.model.find_child("Source_Body",true,false)
	check(character_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()/3==9688,"Original body topology retained")
	check(view.animator.get_animation_list().size()==25,"Twenty source clips, four rifle layers and RESET imported")
	for direction in [Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		u.facing=direction;game.update_views(0);await shot("painted-direction-"+str(int(direction.angle()*100)))
	u.facing=Vector2(.75,.66).normalized()
	for stance in [1,2]:
		u.stance=stance;u.stance_blend=stance;game.update_views(0);await shot("painted-stance-"+str(stance))
		for bone in range(view.skeleton.get_bone_count()):check(view.skeleton.get_bone_global_pose(bone).is_finite(),"Finite stance bone")
	u.stance=0;u.stance_blend=0;u.velocity=Vector2(.46,.888)*5.8;u.sprinting=true;u.walk=1.2;game.update_views(0);await shot("painted-run")
	u.velocity=Vector2.ZERO;u.sprinting=false;u.grounded=false;u.elevation=.85;u.vertical_speed=1;game.update_views(0);await shot("painted-jump")
	u.elevation=0;u.grounded=true
	for phase in [.28,.60,.84]:
		u.reload=2.1*(1-phase);u.reload_duration=2.1;game.update_views(0);await shot("painted-reload-"+str(int(phase*100)))
	var triangles=preload("res://qa/character_turntable.gd").count_meshes(view.body)
	print("CHARACTER HERO TRIANGLES (garments + attachments): ",triangles)
	print("CHARACTER REFERENCE FAILURES: ",failures)
	viewport.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
