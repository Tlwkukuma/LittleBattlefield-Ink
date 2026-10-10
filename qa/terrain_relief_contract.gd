extends SceneTree
## Direct data/geometry checks only. No GUI input or automated user playtest.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Ladder=preload("res://scripts/terrain_ladder.gd")
var checks=0
var failures: Array=[]

func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)

func at(world,point: Vector2):
	Traversal.reset(world.player);world.player.position=point;world.player.elevation=world.terrain.height(point)
	world.player.velocity=Vector2.ZERO;world.player.requested_velocity=Vector2.ZERO

func _initialize():run.call_deferred()
func run():
	var catalog=Catalog.new();var plan=catalog.range_plan();var w=World.new();var compiled=w.setup(plan,catalog);var t=w.terrain
	check(catalog.components.size()>=68 and catalog.prefabs.size()>=57 and catalog.prefabs.has("biome.desert") and catalog.prefabs.has("biome.snowfield"),"original catalog plus five components and five reusable terrain prefabs remains available")
	check(plan.id=="godot-proving-ground" and compiled.vehicles.size()>7,"terrain sector shares existing unified range and vehicle roster")
	check(is_equal_approx(t.height(Vector2(15,-25)),-1.65),"trench has negative floor elevation")
	check(is_equal_approx(t.height(Vector2(37,-25)),3.4),"mountain crest height")
	check(t.grade(Vector2(37,-19))<.82 and t.grade(Vector2(37,-33))>.82,"mountain differentiates accessible slope and steep face")
	check(t.material_at(Vector2(-33,-25))=="terrain.snow","snow surface registered")
	check(t.material_at(Vector2(-9,-25))=="terrain.desert","desert surface registered")
	check(t.material_at(Vector2(18,-20))=="terrain.red-earth","red earth distinct from trench")
	var snow_trail=Vector2(-37,-25.6);var snow_bank=Vector2(-37,-28.5)
	check(t.height(snow_bank)>1.1 and t.height(snow_trail)<.2,"snow is a thick rounded drift beside a depressed packed trail")
	check(t.speed_at(snow_trail)>.90 and t.speed_at(snow_bank)<.76,"powder and packed snow affect walking differently")
	check(t.height(Vector2(-13.5,-25))>1.8 and t.height(Vector2(-9,-25))<.2,"desert has metre-scale dunes with a low inter-dune corridor")
	check(t.grade(Vector2(-16,-25))<t.grade(Vector2(-12,-25)),"dune windward rise and lee face have different geometric slopes")
	check(t.speed_at(Vector2(-9,-25))>t.speed_at(Vector2(-13.5,-25)),"loose dune slopes slow travel more than the corridor")
	check(not t.ray(Vector3(-20,.9,-25),Vector3.RIGHT,18).is_empty(),"actual sand dune blocks bullets at body height")
	check(not t.ray(Vector3(-43,.6,-28.5),Vector3.RIGHT,18).is_empty(),"actual snowbank blocks a low firing line")
	for point in [Vector2(15,-25),Vector2(-37,-25.6),Vector2(-9,-25),Vector2(37,-25),Vector2.ZERO]:
		var surface=Vector3(point.x,t.height(point),point.y)
		check(t.ray(surface,Vector3.UP,3).is_empty(),"surface explosion can propagate upward without self-shielding "+str(point))
	var hit=t.ray(Vector3(15,-.6,-25),Vector3(0,0,1),8)
	check(hit.get("type","")=="terrain" and hit.distance>2 and hit.distance<3.5,"trench bank blocks horizontal bullets below grade")
	check(t.ray(Vector3(15,.2,-25),Vector3(0,0,1),8).is_empty(),"above-grade shot clears bank")
	check(w.trace_3d(Vector3(39,1,-15),Vector3(0,0,-1),15,{},true).get("type","")=="terrain","mountain participates in shared shot and blast shielding")
	for point in [Vector2(15,-25),Vector2(8,-25),Vector2(37,-19),Vector2(37,-33),Vector2(-33,-25)]:
		var ray=t.ray(Vector3(point.x,12,point.y),Vector3.DOWN,30)
		check(not ray.is_empty() and absf(12-ray.distance-t.height(point))<.0001,"vertical pick matches floor "+str(point))
	# Oblique rays traverse cells from outside map bounds and preserve the t parameter.
	var origin=Vector3(15,18,50);var direction=(Vector3(15,-1.65,-25)-origin)/40
	hit=t.ray(origin,direction,60)
	check(not hit.is_empty() and hit.distance<40,"oblique camera ray first hits the near trench lip")
	var mesh=t.mesh();var vertices=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX];var normals=mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	check(mesh.get_aabb().position.y< -1.6 and mesh.get_aabb().end.y>3.3,"render mesh contains real trench and mountain relief")
	var matches=true
	for i in range(0,vertices.size(),173):
		var p: Vector3=vertices[i]
		matches=matches and absf(p.y-t.height(Vector2(p.x,p.z)))<.0001 and normals[i].y>0
	check(matches,"render mesh and collision sampler share exact triangles and upward normals")
	at(w,Vector2(6,-25))
	for i in range(180):w.time+=1.0/60;Traversal.move(w,w.player,Vector2.RIGHT,1.0/60,false,false)
	check(w.player.position.x>13 and w.player.elevation< -1.6 and w.player.grounded,"soldier walks down end ramp into real trench")
	at(w,Vector2(15,-24.5))
	for i in range(150):w.time+=1.0/60;Traversal.move(w,w.player,Vector2.DOWN,1.0/60,false,false)
	check(w.player.position.y< -22 and w.player.elevation<-.5,"steep bank stops walking without teleporting uphill")
	at(w,Vector2(37,-15))
	for i in range(160):w.time+=1.0/60;Traversal.move(w,w.player,Vector2.UP,1.0/60,false,false)
	check(w.player.elevation>2.5 and w.player.grounded,"mountain approach ramp supports grounded walking")
	check(t.ladders.size()==1,"terrain compiler produces usable ladder")
	var ladder: Dictionary=t.ladders[0]
	at(w,Vector2(ladder.low.x,ladder.low.z))
	check(Ladder.interact(w) and not w.player.ladder.is_empty(),"ladder mounts at lower end")
	check(not w.fire(w.player,w.weapon_for(w.player),w.player,w.player.position,0,w.muzzle_height(w.player),Vector2.ZERO),"climbing reserves hands and disables firing")
	for i in range(250):
		if not w.player.ladder.is_empty():Ladder.move(w,w.player,Vector2.UP,1.0/60,false)
	check(w.player.ladder.is_empty() and w.player.grounded and w.player.position.distance_to(Vector2(ladder.high.x,ladder.high.z))<.01,"ladder exits safely on upper rim")
	check(Ladder.interact(w) and not w.player.ladder.is_empty(),"ladder mounts at upper end")
	for i in range(250):
		if not w.player.ladder.is_empty():Ladder.move(w,w.player,Vector2.DOWN,1.0/60,false)
	check(w.player.ladder.is_empty() and w.player.elevation< -1.6 and w.player.grounded,"ladder descends to negative floor")
	Ladder.interact(w);Ladder.move(w,w.player,Vector2.UP,.4,false);Ladder.move(w,w.player,Vector2.ZERO,.01,true)
	check(w.player.ladder.is_empty() and not w.player.grounded,"space detaches into regular gravity")
	for i in range(90):Traversal.vertical_step(w,w.player,1.0/60)
	check(w.player.grounded and absf(w.player.elevation-t.height(w.player.position))<.01,"detached climber lands in trench")
	var bullet={"weapon":{"kind":"bullet","damage":10},"position":Vector2(15,-25),"direction":Vector2.DOWN,"height":-.6,"slope":0.0,"alive":true,"remaining":20.0,"distance":0.0,"penetration":0,"hit":[]}
	w.advance_round(bullet,10)
	check(not bullet.alive and bullet.position.y< -22,"projectile stops at trench bank rather than y=0 plane")
	var grenade={"id":99,"position":Vector2(15,-25),"height":-.3,"motion":World.Grenade.motion({"origin":Vector3(15,-.3,-25),"velocity":Vector3.DOWN}),"weapon":{"kind":"grenade"},"fuse":20.0,"bounce_sounds":0,"last_bounce_sound":-1.0,"age":0.0,"alive":true}
	w.projectiles=[grenade]
	for i in range(70):w.update_projectiles(1.0/60)
	check(absf(grenade.height-(-1.65+World.Grenade.RADIUS))<.015,"grenade rests on trench floor at negative height")
	for angle in [0.0,.71,PI*.5]:
		var p=plan.duplicate(true);p.looseSegments=[];p.instances=[{"id":"pit","prefabId":"biome.trench-ladder","x":2000,"y":1400,"rotation":angle,"scale":1.25,"godot3d":{"height":1.8}}]
		var test=World.new();test.setup(p,catalog)
		check(absf(test.terrain.height(Vector2.ZERO)+1.8)<.01 and test.terrain.ladders.size()==1,"rotated/scaled prefab retains depression and ladder "+str(angle))
		var data=JSON.parse_string(JSON.stringify(p));var copy=World.new();copy.setup(data,catalog)
		check(absf(copy.terrain.height(Vector2.ZERO)+1.8)<.01 and copy.terrain.ladders.size()==1,"JSON roundtrip preserves relief and ladder "+str(angle))
	# Sample the original skeletal resource directly; no game-window control.
	var stage=Node3D.new();root.add_child(stage)
	var view=preload("res://scripts/source_rig_character.gd").soldier(stage,0,true)
	view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle);view.weapon_profile=catalog.weapons.m416
	view.held=preload("res://scripts/proving_art.gd").weapon(view.rifle,view.weapon_profile)
	view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
	for ratio in [0.0,.2,.45,.7,.9,1.0]:
		w.player.ladder={"spec":ladder,"travel":Ladder.length(ladder)*ratio,"total":Ladder.length(ladder),"motion":1.35}
		Ladder.set_position(w.player,Ladder.sample(ladder,w.player.ladder.travel));view.root.position=Vector3(w.player.position.x,w.player.elevation,w.player.position.y)
		preload("res://scripts/source_rig_motion.gd").ladder_pose(view,w.player)
		var finite=true
		for bone in range(view.skeleton.get_bone_count()):finite=finite and view.skeleton.get_bone_global_pose(bone).is_finite()
		check(finite and not w.player.hit_shapes.is_empty() and not view.muzzle.visible,"ladder preserves finite original rig and live hit capsules "+str(ratio))
	stage.free()
	var marks=preload("res://scripts/terrain_footprints.gd").new();marks.world=w;root.add_child(marks)
	marks.add_step(snow_bank,Vector2.RIGHT);marks.rebuild()
	check(marks.stamps.size()==1 and marks.drawing.mesh.get_surface_count()==1,"snow footprint has a real impression/rim mesh")
	var conforms=true;var raised=0.0
	for p in marks.drawing.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var offset=p.y-t.height(Vector2(p.x,p.z));conforms=conforms and offset>=.004 and offset<=.041;raised=maxf(raised,offset)
	check(conforms and raised>.03,"snowprint follows curved ground and has raised powder edges")
	marks.stamps.clear();marks.add_step(Vector2(-13.5,-25),Vector2.RIGHT);marks.rebuild();raised=0.0
	for p in marks.drawing.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:raised=maxf(raised,p.y-t.height(Vector2(p.x,p.z)))
	check(raised<.025 and raised>.012,"sandprint has a thinner displaced-grain rim than snow")
	for i in range(200):marks.add_step(snow_bank,Vector2.RIGHT)
	check(marks.stamps.size()==180,"persistent footprints remain within their rendering budget")
	marks.free()
	# A real wall across the ladder's upper exit must prevent mounting.
	preload("res://scripts/terrain_biomes.gd").segment(plan,"blocked-ladder","wall.concrete",Vector2(14,-21.5),Vector2(16,-21.5),.5,2.8)
	var blocked=World.new();blocked.setup(plan,catalog);at(blocked,Vector2(ladder.low.x,ladder.low.z));Ladder.interact(blocked)
	check(blocked.player.ladder.is_empty(),"blocked exit rejects ladder without moving through solid cover")
	print("TERRAIN_RELIEF_CONTRACT ",checks-failures.size(),"/",checks," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
