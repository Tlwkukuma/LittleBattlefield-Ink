extends SceneTree
## Independent copied-unit kinematics and original-rig pose samples only.
## Never advances the live world, runs decisions, fires or sends input.
const World=preload("res://scripts/proving_world.gd")
const Motion=preload("res://scripts/soldier_motion.gd")
const Traversal=preload("res://scripts/soldier_traversal.gd")
class MeasuredWorld extends World:
	var costs={"ground_usec":0,"ground_calls":0,"collision_usec":0,"collision_calls":0}
	func ground_height(point: Vector2,radius: float,below: float,support_filter: Callable=Callable()) -> float:
		var began=Time.get_ticks_usec();var result=super.ground_height(point,radius,below,support_filter)
		costs.ground_usec+=Time.get_ticks_usec()-began;costs.ground_calls+=1;return result
	func collision_depth(point: Vector2,radius: float,height: float,ignore_vehicle: int=-1,base_height: float=0,first_only: bool=false) -> float:
		var began=Time.get_ticks_usec();var result=super.collision_depth(point,radius,height,ignore_vehicle,base_height,first_only)
		costs.collision_usec+=Time.get_ticks_usec()-began;costs.collision_calls+=1;return result
func _initialize():run.call_deferred()
func run():
	var game=load("res://proving_ground.tscn").instantiate();game.world=MeasuredWorld.new();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	await process_frame
	var profiler=GDScript.new();var code=FileAccess.get_file_as_string("res://scripts/source_rig_motion.gd")
	code=code.replace("static func update(view: Dictionary,u: Dictionary,delta: float,time: float,reload_seconds: float):", "static func update(view: Dictionary,u: Dictionary,delta: float,time: float,reload_seconds: float):\n\tvar qa_start=Time.get_ticks_usec()")
	code=code.replace("\t\tpose_weapon(view,u,time,reload_seconds)","\t\tvar qa_weapon=Time.get_ticks_usec()\n\t\tpose_weapon(view,u,time,reload_seconds)\n\t\tvar qa_hits=Time.get_ticks_usec()")
	code=code.replace("\t\tview.foot_contact=[false,false];Style.update_shadow(view);return","\t\tvar qa_shadow=Time.get_ticks_usec()\n\t\tview.foot_contact=[false,false];Style.update_shadow(view)\n\t\tview.qa_cost={\"body\":qa_weapon-qa_start,\"weapon\":qa_hits-qa_weapon,\"hits\":qa_shadow-qa_hits,\"shadow\":Time.get_ticks_usec()-qa_shadow}\n\t\treturn")
	profiler.source_code=code;profiler.reload()
	var records=[]
	for speed in [0.0,2.8]:
		for count in [1,30,60]:
			var moves=[];var poses=[];var details={"body":0,"weapon":0,"hits":0,"shadow":0}
			game.world.costs={"ground_usec":0,"ground_calls":0,"collision_usec":0,"collision_calls":0}
			for repeat in range(12):
				var copies=[]
				for i in range(count):
					var u=game.world.units[i].duplicate(true);u.velocity=Vector2(speed,0);u.requested_velocity=u.velocity;u.walk=0.0;copies.append(u)
				var began=Time.get_ticks_usec()
				for u in copies:game.world.move_unit(u,u.velocity,1.0/30);Traversal.vertical_step(game.world,u,1.0/30)
				moves.append((Time.get_ticks_usec()-began)/1000.0);began=Time.get_ticks_usec()
				for u in copies:
					profiler.update(game.actors[u.id],u,1.0/24,0.5,game.world.weapon_for(u).reload)
					for key in details:details[key]+=game.actors[u.id].get("qa_cost",{}).get(key,0)
				poses.append((Time.get_ticks_usec()-began)/1000.0)
			records.append({"count":count,"speed":speed,"move_ms":preload("res://scripts/runtime_performance.gd").summary(moves),"pose_ms":preload("res://scripts/runtime_performance.gd").summary(poses),"queries":game.world.costs.duplicate(),"pose_detail_usec":details})
	print("LOCOMOTION_RESOURCES "+JSON.stringify({"records":records,"time":game.world.time,"shots":game.world.shots}))
	game.free();quit()
