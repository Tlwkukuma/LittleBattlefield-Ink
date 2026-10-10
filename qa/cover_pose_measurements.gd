extends SceneTree
## Offline pose/resource measurements for the cover design; no game input or simulation.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Ink=preload("res://scripts/ink_art.gd")
const Props=preload("res://scripts/proving_art.gd")
const Motion=preload("res://scripts/source_rig_motion.gd")
const Effects=preload("res://scripts/weapon_effects.gd")

func _initialize():measure.call_deferred()

func measure():
	var catalog=Catalog.new()
	var world=World.new()
	world.setup({"world":{"w":1600,"h":1600,"groundFeatures":[]},"instances":[],"looseSegments":[],"trees":[],"deployment":{"player":{"x":800,"y":800}}},catalog)
	var stage=Node3D.new();root.add_child(stage)
	var samples=[]
	for id in ["m416","akm","awm"]:
		for stance in [0,1,2]:
			var view=Ink.soldier(stage,0,false,true)
			for child in view.rifle.get_children():view.rifle.remove_child(child);child.free()
			var weapon: Dictionary=catalog.weapons[id]
			view.held=Props.weapon(view.rifle,weapon);view.weapon=id;view.weapon_profile=weapon
			view.muzzle_socket=view.held.get_node("MuzzleSocket");view.muzzle=Effects.flash(view.muzzle_socket,weapon)
			var u: Dictionary=world.player
			u.position=Vector2.ZERO;u.elevation=0;u.stance=stance;u.stance_blend=float(stance);u.hit_shapes=[];u.facing=Vector2.RIGHT
			u.aiming=true;u.aim_valid=true;u.aim_point=Vector2(20,0);u.aim_height=1.35;u.weapon_id=id
			view.root.position=Vector3.ZERO;view.body_yaw=-PI*.5
			Motion.update(view,u,0,1,float(weapon.reload))
			var head: Dictionary=u.hit_shapes.filter(func(s):return s.region=="head")[0]
			var high=-INF;var low=INF
			for shape in u.hit_shapes:
				high=maxf(high,maxf(shape.a.y,shape.b.y)+shape.radius)
				low=minf(low,minf(shape.a.y,shape.b.y)-shape.radius)
			samples.append({"weapon":id,"stance":stance,"muzzle_y":view.muzzle_socket.global_position.y,"head_center_y":head.a.y,"head_top_y":head.a.y+head.radius,"body_max_y":high,"body_min_y":low,"collision_height":World.stance_height(stance)})
			view.root.free()
	stage.free()
	var components=[]
	var ids=catalog.components.keys();ids.sort()
	for id in ids:
		var item: Dictionary=catalog.components[id]
		components.append({"id":id,"material":item.get("material",""),"runtime":item.get("runtime",{}),"role":item.get("role",""),"defaults":item.get("defaults",{}),"default_height_m":catalog.default_height(id)})
	var report={"status":"measured_static_pose_not_gameplay_acceptance","aim_distance_m":20,"aim_target_height_m":1.35,"feet_y":0,"animation_time_s":1,"samples":samples,"registered_components":components}
	var file=FileAccess.open("res://docs/cover-pose-measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n");file.close()
	print("COVER_POSE_MEASUREMENTS samples=",samples.size()," report=res://docs/cover-pose-measurements.json")
	quit()
