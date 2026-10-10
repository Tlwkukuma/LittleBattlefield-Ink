extends SceneTree
## Static silhouettes, ballistic rays, support, and navigation geometry only.
## No GUI input, battle frames, screenshots, or automated playthrough.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Level=preload("res://scripts/orchard_level.gd")
const Surface=preload("res://scripts/terrain_surface.gd")
const Perception=preload("res://scripts/campaign_perception.gd")
const Ink=preload("res://scripts/ink_art.gd")
const Props=preload("res://scripts/proving_art.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
var catalog=Catalog.new()
var checks=0
var failures=[]

func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)

func bench(old: bool=false,angle: float=0) -> Dictionary:
	var plan={"world":{"w":3200,"h":2400,"groundFeatures":[]},"instances":[],"looseSegments":[],"trees":[],"deployment":{"player":{"x":1600,"y":1200}}}
	var feature={"id":"cover-test","componentId":"landform.trench-network","points":[[1600,1600],[1600,800]],"depth_m":1.3 if old else Level.TRENCH_DEPTH,"bottom_width_m":2.4,"bank_run_m":1,"corner_radius_m":2,"parapet_height_m":0 if old else Level.TRENCH_PARAPET,"parados_height_m":0 if old else .3,"parapet_side":1,"ramps":[{"points":[[1600,1600],[1320,1800]],"width_m":2.8},{"points":[[1600,800],[1320,600]],"width_m":2.8}]}
	for i in range(feature.points.size()):
		var p=(catalog.v(feature.points[i])-Vector2(1600,1200)).rotated(angle)+Vector2(1600,1200);feature.points[i]=[p.x,p.y]
	for ramp in feature.ramps:
		for i in range(ramp.points.size()):
			var p=(catalog.v(ramp.points[i])-Vector2(1600,1200)).rotated(angle)+Vector2(1600,1200);ramp.points[i]=[p.x,p.y]
	plan.world.groundFeatures.append(feature)
	var world=World.new();world.setup(plan,catalog);return {"world":world,"plan":plan}

func exposed(terrain,origin: Vector3,target: Vector3) -> bool:
	var line=target-origin;return terrain.ray(origin,line.normalized(),line.length()).is_empty()

func pose(unit: Dictionary,at: Vector2,height: float,stance: int=0):
	unit.position=at;unit.elevation=height;unit.stance=stance;unit.stance_blend=float(stance);unit.hit_shapes=[];unit.facing=Vector2.RIGHT

func _initialize():run.call_deferred()
func run():
	var old=bench(true);var current=bench();var old_terrain=old.world.terrain;var terrain=current.world.terrain
	var before=0;var after=0;var samples=0
	for distance in [12.0,20.0,30.0]:
		for along in [-4.0,0.0,4.0]:
			for local_height in [1.25,1.61,1.82]:
				var source=Vector3(distance,1.35,along);var old_target=Vector3(0,-1.3+local_height,along);var target=Vector3(0,-Level.TRENCH_DEPTH+local_height,along)
				before+=int(exposed(old_terrain,source,old_target));after+=int(exposed(terrain,source,target));samples+=1
	check(before>=18,"old shallow trench exposes real standing head silhouettes to level-ground fire")
	check(after==0,"deep lane plus earth parapet occludes standing torso/head at 12-30m")
	check(absf(terrain.height(Vector2(3.2,0))-Level.TRENCH_PARAPET)<.015,"front breastwork has actual authored crest height")
	check(absf(terrain.height(Vector2(-3.2,0))-.3)<.015,"rear bank has distinct lower height")
	check(absf(terrain.height(Vector2.ZERO)+Level.TRENCH_DEPTH)<.001,"earthwork does not raise or refill the trench floor")
	for stance in [1,2]:
		pose(current.world.player,Vector2.ZERO,-Level.TRENCH_DEPTH,stance)
		check(not exposed(terrain,Vector3(20,1.35,0),World.head_center(current.world.player)),"crouch/prone remain physically below frontal cover "+str(stance))
	pose(current.world.player,Vector2.ZERO,-Level.TRENCH_DEPTH)
	check(exposed(terrain,Vector3(5,3.35,0),World.head_center(current.world.player)),"elevated nearby shooter can still fire down into the trench")
	for entry in [old,current]:
		var w=entry.world;var defender: Dictionary=w.player;pose(defender,Vector2.ZERO,w.terrain.height(Vector2.ZERO))
		var enemy=w.add_unit(Vector2(20,0),false);pose(enemy,Vector2(20,0),0);enemy.facing=Vector2.LEFT
		var perception=Perception.new();perception.configure(w);enemy.weapon_id="kar98k" if catalog.weapons.has("kar98k") else "m416"
		# Use a 12m view ray so all current rifle vision families contain the probe.
		enemy.position=Vector2(12,0)
		check(perception.can_see(enemy,defender)==(entry==old),"AI vision obeys the same actual head/terrain occlusion; old="+str(entry==old))
		var origin=Vector3(enemy.position.x,World.muzzle_height(enemy),0);var head=World.head_center(defender);var line=head-origin
		var hit=w.trace_3d(origin,line.normalized(),line.length()+.3,{"source":enemy.id,"team":enemy.team})
		check(hit.get("type","")==("unit" if entry==old else "terrain"),"real bullet hits old exposed head or new earthwork; old="+str(entry==old))
	for angle in [.37,1.11,PI*.5]:
		var rotated=bench(false,angle);var front=Vector2.RIGHT.rotated(angle)
		for h in [1.61,1.82]:
			check(not exposed(rotated.world.terrain,Vector3(front.x*20,1.35,front.y*20),Vector3(0,-Level.TRENCH_DEPTH+h,0)),"rotated defensive berm occludes standing head "+str(angle))
		for ramp in rotated.world.terrain.features[0].trench_ramps:
			var walkable=true
			for i in range(40):
				var a: Vector2=ramp.points[0].lerp(ramp.points[-1],float(i)/40);var b: Vector2=ramp.points[0].lerp(ramp.points[-1],float(i+1)/40)
				walkable=walkable and rotated.world.terrain.walkable(a,b)
			check(walkable,"rotated berm cutout leaves ramp open "+str(angle))
	# Actual first-level geometry and actual ledge support; no actor movement simulated.
	var plan=Level.plan(catalog);plan.godot3d.campaign=false;plan.units={"red":[],"blue":[]}
	var w=World.new();var compiled=w.setup(plan,catalog)
	var ledge=catalog.position_point(Vector2(1030,1640),plan)
	var top=-INF
	for o in w.objects:
		if o.owner=="orchard-trench-step":
			var local=(ledge-o.position).rotated(-o.angle)
			top=maxf(top,o.elevation+w.HouseGeometry.support(o,local,.05,INF))
	check(absf(top-(-Level.TRENCH_DEPTH+Level.TRENCH_STEP))<.001,"firing ledge really supports feet at the higher firing elevation")
	var endpoint=Vector3(ledge.x+20,1.35,ledge.y)
	pose(w.player,ledge,top)
	var muzzle=Vector3(ledge.x+.45,World.muzzle_height(w.player),ledge.y)
	check(exposed(w.terrain,muzzle,endpoint),"standing on ledge clears frontal soil with the real stance muzzle height")
	check(exposed(w.terrain,endpoint,World.head_center(w.player)),"standing firing posture exposes head in return")
	pose(w.player,ledge,top,1)
	check(not exposed(w.terrain,endpoint,World.head_center(w.player)),"crouching on firing ledge ducks below breastwork")
	pose(w.player,Vector2(ledge.x-.8,ledge.y),-Level.TRENCH_DEPTH)
	check(not exposed(w.terrain,endpoint,World.head_center(w.player)),"stepping off firing ledge returns to protected travel lane")
	var stage=Node3D.new();root.add_child(stage);var rig_measurements=[]
	for id in ["m416","akm","awm"]:
		var weapon: Dictionary=catalog.weapons[id];var view=Ink.soldier(stage,0,false,true)
		for child in view.rifle.get_children():view.rifle.remove_child(child);child.free()
		view.held=Props.weapon(view.rifle,weapon);view.weapon=id;view.weapon_profile=weapon
		view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Effects.flash(view.muzzle_socket,weapon)
		for sample in [["ledge-standing",top,0,true],["ledge-crouched",top,1,false],["lane-standing",-Level.TRENCH_DEPTH,0,false]]:
			pose(w.player,ledge,sample[1],sample[2]);w.player.aiming=true;w.player.aim_valid=true;w.player.aim_point=Vector2(endpoint.x,endpoint.z);w.player.aim_height=endpoint.y;w.player.weapon_id=id
			view.root.position=Vector3(ledge.x,w.player.elevation,ledge.y);view.body_yaw=-PI*.5
			Motion.update(view,w.player,0,1,float(weapon.reload))
			var actual_muzzle: Vector3=view.muzzle_socket.global_position
			var actual_head: Vector3=w.player.hit_shapes.filter(func(s):return s.region=="head")[0].a
			check(exposed(w.terrain,actual_muzzle,endpoint)==bool(sample[3]),"original rig muzzle respects ledge/lane cover: "+id+" "+sample[0])
			check(exposed(w.terrain,endpoint,actual_head)==bool(sample[3]),"original rig head respects ledge/lane exposure: "+id+" "+sample[0])
			rig_measurements.append({"weapon":id,"pose":sample[0],"muzzle_y":actual_muzzle.y,"head_y":actual_head.y})
		view.root.free()
	stage.free()
	check(w.terrain.conflicts.is_empty(),"existing roads/platforms do not refill either trench route")
	var soil_mesh=w.terrain.mesh();var vertices: PackedVector3Array=soil_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX];var shared=true
	# Exterior scenery rings are appended after the playable height field; they
	# are outside terrain.bounds and are not part of trench collision geometry.
	for i in range(0,w.terrain.size.x*w.terrain.size.y*6,173):shared=shared and absf(vertices[i].y-w.terrain.height(Vector2(vertices[i].x,vertices[i].z)))<.00001
	check(shared,"soil cover display and ballistic surface use identical mesh heights")
	print(JSON.stringify({"suite":"trench_cover_contract","checks":checks,"failures":failures,"frontal_samples":samples,"old_exposed":before,"new_exposed":after,"rig":rig_measurements}))
	quit(0 if failures.is_empty() else 1)
