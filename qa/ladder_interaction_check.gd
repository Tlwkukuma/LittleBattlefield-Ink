extends SceneTree
## Direct state/path and source-rig resource checks. No GUI input or screenshots.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Ladder=preload("res://scripts/terrain_ladder.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
var catalog=Catalog.new()
var checks=0
var failures=[]

func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)

func fixture(angle: float=0):
	var p=catalog.range_plan();p.instances=[{"id":"pit","prefabId":"biome.trench-ladder","x":2000,"y":1400,"rotation":angle,"scale":1}]
	p.trees=[];p.vehicles=[];p.emplacements=[];p.units.red=[];p.world.groundFeatures=[]
	p.looseSegments=[{"id":"movable-blocker","componentId":"wall.brick","x1":1360,"y1":1400,"x2":1440,"y2":1400,"thickness":10,"godot3d":{"height":2.8}}]
	var w=World.new();w.setup(p,catalog);return w

func place(w,point: Vector3):
	Traversal.reset(w.player);w.player.position=Vector2(point.x,point.z);w.player.elevation=point.y
	w.player.velocity=Vector2.ZERO;w.player.requested_velocity=Vector2.ZERO

func foot(w) -> Vector3:return Vector3(w.player.position.x,w.player.elevation,w.player.position.y)
func pelvis(view) -> Vector3:return view.skeleton.to_global(view.skeleton.get_bone_global_pose(view.bone_indices.Hip).origin)
func _initialize():run.call_deferred()

func run():
	for angle in [0.0,.71,PI*.5]:
		for end in [0,1]:
			var w=fixture(angle);var ladder: Dictionary=w.terrain.ladders[0]
			var forward=Vector3(ladder.high.x-ladder.low.x,0,ladder.high.z-ladder.low.z).normalized()
			var endpoint: Vector3=ladder.low if end==0 else ladder.high
			place(w,endpoint+forward*(-.65 if end==0 else .65))
			var found=Ladder.nearest(w)
			check(not found.is_empty() and found.end==end,"correct endpoint is reachable at angle %.2f end %d"%[angle,end])
			check(("上梯" if end==0 else "下梯") in Ladder.hint(w),"endpoint-specific E prompt")
			var start=foot(w)
			check(Ladder.interact(w) and not w.player.ladder.is_empty(),"E begins mounting")
			check(foot(w).distance_to(start)<.00001,"E does not snap body to endpoint")
			check(w.player.reload==0 and w.player.requested_velocity==Vector2.ZERO,"mount cancels reload and running momentum")
			var wrong=Vector2.DOWN if end==0 else Vector2.UP
			var continuous=true;var clear=true
			for i in range(80):
				if w.player.ladder.is_empty():break
				var before=foot(w);Ladder.move(w,w.player,wrong,1.0/60,false)
				continuous=continuous and foot(w).distance_to(before)<=Ladder.ENTRY_SPEED/60+.0001
				clear=clear and Ladder.clear(w,foot(w))
			check(continuous and clear,"approach is bounded and checked against real geometry")
			check(not w.player.ladder.is_empty() and foot(w).distance_to(endpoint)<.001,"holding approach direction cannot immediately eject climber")
			check(("W 向上" if end==0 else "S 向下") in Ladder.hint(w),"mounted endpoint explains the valid climbing key")
			for i in range(250):
				if not w.player.ladder.is_empty():Ladder.move(w,w.player,-wrong,1.0/60,false)
			var destination: Vector3=ladder.high if end==0 else ladder.low
			check(w.player.ladder.is_empty() and w.player.grounded and foot(w).distance_to(destination)<.001,"completed traversal exits on opposite endpoint")
	var w=fixture();var ladder: Dictionary=w.terrain.ladders[0]
	place(w,ladder.low-Vector3(0,0,.7));Ladder.interact(w);Ladder.move(w,w.player,Vector2.ZERO,.1,false)
	var before=foot(w);Ladder.interact(w)
	check(w.player.ladder.is_empty() and foot(w).distance_to(before)<.00001,"second E cancels approach in place")
	place(w,ladder.high+Vector3(0,0,.7));Ladder.interact(w);before=foot(w);Ladder.move(w,w.player,Vector2.ZERO,.01,true)
	check(w.player.ladder.is_empty() and foot(w).distance_to(before)<.00001,"space cancels approach in place")
	place(w,ladder.low);Ladder.interact(w)
	var blocker: Dictionary=w.objects[0];blocker.position=Vector2(ladder.low.x,ladder.low.z+.8);w.build_index()
	var notices=[];w.event.connect(func(event):if event.type=="notice":notices.append(event.text))
	for i in range(250):
		if not w.player.ladder.is_empty():Ladder.move(w,w.player,Vector2.UP,1.0/60,false)
	check(not w.player.ladder.is_empty() and w.player.ladder.blocked,"new obstacle stops transfer instead of tunnelling")
	check("受阻" in Ladder.hint(w) and notices.size()==1,"blocked route has persistent prompt without repeated notices")
	for i in range(250):
		if not w.player.ladder.is_empty():Ladder.move(w,w.player,Vector2.DOWN,1.0/60,false)
	check(w.player.ladder.is_empty() and foot(w).distance_to(ladder.low)<.001,"climber can reverse away from blocked exit")
	check(Ladder.interact(w) and w.player.ladder.is_empty(),"pre-existing blocked exit refuses mount")
	blocker.position=Vector2(-15,0);w.build_index()
	place(w,ladder.low+Vector3(0,1,0));w.player.grounded=false
	check(Ladder.nearest(w).is_empty(),"cannot grab an endpoint from midair")
	# Source locomotion contains translated FBX roots; pose blending must cancel them.
	var stage=Node3D.new();root.add_child(stage)
	var view=preload("res://scripts/source_rig_character.gd").soldier(stage,0,true)
	view.rifle=Node3D.new();view.weapon_parent.add_child(view.rifle);view.weapon_profile=catalog.weapons.m416
	view.held=preload("res://scripts/proving_art.gd").weapon(view.rifle,view.weapon_profile)
	view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Node3D.new();view.rifle.add_child(view.muzzle)
	place(w,ladder.low-Vector3(0,0,.7));w.player.facing=Vector2.DOWN;w.player.velocity=Vector2.DOWN*3.4
	view.root.position=foot(w)
	for i in range(30):Motion.update(view,w.player,1.0/60,i/60.0,2.1)
	before=pelvis(view);Ladder.interact(w);Motion.update(view,w.player,.001,1,2.1)
	check(pelvis(view).distance_to(before)<.005,"walk-to-ladder pose does not inherit raw source root displacement")
	var finite=true;var worst=0.0;var previous=pelvis(view)-view.root.position
	for i in range(40):
		Ladder.move(w,w.player,Vector2.ZERO,1.0/60,false);view.root.position=foot(w);Motion.update(view,w.player,1.0/60,1+i/60.0,2.1)
		var relative=pelvis(view)-view.root.position;worst=maxf(worst,relative.distance_to(previous));previous=relative
		for bone in range(view.skeleton.get_bone_count()):finite=finite and view.skeleton.get_bone_global_pose(bone).is_finite()
	check(finite and worst<.08,"approach-to-climb pose is finite and continuous, max local pelvis step %.4f"%worst)
	check(not w.player.hit_shapes.is_empty() and not view.muzzle.visible,"climbing retains hit capsules and hides muzzle flash")
	before=pelvis(view);Ladder.interact(w);Motion.update(view,w.player,.001,2,2.1)
	check(pelvis(view).distance_to(before)<.005,"ladder release blends back without a body snap")
	stage.free()
	print("LADDER_INTERACTION %d/%d passed; failures=%s"%[checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
